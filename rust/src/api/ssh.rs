//! The SSH session Flutter holds, and everything that runs on it: shells,
//! single commands, SFTP and tunnels.

use std::sync::Arc;

use flutter_rust_bridge::frb;

use crate::api::desktop::RemoteDesktop;
use crate::api::desktop_types::{DesktopEvent, DesktopOptions};
use crate::api::sftp::RemoteFiles;
use crate::api::ssh_types::{ConnectError, ConnectOptions, ExecOutput, SessionInfo};
use crate::api::terminal::RemoteShell;
use crate::api::terminal_types::{ShellEvent, ShellOptions};
use crate::engine::desktop::{video, DesktopSession};
use crate::engine::events::EventRelay;
use crate::api::tunnel::ActiveTunnel;
use crate::api::tunnel_types::TunnelSpec;
use crate::engine::runtime::AsyncRuntime;
use crate::engine::sftp::SftpBrowser;
use crate::engine::shell::ShellSession;
use crate::engine::ssh::{Connection, Connector};
use crate::engine::tunnel::Tunnel;

/// One logged-in connection to a server.
#[frb(opaque)]
pub struct SshSession {
    conn: Arc<Connection>,
}

impl SshSession {
    /// Connects and logs in. Fails with a [`ConnectError`] the app can
    /// act on (for example: ask the user to trust the host key).
    pub async fn connect(options: ConnectOptions) -> Result<SshSession, ConnectError> {
        match AsyncRuntime::run(Connector::connect(options)).await {
            Ok(Ok(conn)) => Ok(SshSession { conn: Arc::new(conn) }),
            Ok(Err(err)) => Err(err),
            Err(err) => Err(ConnectError::Protocol { message: err.to_string() }),
        }
    }

    #[frb(sync)]
    pub fn info(&self) -> SessionInfo {
        self.conn.info().clone()
    }

    #[frb(sync)]
    pub fn is_connected(&self) -> bool {
        !self.conn.is_closed()
    }

    /// Runs one command and returns its output (each stream capped at
    /// `max_bytes`).
    pub async fn exec(&self, command: String, max_bytes: u32) -> anyhow::Result<ExecOutput> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { conn.exec(&command, max_bytes as usize).await }).await?
    }

    /// Opens an interactive shell. Listen to [`RemoteShell::events`] for
    /// screen updates; events from before that are kept and delivered.
    pub async fn open_shell(&self, options: ShellOptions) -> anyhow::Result<RemoteShell> {
        let conn = self.conn.clone();
        let relay = Arc::new(EventRelay::<ShellEvent>::new());
        let sink = relay.clone();
        let shell = AsyncRuntime::run(async move { ShellSession::open(&conn, options, sink).await }).await??;
        Ok(RemoteShell::new(shell, relay))
    }

    /// Joins a shell whose connection dropped to this (new) connection.
    /// Its screen and history stay; the new shell carries on below them.
    pub async fn reattach_shell(&self, shell: &RemoteShell, options: ShellOptions) -> anyhow::Result<()> {
        let conn = self.conn.clone();
        let inner = shell.engine();
        AsyncRuntime::run(async move { inner.reattach(&conn, options).await }).await?
    }

    /// True when the server answers within `timeout_secs`.
    pub async fn check_alive(&self, timeout_secs: u32) -> bool {
        let conn = self.conn.clone();
        let limit = std::time::Duration::from_secs(u64::from(timeout_secs.max(1)));
        AsyncRuntime::run(async move { conn.check_alive(limit).await }).await.unwrap_or(false)
    }

    /// Opens a file browser on this connection.
    pub async fn open_files(&self) -> anyhow::Result<RemoteFiles> {
        let conn = self.conn.clone();
        let browser = AsyncRuntime::run(async move { SftpBrowser::open(&conn).await }).await??;
        Ok(RemoteFiles::new(browser))
    }

    /// Starts a remote desktop (gliff) on this connection. The video is
    /// drawn into `options.texture_id`; listen to [`RemoteDesktop::events`]
    /// for everything else.
    pub async fn open_desktop(&self, options: DesktopOptions) -> anyhow::Result<RemoteDesktop> {
        let conn = self.conn.clone();
        let relay = Arc::new(EventRelay::<DesktopEvent>::new());
        let sink = relay.clone();
        let desktop = AsyncRuntime::run(async move {
            let (reports_tx, reports_rx) = tokio::sync::mpsc::unbounded_channel();
            let decoder = video::create(options.texture_id, reports_tx);
            DesktopSession::open(&conn, options, sink, decoder, reports_rx).await
        })
        .await??;
        Ok(RemoteDesktop::new(desktop, relay))
    }

    /// Starts a port forward on this connection.
    pub async fn start_tunnel(&self, spec: TunnelSpec) -> anyhow::Result<ActiveTunnel> {
        let conn = self.conn.clone();
        let tunnel = AsyncRuntime::run(Tunnel::start(conn, spec)).await??;
        Ok(ActiveTunnel::new(tunnel))
    }

    /// Closes the connection (and everything running on it).
    pub async fn disconnect(&self) {
        let conn = self.conn.clone();
        let _ = AsyncRuntime::run(async move { conn.disconnect().await }).await;
    }
}
