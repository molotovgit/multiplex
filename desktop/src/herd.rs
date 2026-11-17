//! `multiplex herd`: everything herdr keeps running here, for the phone.
//!
//! `state` prints it once; `watch` prints it and then again whenever it
//! changes, told by herdr itself over its socket (never by looking again
//! and again); `do` passes on what the phone asks: text for an agent,
//! keys for a pane, a pane's recent output.
//!
//! herdr's socket speaks one line of JSON per request, answer and event.
//! A connection that subscribed to events can ask nothing else, and
//! changes of an agent's status are only told per pane, so `watch` keeps
//! two connections per session: one for what appears and disappears, one
//! for the status of every pane there is, opened anew when the panes
//! change.

use std::collections::{BTreeSet, HashMap};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::mpsc::{channel, RecvTimeoutError, Sender};
use std::time::{Duration, Instant};

use anyhow::{anyhow, bail, Context, Result};
use multiplex_proto::agents::{clean_session_name, AgentStatus};
use multiplex_proto::herd::{Herd, HerdAction, Pane, PaneAgent, PaneText, Session, Tab, Workspace};
use serde_json::{json, Value};

/// One of herdr's running sessions: its name and where its socket is.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Running {
    pub name: String,
    pub socket: PathBuf,
}

/// The running sessions in what `herdr session list` prints: a table with
/// the name first, the status second and the socket last.
pub fn running_in(table: &str) -> Vec<Running> {
    table
        .lines()
        .skip(1)
        .filter_map(|line| {
            let words: Vec<&str> = line.split_whitespace().collect();
            let (name, status, socket) = (words.first()?, words.get(1)?, words.last()?);
            (*status == "running" && words.len() >= 4 && socket.ends_with(".sock")).then(|| clean_session_name(name).ok()).flatten().map(|name| Running { name, socket: PathBuf::from(socket) })
        })
        .collect()
}

/// None: herdr is not installed. With `MULTIPLEX_HERD_SESSION` set, only
/// that session is looked at: the tests keep to a session of their own.
fn running() -> Option<Vec<Running>> {
    let out = Command::new("herdr").args(["session", "list"]).output().ok()?;
    let only = std::env::var("MULTIPLEX_HERD_SESSION").ok().filter(|name| !name.is_empty());
    Some(running_in(&String::from_utf8_lossy(&out.stdout)).into_iter().filter(|session| only.as_ref().is_none_or(|only| &session.name == only)).collect())
}

/// One question to a session's socket, and its answer's `result`.
fn ask(socket: &Path, method: &str, params: Value) -> Result<Value> {
    let mut stream = UnixStream::connect(socket).with_context(|| format!("herdr's socket {} does not answer", socket.display()))?;
    stream.set_read_timeout(Some(Duration::from_secs(5)))?;
    stream.set_write_timeout(Some(Duration::from_secs(5)))?;
    writeln!(stream, "{}", json!({ "id": "multiplex", "method": method, "params": params }))?;
    let mut line = String::new();
    BufReader::new(stream).read_line(&mut line).context("herdr did not answer")?;
    let answer: Value = serde_json::from_str(&line).context("herdr's answer is not JSON")?;
    match answer.get("result") {
        Some(result) => Ok(result.clone()),
        None => bail!("herdr refused `{method}`: {}", answer.get("error").map(Value::to_string).unwrap_or_else(|| line.trim().to_owned())),
    }
}

/// A session as the phone sees it, from herdr's snapshot of it.
pub fn build(name: &str, snapshot: &Value) -> Session {
    let list = |key: &str| snapshot[key].as_array().cloned().unwrap_or_default();
    let text = |value: &Value| value.as_str().map(str::trim).filter(|s| !s.is_empty()).map(str::to_owned);
    let number = |value: &Value| value["number"].as_u64().unwrap_or(u64::MAX);
    let pane = |pane: &Value| -> Option<Pane> {
        Some(Pane {
            id: pane["pane_id"].as_str()?.to_owned(),
            title: text(&pane["title"]).or_else(|| text(&pane["terminal_title_stripped"])).or_else(|| text(&pane["label"])).unwrap_or_default(),
            folder: text(&pane["foreground_cwd"]).or_else(|| text(&pane["cwd"])).unwrap_or_default(),
            focused: pane["focused"].as_bool().unwrap_or(false),
            agent: text(&pane["display_agent"]).or_else(|| text(&pane["agent"])).map(|name| PaneAgent { name, status: serde_json::from_value(pane["agent_status"].clone()).unwrap_or(AgentStatus::Unknown) }),
        })
    };
    let panes = list("panes");
    let mut tabs = list("tabs");
    tabs.sort_by_key(number);
    let mut workspaces = list("workspaces");
    workspaces.sort_by_key(number);
    Session {
        name: name.to_owned(),
        workspaces: workspaces
            .iter()
            .filter_map(|workspace| {
                let id = workspace["workspace_id"].as_str()?;
                Some(Workspace {
                    id: id.to_owned(),
                    label: text(&workspace["label"]).unwrap_or_default(),
                    tabs: tabs
                        .iter()
                        .filter(|tab| tab["workspace_id"].as_str() == Some(id))
                        .filter_map(|tab| {
                            let tab_id = tab["tab_id"].as_str()?;
                            Some(Tab { id: tab_id.to_owned(), label: text(&tab["label"]).unwrap_or_default(), panes: panes.iter().filter(|pane| pane["tab_id"].as_str() == Some(tab_id)).filter_map(pane).collect() })
                        })
                        .collect(),
                })
            })
            .collect(),
    }
}

fn snapshot(session: &Running) -> Result<Session> {
    Ok(build(&session.name, &ask(&session.socket, "session.snapshot", json!({}))?["snapshot"]))
}

/// The ids of every pane of a session.
fn panes_of(session: &Session) -> BTreeSet<String> {
    session.workspaces.iter().flat_map(|w| &w.tabs).flat_map(|t| &t.panes).map(|p| p.id.clone()).collect()
}

/// Everything, once. A session that does not answer is left out.
pub fn state() -> Herd {
    match running() {
        None => Herd::missing(),
        Some(sessions) => Herd { available: true, sessions: sessions.iter().filter_map(|session| snapshot(session).ok()).collect() },
    }
}

/// What appears, disappears, moves or is renamed: told for the whole session.
const TOPOLOGY: &[&str] = &[
    "workspace.created", "workspace.updated", "workspace.renamed", "workspace.moved", "workspace.reordered", "workspace.closed",
    "tab.created", "tab.closed", "tab.renamed", "tab.moved",
    "pane.created", "pane.closed", "pane.updated", "pane.moved", "pane.exited", "pane.agent_detected", "pane.focused",
];

/// What a listening connection tells the watch.
enum Told {
    /// Something changed in this session.
    Changed(String),
    /// This session's connection of this generation ended.
    Ended(String, u64),
}

/// Subscribes on a connection of its own and passes every event on.
/// Gives back the connection's other handle, to end the listening with.
fn listen(session: &Running, subscriptions: Vec<Value>, generation: u64, tell: Sender<Told>) -> Result<UnixStream> {
    let mut stream = UnixStream::connect(&session.socket)?;
    writeln!(stream, "{}", json!({ "id": "multiplex", "method": "events.subscribe", "params": { "subscriptions": subscriptions } }))?;
    let handle = stream.try_clone()?;
    let name = session.name.clone();
    std::thread::spawn(move || {
        let mut started = false;
        for line in BufReader::new(stream).lines() {
            let Ok(line) = line else { break };
            // The first line is the answer to subscribing; an error there ends it.
            if !started {
                started = true;
                if !line.contains("subscription_started") {
                    break;
                }
                continue;
            }
            if tell.send(Told::Changed(name.clone())).is_err() {
                return;
            }
        }
        let _ = tell.send(Told::Ended(name, generation));
    });
    Ok(handle)
}

/// One session being watched.
struct Watched {
    session: Running,
    generation: u64,
    /// The connection for what appears and disappears.
    topology: Option<UnixStream>,
    /// The connection for every pane's status, and the panes it covers.
    status: Option<(UnixStream, BTreeSet<String>)>,
    seen: Option<Session>,
}

impl Watched {
    fn hang_up(&mut self) {
        for stream in self.topology.take().into_iter().chain(self.status.take().map(|(stream, _)| stream)) {
            let _ = stream.shutdown(std::net::Shutdown::Both);
        }
    }

    /// Looks at the session now. Listening comes first, so nothing that
    /// happens while looking is missed; and when the panes are not the
    /// ones whose status is listened to, that listening is renewed and
    /// the session looked at once more.
    fn look(&mut self, tell: &Sender<Told>) -> Result<Session> {
        if self.topology.is_none() {
            self.generation += 1;
            self.topology = Some(listen(&self.session, TOPOLOGY.iter().map(|kind| json!({ "type": kind })).collect(), self.generation, tell.clone())?);
        }
        let mut now = snapshot(&self.session)?;
        let panes = panes_of(&now);
        if self.status.as_ref().map(|(_, covered)| covered) != Some(&panes) {
            if let Some((old, _)) = self.status.take() {
                let _ = old.shutdown(std::net::Shutdown::Both);
            }
            if !panes.is_empty() {
                // Ended on purpose above: its generation is the old one.
                self.generation += 1;
                let subscriptions = panes.iter().map(|pane| json!({ "type": "pane.agent_status_changed", "pane_id": pane })).collect();
                self.status = Some((listen(&self.session, subscriptions, self.generation, tell.clone())?, panes));
                now = snapshot(&self.session)?;
            }
        }
        Ok(now)
    }
}

/// `multiplex herd watch`: the herd now, and again whenever it changes.
pub fn watch() -> Result<()> {
    // Events come in bursts (a new tab is five of them): looked at once
    // they settle.
    const SETTLE: Duration = Duration::from_millis(30);
    // Sessions start and stop without an event: looked for now and then.
    const SESSIONS: Duration = Duration::from_secs(5);
    // An empty line now and then, so a phone that hung up is noticed.
    const ALIVE: Duration = Duration::from_secs(10);

    let mut out = std::io::stdout().lock();
    let (tell, told) = channel::<Told>();
    let mut watched: HashMap<String, Watched> = HashMap::new();
    let mut order: Vec<String> = Vec::new();
    let mut dirty: BTreeSet<String> = BTreeSet::new();
    let mut last: Option<Herd> = None;
    let mut sessions_at: Option<Instant> = None;
    let mut said_at = Instant::now();
    let mut available = true;
    loop {
        if sessions_at.is_none_or(|at| at.elapsed() >= SESSIONS) {
            sessions_at = Some(Instant::now());
            let found = running();
            available = found.is_some();
            let found = found.unwrap_or_default();
            order = found.iter().map(|session| session.name.clone()).collect();
            watched.retain(|name, one| {
                let stays = found.iter().any(|session| &session.name == name && session.socket == one.session.socket);
                if !stays {
                    one.hang_up();
                }
                stays
            });
            for session in found {
                if !watched.contains_key(&session.name) {
                    dirty.insert(session.name.clone());
                    watched.insert(session.name.clone(), Watched { session, generation: 0, topology: None, status: None, seen: None });
                }
            }
        }
        for name in std::mem::take(&mut dirty) {
            let Some(one) = watched.get_mut(&name) else { continue };
            match one.look(&tell) {
                Ok(session) => one.seen = Some(session),
                Err(_) => {
                    // It stopped answering: gone until it is found again.
                    one.hang_up();
                    watched.remove(&name);
                    sessions_at = None;
                }
            }
        }
        let herd = Herd { available, sessions: order.iter().filter_map(|name| watched.get(name)?.seen.clone()).collect() };
        if last.as_ref() != Some(&herd) {
            writeln!(out, "{}", serde_json::to_string(&herd)?)?;
            out.flush()?;
            said_at = Instant::now();
            last = Some(herd);
        } else if said_at.elapsed() >= ALIVE {
            writeln!(out)?;
            out.flush()?;
            said_at = Instant::now();
        }

        // Wait for news; then for the burst to end.
        let mut wait = Duration::from_secs(1);
        loop {
            match told.recv_timeout(wait) {
                Ok(Told::Changed(name)) => {
                    dirty.insert(name);
                    wait = SETTLE;
                }
                Ok(Told::Ended(name, generation)) => {
                    // A connection we ended ourselves is an older generation.
                    if let Some(one) = watched.get_mut(&name) {
                        if generation == one.generation {
                            one.hang_up();
                            dirty.insert(name);
                            wait = SETTLE;
                        }
                    }
                }
                Err(RecvTimeoutError::Timeout) => break,
                Err(RecvTimeoutError::Disconnected) => return Ok(()),
            }
        }
    }
}

/// herdr's own command, for one session, and what it printed.
fn herdr(session: &str, args: &[&str]) -> Result<String> {
    let done = Command::new("herdr").args(["--session", session]).args(args).output().context("herdr could not be run")?;
    if !done.status.success() {
        let said = String::from_utf8_lossy(if done.stderr.is_empty() { &done.stdout } else { &done.stderr }).trim().to_owned();
        // herdr's errors are JSON with a message; that is what is passed on.
        let message = serde_json::from_str::<Value>(&said).ok().and_then(|v| v["error"]["message"].as_str().map(str::to_owned)).unwrap_or(said);
        bail!("herdr: {message}");
    }
    Ok(String::from_utf8_lossy(&done.stdout).into_owned())
}

/// The text in what `herdr pane read` printed. herdr 0.9 prints the text
/// itself; should a version wrap it in its usual JSON answer, the text is
/// taken out of that.
fn read_text(printed: &str) -> String {
    let wrapped = serde_json::from_str::<Value>(printed.trim()).ok().and_then(|answer| answer["result"]["read"]["text"].as_str().or_else(|| answer["result"]["text"].as_str()).map(str::to_owned));
    wrapped.unwrap_or_else(|| printed.trim_end_matches('\n').to_owned())
}

/// `multiplex herd do …`.
fn act(action: &HerdAction) -> Result<()> {
    match action {
        HerdAction::Prompt { session, pane, text } => {
            // An agent takes text and Enter as one piece. A plain terminal
            // has no agent to give it to: there it is typed, then Enter.
            if herdr(session, &["agent", "prompt", pane, text]).is_err() {
                herdr(session, &["pane", "send-text", pane, text])?;
                herdr(session, &["pane", "send-keys", pane, "enter"])?;
            }
        }
        HerdAction::Keys { session, pane, keys } => {
            let mut args = vec!["pane", "send-keys", pane.as_str()];
            args.extend(keys.iter().map(String::as_str));
            herdr(session, &args)?;
        }
        HerdAction::Read { session, pane, lines } => {
            let printed = herdr(session, &["pane", "read", pane, "--source", "recent-unwrapped", "--lines", &lines.to_string()])?;
            println!("{}", serde_json::to_string(&PaneText { text: read_text(&printed) })?);
        }
    }
    Ok(())
}

pub fn run(args: &[&str]) -> Result<()> {
    match args {
        ["state"] => println!("{}", serde_json::to_string(&state())?),
        ["watch"] => watch()?,
        ["do", rest @ ..] => act(&HerdAction::parse(rest).map_err(|e| anyhow!("{e}"))?)?,
        _ => bail!("usage: multiplex herd state | watch | do <action>"),
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn running_sessions_are_read_from_herdrs_table() {
        let table = "name                 status   directory                                        socket\n\
                     default              running  /home/sam/.config/herdr                          /home/sam/.config/herdr/herdr.sock\n\
                     night-shift          stopped  /home/sam/.config/herdr/sessions/night-shift     /home/sam/.config/herdr/sessions/night-shift/herdr.sock\n\
                     work.api             running  /home/sam/.config/herdr/sessions/work.api        /home/sam/.config/herdr/sessions/work.api/herdr.sock\n\
                     bad;name             running  /x                                               /x/herdr.sock\n\
                     short                running\n";
        assert_eq!(running_in(table), [
            Running { name: "default".into(), socket: "/home/sam/.config/herdr/herdr.sock".into() },
            Running { name: "work.api".into(), socket: "/home/sam/.config/herdr/sessions/work.api/herdr.sock".into() },
        ]);
        assert!(running_in("").is_empty());
        assert!(running_in("name status directory socket\n").is_empty());
    }

    fn snapshot() -> Value {
        json!({
            "workspaces": [
                {"workspace_id": "w2", "label": "site", "number": 2},
                {"workspace_id": "w1", "label": "api", "number": 1},
            ],
            "tabs": [
                {"tab_id": "w1:t2", "workspace_id": "w1", "label": "review", "number": 2},
                {"tab_id": "w1:t1", "workspace_id": "w1", "label": "1", "number": 1},
                {"tab_id": "w2:t1", "workspace_id": "w2", "label": "1", "number": 1},
            ],
            "panes": [
                {"pane_id": "w1:p1", "tab_id": "w1:t1", "workspace_id": "w1", "agent": "claude", "display_agent": "Claude", "agent_status": "blocked", "title": "Fix the tests", "cwd": "/home/sam/code/api", "focused": true},
                {"pane_id": "w1:p2", "tab_id": "w1:t1", "workspace_id": "w1", "agent": null, "agent_status": "unknown", "terminal_title_stripped": "sam@desk:~", "cwd": "/home/sam"},
                {"pane_id": "w1:p3", "tab_id": "w1:t2", "workspace_id": "w1", "agent": "codex", "agent_status": "a state from the future", "foreground_cwd": "/srv/web", "cwd": "/home/sam"},
                {"pane_id": "w9:p1", "tab_id": "w9:t1", "workspace_id": "w9", "agent": "pi", "agent_status": "idle"},
                {"tab_id": "w2:t1", "workspace_id": "w2"},
            ],
        })
    }

    #[test]
    fn a_snapshot_becomes_workspaces_tabs_and_panes_in_herdrs_order() {
        let session = build("default", &snapshot());
        assert_eq!(session.name, "default");
        assert_eq!(session.workspaces.iter().map(|w| (w.id.as_str(), w.label.as_str())).collect::<Vec<_>>(), [("w1", "api"), ("w2", "site")]);
        let api = &session.workspaces[0];
        assert_eq!(api.tabs.iter().map(|t| (t.id.as_str(), t.label.as_str(), t.panes.len())).collect::<Vec<_>>(), [("w1:t1", "1", 2), ("w1:t2", "review", 1)]);
        assert_eq!(api.tabs[0].panes[0], Pane { id: "w1:p1".into(), title: "Fix the tests".into(), folder: "/home/sam/code/api".into(), focused: true, agent: Some(PaneAgent { name: "Claude".into(), status: AgentStatus::Blocked }) });
        // A plain terminal: no agent, and its title from the terminal.
        assert_eq!(api.tabs[0].panes[1], Pane { id: "w1:p2".into(), title: "sam@desk:~".into(), folder: "/home/sam".into(), focused: false, agent: None });
        // A status this version does not know, and the folder of what runs in front.
        let codex = &api.tabs[1].panes[0];
        assert_eq!((codex.agent.as_ref().unwrap().name.as_str(), codex.agent.as_ref().unwrap().status, codex.folder.as_str()), ("codex", AgentStatus::Unknown, "/srv/web"));
        // A pane of a workspace that is not listed, and one without an id, are left out.
        assert!(session.workspaces[1].tabs[0].panes.is_empty());
        assert_eq!(panes_of(&session), ["w1:p1", "w1:p2", "w1:p3"].map(str::to_owned).into());
        // Nothing at all is an empty session, not an error.
        assert_eq!(build("x", &json!({})), Session { name: "x".into(), workspaces: vec![] });
    }

    #[test]
    fn a_panes_text_is_what_herdr_printed() {
        // As herdr 0.9 prints it: the text itself.
        assert_eq!(read_text("$ make test\nok: 12 passed\n"), "$ make test\nok: 12 passed");
        assert_eq!(read_text(""), "");
        // Output that happens to be JSON of its own stays what it is.
        assert_eq!(read_text("{\"passed\": 12}\n"), "{\"passed\": 12}");
        // Wrapped in herdr's usual answer: taken out.
        assert_eq!(read_text(r#"{"id":"cli:pane:read","result":{"read":{"text":"one\ntwo"},"type":"pane_read"}}"#), "one\ntwo");
        assert_eq!(read_text(r#"{"id":"x","result":{"text":"plain"}}"#), "plain");
    }
}
