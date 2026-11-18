//! `multiplex herd`: everything herdr keeps running here, for the phone.
//!
//! `state` prints it once; `watch` prints it and then again whenever it
//! changes, told by herdr itself over its socket (never by looking again
//! and again); `do` passes on what the phone asks: text for an agent,
//! keys for a pane, a pane's recent output; `pane` (in `pane.rs`) puts one
//! pane into the terminal it runs in.
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
use multiplex_proto::agents::{clean_session_name, Agent, AgentStatus};
use multiplex_proto::asked::{asked, keys_for, may_answer, Asked, Reply};
use multiplex_proto::herd::{clean_folder, clean_kind, Herd, HerdAction, HerdAgent, Kind, Made, Pane, PaneAgent, PaneText, Place, Session, Tab, Workspace};
use multiplex_proto::share::LinkEvent;
use serde_json::{json, Value};

/// One of herdr's running sessions: its name and where its socket is.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Running {
    pub name: String,
    pub socket: PathBuf,
}

/// herdr's sessions in what `herdr session list` prints: a table with the
/// name first, the status second and the socket last. A session that is
/// not running has no socket to ask.
pub fn sessions_in(table: &str) -> Vec<(String, Option<PathBuf>)> {
    table
        .lines()
        .skip(1)
        .filter_map(|line| {
            let words: Vec<&str> = line.split_whitespace().collect();
            let (name, status, socket) = (words.first()?, words.get(1)?, words.last()?);
            if words.len() < 4 || !socket.ends_with(".sock") {
                return None;
            }
            let name = clean_session_name(name).ok()?;
            Some((name, (*status == "running").then(|| PathBuf::from(socket))))
        })
        .collect()
}

/// Every session herdr knows, running or not, in its order. None: herdr
/// is not installed. With `MULTIPLEX_HERD_SESSION` set, only that session
/// is looked at: the tests keep to a session of their own.
fn known() -> Option<Vec<(String, Option<PathBuf>)>> {
    let out = Command::new("herdr").args(["session", "list"]).output().ok()?;
    let only = std::env::var("MULTIPLEX_HERD_SESSION").ok().filter(|name| !name.is_empty());
    Some(sessions_in(&String::from_utf8_lossy(&out.stdout)).into_iter().filter(|(name, _)| only.as_ref().is_none_or(|only| name == only)).collect())
}

fn stopped(name: &str) -> Session {
    Session { name: name.to_owned(), running: false, workspaces: Vec::new() }
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
        running: true,
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

/// Everything, once. A session that is not running, or does not answer,
/// is there by name with nothing in it.
pub fn state() -> Herd {
    match known() {
        None => Herd::missing(),
        Some(sessions) => Herd {
            available: true,
            sessions: sessions
                .into_iter()
                .map(|(name, socket)| socket.and_then(|socket| snapshot(&Running { name: name.clone(), socket }).ok()).unwrap_or_else(|| stopped(&name)))
                .collect(),
        },
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
    // An empty line now and then, so a phone that hung up is noticed.
    const ALIVE: Duration = Duration::from_secs(10);
    let mut out = std::io::stdout().lock();
    let mut said_at = Instant::now();
    follow(|herd| {
        match herd {
            Some(herd) => writeln!(out, "{}", serde_json::to_string(herd)?)?,
            None if said_at.elapsed() >= ALIVE => writeln!(out)?,
            None => return Ok(true),
        }
        out.flush()?;
        said_at = Instant::now();
        Ok(true)
    })
}

/// Follows the herd: `on` gets it now and again whenever it changes, and
/// nothing (`None`) about once a second in between, so it can do what it
/// does by the clock. It ends when `on` says false or fails.
pub fn follow(mut on: impl FnMut(Option<&Herd>) -> Result<bool>) -> Result<()> {
    // Events come in bursts (a new tab is five of them): looked at once
    // they settle.
    const SETTLE: Duration = Duration::from_millis(30);
    // Sessions start and stop without an event: looked for now and then.
    const SESSIONS: Duration = Duration::from_secs(5);

    let (tell, told) = channel::<Told>();
    let mut watched: HashMap<String, Watched> = HashMap::new();
    let mut order: Vec<String> = Vec::new();
    let mut dirty: BTreeSet<String> = BTreeSet::new();
    let mut last: Option<Herd> = None;
    let mut sessions_at: Option<Instant> = None;
    let mut available = true;
    loop {
        if sessions_at.is_none_or(|at| at.elapsed() >= SESSIONS) {
            sessions_at = Some(Instant::now());
            let known = known();
            available = known.is_some();
            let known = known.unwrap_or_default();
            order = known.iter().map(|(name, _)| name.clone()).collect();
            let found: Vec<Running> = known.into_iter().filter_map(|(name, socket)| Some(Running { name, socket: socket? })).collect();
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
        // A session that is not running (or has not answered yet) is
        // there by name, with nothing in it.
        let herd = Herd { available, sessions: order.iter().map(|name| watched.get(name).and_then(|one| one.seen.clone()).unwrap_or_else(|| stopped(name))).collect() };
        let changed = last.as_ref() != Some(&herd);
        if !on(changed.then_some(&herd))? {
            return Ok(());
        }
        if changed {
            last = Some(herd);
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

/// What in the herd is news for a phone that is not looking.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct News {
    /// Agents that began to wait for an answer, or finished.
    pub wants: Vec<HerdAgent>,
    /// Session and pane of agents that waited or were done, and are not
    /// any more: answered at the computer, gone on, or closed.
    pub settled: Vec<(String, String)>,
}

/// Every agent's state, by session and pane.
pub fn statuses(herd: &Herd) -> HashMap<(String, String), AgentStatus> {
    herd.agents().into_iter().map(|agent| ((agent.session, agent.pane), agent.status)).collect()
}

pub fn news(before: &HashMap<(String, String), AgentStatus>, now: &Herd) -> News {
    let wants_owner = |status: AgentStatus| matches!(status, AgentStatus::Blocked | AgentStatus::Done);
    let agents = now.agents();
    let wants = agents
        .iter()
        .filter(|agent| wants_owner(agent.status))
        // An agent seen for the first time in that state is not news: the
        // phone has just connected, or the agent has just been listed.
        .filter(|agent| before.get(&(agent.session.clone(), agent.pane.clone())).is_some_and(|was| *was != agent.status))
        .cloned()
        .collect();
    let mut settled: Vec<(String, String)> = before
        .iter()
        .filter(|(_, was)| wants_owner(**was))
        .filter(|(key, _)| !agents.iter().any(|agent| (&agent.session, &agent.pane) == (&key.0, &key.1) && wants_owner(agent.status)))
        .map(|(key, _)| key.clone())
        .collect();
    settled.sort();
    News { wants, settled }
}

/// What a pane shows now.
fn screen(session: &str, pane: &str) -> Result<String> {
    Ok(read_text(&herdr(session, &["pane", "read", pane, "--source", "visible"])?))
}

/// What the agent in a pane is doing now. None: no agent is there.
fn status_of(session: &str, pane: &str) -> Result<Option<AgentStatus>> {
    let socket = known().into_iter().flatten().find(|(name, _)| name == session).and_then(|(_, socket)| socket).ok_or_else(|| anyhow!("The session {session} is not running."))?;
    let now = snapshot(&Running { name: session.to_owned(), socket })?;
    Ok(now.workspaces.iter().flat_map(|w| &w.tabs).flat_map(|t| &t.panes).find(|p| p.id == pane).and_then(|p| p.agent.as_ref()).map(|agent| agent.status))
}

/// What an agent that has just begun to wait asks by choice. Its screen
/// may be a moment behind its state, so a screen without choices is read
/// once more before it is taken to ask in words.
fn asked_soon(session: &str, pane: &str) -> Asked {
    let read = || screen(session, pane).map(|text| asked(&text)).unwrap_or_default();
    let first = read();
    if !first.choices.is_empty() {
        return first;
    }
    std::thread::sleep(Duration::from_millis(400));
    read()
}

/// For `multiplex link`: says what is news for the phone, as it happens,
/// until `tell` says the phone is gone. An agent that waits on a choice
/// is told with its question and choices, when `questions` may be told.
pub fn tell_news(questions: bool, mut tell: impl FnMut(LinkEvent) -> bool) {
    let mut before: Option<HashMap<(String, String), AgentStatus>> = None;
    let _ = follow(|herd| {
        let Some(herd) = herd else { return Ok(true) };
        if let Some(before) = &before {
            let news = news(before, herd);
            for agent in news.wants {
                let asked = if questions && agent.status == AgentStatus::Blocked { asked_soon(&agent.session, &agent.pane) } else { Asked::default() };
                let event = LinkEvent::Agent(Agent {
                    id: agent.pane,
                    name: agent.name,
                    status: agent.status,
                    title: agent.title,
                    workspace: agent.workspace,
                    folder: agent.folder,
                    session: agent.session,
                    question: asked.question,
                    choices: asked.choices,
                    mark: asked.mark,
                });
                if !tell(event) {
                    return Ok(false);
                }
            }
            for (session, pane) in news.settled {
                if !tell(LinkEvent::Settled { session, pane }) {
                    return Ok(false);
                }
            }
        }
        before = Some(statuses(herd));
        Ok(true)
    });
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

/// herdr's ids for what it just made, from its answer to `tab create` or
/// `workspace create`.
pub fn made(printed: &str) -> Result<Made> {
    let answer: Value = serde_json::from_str(printed.trim()).map_err(|_| anyhow!("herdr's answer is not JSON"))?;
    let result = &answer["result"];
    let id = |what: &str, key: &str| result[what][key].as_str().map(str::to_owned);
    Ok(Made {
        workspace: id("workspace", "workspace_id").unwrap_or_default(),
        tab: id("tab", "tab_id").context("herdr did not say which tab it made")?,
        pane: id("root_pane", "pane_id").context("herdr did not say which pane it made")?,
    })
}

/// The kinds of agent in what `herdr agent` prints about itself: a line
/// "kinds: claude|codex|…". A kind's name is also its program's.
pub fn kinds_in(help: &str) -> Vec<String> {
    help.lines()
        .find_map(|line| line.trim().strip_prefix("kinds:"))
        .map(|list| list.split('|').map(str::trim).filter(|kind| clean_kind(kind).is_ok()).map(str::to_owned).collect())
        .unwrap_or_default()
}

/// The folders of a `PATH` in a process's environment as the kernel
/// shows it (`/proc/<pid>/environ`: entries divided by zero bytes).
pub fn path_in(environ: &[u8]) -> Vec<PathBuf> {
    environ
        .split(|byte| *byte == 0)
        .find_map(|entry| entry.strip_prefix(b"PATH="))
        .map(|path| std::env::split_paths(std::ffi::OsStr::new(&*String::from_utf8_lossy(path))).collect())
        .unwrap_or_default()
}

/// Where herdr itself looks for programs: the `PATH` of each herdr that
/// runs, besides this command's own. It is herdr that starts an agent,
/// and it was started from the user's desktop, where version managers
/// have put their folders on the path; this command, asked over SSH, has
/// a barer one (seen: 2 agents found this way, 14 herdr's way).
fn herdr_folders() -> Vec<PathBuf> {
    let mut folders: Vec<PathBuf> = std::env::var_os("PATH").map(|path| std::env::split_paths(&path).collect()).unwrap_or_default();
    for entry in std::fs::read_dir("/proc").into_iter().flatten().flatten() {
        let dir = entry.path();
        if std::fs::read_to_string(dir.join("comm")).is_ok_and(|name| name.trim() == "herdr") {
            if let Ok(environ) = std::fs::read(dir.join("environ")) {
                folders.extend(path_in(&environ));
            }
        }
    }
    folders
}

/// Those of `kinds` whose program is in one of `folders`, each with where
/// it was found first.
pub fn found(kinds: Vec<String>, folders: &[PathBuf]) -> Vec<(String, PathBuf)> {
    kinds.into_iter().filter_map(|kind| folders.iter().map(|folder| folder.join(&kind)).find(|program| program.is_file()).map(|program| (kind, program))).collect()
}

/// Whether a program is a stand-in of the tool manager mise: a link to
/// mise itself, which runs the real tool, and first installs one that is
/// marked to be installed when first used.
pub fn is_mise_shim(program: &Path) -> bool {
    std::fs::read_link(program).is_ok_and(|target| target.file_name().is_some_and(|name| name == "mise"))
}

/// The kinds that can be started here, and for each whether its program
/// is really there. Omarchy keeps most agents as tools that install
/// themselves on first use (seen: asking herdr to start one began a
/// 139 MB download); those are told apart by asking mise where the tool
/// is, which it can only say for one that is installed.
fn kinds() -> Vec<Kind> {
    let help = Command::new("herdr").arg("agent").output().map(|out| format!("{}{}", String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr))).unwrap_or_default();
    let found = found(kinds_in(&help), &herdr_folders());
    let asked: Vec<_> = found
        .into_iter()
        .map(|(kind, program)| {
            let shim = is_mise_shim(&program);
            std::thread::spawn(move || {
                // The program itself is never run to find out: for a tool
                // not yet installed, running it is what installs it.
                let installed = !shim || Command::new("mise").args(["which", &kind]).output().is_ok_and(|out| out.status.success());
                Kind { kind, installed }
            })
        })
        .collect();
    asked.into_iter().filter_map(|thread| thread.join().ok()).collect()
}

/// A path as people write it: `~` for the home folder.
pub fn shown(path: &str, home: &str) -> String {
    let home = home.trim_end_matches('/');
    match path.strip_prefix(home) {
        Some("") if !home.is_empty() => "~".to_owned(),
        Some(rest) if !home.is_empty() && rest.starts_with('/') => format!("~{rest}"),
        _ => path.to_owned(),
    }
}

/// The folders to offer for a new workspace, best first: those the user
/// goes to, then those herdr's panes are in, then projects. Each once,
/// and never the home folder or the root themselves.
pub fn offered(visited: Vec<String>, open: Vec<String>, projects: Vec<String>, home: &str) -> Vec<Place> {
    let mut seen = BTreeSet::new();
    visited
        .into_iter()
        .chain(open)
        .chain(projects)
        .map(|path| if path.len() > 1 { path.trim_end_matches('/').to_owned() } else { path })
        .filter(|path| clean_folder(path).is_ok() && path != "/" && path != home.trim_end_matches('/'))
        .filter(|path| seen.insert(path.clone()))
        .take(60)
        .map(|path| Place { shown: shown(&path, home), project: false, path })
        .collect()
}

/// The folders inside a folder, by name, each marked when it holds a
/// project. Hidden ones are left out.
pub fn folders_in(dir: &Path, home: &str) -> Vec<Place> {
    let mut inside: Vec<PathBuf> = std::fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| path.is_dir() && path.file_name().is_some_and(|name| !name.to_string_lossy().starts_with('.')))
        .collect();
    inside.sort_by_key(|path| path.file_name().map(|name| name.to_string_lossy().to_lowercase()));
    inside
        .into_iter()
        .filter_map(|path| {
            let text = path.to_str()?.to_owned();
            clean_folder(&text).ok()?;
            Some(Place { shown: shown(&text, home), project: path.join(".git").exists(), path: text })
        })
        .take(400)
        .collect()
}

/// Projects in the home folder: folders with a `.git` in them, the home
/// folder's own and those one level further in (`~/api`, `~/code/api`).
/// Hidden folders are not looked into.
pub fn projects_under(home: &Path) -> Vec<String> {
    let folders = |dir: &Path| -> Vec<PathBuf> {
        let mut list: Vec<PathBuf> = std::fs::read_dir(dir)
            .into_iter()
            .flatten()
            .flatten()
            .map(|entry| entry.path())
            .filter(|path| path.is_dir() && path.file_name().is_some_and(|name| !name.to_string_lossy().starts_with('.')))
            .take(400)
            .collect();
        list.sort();
        list
    };
    let mut found = Vec::new();
    for child in folders(home) {
        if child.join(".git").exists() {
            found.push(child.to_string_lossy().into_owned());
            continue;
        }
        found.extend(folders(&child).into_iter().filter(|inner| inner.join(".git").exists()).map(|inner| inner.to_string_lossy().into_owned()));
    }
    found
}

/// `multiplex herd places`.
fn places() -> Vec<Place> {
    let home = std::env::var("HOME").unwrap_or_default();
    // Where the user goes, from zoxide when it is there, most used first.
    let visited: Vec<String> = Command::new("zoxide").args(["query", "-l"]).output().map(|out| String::from_utf8_lossy(&out.stdout).lines().map(str::to_owned).collect()).unwrap_or_default();
    let open: Vec<String> = state().sessions.iter().flat_map(|s| &s.workspaces).flat_map(|w| &w.tabs).flat_map(|t| &t.panes).map(|p| p.folder.clone()).filter(|folder| !folder.is_empty()).collect();
    let projects = if home.is_empty() { Vec::new() } else { projects_under(Path::new(&home)) };
    let mut places: Vec<Place> = offered(visited, open, projects, &home)
        .into_iter()
        .filter(|place| Path::new(&place.path).is_dir())
        .map(|place| Place { project: Path::new(&place.path).join(".git").exists(), ..place })
        .collect();
    places.extend(starting_points(&home));
    places
}

/// The two folders every other one can be walked to from, offered last:
/// the home folder and the root.
pub fn starting_points(home: &str) -> Vec<Place> {
    let home = home.trim_end_matches('/');
    let mut points = Vec::new();
    if clean_folder(home).is_ok() {
        points.push(Place { path: home.to_owned(), shown: "~".to_owned(), project: false });
    }
    points.push(Place { path: "/".to_owned(), shown: "/".to_owned(), project: false });
    points
}

/// A name for an agent that herdr takes and no other agent has: its kind
/// and a few letters of chance ("claude-3fa9").
pub fn agent_name(kind: &str, chance: &str) -> String {
    let tail: String = chance.chars().filter(|c| c.is_ascii_lowercase() || c.is_ascii_digit()).take(4).collect();
    format!("{kind}-{tail}")
}

/// `multiplex herd do …`.
fn act(action: &HerdAction) -> Result<()> {
    match action {
        HerdAction::NewTab { session, workspace, label } => {
            let mut args = vec!["tab", "create", "--workspace", workspace, "--no-focus"];
            if !label.is_empty() {
                args.extend(["--label", label]);
            }
            println!("{}", serde_json::to_string(&made(&herdr(session, &args)?)?)?);
        }
        HerdAction::NewWorkspace { session, folder, label } => {
            if !Path::new(folder).is_dir() {
                bail!("{folder} is not a folder on this computer");
            }
            let mut args = vec!["workspace", "create", "--cwd", folder, "--no-focus"];
            if !label.is_empty() {
                args.extend(["--label", label]);
            }
            println!("{}", serde_json::to_string(&made(&herdr(session, &args)?)?)?);
        }
        HerdAction::Start { session, pane, kind } => {
            // herdr answers once the agent sits ready in the pane, or says
            // why it does not.
            let name = agent_name(kind, &crate::share::random_id()?);
            herdr(session, &["agent", "start", &name, "--kind", kind, "--pane", pane, "--timeout", "30000"])?;
        }
        HerdAction::ClosePane { session, pane } => {
            herdr(session, &["pane", "close", pane])?;
        }
        HerdAction::CloseTab { session, tab } => {
            herdr(session, &["tab", "close", tab])?;
        }
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
        HerdAction::Answer { session, pane, mark, with } => {
            // Only while it still asks what the answer was given to.
            let status = status_of(session, pane)?;
            let now = if status == Some(AgentStatus::Blocked) { asked(&screen(session, pane)?) } else { Asked::default() };
            may_answer(status, &now, mark, with).map_err(|why| anyhow!(why))?;
            match with {
                Reply::Choice(key) => {
                    let keys = keys_for(&now, key).ok_or_else(|| anyhow!("That is not one of its choices. Nothing was sent."))?;
                    let mut args = vec!["pane", "send-keys", pane.as_str()];
                    args.extend(keys.iter().map(String::as_str));
                    herdr(session, &args)?;
                }
                Reply::Text(text) => return act(&HerdAction::Prompt { session: session.clone(), pane: pane.clone(), text: text.clone() }),
            }
        }
        HerdAction::Read { session, pane, lines } => {
            let printed = herdr(session, &["pane", "read", pane, "--source", "recent-unwrapped", "--lines", &lines.to_string()])?;
            // With what its agent asks by choice, if it waits on one: read
            // off the screen as it stands, which is what an answer is
            // checked against.
            let waits = status_of(session, pane).ok().flatten() == Some(AgentStatus::Blocked);
            let asked = waits.then(|| screen(session, pane).map(|text| asked(&text)).unwrap_or_default()).filter(|asked| !asked.choices.is_empty());
            println!("{}", serde_json::to_string(&PaneText { text: read_text(&printed), asked })?);
        }
    }
    Ok(())
}

pub fn run(args: &[&str]) -> Result<()> {
    match args {
        ["state"] => println!("{}", serde_json::to_string(&state())?),
        ["watch"] => watch()?,
        ["news"] => {
            // What a linked phone is told about agents, for scripts: a
            // line of JSON when one begins to wait (with what it asks) or
            // finishes, and when one no longer does.
            let mut out = std::io::stdout().lock();
            tell_news(true, |event| serde_json::to_string(&event).is_ok_and(|line| writeln!(out, "{line}").is_ok() && out.flush().is_ok()));
        }
        ["kinds"] => println!("{}", serde_json::to_string(&kinds())?),
        ["places"] => println!("{}", serde_json::to_string(&places())?),
        ["folders", word] => {
            let inside = multiplex_proto::herd::folder_asked(word).map_err(|e| anyhow!("{e}"))?;
            if !Path::new(&inside).is_dir() {
                bail!("{inside} is not a folder on this computer");
            }
            println!("{}", serde_json::to_string(&folders_in(Path::new(&inside), &std::env::var("HOME").unwrap_or_default()))?);
        }
        ["do", rest @ ..] => act(&HerdAction::parse(rest).map_err(|e| anyhow!("{e}"))?)?,
        ["pane", rest @ ..] => crate::pane::run(rest)?,
        _ => bail!("usage: multiplex herd state | watch | news | kinds | places | do <action> | pane <session> <pane>"),
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sessions_are_read_from_herdrs_table() {
        let table = "name                 status   directory                                        socket\n\
                     default              running  /home/sam/.config/herdr                          /home/sam/.config/herdr/herdr.sock\n\
                     night-shift          stopped  /home/sam/.config/herdr/sessions/night-shift     /home/sam/.config/herdr/sessions/night-shift/herdr.sock\n\
                     work.api             running  /home/sam/.config/herdr/sessions/work.api        /home/sam/.config/herdr/sessions/work.api/herdr.sock\n\
                     bad;name             running  /x                                               /x/herdr.sock\n\
                     short                running\n";
        // A name herdr would not allow, and a line that is not a session's, are left out.
        assert_eq!(sessions_in(table).iter().filter_map(|(name, socket)| Some((name.as_str(), socket.as_ref()?.to_str()?))).collect::<Vec<_>>(), [
            ("default", "/home/sam/.config/herdr/herdr.sock"),
            ("work.api", "/home/sam/.config/herdr/sessions/work.api/herdr.sock"),
        ]);
        assert!(sessions_in("").is_empty());
        assert!(sessions_in("name status directory socket\n").is_empty());
        // All of them, in herdr's order; one that is not running has no socket to ask.
        assert_eq!(sessions_in(table).iter().map(|(name, socket)| (name.as_str(), socket.is_some())).collect::<Vec<_>>(), [("default", true), ("night-shift", false), ("work.api", true)]);
        assert_eq!(stopped("night-shift"), Session { name: "night-shift".into(), running: false, workspaces: vec![] });
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
        assert_eq!(build("x", &json!({})), Session { name: "x".into(), running: true, workspaces: vec![] });
    }

    #[test]
    fn a_phone_that_is_not_looking_hears_who_began_to_wait_and_who_no_longer_does() {
        let herd = |states: &[(&str, &str)]| Herd {
            available: true,
            sessions: vec![Session {
                name: "default".into(),
                running: true,
                workspaces: vec![Workspace {
                    id: "w1".into(),
                    label: "api".into(),
                    tabs: vec![Tab {
                        id: "w1:t1".into(),
                        label: "1".into(),
                        panes: states
                            .iter()
                            .map(|(id, status)| Pane {
                                id: (*id).into(),
                                title: format!("title of {id}"),
                                folder: "/home/sam/api".into(),
                                focused: false,
                                agent: (!status.is_empty()).then(|| PaneAgent { name: "claude".into(), status: serde_json::from_value(json!(status)).unwrap() }),
                            })
                            .collect(),
                    }],
                }],
            }],
        };
        let key = |pane: &str| ("default".to_owned(), pane.to_owned());
        let before = statuses(&herd(&[("w1:p1", "working"), ("w1:p2", "blocked"), ("w1:p3", "done"), ("w1:p4", "working"), ("w1:p5", "blocked"), ("w1:p6", "")]));
        assert_eq!(before.len(), 5, "a plain terminal has no state");
        // Just connected: nothing is news, whatever state the agents are in.
        assert_eq!(news(&HashMap::new(), &herd(&[("w1:p1", "blocked")])), News::default());
        // p1 began to wait; p2 was answered; p3 is still done (not news
        // again); p4 finished; p5's pane closed; p6 is a new agent that
        // already waits (listed for the first time: not news).
        let now = herd(&[("w1:p1", "blocked"), ("w1:p2", "working"), ("w1:p3", "done"), ("w1:p4", "done"), ("w1:p6", "blocked")]);
        let told = news(&before, &now);
        assert_eq!(told.wants.iter().map(|a| (a.pane.as_str(), a.status, a.workspace.as_str())).collect::<Vec<_>>(), [("w1:p1", AgentStatus::Blocked, "api"), ("w1:p4", AgentStatus::Done, "api")]);
        assert_eq!(told.settled, [key("w1:p2"), key("w1:p5")]);
        // From waiting to done is news, and nothing is withdrawn: the one
        // notice takes the other's place.
        let told = news(&statuses(&herd(&[("w1:p1", "blocked")])), &herd(&[("w1:p1", "done")]));
        assert_eq!((told.wants.len(), told.settled.len()), (1, 0));
    }

    #[test]
    fn what_herdr_made_is_read_from_its_answer() {
        let tab = r#"{"id":"cli:tab:create","result":{"root_pane":{"pane_id":"w1:p5","tab_id":"w1:t3","workspace_id":"w1"},"tab":{"tab_id":"w1:t3","label":"x"},"type":"tab_created"}}"#;
        assert_eq!(made(tab).unwrap(), Made { workspace: String::new(), tab: "w1:t3".into(), pane: "w1:p5".into() });
        let space = r#"{"id":"cli:workspace:create","result":{"root_pane":{"pane_id":"w4:p1"},"tab":{"tab_id":"w4:t1"},"workspace":{"workspace_id":"w4","label":"api"}}}"#;
        assert_eq!(made(space).unwrap(), Made { workspace: "w4".into(), tab: "w4:t1".into(), pane: "w4:p1".into() });
        assert!(made(r#"{"result":{"tab":{"tab_id":"w1:t3"}}}"#).is_err());
        assert!(made("not json").is_err());
    }

    #[test]
    fn the_kinds_of_agent_are_read_from_herdrs_own_words() {
        let help = "herdr agent commands:\n  herdr agent list\n  targets accept unique agent names\n  kinds: pi|claude|codex|not a kind|gemini\n";
        assert_eq!(kinds_in(help), ["pi", "claude", "codex", "gemini"]);
        assert!(kinds_in("no such line").is_empty());
        // Startable means: its program is in a folder herdr looks in.
        let bin = tempfile::tempdir().unwrap();
        std::fs::write(bin.path().join("codex"), b"#!/bin/sh\n").unwrap();
        std::fs::create_dir(bin.path().join("pi")).unwrap();
        let folders = path_in(format!("HOME=/home/sam\0PATH=/usr/bin:{}\0TERM=xterm\0", bin.path().display()).as_bytes());
        assert_eq!(folders, [PathBuf::from("/usr/bin"), bin.path().to_path_buf()]);
        assert_eq!(found(kinds_in(help), &folders), [("codex".to_owned(), bin.path().join("codex"))], "a folder of that name is not a program");
        assert!(path_in(b"HOME=/home/sam\0").is_empty() && path_in(b"").is_empty());
        // A stand-in of mise is a link to mise itself; a program or another link is not.
        let mise = bin.path().join("mise");
        std::fs::write(&mise, b"").unwrap();
        std::os::unix::fs::symlink(&mise, bin.path().join("amp")).unwrap();
        std::os::unix::fs::symlink(bin.path().join("codex"), bin.path().join("gemini")).unwrap();
        assert!(is_mise_shim(&bin.path().join("amp")));
        assert!(!is_mise_shim(&bin.path().join("codex")) && !is_mise_shim(&bin.path().join("gemini")) && !is_mise_shim(&bin.path().join("none")));
        // A name herdr takes: starts with a letter, at most 32 of a-z, 0-9, - and _.
        let name = agent_name("claude", "3FA9c0de11");
        assert_eq!(name, "claude-39c0", "only what herdr takes in a name is kept");
        let longest = agent_name(&"k".repeat(24), "abcdef");
        assert!(longest.len() <= 32 && longest.starts_with('k'));
    }

    #[test]
    fn folders_for_a_new_workspace_are_offered_best_first_and_once() {
        assert_eq!(shown("/home/sam/code/api", "/home/sam"), "~/code/api");
        assert_eq!(shown("/home/sam", "/home/sam/"), "~");
        assert_eq!(shown("/home/samuel/x", "/home/sam"), "/home/samuel/x", "another user's folder is not this one's");
        assert_eq!(shown("/srv/site", "/home/sam"), "/srv/site");
        assert_eq!(shown("/srv/site", ""), "/srv/site");
        let places = offered(
            vec!["/home/sam/code/api".into(), "/home/sam".into(), "relative/path".into()],
            vec!["/home/sam/code/api/".into(), "/srv/site".into(), "/".into()],
            vec!["/home/sam/code/web".into(), "/srv/site".into()],
            "/home/sam",
        );
        assert_eq!(places.iter().map(|p| p.shown.as_str()).collect::<Vec<_>>(), ["~/code/api", "/srv/site", "~/code/web"]);
        assert_eq!(places[0].path, "/home/sam/code/api");
        assert_eq!(offered((0..200).map(|i| format!("/x/{i}")).collect(), vec![], vec![], "/home/sam").len(), 60);
        // Last come the two folders every other one can be walked to from.
        assert_eq!(starting_points("/home/sam/").iter().map(|p| (p.path.as_str(), p.shown.as_str())).collect::<Vec<_>>(), [("/home/sam", "~"), ("/", "/")]);
        assert_eq!(starting_points("").len(), 1, "without a home folder there is still the root");
    }

    #[test]
    fn projects_are_folders_with_a_git_in_them_up_to_one_level_in() {
        let home = tempfile::tempdir().unwrap();
        let make = |path: &str| std::fs::create_dir_all(home.path().join(path)).unwrap();
        make("api/.git");
        make("code/web/.git");
        make("code/notes");
        make("code/deep/inner/.git");
        make(".hidden/.git");
        make("code/.cache/.git");
        make("music");
        let found = projects_under(home.path());
        let names: Vec<String> = found.iter().map(|path| path.strip_prefix(&format!("{}/", home.path().display())).unwrap().to_owned()).collect();
        assert_eq!(names, ["api", "code/web"]);
        assert!(projects_under(&home.path().join("none")).is_empty());
        // Looking inside one folder: its folders by name, projects marked, hidden ones left out.
        std::fs::write(home.path().join("code/a file"), b"").unwrap();
        make("code/Zeta");
        let inside = folders_in(&home.path().join("code"), &home.path().to_string_lossy());
        assert_eq!(inside.iter().map(|p| (p.shown.as_str(), p.project)).collect::<Vec<_>>(), [("~/code/deep", false), ("~/code/notes", false), ("~/code/web", true), ("~/code/Zeta", false)]);
        assert!(folders_in(&home.path().join("none"), "").is_empty());
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
