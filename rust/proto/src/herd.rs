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

/// Something the phone asks of the herd.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HerdAction {
    /// Give an agent this text and press Enter, as one piece.
    Prompt { session: String, pane: String, text: String },
    /// Press keys in a pane: Esc, a choice's number, Ctrl+C.
    Keys { session: String, pane: String, keys: Vec<String> },
    /// Print a pane's recent output.
    Read { session: String, pane: String, lines: u32 },
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

/// What `herd do read` prints: the pane's recent output, one line of JSON.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct PaneText {
    pub text: String,
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
        assert!(HerdAction::Read { session: "default".into(), pane: "w1:p1; reboot".into(), lines: 10 }.command_line().is_err());
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
        let text = PaneText { text: "line one\nline two \u{1b}[1mbold\u{1b}[0m".into() };
        let line = serde_json::to_string(&text).unwrap();
        assert!(!line.contains('\n'));
        assert_eq!(parse_text(&line).unwrap(), text);
        assert!(parse_text("").is_err());
    }
}
