//! The herd: everything herdr keeps running on a paired computer. The
//! whole of it now, again whenever it changes, and what the phone can ask
//! of a pane: text for its agent, keys, its recent output.

use std::sync::Arc;

use flutter_rust_bridge::frb;
use multiplex_proto::herd as proto;

use super::herd_types::{HerdKind, HerdMade, HerdPlace, HerdState};
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

    /// A new tab in a workspace, with a terminal in it. With an empty
    /// label herdr names it.
    pub async fn herd_new_tab(&self, session: String, workspace: String, label: String) -> anyhow::Result<HerdMade> {
        let conn = self.conn.clone();
        Ok(AsyncRuntime::run(async move { herd::make(&conn, &proto::HerdAction::NewTab { session, workspace, label }).await }).await??.into())
    }

    /// A new workspace in a folder of the computer, with a tab and a
    /// terminal in it.
    pub async fn herd_new_workspace(&self, session: String, folder: String, label: String) -> anyhow::Result<HerdMade> {
        let conn = self.conn.clone();
        Ok(AsyncRuntime::run(async move { herd::make(&conn, &proto::HerdAction::NewWorkspace { session, folder, label }).await }).await??.into())
    }

    /// Starts an agent of this kind in a pane that sits at its prompt.
    /// Returns once the agent is ready there, or says why it is not.
    pub async fn herd_start_agent(&self, session: String, pane: String, kind: String) -> anyhow::Result<()> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { herd::act(&conn, &proto::HerdAction::Start { session, pane, kind }).await }).await??;
        Ok(())
    }

    /// Closes a pane, and whatever runs in it.
    pub async fn herd_close_pane(&self, session: String, pane: String) -> anyhow::Result<()> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { herd::act(&conn, &proto::HerdAction::ClosePane { session, pane }).await }).await??;
        Ok(())
    }

    /// Closes a tab with all its panes.
    pub async fn herd_close_tab(&self, session: String, tab: String) -> anyhow::Result<()> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { herd::act(&conn, &proto::HerdAction::CloseTab { session, tab }).await }).await??;
        Ok(())
    }

    /// The kinds of agent that can be started on the computer, those that
    /// are installed first; the others install themselves when first
    /// started.
    pub async fn herd_kinds(&self) -> anyhow::Result<Vec<HerdKind>> {
        let conn = self.conn.clone();
        let kinds = AsyncRuntime::run(async move { herd::kinds(&conn).await }).await??;
        Ok(kinds.into_iter().map(|kind| HerdKind { name: kind.kind, installed: kind.installed }).collect())
    }

    /// Folders worth offering for a new workspace: those the user goes
    /// to, those herdr's panes are in, and projects in the home folder.
    pub async fn herd_places(&self) -> anyhow::Result<Vec<HerdPlace>> {
        let conn = self.conn.clone();
        let places = AsyncRuntime::run(async move { herd::places(&conn).await }).await??;
        Ok(places.into_iter().map(Into::into).collect())
    }

    /// The folders inside a folder of the computer, by name.
    pub async fn herd_folders(&self, inside: String) -> anyhow::Result<Vec<HerdPlace>> {
        let conn = self.conn.clone();
        let places = AsyncRuntime::run(async move { herd::folders(&conn, &inside).await }).await??;
        Ok(places.into_iter().map(Into::into).collect())
    }

    /// A pane's recent output, as text, at most `lines` lines of it.
    pub async fn herd_read(&self, session: String, pane: String, lines: u32) -> anyhow::Result<String> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { herd::read(&conn, session, pane, lines).await }).await?
    }
}

/// What to type in a terminal on the computer to sit in front of one
/// pane, drawn at that terminal's own size while the pane keeps its own on
/// the computer; `None` for a session or pane that is not one.
#[frb(sync)]
pub fn herd_pane_command(session: String, pane: String) -> Option<String> {
    proto::pane_command(&session, &pane).ok()
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
