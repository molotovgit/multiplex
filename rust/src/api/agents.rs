//! Coding agents on a paired computer (under herdr): what each is doing,
//! and the command that attaches a terminal to them.

use flutter_rust_bridge::frb;
use multiplex_proto::agents as proto;

use super::ssh::SshSession;
use crate::engine::runtime::AsyncRuntime;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentStatus {
    Idle,
    Working,
    /// Waiting for the user: a question, a permission.
    Blocked,
    Done,
    Unknown,
}

#[derive(Debug, Clone)]
pub struct Agent {
    pub id: String,
    /// The agent's name ("Claude", "codex").
    pub name: String,
    pub status: AgentStatus,
    /// What it is doing, as its terminal's title says.
    pub title: String,
    /// The herdr workspace it is in.
    pub workspace: String,
    /// The folder it works in.
    pub folder: String,
    /// The herdr session it runs in.
    pub session: String,
}

impl From<proto::Agent> for Agent {
    fn from(agent: proto::Agent) -> Self {
        let status = match agent.status {
            proto::AgentStatus::Idle => AgentStatus::Idle,
            proto::AgentStatus::Working => AgentStatus::Working,
            proto::AgentStatus::Blocked => AgentStatus::Blocked,
            proto::AgentStatus::Done => AgentStatus::Done,
            proto::AgentStatus::Unknown => AgentStatus::Unknown,
        };
        Self { id: agent.id, name: agent.name, status, title: agent.title, workspace: agent.workspace, folder: agent.folder, session: agent.session }
    }
}

impl SshSession {
    /// The agents running on the computer now. Empty without herdr.
    pub async fn agents(&self) -> anyhow::Result<Vec<Agent>> {
        let conn = self.conn.clone();
        let out = AsyncRuntime::run(async move { conn.exec(&proto::agents_command(), 512 * 1024).await }).await??;
        if out.exit_code == Some(127) {
            anyhow::bail!("This computer does not have the Multiplex package (or it is an old one). Install it there, then try again.");
        }
        if out.exit_code != Some(0) {
            let said = out.stderr.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or("The computer did not answer.").trim().to_owned();
            anyhow::bail!("{}", said.strip_prefix("multiplex: ").unwrap_or(&said));
        }
        let agents = proto::parse_agents(&out.stdout).map_err(|_| anyhow::anyhow!("The computer's answer was not understood."))?;
        Ok(agents.into_iter().map(Into::into).collect())
    }
}

/// What to type in a terminal on the computer to sit in front of a herdr
/// session's agents; `None` for a name that is not a plain session name.
#[frb(sync)]
pub fn agent_attach_command(session: String) -> Option<String> {
    proto::attach_command(&session).ok()
}
