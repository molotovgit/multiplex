//! Coding agents on this computer, from herdr (a terminal workspace
//! manager for AI agents): which are working, which wait for an answer,
//! which are done. Read from `herdr api snapshot`; nothing is changed.

use std::collections::HashMap;
use std::process::Command;

use multiplex_proto::agents::{clean_session_name, Agent, AgentStatus};
use serde_json::Value;

/// herdr's running sessions, from `herdr session list` (a table with the
/// name first and the status second).
fn running_sessions() -> Vec<String> {
    let Ok(out) = Command::new("herdr").args(["session", "list"]).output() else { return Vec::new() };
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .skip(1)
        .filter_map(|line| {
            let mut words = line.split_whitespace();
            let (name, status) = (words.next()?, words.next()?);
            (status == "running").then(|| clean_session_name(name).ok()).flatten()
        })
        .collect()
}

/// The agents in one session's snapshot: every pane an agent runs in.
fn build_agents(session: &str, snapshot: &Value) -> Vec<Agent> {
    let snapshot = &snapshot["result"]["snapshot"];
    let workspaces: HashMap<&str, &str> = snapshot["workspaces"]
        .as_array()
        .map(|list| list.iter().filter_map(|w| Some((w["workspace_id"].as_str()?, w["label"].as_str().unwrap_or_default()))).collect())
        .unwrap_or_default();
    let text = |value: &Value| value.as_str().map(str::trim).filter(|s| !s.is_empty()).map(str::to_owned);
    snapshot["panes"]
        .as_array()
        .map(|panes| {
            panes
                .iter()
                .filter_map(|pane| {
                    // A pane without an agent is a plain terminal.
                    let name = text(&pane["display_agent"]).or_else(|| text(&pane["agent"]))?;
                    let folder = text(&pane["foreground_cwd"]).or_else(|| text(&pane["cwd"])).unwrap_or_default();
                    Some(Agent {
                        id: pane["pane_id"].as_str()?.to_owned(),
                        name,
                        status: serde_json::from_value(pane["agent_status"].clone()).unwrap_or(AgentStatus::Unknown),
                        title: text(&pane["title"]).or_else(|| text(&pane["terminal_title_stripped"])).or_else(|| text(&pane["label"])).unwrap_or_default(),
                        workspace: pane["workspace_id"].as_str().and_then(|id| workspaces.get(id)).map(|l| (*l).to_owned()).unwrap_or_default(),
                        folder: folder.trim_end_matches('/').rsplit('/').next().unwrap_or_default().to_owned(),
                        session: session.to_owned(),
                        ..Agent::default()
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

/// Every agent in every running herdr session. Empty without herdr.
pub fn list() -> Vec<Agent> {
    running_sessions()
        .iter()
        .flat_map(|session| {
            let out = Command::new("herdr").args(["--session", session, "api", "snapshot"]).output().ok();
            let snapshot: Option<Value> = out.filter(|o| o.status.success()).and_then(|o| serde_json::from_slice(&o.stdout).ok());
            snapshot.map(|s| build_agents(session, &s)).unwrap_or_default()
        })
        .collect()
}

/// `multiplex agents`.
pub fn run() -> anyhow::Result<()> {
    println!("{}", serde_json::to_string(&list())?);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn snapshot() -> Value {
        json!({"id": "x", "result": {"type": "snapshot", "snapshot": {
            "workspaces": [{"workspace_id": "w1", "label": "api"}],
            "panes": [
                {"pane_id": "p1", "workspace_id": "w1", "agent": "claude", "display_agent": "Claude", "agent_status": "blocked", "title": "Fix the tests", "cwd": "/home/me/code/api/"},
                {"pane_id": "p2", "workspace_id": "w1", "agent": null, "agent_status": "unknown", "title": "htop", "cwd": "/home/me"},
                {"pane_id": "p3", "workspace_id": "w9", "agent": "codex", "agent_status": "something new", "terminal_title_stripped": "Refactor", "foreground_cwd": "/srv/web"},
            ],
        }}})
    }

    #[test]
    fn panes_with_an_agent_become_agents() {
        let agents = build_agents("default", &snapshot());
        assert_eq!(agents.len(), 2, "a plain terminal is not an agent");
        assert_eq!(agents[0], Agent { id: "p1".into(), name: "Claude".into(), status: AgentStatus::Blocked, title: "Fix the tests".into(), workspace: "api".into(), folder: "api".into(), session: "default".into(), ..Agent::default() });
        assert_eq!((agents[1].name.as_str(), agents[1].status, agents[1].title.as_str(), agents[1].folder.as_str(), agents[1].workspace.as_str()), ("codex", AgentStatus::Unknown, "Refactor", "web", ""));
        assert!(build_agents("default", &json!({"result": {"snapshot": {"panes": [], "workspaces": []}}})).is_empty());
        assert!(build_agents("default", &json!({})).is_empty());
    }
}
