//! The object russh calls back into while a connection is open.

use std::sync::{Arc, Mutex};

use russh::client::{self, ChannelOpenHandle, Msg, Session};
use russh::keys::PublicKeyOrCertificate;
use russh::Channel;

use super::host_key::HostKeyGuard;
use crate::engine::tunnel::remote::RemoteForwardRouter;

/// Reacts to server events: checks the host key, keeps the login banner
/// and routes remote-forwarded connections.
pub struct ClientHandler {
    guard: Arc<HostKeyGuard>,
    forwards: Arc<RemoteForwardRouter>,
    banner: Arc<Mutex<Option<String>>>,
}

impl ClientHandler {
    pub fn new(guard: Arc<HostKeyGuard>, forwards: Arc<RemoteForwardRouter>, banner: Arc<Mutex<Option<String>>>) -> Self {
        Self { guard, forwards, banner }
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
