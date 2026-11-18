//! The herd as the phone shows it: herdr's sessions with their
//! workspaces, tabs and panes, and every agent in inbox order. The wire
//! format, its checks and that order are in `multiplex-proto`, shared with
//! the computer's side; nothing is decided in the screens.

use multiplex_proto::herd as proto;

use super::agents::AgentStatus;

#[derive(Debug, Clone, Default)]
pub struct HerdState {
    /// False when the computer has no herdr.
    pub available: bool,
    pub sessions: Vec<HerdSession>,
    /// Every agent of every session: those that need the user first, then
    /// those that finished, the busy, the idle.
    pub inbox: Vec<HerdAgent>,
    /// How many agents wait for the user.
    pub waiting: u32,
}

#[derive(Debug, Clone, Default)]
pub struct HerdSession {
    pub name: String,
    /// False for a session herdr remembers but does not run now; it
    /// starts again when its screen is opened.
    pub running: bool,
    pub workspaces: Vec<HerdWorkspace>,
}

#[derive(Debug, Clone, Default)]
pub struct HerdWorkspace {
    pub id: String,
    pub label: String,
    pub tabs: Vec<HerdTab>,
}

#[derive(Debug, Clone, Default)]
pub struct HerdTab {
    pub id: String,
    pub label: String,
    pub panes: Vec<HerdPane>,
}

#[derive(Debug, Clone)]
pub struct HerdPane {
    pub id: String,
    /// What its terminal's title says.
    pub title: String,
    /// The folder it is in, in full, and that folder's own name.
    pub folder: String,
    pub folder_name: String,
    /// The pane herdr's own screen has in focus.
    pub focused: bool,
    /// The agent in it; none in a plain terminal.
    pub agent: Option<String>,
    pub status: AgentStatus,
}

/// What was just made on the computer: a tab (in a new workspace, when
/// one was asked for) and the terminal in it.
#[derive(Debug, Clone, Default)]
pub struct HerdMade {
    /// Empty unless a workspace was made.
    pub workspace: String,
    pub tab: String,
    pub pane: String,
}

impl From<proto::Made> for HerdMade {
    fn from(made: proto::Made) -> Self {
        Self { workspace: made.workspace, tab: made.tab, pane: made.pane }
    }
}

/// A kind of agent the computer can start.
#[derive(Debug, Clone)]
pub struct HerdKind {
    /// herdr's name for it ("claude").
    pub name: String,
    /// False for one that installs itself (a download) the first time it
    /// is started.
    pub installed: bool,
}

/// One agent with where it is.
#[derive(Debug, Clone)]
pub struct HerdAgent {
    pub session: String,
    pub workspace: String,
    pub tab: String,
    pub pane: String,
    pub name: String,
    pub status: AgentStatus,
    pub title: String,
    /// The folder's own name.
    pub folder: String,
}

fn status(status: multiplex_proto::agents::AgentStatus) -> AgentStatus {
    use multiplex_proto::agents::AgentStatus as Proto;
    match status {
        Proto::Idle => AgentStatus::Idle,
        Proto::Working => AgentStatus::Working,
        Proto::Blocked => AgentStatus::Blocked,
        Proto::Done => AgentStatus::Done,
        Proto::Unknown => AgentStatus::Unknown,
    }
}

impl From<proto::Herd> for HerdState {
    fn from(herd: proto::Herd) -> Self {
        let inbox: Vec<HerdAgent> = herd
            .agents()
            .into_iter()
            .map(|a| HerdAgent { session: a.session, workspace: a.workspace, tab: a.tab, pane: a.pane, name: a.name, status: status(a.status), title: a.title, folder: a.folder })
            .collect();
        let waiting = herd.waiting() as u32;
        let pane = |p: proto::Pane| HerdPane {
            folder_name: proto::folder_name(&p.folder).to_owned(),
            id: p.id,
            title: p.title,
            folder: p.folder,
            focused: p.focused,
            status: p.agent.as_ref().map_or(AgentStatus::Unknown, |a| status(a.status)),
            agent: p.agent.map(|a| a.name),
        };
        let sessions = herd
            .sessions
            .into_iter()
            .map(|s| HerdSession {
                name: s.name,
                running: s.running,
                workspaces: s
                    .workspaces
                    .into_iter()
                    .map(|w| HerdWorkspace { id: w.id, label: w.label, tabs: w.tabs.into_iter().map(|t| HerdTab { id: t.id, label: t.label, panes: t.panes.into_iter().map(pane).collect() }).collect() })
                    .collect(),
            })
            .collect();
        HerdState { available: herd.available, sessions, inbox, waiting }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_herd_arrives_with_its_inbox_already_in_order() {
        let line = r#"{"available":true,"sessions":[{"name":"default","workspaces":[{"id":"w1","label":"api","tabs":[
            {"id":"w1:t1","label":"1","panes":[
                {"id":"w1:p1","title":"Refactor","folder":"/home/sam/code/api","focused":true,"agent":{"name":"Claude","status":"working"}},
                {"id":"w1:p2","title":"sam@desk:~","folder":"/home/sam","focused":false}]},
            {"id":"w1:t2","label":"review","panes":[
                {"id":"w1:p3","title":"Allow this?","folder":"/srv/web/","focused":false,"agent":{"name":"codex","status":"blocked"}}]}]}]}]}"#;
        let state: HerdState = proto::parse_state(line).unwrap().into();
        assert!(state.available);
        assert_eq!(state.waiting, 1);
        assert_eq!(state.inbox.iter().map(|a| (a.pane.as_str(), a.status, a.folder.as_str(), a.tab.as_str())).collect::<Vec<_>>(), [("w1:p3", AgentStatus::Blocked, "web", "review"), ("w1:p1", AgentStatus::Working, "api", "1")]);
        let panes = &state.sessions[0].workspaces[0].tabs[0].panes;
        assert_eq!((panes[0].agent.as_deref(), panes[0].status, panes[0].folder_name.as_str(), panes[0].focused), (Some("Claude"), AgentStatus::Working, "api", true));
        // A plain terminal: no agent, and no status to speak of.
        assert_eq!((panes[1].agent.as_deref(), panes[1].status, panes[1].folder.as_str(), panes[1].folder_name.as_str()), (None, AgentStatus::Unknown, "/home/sam", "sam"));
        assert!(state.sessions[0].running);
        // A session that is not running comes as that, with nothing in it.
        let stopped: HerdState = proto::parse_state(r#"{"sessions":[{"name":"old","running":false,"workspaces":[]}]}"#).unwrap().into();
        assert_eq!((stopped.sessions[0].name.as_str(), stopped.sessions[0].running, stopped.sessions[0].workspaces.len()), ("old", false, 0));
        // A computer without herdr.
        let none: HerdState = proto::Herd::missing().into();
        assert!(!none.available && none.sessions.is_empty() && none.inbox.is_empty() && none.waiting == 0);
    }
}
