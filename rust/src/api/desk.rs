//! Steering the computer's desktop without its picture: workspaces, the
//! window in focus, media keys and every key binding, through the
//! `multiplex desk` command of the computer's package, over the SSH
//! connection that is already open.

use std::sync::Arc;

use flutter_rust_bridge::frb;
use multiplex_proto::desk as proto;

use super::desk_types::{DeskAction, DeskBinding, DeskState};
use super::ssh::SshSession;
use super::watch::RemoteWatch;
use crate::engine::desk;
use crate::engine::runtime::AsyncRuntime;
use crate::frb_generated::StreamSink;

impl SshSession {
    /// The desktop's state now.
    pub async fn desk_state(&self) -> anyhow::Result<DeskState> {
        let conn = self.conn.clone();
        Ok(AsyncRuntime::run(async move { desk::state(&conn).await }).await??.into())
    }

    /// Asks the desktop to do something. The answer is the state after it.
    pub async fn desk_do(&self, action: DeskAction) -> anyhow::Result<DeskState> {
        let conn = self.conn.clone();
        let action = proto::DeskAction::from(action);
        Ok(AsyncRuntime::run(async move { desk::act(&conn, &action).await }).await??.into())
    }

    /// Every key binding with a description, in Omarchy's order.
    pub async fn desk_bindings(&self) -> anyhow::Result<Vec<DeskBinding>> {
        let conn = self.conn.clone();
        let list = AsyncRuntime::run(async move { desk::bindings(&conn).await }).await??;
        Ok(list.into_iter().map(Into::into).collect())
    }

    /// The state now, and again whenever it changes, until
    /// [`DeskWatch::stop`].
    pub async fn desk_watch(&self) -> anyhow::Result<DeskWatch> {
        let conn = self.conn.clone();
        let inner = AsyncRuntime::run(RemoteWatch::start(conn, proto::watch_command())).await??;
        Ok(DeskWatch { inner })
    }
}

/// The desktop's state as it changes.
#[frb(opaque)]
pub struct DeskWatch {
    inner: RemoteWatch,
}

impl DeskWatch {
    /// Each new state. Listen once.
    pub fn states(&self, sink: StreamSink<DeskState>) {
        self.inner.lines.attach(Arc::new(move |line: String| match proto::parse_state(&line) {
            Ok(state) => sink.add(state.into()).is_ok(),
            // Not a state (a notice from the shell, say): keep listening.
            Err(_) => true,
        }));
    }

    #[frb(sync)]
    pub fn stop(&self) {
        self.inner.stop();
    }
}
