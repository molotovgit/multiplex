//! The herd (everything herdr keeps running on the computer), through the
//! `multiplex herd` command of the computer's package, over the SSH
//! connection that is already open. The messages and their checks are in
//! `multiplex-proto`, shared with the computer's side.

use multiplex_proto::herd::{self as proto, Herd, HerdAction};

use super::desk::reply;
use super::ssh::Connection;

const NOT_UNDERSTOOD: &str = "The computer's answer was not understood.";

/// The herd now.
pub async fn state(conn: &Connection) -> anyhow::Result<Herd> {
    proto::parse_state(&reply(conn, &proto::state_command()).await?).map_err(|_| anyhow::anyhow!(NOT_UNDERSTOOD))
}

/// Asks something of the herd; what the computer printed is the answer.
/// The action is checked before it becomes a command.
pub async fn act(conn: &Connection, action: &HerdAction) -> anyhow::Result<String> {
    let command = action.command_line().map_err(|err| anyhow::anyhow!("{err}"))?;
    reply(conn, &command).await
}

/// Makes a tab or a workspace; herdr's ids for what was made come back.
pub async fn make(conn: &Connection, action: &HerdAction) -> anyhow::Result<proto::Made> {
    proto::parse_made(&act(conn, action).await?).map_err(|_| anyhow::anyhow!(NOT_UNDERSTOOD))
}

/// The kinds of agent that can be started on the computer.
pub async fn kinds(conn: &Connection) -> anyhow::Result<Vec<proto::Kind>> {
    proto::parse_kinds(&reply(conn, &proto::kinds_command()).await?).map_err(|_| anyhow::anyhow!(NOT_UNDERSTOOD))
}

/// The agents that run outside any terminal the computer keeps.
pub async fn outside(conn: &Connection) -> anyhow::Result<Vec<proto::Outside>> {
    proto::parse_outside(&reply(conn, &proto::outside_command()).await?).map_err(|_| anyhow::anyhow!(NOT_UNDERSTOOD))
}

/// Folders worth offering for a new workspace.
pub async fn places(conn: &Connection) -> anyhow::Result<Vec<proto::Place>> {
    proto::parse_places(&reply(conn, &proto::places_command()).await?).map_err(|_| anyhow::anyhow!(NOT_UNDERSTOOD))
}

/// The folders inside a folder of the computer.
pub async fn folders(conn: &Connection, inside: &str) -> anyhow::Result<Vec<proto::Place>> {
    let command = proto::folders_command(inside).map_err(|err| anyhow::anyhow!("{err}"))?;
    proto::parse_places(&reply(conn, &command).await?).map_err(|_| anyhow::anyhow!(NOT_UNDERSTOOD))
}

/// A pane's recent output, and what its agent asks by choice.
pub async fn read(conn: &Connection, session: String, pane: String, lines: u32) -> anyhow::Result<proto::PaneText> {
    let printed = act(conn, &HerdAction::Read { session, pane, lines }).await?;
    proto::parse_text(&printed).map_err(|_| anyhow::anyhow!(NOT_UNDERSTOOD))
}
