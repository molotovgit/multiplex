//! The object russh calls back into while a connection is open.

use std::sync::{Arc, Mutex};

use russh::client::{self, ChannelOpenHandle, Msg, Session};
use russh::keys::PublicKeyOrCertificate;
use russh::Channel;

use super::agent::ForwardedAgent;
use super::host_key::HostKeyGuard;
use crate::engine::tunnel::remote::RemoteForwardRouter;

/// Reacts to server events: checks the host key, keeps the login banner
/// and routes remote-forwarded connections.
pub struct ClientHandler {
    guard: Arc<HostKeyGuard>,
    forwards: Arc<RemoteForwardRouter>,
    banner: Arc<Mutex<Option<String>>>,
    /// Set when the user allowed agent forwarding to this server.
    agent: Option<Arc<ForwardedAgent>>,
}

impl ClientHandler {
    pub fn new(guard: Arc<HostKeyGuard>, forwards: Arc<RemoteForwardRouter>, banner: Arc<Mutex<Option<String>>>) -> Self {
        Self { guard, forwards, banner, agent: None }
    }

    pub fn with_agent(mut self, agent: Option<Arc<ForwardedAgent>>) -> Self {
        self.agent = agent;
        self
    }
}

impl client::Handler for ClientHandler {
    type Error = russh::Error;

    async fn check_server_key(&mut self, key: &PublicKeyOrCertificate) -> Result<bool, Self::Error> {
        Ok(self.guard.check(key))
    }

    async fn auth_banner(&mut self, banner: &str, _session: &mut Session) -> Result<(), Self::Error> {
        let mut slot = self.banner.lock().expect("banner lock");
        let text = slot.get_or_insert_with(String::new);
        text.push_str(banner);
        Ok(())
    }

    /// The server wants to use our key. Only when the user allowed it for
    /// this host; otherwise the channel is refused.
    async fn server_channel_open_agent_forward(&mut self, channel: Channel<Msg>, reply: ChannelOpenHandle, _session: &mut Session) -> Result<(), Self::Error> {
        match &self.agent {
            Some(agent) => {
                reply.accept().await;
                agent.serve(channel);
            }
            None => reply.reject(russh::ChannelOpenFailure::AdministrativelyProhibited).await,
        }
        Ok(())
    }

    async fn server_channel_open_forwarded_tcpip(
        &mut self,
        channel: Channel<Msg>,
        connected_address: &str,
        connected_port: u32,
        _originator_address: &str,
        _originator_port: u32,
        reply: ChannelOpenHandle,
        _session: &mut Session,
    ) -> Result<(), Self::Error> {
        self.forwards
            .accept(channel, connected_address, connected_port, reply)
            .await;
        Ok(())
    }
}
