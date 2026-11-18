//! `multiplex agents`: the coding agents in the terminals Multiplex keeps,
//! with what each is doing, as one line of JSON. (An older app asks this
//! way; the newer one follows `multiplex herd watch`.)

use multiplex_proto::agents::Agent;

/// Every agent, those that need the owner first.
pub fn list() -> Vec<Agent> {
    crate::herd::state()
        .agents()
        .into_iter()
        .map(|agent| Agent { id: agent.pane, name: agent.name, status: agent.status, title: agent.title, workspace: agent.workspace, folder: agent.folder, session: agent.session, ..Agent::default() })
        .collect()
}

pub fn run() -> anyhow::Result<()> {
    println!("{}", serde_json::to_string(&list())?);
    Ok(())
}
