//! Coding agents running on the computer under herdr (a terminal
//! workspace manager for AI agents), as the phone lists them: which are
//! working, which wait for an answer, which are done.

use serde::{Deserialize, Serialize};

use crate::share::SHARE_COMMAND;
use crate::ProtoError;

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Default)]
#[serde(rename_all = "lowercase")]
pub enum AgentStatus {
    Idle,
    Working,
    /// Waiting for the user: a question, a permission.
    Blocked,
    Done,
    #[default]
    #[serde(other)]
    Unknown,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct Agent {
    /// herdr's id for the pane it runs in.
    pub id: String,
    /// The agent's name ("claude", "codex").
    pub name: String,
    pub status: AgentStatus,
    /// What it is doing, as its terminal's title says.
    pub title: String,
    /// The herdr workspace it is in.
    pub workspace: String,
    /// The folder it works in (the last part of the path).
    pub folder: String,
    /// The herdr session, for attaching a terminal to it.
    pub session: String,
    /// When it waits on a choice: what it asks, the choices, and the mark
    /// an answer carries back (see [`crate::asked`]). Only in news sent
    /// over the link.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub question: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub choices: Vec<crate::asked::Choice>,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub mark: String,
}

/// Prints the agents as one line of JSON.
pub fn agents_command() -> String {
    format!("{SHARE_COMMAND} agents")
}

pub fn parse_agents(text: &str) -> Result<Vec<Agent>, ProtoError> {
    serde_json::from_str(text.trim()).map_err(|_| ProtoError::Damaged)
}

/// A herdr session's name, safe to hand to a shell: what herdr itself
/// allows in one.
pub fn clean_session_name(name: &str) -> Result<String, ProtoError> {
    if !name.is_empty() && name.len() <= 64 && name.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.')) {
        Ok(name.to_owned())
    } else {
        Err(ProtoError::Invalid("this is not a herdr session's name"))
    }
}

/// What to type in a terminal on the computer to sit in front of a
/// session's agents.
pub fn attach_command(session: &str) -> Result<String, ProtoError> {
    Ok(format!("herdr session attach {}", clean_session_name(session)?))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn agents_read_back_and_an_unknown_status_is_just_unknown() {
        let agent = Agent { id: "p1".into(), name: "claude".into(), status: AgentStatus::Blocked, title: "Fix the tests".into(), workspace: "api".into(), folder: "api".into(), session: "default".into(), ..Agent::default() };
        let text = serde_json::to_string(&vec![agent.clone()]).unwrap();
        assert!(text.contains(r#""status":"blocked""#));
        assert!(!text.contains("question") && !text.contains("choices") && !text.contains("mark"), "nothing asked: nothing said about it");
        assert_eq!(parse_agents(&text).unwrap(), vec![agent]);
        let odd = r#"[{"id":"p","name":"x","status":"dreaming","title":"","workspace":"","folder":"","session":"default"}]"#;
        assert_eq!(parse_agents(odd).unwrap()[0].status, AgentStatus::Unknown);
        assert!(parse_agents("nope").is_err());
    }

    #[test]
    fn only_plain_session_names_reach_a_terminal() {
        assert_eq!(attach_command("default").unwrap(), "herdr session attach default");
        assert_eq!(attach_command("work-2.api").unwrap(), "herdr session attach work-2.api");
        for bad in ["", "a b", "x; rm -rf ~", "$(id)", "a/b", "--help x"] {
            assert!(attach_command(bad).is_err(), "{bad}");
        }
    }
}
