//! Pairing with a computer from its QR code (see multiplex-proto).
//!
//! The code carries a one-time key that may do one thing on the computer:
//! register this phone's own public key. We log in with it, checking the
//! computer's host key against the one in the code (so the first
//! connection already knows who it talks to), send the request and read
//! the answer. After that the phone logs in with its own key and the
//! one-time key is gone.

use std::time::{SystemTime, UNIX_EPOCH};

use multiplex_proto::{PairingCode, ProtoError, RegisterReply, RegisterRequest};
use russh::keys::ssh_key::private::{Ed25519Keypair, KeypairData};
use russh::keys::ssh_key::LineEnding;
use russh::keys::PrivateKey;

use crate::api::ssh_types::{ConnectError, ConnectOptions, Credentials};
use crate::engine::ssh::Connector;

/// Why pairing did not work, in words for the person holding the phone.
#[derive(Debug, thiserror::Error)]
pub enum PairError {
    #[error(transparent)]
    Code(#[from] ProtoError),
    #[error("The phone cannot reach {name}. Put the phone on the same Wi-Fi as the computer, or sign in to Tailscale on both, then scan again.")]
    Unreachable { name: String },
    #[error("The computer that answered is not the one that showed the code. Nothing was paired.")]
    WrongComputer,
    #[error("The computer no longer accepts this code (it was used, or it expired). Show a new one with `multiplex pair`.")]
    CodeRefused,
    #[error("The computer refused to pair: {0}")]
    Refused(String),
    #[error("Pairing failed: {0}")]
    Other(String),
}

/// How pairing went.
#[derive(Debug, Clone)]
pub struct Paired {
    /// The computer's own name for itself.
    pub computer: String,
    /// The address that worked.
    pub address: String,
    pub via_tailscale: bool,
    /// What the computer has ("gliff", "hyprland", "tailscale", "fcitx5").
    pub features: Vec<String>,
}

pub fn now_unix() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// The one-time key as OpenSSH private key text.
fn one_time_key(code: &PairingCode) -> Result<String, PairError> {
    let keypair = Ed25519Keypair::from_seed(&code.seed());
    let key = PrivateKey::new(KeypairData::Ed25519(keypair), "multiplex-pairing").map_err(|e| PairError::Other(e.to_string()))?;
    Ok(key.to_openssh(LineEnding::LF).map_err(|e| PairError::Other(e.to_string()))?.to_string())
}

/// Registers `phone_key` (an OpenSSH public key line) on the computer the
/// code is from. Tailscale is tried first when `tailscale_ready` (it works
/// from anywhere and goes direct on the home network), then the
/// home-network addresses.
pub async fn register(code: &PairingCode, phone_key: &str, phone_name: &str, tailscale_ready: bool) -> Result<Paired, PairError> {
    let request = RegisterRequest { key: phone_key.to_owned(), name: phone_name.to_owned() };
    // Fail on our own mistakes before going on the network.
    RegisterRequest::parse(&request.command_line())?;
    let private_key = one_time_key(code)?;

    let mut routes: Vec<(String, bool)> = Vec::new();
    if let (true, Some(name)) = (tailscale_ready, &code.t) {
        routes.push((name.clone(), true));
    }
    routes.extend(code.a.iter().map(|a| (a.clone(), false)));

    for (address, via_tailscale) in routes {
        let options = ConnectOptions {
            host: address.clone(),
            port: code.p,
            username: code.u.clone(),
            credentials: Credentials { private_key: Some(private_key.clone()), ..Default::default() },
            // Only the computer that showed the code has this key.
            trusted_host_keys: vec![code.host_key_line()],
            keepalive_secs: 0,
            connect_timeout_secs: if via_tailscale { 10 } else { 5 },
            jump: None,
            forward_agent: false,
            via_tailscale,
        };
        let conn = match Connector::connect(options).await {
            Ok(conn) => conn,
            Err(ConnectError::HostKeyUnknown { .. } | ConnectError::HostKeyChanged { .. }) => return Err(PairError::WrongComputer),
            Err(ConnectError::AuthFailed { .. }) => return Err(PairError::CodeRefused),
            // Not reachable this way: try the next one.
            Err(_) => continue,
        };
        let output = conn.exec(&request.command_line(), 8 * 1024).await;
        conn.disconnect().await;
        let output = output.map_err(|e| PairError::Other(e.to_string()))?;
        let reply: RegisterReply = output
            .stdout
            .lines()
            .rev()
            .find_map(|l| serde_json::from_str(l.trim()).ok())
            .ok_or_else(|| PairError::Other("the computer gave no answer (is the multiplex package installed there?)".into()))?;
        if !reply.ok {
            return Err(PairError::Refused(reply.error));
        }
        return Ok(Paired { computer: reply.computer, address, via_tailscale, features: reply.features });
    }
    Err(PairError::Unreachable { name: code.n.clone() })
}
