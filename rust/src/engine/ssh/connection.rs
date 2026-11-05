//! Opening an SSH connection, directly or through a jump host.

use std::borrow::Cow;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use russh::client::{self, Handle};
use russh::{ChannelMsg, Disconnect, SshId};

use super::auth::Authenticator;
use super::handler::ClientHandler;
use super::host_key::{HostKeyGuard, HostKeyProblem};
use crate::api::ssh_types::{ConnectError, ConnectOptions, Credentials, ExecOutput, SessionInfo};
use crate::engine::tunnel::remote::RemoteForwardRouter;

/// An open, logged-in SSH connection.
pub struct Connection {
    handle: Handle<ClientHandler>,
    /// The hop we went through, kept alive as long as the connection.
    jump: Option<Handle<ClientHandler>>,
    forwards: Arc<RemoteForwardRouter>,
    info: SessionInfo,
}

impl Connection {
    pub fn handle(&self) -> &Handle<ClientHandler> {
        &self.handle
    }

    pub fn forwards(&self) -> &Arc<RemoteForwardRouter> {
        &self.forwards
    }

    pub fn info(&self) -> &SessionInfo {
        &self.info
    }

    /// True once the server or the network closed the connection.
    pub fn is_closed(&self) -> bool {
        self.handle.is_closed() || self.jump.as_ref().is_some_and(|j| j.is_closed())
    }

    pub async fn disconnect(&self) {
        let _ = self.handle.disconnect(Disconnect::ByApplication, "", "en").await;
        if let Some(jump) = &self.jump {
            let _ = jump.disconnect(Disconnect::ByApplication, "", "en").await;
        }
    }

    /// Runs one command without a terminal and collects its output, up to
    /// `max_bytes` per stream.
    pub async fn exec(&self, command: &str, max_bytes: usize) -> anyhow::Result<ExecOutput> {
        let mut channel = self.handle.channel_open_session().await?;
        channel.exec(true, command).await?;
        let mut out = ExecOutput { stdout: String::new(), stderr: String::new(), exit_code: None, truncated: false };
        let (mut stdout, mut stderr) = (Vec::new(), Vec::new());
        while let Some(msg) = channel.wait().await {
            match msg {
                ChannelMsg::Data { data } => Self::append(&mut stdout, &data, max_bytes, &mut out.truncated),
                ChannelMsg::ExtendedData { data, .. } => Self::append(&mut stderr, &data, max_bytes, &mut out.truncated),
                ChannelMsg::ExitStatus { exit_status } => out.exit_code = Some(exit_status),
                ChannelMsg::Close => break,
                _ => {}
            }
        }
        out.stdout = String::from_utf8_lossy(&stdout).into_owned();
        out.stderr = String::from_utf8_lossy(&stderr).into_owned();
        Ok(out)
    }

    fn append(buf: &mut Vec<u8>, data: &[u8], max: usize, truncated: &mut bool) {
        let room = max.saturating_sub(buf.len());
        if data.len() > room {
            *truncated = true;
        }
        buf.extend_from_slice(&data[..data.len().min(room)]);
    }
}

/// One server to log in to, as the connector sees it.
struct Hop<'a> {
    host: &'a str,
    port: u16,
    username: &'a str,
    credentials: &'a Credentials,
    trusted: &'a [String],
}

/// A logged-in hop plus what we learned while connecting.
struct OpenHop {
    handle: Handle<ClientHandler>,
    guard: Arc<HostKeyGuard>,
    banner: Option<String>,
}

/// Builds [`Connection`]s from [`ConnectOptions`].
pub struct Connector;

impl Connector {
    const CLIENT_ID: &'static str = concat!("SSH-2.0-Multiplex_", env!("CARGO_PKG_VERSION"));

    pub async fn connect(options: ConnectOptions) -> Result<Connection, ConnectError> {
        let limit = Duration::from_secs(u64::from(options.connect_timeout_secs.max(1)));
        tokio::time::timeout(limit, Self::connect_inner(options))
            .await
            .map_err(|_| ConnectError::Timeout)?
    }

    async fn connect_inner(options: ConnectOptions) -> Result<Connection, ConnectError> {
        let config = Arc::new(Self::config(options.keepalive_secs));
        let forwards = Arc::new(RemoteForwardRouter::default());
        let target = Hop {
            host: &options.host,
            port: options.port,
            username: &options.username,
            credentials: &options.credentials,
            trusted: &options.trusted_host_keys,
        };

        let (opened, jump, via) = match &options.jump {
            None => (Self::open_direct(config, &target, forwards.clone()).await?, None, None),
            Some(j) => {
                let jump_hop = Hop {
                    host: &j.host,
                    port: j.port,
                    username: &j.username,
                    credentials: &j.credentials,
                    trusted: &j.trusted_host_keys,
                };
                // The jump host never forwards ports for us, so it gets its
                // own empty router.
                let jump_open = Self::open_direct(config.clone(), &jump_hop, Arc::default()).await?;
                let opened = Self::open_through(config, &target, &jump_open.handle, forwards.clone()).await?;
                (opened, Some(jump_open.handle), Some(j.host.clone()))
            }
        };

        let info = SessionInfo {
            host: options.host.clone(),
            port: options.port,
            username: options.username.clone(),
            via,
            banner: opened.banner,
            host_key: opened.guard.seen().unwrap_or_else(|| crate::api::ssh_types::HostKeyInfo {
                algorithm: String::new(),
                fingerprint: String::new(),
                public_key: String::new(),
            }),
        };
        Ok(Connection { handle: opened.handle, jump, forwards, info })
    }

    /// TCP connection straight to the server, then login.
    async fn open_direct(config: Arc<client::Config>, hop: &Hop<'_>, forwards: Arc<RemoteForwardRouter>) -> Result<OpenHop, ConnectError> {
        let guard = Arc::new(HostKeyGuard::new(hop.trusted));
        let banner = Arc::new(Mutex::new(None));
        let handler = ClientHandler::new(guard.clone(), forwards, banner.clone());
        let handle = client::connect(config, (hop.host, hop.port), handler)
            .await
            .map_err(|err| Self::classify(err, hop, &guard))?;
        Self::finish(handle, hop, guard, banner).await
    }

    /// SSH connection carried inside a channel of the jump host.
    async fn open_through(
        config: Arc<client::Config>,
        hop: &Hop<'_>,
        jump: &Handle<ClientHandler>,
        forwards: Arc<RemoteForwardRouter>,
    ) -> Result<OpenHop, ConnectError> {
        let channel = jump
            .channel_open_direct_tcpip(hop.host, u32::from(hop.port), "127.0.0.1", 0)
            .await
            .map_err(|err| ConnectError::Network {
                host: hop.host.to_owned(),
                port: hop.port,
                message: format!("the jump host could not reach it ({err})"),
            })?;
        let guard = Arc::new(HostKeyGuard::new(hop.trusted));
        let banner = Arc::new(Mutex::new(None));
        let handler = ClientHandler::new(guard.clone(), forwards, banner.clone());
        let handle = client::connect_stream(config, channel.into_stream(), handler)
            .await
            .map_err(|err| Self::classify(err, hop, &guard))?;
        Self::finish(handle, hop, guard, banner).await
    }

    async fn finish(
        mut handle: Handle<ClientHandler>,
        hop: &Hop<'_>,
        guard: Arc<HostKeyGuard>,
        banner: Arc<Mutex<Option<String>>>,
    ) -> Result<OpenHop, ConnectError> {
        Authenticator::new(&mut handle, hop.host, hop.username)
            .login(hop.credentials)
            .await?;
        let banner = banner.lock().expect("banner lock").take();
        Ok(OpenHop { handle, guard, banner })
    }

    /// Turns a low-level failure into something the user can act on.
    fn classify(err: russh::Error, hop: &Hop<'_>, guard: &HostKeyGuard) -> ConnectError {
        match guard.problem() {
            Some(HostKeyProblem::Unknown(key)) => {
                return ConnectError::HostKeyUnknown { host: hop.host.to_owned(), port: hop.port, key }
            }
            Some(HostKeyProblem::Changed(key)) => {
                return ConnectError::HostKeyChanged { host: hop.host.to_owned(), port: hop.port, key }
            }
            None => {}
        }
        match err {
            russh::Error::IO(io) => ConnectError::Network {
                host: hop.host.to_owned(),
                port: hop.port,
                message: io.to_string(),
            },
            russh::Error::ConnectionTimeout | russh::Error::InactivityTimeout => ConnectError::Timeout,
            other => ConnectError::Protocol { message: other.to_string() },
        }
    }

    fn config(keepalive_secs: u32) -> client::Config {
        client::Config {
            client_id: SshId::Standard(Cow::Borrowed(Self::CLIENT_ID)),
            keepalive_interval: (keepalive_secs > 0).then(|| Duration::from_secs(u64::from(keepalive_secs))),
            keepalive_max: 3,
            nodelay: true,
            ..Default::default()
        }
    }
}
