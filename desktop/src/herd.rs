//! `multiplex herd`: everything Multiplex's session server keeps running
//! here (see `sessions.rs`), for the phone.
//!
//! `state` prints it once; `watch` prints it and then again whenever it
//! changes, told by the server; `news` says what a phone that is not
//! looking wants to hear; `do` passes on what the phone asks: text for an
//! agent, keys for a terminal, its text, a new one, an answer; `pane`
//! puts one terminal into the terminal the command runs in.
//!
//! (The command's name and the word "pane" are from the program this
//! was first built on; the phone's app still says them.)

use std::collections::{BTreeSet, HashMap};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

use anyhow::{anyhow, bail, Result};
use multiplex_proto::agents::{Agent, AgentStatus};
use multiplex_proto::asked::{asked, keys_for, may_answer, Asked};
use multiplex_proto::asked::Reply;
use multiplex_proto::herd::{clean_folder, Herd, HerdAction, HerdAgent, Kind, Made, PaneText, Place};
use multiplex_proto::share::LinkEvent;

use crate::sessions::{self, read_frame, Request, AGENTS, SESSION};

/// Asks the session server.
fn server(request: &Request) -> Result<sessions::Answer> {
    Ok(sessions::ask(&sessions::socket_path(), request)?.0)
}

/// The one session there is; any other name is nobody's.
fn ours(session: &str) -> Result<()> {
    if session == SESSION {
        Ok(())
    } else {
        bail!("There is no session {session}.")
    }
}

pub fn state() -> Herd {
    let session = server(&Request::State).ok().and_then(|answer| answer.state);
    Herd { available: true, sessions: session.into_iter().collect() }
}

/// `multiplex herd watch`: the herd now, and again whenever it changes.
pub fn watch() -> Result<()> {
    // An empty line now and then, so a phone that hung up is noticed.
    const ALIVE: Duration = Duration::from_secs(10);
    let mut out = std::io::stdout().lock();
    let mut said_at = std::time::Instant::now();
    follow(|herd| {
        match herd {
            Some(herd) => writeln!(out, "{}", serde_json::to_string(herd)?)?,
            None if said_at.elapsed() >= ALIVE => writeln!(out)?,
            None => return Ok(true),
        }
        out.flush()?;
        said_at = std::time::Instant::now();
        Ok(true)
    })
}

/// Follows the herd: `on` gets it now and again whenever it changes, and
/// nothing (`None`) about once a second in between, so it can do what it
/// does by the clock. It ends when `on` says false or fails. A server
/// that goes away is waited for and followed again.
pub fn follow(mut on: impl FnMut(Option<&Herd>) -> Result<bool>) -> Result<()> {
    let mut last: Option<Herd> = None;
    loop {
        let Ok((first, mut stream)) = sessions::ask(&sessions::socket_path(), &Request::Watch) else {
            if !on(None)? {
                return Ok(());
            }
            std::thread::sleep(Duration::from_secs(1));
            continue;
        };
        stream.set_read_timeout(Some(Duration::from_secs(1)))?;
        let mut next = first.state;
        loop {
            if let Some(session) = next.take() {
                let herd = Herd { available: true, sessions: vec![session] };
                let changed = last.as_ref() != Some(&herd);
                if !on(changed.then_some(&herd))? {
                    return Ok(());
                }
                last = Some(herd);
            }
            match read_frame(&mut stream) {
                Ok((b'S', bytes)) => next = serde_json::from_slice(&bytes).ok(),
                Ok(_) => {}
                Err(err) if matches!(err.kind(), std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut) => {
                    if !on(None)? {
                        return Ok(());
                    }
                }
                // The server went away.
                Err(_) => break,
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

/// What a terminal shows now, and what the agent in it is doing (None:
/// no agent is there).
fn screen(session: &str, pane: &str) -> Result<(String, Option<AgentStatus>)> {
    ours(session)?;
    let answer = server(&Request::Read { id: pane.to_owned(), lines: 0 })?;
    Ok((answer.text.unwrap_or_default(), answer.status))
}

/// What an agent that has just begun to wait asks by choice. Its screen
/// may be a moment behind its state, so a screen without choices is read
/// once more before it is taken to ask in words.
fn asked_soon(session: &str, pane: &str) -> Asked {
    let read = || screen(session, pane).map(|(text, _)| asked(&text)).unwrap_or_default();
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

/// Where agents' programs are looked for: this command's own path, and
/// the folders version managers and installers put programs in, which a
/// command asked over SSH does not have on its path.
fn program_folders() -> Vec<PathBuf> {
    let mut folders: Vec<PathBuf> = std::env::var_os("PATH").map(|path| std::env::split_paths(&path).collect()).unwrap_or_default();
    if let Some(home) = std::env::var_os("HOME").map(PathBuf::from) {
        folders.extend([".local/bin", ".local/share/mise/shims", ".cargo/bin", ".bun/bin", ".npm-global/bin", ".claude/local"].map(|sub| home.join(sub)));
    }
    folders.push(PathBuf::from("/usr/local/bin"));
    folders
}

/// The agents that can be started here, and for each whether its program
/// is really there. Omarchy keeps most agents as tools that install
/// themselves on first use (seen: starting one began a 139 MB download);
/// those are told apart by asking mise where the tool is, which it can
/// only say for one that is installed.
fn kinds() -> Vec<Kind> {
    let found = found(AGENTS.iter().map(|agent| (*agent).to_owned()).collect(), &program_folders());
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
/// goes to, then those terminals are open in, then projects. Each once,
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

fn made(answer: &sessions::Answer) -> Made {
    Made { workspace: answer.workspace.clone(), tab: answer.tab.clone(), pane: answer.id.clone() }
}

/// A new terminal at a phone's size; whoever sits in front of it gives it
/// their own.
fn new_terminal(cwd: &str, workspace: &str, label: &str, fresh: bool) -> Result<Made> {
    Ok(made(&server(&Request::New { cwd: cwd.to_owned(), command: Vec::new(), cols: 80, rows: 24, workspace: workspace.to_owned(), label: label.to_owned(), fresh, env: Vec::new(), window: false })?))
}

fn act(action: &HerdAction) -> Result<()> {
    match action {
        HerdAction::NewTab { session, workspace, label: _ } => {
            ours(session)?;
            // In the workspace's own folder.
            let folder = state().sessions.iter().flat_map(|s| &s.workspaces).find(|w| &w.id == workspace).and_then(|w| w.tabs.first()).and_then(|t| t.panes.first()).map(|p| p.folder.clone());
            let folder = folder.ok_or_else(|| anyhow!("There is no workspace {workspace}."))?;
            println!("{}", serde_json::to_string(&new_terminal(&folder, workspace, "", false)?)?);
        }
        HerdAction::NewWorkspace { session, folder, label } => {
            ours(session)?;
            println!("{}", serde_json::to_string(&new_terminal(folder, "", label, true)?)?);
        }
        HerdAction::Start { session, pane, kind } => {
            ours(session)?;
            // Typed at the terminal's prompt, as its owner would.
            server(&Request::Text { id: pane.clone(), text: kind.clone() })?;
        }
        HerdAction::ClosePane { session, pane } => {
            ours(session)?;
            server(&Request::Kill { id: pane.clone() })?;
        }
        HerdAction::CloseTab { session, tab } => {
            ours(session)?;
            // A tab holds one terminal, whose number it shares.
            server(&Request::Kill { id: tab.replacen(":t", ":p", 1) })?;
        }
        HerdAction::Prompt { session, pane, text } => {
            ours(session)?;
            server(&Request::Text { id: pane.clone(), text: text.clone() })?;
        }
        HerdAction::Keys { session, pane, keys } => {
            ours(session)?;
            server(&Request::Keys { id: pane.clone(), keys: keys.clone() })?;
        }
        HerdAction::Answer { session, pane, mark, with } => {
            // Only while it still asks what the answer was given to.
            let (text, status) = screen(session, pane)?;
            let now = if status == Some(AgentStatus::Blocked) { asked(&text) } else { Asked::default() };
            may_answer(status, &now, mark, with).map_err(|why| anyhow!(why))?;
            match with {
                Reply::Choice(key) => {
                    let keys = keys_for(&now, key).ok_or_else(|| anyhow!("That is not one of its choices. Nothing was sent."))?;
                    server(&Request::Keys { id: pane.clone(), keys })?;
                }
                Reply::Text(text) => {
                    server(&Request::Text { id: pane.clone(), text: text.clone() })?;
                }
            }
        }
        HerdAction::Read { session, pane, lines } => {
            ours(session)?;
            let answer = server(&Request::Read { id: pane.clone(), lines: *lines })?;
            // With what its agent asks by choice, if it waits on one: read
            // off the screen as it stands, which is what an answer is
            // checked against.
            let waits = answer.status == Some(AgentStatus::Blocked);
            let asked = waits.then(|| screen(session, pane).map(|(text, _)| asked(&text)).unwrap_or_default()).filter(|asked| !asked.choices.is_empty());
            println!("{}", serde_json::to_string(&PaneText { text: answer.text.unwrap_or_default(), asked })?);
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
        ["pane", session, pane, rest @ ..] => {
            ours(session)?;
            // One terminal in this one: Ctrl+\ leaves it running.
            if let Some(code) = sessions::attach(&sessions::socket_path(), pane, true, rest.contains(&"--watch"))? {
                std::process::exit(code);
            }
        }
        _ => bail!("usage: multiplex herd state | watch | news | kinds | places | do <action> | pane <session> <pane>"),
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use multiplex_proto::herd::{Pane, PaneAgent, Session, Tab, Workspace};
    use serde_json::json;

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
}
