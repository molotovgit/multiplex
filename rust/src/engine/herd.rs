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

/// A pane's recent output.
pub async fn read(conn: &Connection, session: String, pane: String, lines: u32) -> anyhow::Result<String> {
    let printed = act(conn, &HerdAction::Read { session, pane, lines }).await?;
    Ok(proto::parse_text(&printed).map_err(|_| anyhow::anyhow!(NOT_UNDERSTOOD))?.text)
}
