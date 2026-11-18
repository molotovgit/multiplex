//! Steering the computer's desktop without its picture, through the
//! `multiplex desk` command of the computer's package, over the SSH
//! connection that is already open. The messages and their checks are in
//! `multiplex-proto`, shared with the computer's side.

use multiplex_proto::desk::{self as proto, DeskAction, DeskBinding, DeskState};

use super::ssh::Connection;

/// Enough for a few hundred bindings.
const MAX_REPLY: usize = 512 * 1024;

const NOT_UNDERSTOOD: &str = "The computer's answer was not understood.";

/// Why a desk command failed, in words for the user.
fn problem(exit_code: Option<u32>, stderr: &str) -> anyhow::Error {
    // 127: the shell did not find the command.
    if exit_code == Some(127) {
        return anyhow::anyhow!("This computer does not have the Multiplex package (or it is an old one). Install it there, then try again.");
    }
    // The package answers a command it does not know with its list of
    // commands: it is older than this app.
    if exit_code == Some(2) && stderr.trim_start().starts_with("multiplex: the Omarchy side of Multiplex") {
        return anyhow::anyhow!("The Multiplex package on this computer is older than this app and cannot do this yet. Update it there, then try again.");
    }
    let said = stderr.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or_default().trim();
    let said = said.strip_prefix("multiplex: ").unwrap_or(said);
    if said.is_empty() {
        return anyhow::anyhow!("The computer did not answer.");
    }
    let mut text = said.to_owned();
    if let Some(first) = text.get_mut(..1) {
        first.make_ascii_uppercase();
    }
    anyhow::anyhow!("{text}")
}

pub(crate) async fn reply(conn: &Connection, command: &str) -> anyhow::Result<String> {
    let out = conn.exec(command, MAX_REPLY).await?;
    if out.exit_code == Some(0) {
        Ok(out.stdout)
    } else {
        Err(problem(out.exit_code, &out.stderr))
    }
}

/// The desktop's state now.
pub async fn state(conn: &Connection) -> anyhow::Result<DeskState> {
    proto::parse_state(&reply(conn, &proto::state_command()).await?).map_err(|_| anyhow::anyhow!(NOT_UNDERSTOOD))
}

/// Asks the desktop to do something. The answer is the state after it.
pub async fn act(conn: &Connection, action: &DeskAction) -> anyhow::Result<DeskState> {
    let command = action.command_line().map_err(|err| anyhow::anyhow!("{err}"))?;
    proto::parse_state(&reply(conn, &command).await?).map_err(|_| anyhow::anyhow!(NOT_UNDERSTOOD))
}

/// Every key binding with a description, in Omarchy's order.
pub async fn bindings(conn: &Connection) -> anyhow::Result<Vec<DeskBinding>> {
    proto::parse_bindings(&reply(conn, &proto::bindings_command()).await?).map_err(|_| anyhow::anyhow!(NOT_UNDERSTOOD))
}

#[cfg(test)]
mod tests {
    use super::problem;

    #[test]
    fn failures_are_put_in_words() {
        assert!(problem(Some(127), "sh: multiplex: command not found").to_string().contains("Multiplex package"));
        assert_eq!(problem(Some(1), "multiplex: the computer has no binding for X\n").to_string(), "The computer has no binding for X");
        assert_eq!(problem(None, "").to_string(), "The computer did not answer.");
        // An older package prints its help for a command it does not know;
        // the last line of that is no reason to show anyone.
        let help = "multiplex: the Omarchy side of Multiplex\n\n  multiplex pair              Show a QR code\n  multiplex speaker           The phone as a loudspeaker\n";
        assert!(problem(Some(2), help).to_string().contains("older than this app"));
        // Exit code 2 for another reason keeps its own words.
        assert_eq!(problem(Some(2), "multiplex: usage: multiplex herd state | watch | do <action>").to_string(), "Usage: multiplex herd state | watch | do <action>");
    }
}
