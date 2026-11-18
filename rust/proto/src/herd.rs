//! The herd: everything herdr (a terminal workspace manager for coding
//! agents) keeps running on the computer, as the phone sees it. Sessions
//! hold workspaces, workspaces hold tabs, tabs hold panes, and a pane is a
//! terminal that may have an agent in it.
//!
//! The computer prints the whole of it as one line of JSON, and again
//! whenever something changes (`multiplex herd watch`); the phone asks for
//! changes with `multiplex herd do …`. Everything the phone sends is
//! checked here before it is made into a command line.

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use serde::{Deserialize, Serialize};

use crate::agents::{clean_session_name, AgentStatus};
use crate::asked::{clean_mark, Reply};
use crate::share::SHARE_COMMAND;
use crate::ProtoError;

/// The longest text sent to an agent in one go.
pub const MAX_PROMPT: usize = 32 * 1024;
/// The most lines of a pane's earlier output asked for at once.
pub const MAX_LINES: u32 = 2000;

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct Herd {
    /// False when herdr is not installed on the computer.
    #[serde(default = "yes")]
    pub available: bool,
    #[serde(default)]
    pub sessions: Vec<Session>,
}

fn yes() -> bool {
    true
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct Session {
    pub name: String,
    /// False for a session herdr remembers but does not run now: its
    /// terminals ended with it, and it starts again when it is opened.
    #[serde(default = "yes", skip_serializing_if = "is_true")]
    pub running: bool,
    #[serde(default)]
    pub workspaces: Vec<Workspace>,
}

impl Default for Session {
    fn default() -> Self {
        Session { name: String::new(), running: true, workspaces: Vec::new() }
    }
}

fn is_true(value: &bool) -> bool {
    *value
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct Workspace {
    /// herdr's id for it ("w1").
    pub id: String,
    #[serde(default)]
    pub label: String,
    #[serde(default)]
    pub tabs: Vec<Tab>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct Tab {
    /// "w1:t1".
    pub id: String,
    #[serde(default)]
    pub label: String,
    #[serde(default)]
    pub panes: Vec<Pane>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct Pane {
    /// "w1:p1".
    pub id: String,
    /// What its terminal's title says.
    #[serde(default)]
    pub title: String,
    /// The folder it is in, in full.
    #[serde(default)]
    pub folder: String,
    /// The pane herdr's own screen has in focus.
    #[serde(default)]
    pub focused: bool,
    /// The agent running in it; none in a plain terminal.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent: Option<PaneAgent>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct PaneAgent {
    /// "Claude", "codex".
    pub name: String,
    #[serde(default)]
    pub status: AgentStatus,
}

/// One agent with where it is, for a list across sessions.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HerdAgent {
    pub session: String,
    pub workspace: String,
    pub tab: String,
    pub pane: String,
    pub name: String,
    pub status: AgentStatus,
    pub title: String,
    /// The last part of the folder's path.
    pub folder: String,
}

/// Where an agent stands in the inbox: those that need the user first,
/// then those that finished, then the busy, then the idle.
pub fn rank(status: AgentStatus) -> u8 {
    match status {
        AgentStatus::Blocked => 0,
        AgentStatus::Done => 1,
        AgentStatus::Working => 2,
        AgentStatus::Idle => 3,
        AgentStatus::Unknown => 4,
    }
}

/// The last part of a path, as a folder's short name.
pub fn folder_name(path: &str) -> &str {
    path.trim_end_matches('/').rsplit('/').next().unwrap_or_default()
}

impl Herd {
    /// What a computer without herdr says.
    pub fn missing() -> Self {
        Herd { available: false, sessions: Vec::new() }
    }

    /// Every agent, in inbox order; among equals, in herdr's own order.
    pub fn agents(&self) -> Vec<HerdAgent> {
        let mut agents: Vec<HerdAgent> = Vec::new();
        for session in &self.sessions {
            for workspace in &session.workspaces {
                for tab in &workspace.tabs {
                    for pane in &tab.panes {
                        if let Some(agent) = &pane.agent {
                            agents.push(HerdAgent {
                                session: session.name.clone(),
                                workspace: workspace.label.clone(),
                                tab: tab.label.clone(),
                                pane: pane.id.clone(),
                                name: agent.name.clone(),
                                status: agent.status,
                                title: pane.title.clone(),
                                folder: folder_name(&pane.folder).to_owned(),
                            });
                        }
                    }
                }
            }
        }
        // A stable sort: equals keep the order herdr lists them in.
        agents.sort_by_key(|agent| rank(agent.status));
        agents
    }

    /// How many agents wait for the user.
    pub fn waiting(&self) -> usize {
        self.agents().iter().filter(|agent| agent.status == AgentStatus::Blocked).count()
    }
}

/// herdr's id for a pane ("w1:p12"), or a tab ("w1:t2"), or a workspace
/// ("w3"): exactly that shape, nothing a shell could read differently.
fn clean_id(id: &str, kind: Option<char>) -> Result<String, ProtoError> {
    let number = |text: &str| !text.is_empty() && text.len() <= 9 && text.bytes().all(|b| b.is_ascii_digit());
    let ok = match (id.split_once(':'), kind) {
        (None, None) => id.strip_prefix('w').is_some_and(number),
        (Some((workspace, rest)), Some(kind)) => workspace.strip_prefix('w').is_some_and(number) && rest.strip_prefix(kind).is_some_and(number),
        _ => false,
    };
    if ok {
        Ok(id.to_owned())
    } else {
        Err(ProtoError::Invalid("this is not one of herdr's ids"))
    }
}

pub fn clean_pane_id(id: &str) -> Result<String, ProtoError> {
    clean_id(id, Some('p'))
}

pub fn clean_tab_id(id: &str) -> Result<String, ProtoError> {
    clean_id(id, Some('t'))
}

pub fn clean_workspace_id(id: &str) -> Result<String, ProtoError> {
    clean_id(id, None)
}

/// A key by herdr's name for it: "esc", "enter", "ctrl+c", "up", "1".
pub fn clean_key(key: &str) -> Result<String, ProtoError> {
    let ok = !key.is_empty() && key.len() <= 24 && key.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || matches!(b, b'+' | b'-' | b'_'));
    if ok {
        Ok(key.to_owned())
    } else {
        Err(ProtoError::Invalid("this is not a key's name"))
    }
}

/// A kind of agent by herdr's name for it, which is also the name of its
/// program: "claude", "codex".
pub fn clean_kind(kind: &str) -> Result<String, ProtoError> {
    let ok = !kind.is_empty() && kind.len() <= 24 && kind.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || matches!(b, b'-' | b'_'));
    if ok {
        Ok(kind.to_owned())
    } else {
        Err(ProtoError::Invalid("this is not a kind of agent"))
    }
}

/// A name for a tab or a workspace: one line of up to 48 characters.
pub fn clean_label(label: &str) -> Result<String, ProtoError> {
    if label.chars().any(char::is_control) {
        return Err(ProtoError::Invalid("a name is one line of ordinary characters"));
    }
    let tidy = label.split_whitespace().collect::<Vec<_>>().join(" ");
    if tidy.is_empty() || tidy.chars().count() > 48 {
        return Err(ProtoError::Invalid("a name is 1 to 48 characters"));
    }
    Ok(tidy)
}

/// A folder on the computer: a full path, one line, no way up out of it.
pub fn clean_folder(folder: &str) -> Result<String, ProtoError> {
    let ok = folder.starts_with('/') && folder.len() <= 1024 && !folder.chars().any(char::is_control) && !folder.split('/').any(|part| part == "..");
    if ok {
        Ok(folder.to_owned())
    } else {
        Err(ProtoError::Invalid("a folder is given by its full path"))
    }
}

/// Something the phone asks of the herd.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HerdAction {
    /// Give an agent this text and press Enter, as one piece.
    Prompt { session: String, pane: String, text: String },
    /// Press keys in a pane: Esc, a choice's number, Ctrl+C.
    Keys { session: String, pane: String, keys: Vec<String> },
    /// Print a pane's recent output.
    Read { session: String, pane: String, lines: u32 },
    /// A new tab in a workspace, with a terminal in it. An empty label
    /// leaves the naming to herdr.
    NewTab { session: String, workspace: String, label: String },
    /// A new workspace in a folder, with a tab and a terminal in it.
    NewWorkspace { session: String, folder: String, label: String },
    /// Start an agent of this kind in a pane that sits at its prompt.
    Start { session: String, pane: String, kind: String },
    ClosePane { session: String, pane: String },
    CloseTab { session: String, tab: String },
    /// Answer what an agent asked, if it still asks it: `mark` is the
    /// mark of the question the answer was given to (empty when it was
    /// not a choice). See [`crate::asked::may_answer`].
    Answer { session: String, pane: String, mark: String, with: Reply },
}

fn lines(text: &str) -> Result<u32, ProtoError> {
    match text.parse::<u32>() {
        Ok(n) if (1..=MAX_LINES).contains(&n) => Ok(n),
        _ => Err(ProtoError::Invalid("a pane's output is asked for in 1 to 2000 lines")),
    }
}

/// Text travels as base64, so no character of it means anything to a shell.
fn packed(text: &str) -> String {
    URL_SAFE_NO_PAD.encode(text.as_bytes())
}

fn unpacked(packed: &str) -> Result<String, ProtoError> {
    let bytes = URL_SAFE_NO_PAD.decode(packed).map_err(|_| ProtoError::Invalid("this text did not arrive whole"))?;
    let text = String::from_utf8(bytes).map_err(|_| ProtoError::Invalid("this text did not arrive whole"))?;
    if text.is_empty() || text.len() > MAX_PROMPT {
        return Err(ProtoError::Invalid("text for an agent is 1 to 32768 bytes"));
    }
    Ok(text)
}

fn quoted(arg: &str) -> String {
    format!("'{}'", arg.replace('\'', r"'\''"))
}

impl HerdAction {
    /// The words after `multiplex herd do`.
    pub fn to_args(&self) -> Vec<String> {
        match self {
            HerdAction::Prompt { session, pane, text } => vec!["prompt".to_owned(), session.clone(), pane.clone(), packed(text)],
            HerdAction::Keys { session, pane, keys } => {
                let mut args = vec!["keys".to_owned(), session.clone(), pane.clone()];
                args.extend(keys.iter().cloned());
                args
            }
            HerdAction::Read { session, pane, lines } => vec!["read".to_owned(), session.clone(), pane.clone(), lines.to_string()],
            HerdAction::NewTab { session, workspace, label } => {
                let mut args = vec!["new-tab".to_owned(), session.clone(), workspace.clone()];
                if !label.is_empty() {
                    args.push(packed(label));
                }
                args
            }
            HerdAction::NewWorkspace { session, folder, label } => {
                let mut args = vec!["new-workspace".to_owned(), session.clone(), packed(folder)];
                if !label.is_empty() {
                    args.push(packed(label));
                }
                args
            }
            HerdAction::Start { session, pane, kind } => vec!["start".to_owned(), session.clone(), pane.clone(), kind.clone()],
            HerdAction::ClosePane { session, pane } => vec!["close-pane".to_owned(), session.clone(), pane.clone()],
            HerdAction::CloseTab { session, tab } => vec!["close-tab".to_owned(), session.clone(), tab.clone()],
            HerdAction::Answer { session, pane, mark, with } => {
                // A dash stands for "it was not a choice": no word is empty.
                let mut args = vec!["answer".to_owned(), session.clone(), pane.clone(), if mark.is_empty() { "-".to_owned() } else { mark.clone() }];
                match with {
                    Reply::Choice(key) => args.extend(["choice".to_owned(), key.clone()]),
                    Reply::Text(text) => args.extend(["text".to_owned(), packed(text)]),
                }
                args
            }
        }
    }

    /// Reads the words after `multiplex herd do`. Everything is checked.
    pub fn parse(args: &[&str]) -> Result<Self, ProtoError> {
        Ok(match args {
            ["prompt", session, pane, text] => HerdAction::Prompt { session: clean_session_name(session)?, pane: clean_pane_id(pane)?, text: unpacked(text)? },
            ["keys", session, pane, keys @ ..] if !keys.is_empty() && keys.len() <= 16 => {
                HerdAction::Keys { session: clean_session_name(session)?, pane: clean_pane_id(pane)?, keys: keys.iter().map(|key| clean_key(key)).collect::<Result<_, _>>()? }
            }
            ["read", session, pane, count] => HerdAction::Read { session: clean_session_name(session)?, pane: clean_pane_id(pane)?, lines: lines(count)? },
            ["new-tab", session, workspace] => HerdAction::NewTab { session: clean_session_name(session)?, workspace: clean_workspace_id(workspace)?, label: String::new() },
            ["new-tab", session, workspace, label] => HerdAction::NewTab { session: clean_session_name(session)?, workspace: clean_workspace_id(workspace)?, label: clean_label(&unpacked(label)?)? },
            ["new-workspace", session, folder] => HerdAction::NewWorkspace { session: clean_session_name(session)?, folder: clean_folder(&unpacked(folder)?)?, label: String::new() },
            ["new-workspace", session, folder, label] => {
                HerdAction::NewWorkspace { session: clean_session_name(session)?, folder: clean_folder(&unpacked(folder)?)?, label: clean_label(&unpacked(label)?)? }
            }
            ["start", session, pane, kind] => HerdAction::Start { session: clean_session_name(session)?, pane: clean_pane_id(pane)?, kind: clean_kind(kind)? },
            ["close-pane", session, pane] => HerdAction::ClosePane { session: clean_session_name(session)?, pane: clean_pane_id(pane)? },
            ["close-tab", session, tab] => HerdAction::CloseTab { session: clean_session_name(session)?, tab: clean_tab_id(tab)? },
            ["answer", session, pane, mark, how, what] => HerdAction::Answer {
                session: clean_session_name(session)?,
                pane: clean_pane_id(pane)?,
                mark: clean_mark(if *mark == "-" { "" } else { mark })?,
                with: match *how {
                    "choice" if what.len() == 1 && what.as_bytes()[0].is_ascii_digit() => Reply::Choice((*what).to_owned()),
                    "text" => Reply::Text(unpacked(what)?),
                    _ => return Err(ProtoError::Invalid("an agent is answered with a choice or with text")),
                },
            },
            _ => return Err(ProtoError::Invalid("this is not something the herd can be asked to do")),
        })
    }

    /// The command the phone runs on the computer, checked first.
    pub fn command_line(&self) -> Result<String, ProtoError> {
        let args = self.to_args();
        let refs: Vec<&str> = args.iter().map(String::as_str).collect();
        let checked = Self::parse(&refs)?.to_args();
        Ok(format!("{SHARE_COMMAND} herd do {}", checked.iter().map(|a| quoted(a)).collect::<Vec<_>>().join(" ")))
    }
}

/// Prints the herd once, as one line of JSON.
pub fn state_command() -> String {
    format!("{SHARE_COMMAND} herd state")
}

/// Prints the herd now, and again whenever something in it changes.
pub fn watch_command() -> String {
    format!("{SHARE_COMMAND} herd watch")
}

/// What to type in a terminal on the computer to sit in front of one
/// pane, at that terminal's own size. Plain words, so it is the same in
/// whichever shell the terminal runs.
pub fn pane_command(session: &str, pane: &str) -> Result<String, ProtoError> {
    Ok(format!("multiplex herd pane {} {}", clean_session_name(session)?, clean_pane_id(pane)?))
}

/// Reads a line the state or watch command printed.
pub fn parse_state(line: &str) -> Result<Herd, ProtoError> {
    serde_json::from_str(line.trim()).map_err(|_| ProtoError::Damaged)
}

/// What making a tab or a workspace prints: herdr's ids for what was
/// made, so the phone can go straight to the new terminal.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct Made {
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub workspace: String,
    pub tab: String,
    pub pane: String,
}

/// Reads it, and takes only ids that are ids.
pub fn parse_made(line: &str) -> Result<Made, ProtoError> {
    let made: Made = serde_json::from_str(line.trim()).map_err(|_| ProtoError::Damaged)?;
    if !made.workspace.is_empty() {
        clean_workspace_id(&made.workspace)?;
    }
    clean_tab_id(&made.tab)?;
    clean_pane_id(&made.pane)?;
    Ok(made)
}

/// Prints the kinds of agent that can be started on the computer: those
/// herdr knows whose program is installed, as a JSON list.
pub fn kinds_command() -> String {
    format!("{SHARE_COMMAND} herd kinds")
}

/// A kind of agent the computer can start.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct Kind {
    /// herdr's name for it, which is also its program's.
    pub kind: String,
    /// False for one whose program installs itself the first time it is
    /// run (a download, on a computer that keeps its tools that way).
    #[serde(default = "yes")]
    pub installed: bool,
}

/// Reads that list; what is not a kind's name is left out. Those that are
/// installed come first, each group in the computer's order.
pub fn parse_kinds(line: &str) -> Result<Vec<Kind>, ProtoError> {
    let kinds: Vec<Kind> = serde_json::from_str(line.trim()).map_err(|_| ProtoError::Damaged)?;
    let mut kinds: Vec<Kind> = kinds.into_iter().filter(|kind| clean_kind(&kind.kind).is_ok()).take(64).collect();
    kinds.sort_by_key(|kind| !kind.installed);
    Ok(kinds)
}

/// A folder on the computer that a new workspace could be opened in.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct Place {
    /// Its full path.
    pub path: String,
    /// The path as people write it, with `~` for the home folder.
    pub shown: String,
    /// It holds a project (a `.git` is in it).
    #[serde(default)]
    pub project: bool,
}

/// Prints folders worth offering for a new workspace: those the user
/// goes to, those herdr's panes are in, and projects in the home folder.
pub fn places_command() -> String {
    format!("{SHARE_COMMAND} herd places")
}

/// Prints the folders inside a folder, for walking to the one wanted.
pub fn folders_command(inside: &str) -> Result<String, ProtoError> {
    Ok(format!("{SHARE_COMMAND} herd folders {}", quoted(&packed(&clean_folder(inside)?))))
}

/// The folder asked about, from the word after `herd folders`.
pub fn folder_asked(word: &str) -> Result<String, ProtoError> {
    clean_folder(&unpacked(word)?)
}

/// Reads that list; what is not a folder's full path is left out.
pub fn parse_places(line: &str) -> Result<Vec<Place>, ProtoError> {
    let places: Vec<Place> = serde_json::from_str(line.trim()).map_err(|_| ProtoError::Damaged)?;
    Ok(places.into_iter().filter(|place| clean_folder(&place.path).is_ok() && !place.shown.chars().any(char::is_control) && place.shown.len() <= 1100).take(400).collect())
}

/// What `herd do read` prints: the pane's recent output, one line of JSON.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct PaneText {
    pub text: String,
    /// What the agent in it asks by choice, when it waits on one.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub asked: Option<crate::asked::Asked>,
}

pub fn parse_text(line: &str) -> Result<PaneText, ProtoError> {
    serde_json::from_str(line.trim()).map_err(|_| ProtoError::Damaged)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pane(id: &str, agent: Option<(&str, AgentStatus)>, folder: &str) -> Pane {
        Pane { id: id.to_owned(), title: format!("title of {id}"), folder: folder.to_owned(), focused: false, agent: agent.map(|(name, status)| PaneAgent { name: name.to_owned(), status }) }
    }

    fn herd() -> Herd {
        Herd {
            available: true,
            sessions: vec![
                Session {
                    name: "default".into(),
                    running: true,
                    workspaces: vec![Workspace {
                        id: "w1".into(),
                        label: "api".into(),
                        tabs: vec![
                            Tab { id: "w1:t1".into(), label: "1".into(), panes: vec![pane("w1:p1", Some(("Claude", AgentStatus::Working)), "/home/sam/code/api/"), pane("w1:p2", None, "/home/sam")] },
                            Tab { id: "w1:t2".into(), label: "review".into(), panes: vec![pane("w1:p3", Some(("codex", AgentStatus::Blocked)), "/srv/web")] },
                        ],
                    }],
                },
                Session { name: "night".into(), running: true, workspaces: vec![Workspace { id: "w1".into(), label: "site".into(), tabs: vec![Tab { id: "w1:t1".into(), label: "1".into(), panes: vec![pane("w1:p1", Some(("Claude", AgentStatus::Done)), "/"), pane("w1:p4", Some(("pi", AgentStatus::Blocked)), "")] }] }] },
            ],
        }
    }

    #[test]
    fn the_herd_survives_the_trip_as_one_line() {
        let line = serde_json::to_string(&herd()).unwrap();
        assert!(!line.contains('\n'));
        assert_eq!(parse_state(&format!("{line}\n")).unwrap(), herd());
        // A plain terminal says nothing about an agent.
        assert!(line.contains(r#"{"id":"w1:p2","title":"title of w1:p2","folder":"/home/sam","focused":false}"#), "{line}");
        // Fields a newer computer adds, and ones an older one lacks, do no harm.
        let other = parse_state(r#"{"sessions":[{"name":"a","new":1,"workspaces":[{"id":"w1","tabs":[{"id":"w1:t1","panes":[{"id":"w1:p1","agent":{"name":"x","status":"thinking"}}]}]}]}]}"#).unwrap();
        assert!(other.available);
        assert_eq!(other.sessions[0].workspaces[0].tabs[0].panes[0].agent.as_ref().unwrap().status, AgentStatus::Unknown);
        assert!(parse_state("not json").is_err());
        // A session that is not running says so, and has nothing in it; a
        // running one says nothing about it (an older computer never does).
        let stopped = Herd { available: true, sessions: vec![Session { name: "old".into(), running: false, workspaces: vec![] }, Session { name: "now".into(), ..Session::default() }] };
        let line = serde_json::to_string(&stopped).unwrap();
        assert_eq!(line, r#"{"available":true,"sessions":[{"name":"old","running":false,"workspaces":[]},{"name":"now","workspaces":[]}]}"#);
        assert_eq!(parse_state(&line).unwrap(), stopped);
        assert!(parse_state(r#"{"sessions":[{"name":"a"}]}"#).unwrap().sessions[0].running);
        // A computer without herdr.
        let none = parse_state(&serde_json::to_string(&Herd::missing()).unwrap()).unwrap();
        assert!(!none.available && none.sessions.is_empty());
    }

    #[test]
    fn the_inbox_puts_who_needs_the_user_first() {
        let agents = herd().agents();
        assert_eq!(agents.iter().map(|a| (a.session.as_str(), a.pane.as_str(), a.status)).collect::<Vec<_>>(), [
            ("default", "w1:p3", AgentStatus::Blocked),
            ("night", "w1:p4", AgentStatus::Blocked),
            ("night", "w1:p1", AgentStatus::Done),
            ("default", "w1:p1", AgentStatus::Working),
        ]);
        assert_eq!(herd().waiting(), 2);
        // Where each is, in words for a list.
        assert_eq!((agents[0].workspace.as_str(), agents[0].tab.as_str(), agents[0].name.as_str(), agents[0].folder.as_str()), ("api", "review", "codex", "web"));
        assert_eq!(agents[3].folder, "api");
        assert_eq!((agents[2].folder.as_str(), agents[1].folder.as_str()), ("", ""));
        assert!(Herd::default().agents().is_empty());
        assert!([AgentStatus::Blocked, AgentStatus::Done, AgentStatus::Working, AgentStatus::Idle, AgentStatus::Unknown].windows(2).all(|pair| rank(pair[0]) < rank(pair[1])));
    }

    #[test]
    fn ids_are_exactly_herdrs_shape() {
        for good in ["w1:p1", "w12:p345"] {
            assert_eq!(clean_pane_id(good).unwrap(), good);
        }
        for bad in ["", "w1", "w1:t1", "p1", "w1:p", "w:p1", "w1:p1 ", "w1:p1;ls", "W1:P1", "w1:p-1", "w1:p1:p2", "w1:p1234567890", "w1:p١"] {
            assert!(clean_pane_id(bad).is_err(), "{bad:?}");
        }
        assert_eq!(clean_tab_id("w3:t2").unwrap(), "w3:t2");
        assert!(clean_tab_id("w3:p2").is_err());
        assert_eq!(clean_workspace_id("w7").unwrap(), "w7");
        assert!(clean_workspace_id("w7:t1").is_err() && clean_workspace_id("7").is_err() && clean_workspace_id("w").is_err());
        for good in ["esc", "enter", "ctrl+c", "up", "1", "shift+tab", "page_down", "f5"] {
            assert_eq!(clean_key(good).unwrap(), good);
        }
        for bad in ["", "Esc", "ctrl c", "a;b", "$(x)", "é", "x".repeat(25).as_str()] {
            assert!(clean_key(bad).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn an_action_makes_one_checked_command_line() {
        let prompt = HerdAction::Prompt { session: "default".into(), pane: "w1:p3".into(), text: "Yes; it's fine.\nThen run `make test` && say \"done\" $HOME".into() };
        let line = prompt.command_line().unwrap();
        // Nothing of the text is there for a shell to read.
        let tail = line.split(" herd do ").nth(1).unwrap();
        assert!(tail.starts_with("'prompt' 'default' 'w1:p3' '"), "{tail}");
        assert!(!tail.contains("make") && !tail.contains('$') && !tail.contains('`') && !tail.contains('\n'), "{tail}");
        // And the computer reads back exactly what was written.
        let words: Vec<String> = tail.split(' ').map(|word| word.trim_matches('\'').to_owned()).collect();
        let refs: Vec<&str> = words.iter().map(String::as_str).collect();
        assert_eq!(HerdAction::parse(&refs).unwrap(), prompt);

        let keys = HerdAction::Keys { session: "night".into(), pane: "w1:p4".into(), keys: vec!["esc".into(), "2".into(), "enter".into()] };
        assert!(keys.command_line().unwrap().ends_with(" herd do 'keys' 'night' 'w1:p4' 'esc' '2' 'enter'"));
        let read = HerdAction::Read { session: "default".into(), pane: "w1:p1".into(), lines: 120 };
        assert!(read.command_line().unwrap().ends_with(" herd do 'read' 'default' 'w1:p1' '120'"));
        assert_eq!(HerdAction::parse(&["read", "default", "w1:p1", "120"]).unwrap(), read);
    }

    #[test]
    fn what_is_not_an_action_is_refused() {
        let bad: &[&[&str]] = &[
            &[],
            &["prompt", "default", "w1:p1"],
            &["prompt", "default", "w1:p1", ""],
            &["prompt", "default", "w1:p1", "not base64 !"],
            &["prompt", "bad session!", "w1:p1", "aGk"],
            &["prompt", "default", "w1:t1", "aGk"],
            &["keys", "default", "w1:p1"],
            &["keys", "default", "w1:p1", "rm -rf"],
            &["read", "default", "w1:p1", "0"],
            &["read", "default", "w1:p1", "2001"],
            &["read", "default", "w1:p1", "many"],
            &["close", "default", "w1:p1"],
        ];
        for args in bad {
            assert!(HerdAction::parse(args).is_err(), "{args:?}");
        }
        // Too many keys, too much text, and text that is not text.
        let many: Vec<&str> = ["keys", "default", "w1:p1"].into_iter().chain(std::iter::repeat_n("up", 17)).collect();
        assert!(HerdAction::parse(&many).is_err());
        let long = HerdAction::Prompt { session: "default".into(), pane: "w1:p1".into(), text: "x".repeat(MAX_PROMPT + 1) };
        assert!(long.command_line().is_err());
        assert!(HerdAction::parse(&["prompt", "default", "w1:p1", &URL_SAFE_NO_PAD.encode([0xff, 0xfe])]).is_err());
        // A session or pane the phone was handed that is not one: refused before any command line exists.
        assert!(HerdAction::Keys { session: "a b".into(), pane: "w1:p1".into(), keys: vec!["esc".into()] }.command_line().is_err());
        // An answer travels with the mark of the question it was given to.
        let yes = HerdAction::Answer { session: "night".into(), pane: "w1:p4".into(), mark: "0123456789abcdef".into(), with: Reply::Choice("2".into()) };
        assert!(yes.command_line().unwrap().ends_with(" herd do 'answer' 'night' 'w1:p4' '0123456789abcdef' 'choice' '2'"));
        let words = HerdAction::Answer { session: "night".into(), pane: "w1:p4".into(), mark: String::new(), with: Reply::Text("it's fine; go on".into()) };
        let line = words.command_line().unwrap();
        assert!(line.contains(" herd do 'answer' 'night' 'w1:p4' '-' 'text' '") && !line.contains("fine"), "{line}");
        let args = words.to_args();
        assert_eq!(HerdAction::parse(&args.iter().map(String::as_str).collect::<Vec<_>>()).unwrap(), words);
        for bad in [["answer", "night", "w1:p4", "0123", "choice", "2"], ["answer", "night", "w1:p4", "-", "choice", "12"], ["answer", "night", "w1:p4", "-", "choice", "x"], ["answer", "night", "w1:p4", "-", "shout", "2"], ["answer", "night", "w1:p4", "-", "text", "!!"]] {
            assert!(HerdAction::parse(&bad).is_err(), "{bad:?}");
        }
        assert!(HerdAction::Read { session: "default".into(), pane: "w1:p1; reboot".into(), lines: 10 }.command_line().is_err());
    }

    #[test]
    fn making_and_closing_are_checked_like_everything_else() {
        let tab = HerdAction::NewTab { session: "default".into(), workspace: "w2".into(), label: "fix the tests".into() };
        let line = tab.command_line().unwrap();
        assert!(line.contains(" herd do 'new-tab' 'default' 'w2' '") && !line.contains("fix"), "{line}");
        let words: Vec<String> = line.split(" herd do ").nth(1).unwrap().split(' ').map(|w| w.trim_matches('\'').to_owned()).collect();
        let refs: Vec<&str> = words.iter().map(String::as_str).collect();
        assert_eq!(HerdAction::parse(&refs).unwrap(), tab);
        // Without a name herdr gives it one.
        let plain = HerdAction::NewTab { session: "default".into(), workspace: "w2".into(), label: String::new() };
        assert!(plain.command_line().unwrap().ends_with(" herd do 'new-tab' 'default' 'w2'"));
        assert_eq!(HerdAction::parse(&["new-tab", "default", "w2"]).unwrap(), plain);
        // A name is tidied to one line; a folder is a full path.
        assert_eq!(clean_label("  fix   the tests ").unwrap(), "fix the tests");
        assert!(clean_label("two\nlines").is_err() && clean_label("").is_err() && clean_label(&"x".repeat(49)).is_err());
        let space = HerdAction::NewWorkspace { session: "default".into(), folder: "/home/sam/code/my app".into(), label: "my app".into() };
        let words = space.to_args();
        let refs: Vec<&str> = words.iter().map(String::as_str).collect();
        assert_eq!(HerdAction::parse(&refs).unwrap(), space);
        assert!(!space.command_line().unwrap().contains("my app"));
        for bad in ["code", "~/code", "/home/sam/../root", "/home/sam\n/x", ""] {
            assert!(clean_folder(bad).is_err(), "{bad:?}");
        }
        // Starting and closing: only kinds that are a kind's name, only ids that are ids.
        assert!(HerdAction::Start { session: "default".into(), pane: "w1:p2".into(), kind: "claude".into() }.command_line().unwrap().ends_with(" herd do 'start' 'default' 'w1:p2' 'claude'"));
        assert!(HerdAction::Start { session: "default".into(), pane: "w1:p2".into(), kind: "claude --dangerously".into() }.command_line().is_err());
        assert!(HerdAction::parse(&["start", "default", "w1:p2", "Claude"]).is_err());
        assert!(HerdAction::ClosePane { session: "default".into(), pane: "w1:p2".into() }.command_line().unwrap().ends_with(" herd do 'close-pane' 'default' 'w1:p2'"));
        assert!(HerdAction::CloseTab { session: "default".into(), tab: "w1:t2".into() }.command_line().unwrap().ends_with(" herd do 'close-tab' 'default' 'w1:t2'"));
        assert!(HerdAction::parse(&["close-tab", "default", "w1:p2"]).is_err() && HerdAction::parse(&["close-pane", "default", "w1:t2"]).is_err());
    }

    #[test]
    fn what_was_made_and_what_can_be_started_are_read_back_checked() {
        assert_eq!(parse_made(r#"{"tab":"w1:t3","pane":"w1:p5"}"#).unwrap(), Made { workspace: String::new(), tab: "w1:t3".into(), pane: "w1:p5".into() });
        let made = Made { workspace: "w4".into(), tab: "w4:t1".into(), pane: "w4:p1".into() };
        assert_eq!(parse_made(&serde_json::to_string(&made).unwrap()).unwrap(), made);
        assert!(parse_made(r#"{"tab":"w1:t3","pane":"w1:p5; reboot"}"#).is_err());
        assert!(parse_made(r#"{"tab":"w1:t3"}"#).is_err() && parse_made("").is_err());
        let kinds = parse_kinds(r#"[{"kind":"amp","installed":false},{"kind":"claude","installed":true},{"kind":"rm -rf","installed":true},{"kind":"codex"},{"kind":"pi","installed":false}]"#).unwrap();
        assert_eq!(kinds.iter().map(|k| (k.kind.as_str(), k.installed)).collect::<Vec<_>>(), [("claude", true), ("codex", true), ("amp", false), ("pi", false)], "installed first, the rest in order");
        assert!(parse_kinds("[]").unwrap().is_empty());
        assert!(parse_kinds("claude").is_err() && parse_kinds(r#"["claude"]"#).is_err());
        assert!(kinds_command().ends_with(" herd kinds"));
    }

    #[test]
    fn folders_offered_for_a_workspace_are_full_paths_only() {
        let line = r#"[{"path":"/home/sam/code/api","shown":"~/code/api"},{"path":"code/web","shown":"code/web"},{"path":"/srv/site","shown":"/srv/site"},{"path":"/home/sam/../root","shown":"x"},{"path":"/home/sam/a","shown":"two\nlines"}]"#;
        let places = parse_places(line).unwrap();
        assert_eq!(places.iter().map(|p| (p.path.as_str(), p.shown.as_str())).collect::<Vec<_>>(), [("/home/sam/code/api", "~/code/api"), ("/srv/site", "/srv/site")]);
        assert!(parse_places("[]").unwrap().is_empty());
        assert!(parse_places("nothing").is_err());
        assert!(places_command().ends_with(" herd places"));
        assert!(!places[0].project, "a computer that does not say is not believed to have said yes");
        assert!(parse_places(r#"[{"path":"/srv/site","shown":"/srv/site","project":true}]"#).unwrap()[0].project);
        // Looking inside a folder: its path travels like all text, and is read back checked.
        let asked = folders_command("/home/sam/my code").unwrap();
        assert!(asked.contains(" herd folders '") && !asked.contains("my code"), "{asked}");
        let word = asked.rsplit(' ').next().unwrap().trim_matches('\'');
        assert_eq!(folder_asked(word).unwrap(), "/home/sam/my code");
        assert!(folders_command("relative").is_err() && folders_command("/a/../b").is_err());
        assert!(folder_asked("not base64 !").is_err());
    }

    #[test]
    fn the_command_for_one_pane_is_plain_words_or_nothing() {
        assert_eq!(pane_command("default", "w1:p3").unwrap(), "multiplex herd pane default w1:p3");
        assert_eq!(pane_command("work.api", "w12:p4").unwrap(), "multiplex herd pane work.api w12:p4");
        for (session, pane) in [("default; reboot", "w1:p1"), ("default", "w1:p1; reboot"), ("", "w1:p1"), ("default", "w1:t1"), ("$(x)", "w1:p1")] {
            assert!(pane_command(session, pane).is_err(), "{session:?} {pane:?}");
        }
    }

    #[test]
    fn a_panes_text_is_one_line_of_json() {
        let text = PaneText { text: "line one\nline two \u{1b}[1mbold\u{1b}[0m".into(), asked: None };
        let line = serde_json::to_string(&text).unwrap();
        assert!(!line.contains('\n'));
        assert_eq!(parse_text(&line).unwrap(), text);
        assert!(parse_text("").is_err());
    }
}
