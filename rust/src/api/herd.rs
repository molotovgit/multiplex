//! The herd: everything herdr keeps running on a paired computer. The
//! whole of it now, again whenever it changes, and what the phone can ask
//! of a pane: text for its agent, keys, its recent output.

use std::sync::Arc;

use flutter_rust_bridge::frb;
use multiplex_proto::herd as proto;

use super::herd_types::HerdState;
use super::ssh::SshSession;
use super::watch::RemoteWatch;
use crate::engine::herd;
use crate::engine::runtime::AsyncRuntime;
use crate::frb_generated::StreamSink;

impl SshSession {
    /// The herd now.
    pub async fn herd_state(&self) -> anyhow::Result<HerdState> {
        let conn = self.conn.clone();
        Ok(AsyncRuntime::run(async move { herd::state(&conn).await }).await??.into())
    }

    /// The herd now, and again whenever something in it changes, until
    /// [`HerdWatch::stop`]. The computer is told by herdr itself, so a
    /// change is here as fast as the connection carries it.
    pub async fn herd_watch(&self) -> anyhow::Result<HerdWatch> {
        let conn = self.conn.clone();
        let inner = AsyncRuntime::run(RemoteWatch::start(conn, proto::watch_command())).await??;
        Ok(HerdWatch { inner })
    }

    /// Gives a pane's agent this text and Enter, as one piece. In a plain
    /// terminal it is typed, then Enter.
    pub async fn herd_prompt(&self, session: String, pane: String, text: String) -> anyhow::Result<()> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { herd::act(&conn, &proto::HerdAction::Prompt { session, pane, text }).await }).await??;
        Ok(())
    }

    /// Presses keys in a pane, by herdr's names for them: "esc", "enter",
    /// "ctrl+c", "up", "2".
    pub async fn herd_keys(&self, session: String, pane: String, keys: Vec<String>) -> anyhow::Result<()> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { herd::act(&conn, &proto::HerdAction::Keys { session, pane, keys }).await }).await??;
        Ok(())
    }

    /// A pane's recent output, as text, at most `lines` lines of it.
    pub async fn herd_read(&self, session: String, pane: String, lines: u32) -> anyhow::Result<String> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { herd::read(&conn, session, pane, lines).await }).await?
    }
}

/// The herd as it changes.
#[frb(opaque)]
pub struct HerdWatch {
    inner: RemoteWatch,
}

impl HerdWatch {
    /// Each new state. Listen once.
    pub fn states(&self, sink: StreamSink<HerdState>) {
        self.inner.lines.attach(Arc::new(move |line: String| match proto::parse_state(&line) {
            Ok(state) => sink.add(state.into()).is_ok(),
            // Not a state (the empty line that says "still here", a notice
            // from the shell): keep listening.
            Err(_) => true,
        }));
    }

    #[frb(sync)]
    pub fn stop(&self) {
        self.inner.stop();
    }
}
