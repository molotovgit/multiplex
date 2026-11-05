//! Starting and stopping tunnels of all three kinds.

use std::sync::Arc;

use tokio::net::{TcpListener, TcpStream};
use tokio_util::sync::CancellationToken;

use super::pipe::{Pipe, TunnelCounters};
use super::socks::Socks5;
use crate::api::tunnel_types::{TunnelKind, TunnelSpec, TunnelStats};
use crate::engine::runtime::AsyncRuntime;
use crate::engine::ssh::Connection;

/// A running tunnel. Dropping it does not stop it; call [`Tunnel::stop`].
pub struct Tunnel {
    spec: TunnelSpec,
    bound_port: u16,
    counters: Arc<TunnelCounters>,
    stop: CancellationToken,
    conn: Arc<Connection>,
}

impl Tunnel {
    /// Starts listening. For Local and Dynamic the port is opened on this
    /// device right away, so a "port already in use" error shows up here.
    pub async fn start(conn: Arc<Connection>, spec: TunnelSpec) -> anyhow::Result<Self> {
        let counters = Arc::new(TunnelCounters::default());
        let stop = CancellationToken::new();
        let bound_port = match spec.kind {
            TunnelKind::Local | TunnelKind::Dynamic => {
                let listener = TcpListener::bind((spec.bind_host.as_str(), spec.bind_port)).await?;
                let port = listener.local_addr()?.port();
                AsyncRuntime::spawn(Self::accept_loop(listener, conn.clone(), spec.clone(), counters.clone(), stop.clone()));
                port
            }
            TunnelKind::Remote => {
                let port = conn.handle().tcpip_forward(spec.bind_host.clone(), u32::from(spec.bind_port)).await?;
                // The server returns 0 when it used the port we asked for.
                let port = if port == 0 { spec.bind_port } else { port as u16 };
                conn.forwards().add(&spec.bind_host, u32::from(port), &spec.target_host, spec.target_port, counters.clone());
                port
            }
        };
        Ok(Self { spec, bound_port, counters, stop, conn })
    }

    pub fn spec(&self) -> &TunnelSpec {
        &self.spec
    }

    /// The port actually in use (differs from the request when it was 0).
    pub fn bound_port(&self) -> u16 {
        self.bound_port
    }

    pub fn stats(&self) -> TunnelStats {
        self.counters.snapshot()
    }

    pub fn is_running(&self) -> bool {
        !self.stop.is_cancelled() && !self.conn.is_closed()
    }

    /// Stops accepting new connections. Connections already open finish
    /// on their own.
    pub async fn stop(&self) {
        if self.stop.is_cancelled() {
            return;
        }
        self.stop.cancel();
        if self.spec.kind == TunnelKind::Remote {
            let port = u32::from(self.bound_port);
            self.conn.forwards().remove(&self.spec.bind_host, port);
            let _ = self.conn.handle().cancel_tcpip_forward(self.spec.bind_host.clone(), port).await;
        }
    }

    async fn accept_loop(listener: TcpListener, conn: Arc<Connection>, spec: TunnelSpec, counters: Arc<TunnelCounters>, stop: CancellationToken) {
        loop {
            let accepted = tokio::select! {
                _ = stop.cancelled() => break,
                accepted = listener.accept() => accepted,
            };
            let Ok((socket, peer)) = accepted else { continue };
            if conn.is_closed() {
                break;
            }
            let (conn, spec, counters) = (conn.clone(), spec.clone(), counters.clone());
            AsyncRuntime::spawn(async move {
                let _ = socket.set_nodelay(true);
                let result = match spec.kind {
                    TunnelKind::Dynamic => Self::serve_socks(socket, peer, &conn, &counters).await,
                    _ => Self::serve_local(socket, peer, &conn, &spec, &counters).await,
                };
                // A failed single connection is normal (target down); the
                // tunnel itself keeps running.
                let _ = result;
            });
        }
    }

    async fn serve_local(socket: TcpStream, peer: std::net::SocketAddr, conn: &Connection, spec: &TunnelSpec, counters: &TunnelCounters) -> anyhow::Result<()> {
        let channel = conn
            .handle()
            .channel_open_direct_tcpip(spec.target_host.clone(), u32::from(spec.target_port), peer.ip().to_string(), u32::from(peer.port()))
            .await?;
        Pipe::run(socket, channel.into_stream(), counters).await;
        Ok(())
    }

    async fn serve_socks(mut socket: TcpStream, peer: std::net::SocketAddr, conn: &Connection, counters: &TunnelCounters) -> anyhow::Result<()> {
        let target = Socks5::accept(&mut socket).await?;
        let opened = conn
            .handle()
            .channel_open_direct_tcpip(target.host, u32::from(target.port), peer.ip().to_string(), u32::from(peer.port()))
            .await;
        match opened {
            Ok(channel) => {
                Socks5::confirm(&mut socket).await?;
                Pipe::run(socket, channel.into_stream(), counters).await;
                Ok(())
            }
            Err(err) => {
                Socks5::refuse(&mut socket).await?;
                Err(err.into())
            }
        }
    }
}
