//! Pairing the phone with a computer by scanning the QR code that
//! `multiplex pair` shows there.

use flutter_rust_bridge::frb;
use multiplex_proto::PairingCode;

use crate::engine::pairing;
use crate::engine::runtime::AsyncRuntime;

/// What a pairing code says, to show before and save after pairing.
#[derive(Debug, Clone)]
pub struct PairingInfo {
    /// The computer's name.
    pub name: String,
    pub user: String,
    pub port: u16,
    /// Home-network addresses, best first.
    pub addresses: Vec<String>,
    /// The computer's name on the tailnet, when it is on one.
    pub tailscale: Option<String>,
    /// The computer's SSH host key, as an OpenSSH public key line.
    pub host_key: String,
    /// The network card's address, for Wake-on-LAN.
    pub mac: Option<String>,
    /// Seconds until the code stops working.
    pub seconds_left: u32,
}

/// How pairing went.
#[derive(Debug, Clone)]
pub struct PairingOutcome {
    pub info: PairingInfo,
    /// The address that worked.
    pub address: String,
    pub via_tailscale: bool,
    /// What the computer has ("gliff", "hyprland", "tailscale", "fcitx5").
    pub features: Vec<String>,
}

fn info_of(code: &PairingCode) -> PairingInfo {
    PairingInfo {
        name: code.n.clone(),
        user: code.u.clone(),
        port: code.p,
        addresses: code.a.clone(),
        tailscale: code.t.clone(),
        host_key: code.host_key_line(),
        mac: code.m.clone(),
        seconds_left: code.x.saturating_sub(pairing::now_unix()).min(u64::from(u32::MAX)) as u32,
    }
}

/// True when the text looks like a Multiplex pairing code (for telling a
/// scanned code from any other QR code).
#[frb(sync)]
pub fn pairing_is_code(text: String) -> bool {
    text.trim().starts_with(multiplex_proto::CODE_PREFIX)
}

/// Reads a scanned or pasted code. Fails with a sentence for the user when
/// it is damaged, expired or not a pairing code.
#[frb(sync)]
pub fn pairing_read(code: String) -> anyhow::Result<PairingInfo> {
    Ok(info_of(&PairingCode::decode(&code, pairing::now_unix())?))
}

/// Pairs: registers `phone_key` (this phone's OpenSSH public key line)
/// under `phone_name` on the computer the code is from. `tailscale_ready`
/// says the app's Tailscale is signed in and may be used to reach it.
pub async fn pairing_register(code: String, phone_key: String, phone_name: String, tailscale_ready: bool) -> anyhow::Result<PairingOutcome> {
    let code = PairingCode::decode(&code, pairing::now_unix())?;
    let paired = AsyncRuntime::run(async move {
        let result = pairing::register(&code, &phone_key, &phone_name, tailscale_ready).await;
        result.map(|p| (p, code))
    })
    .await??;
    let (paired, code) = paired;
    Ok(PairingOutcome { info: info_of(&code), address: paired.address, via_tailscale: paired.via_tailscale, features: paired.features })
}
