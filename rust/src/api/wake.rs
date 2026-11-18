//! Switching a paired computer on from the phone (Wake-on-LAN).

use crate::engine::runtime::AsyncRuntime;
use crate::engine::wol;

/// Broadcasts the wake signal for the network card `mac` ("aa:bb:…").
/// `home_address` is the computer's address on its home network, when
/// known. It works only from that network.
pub async fn wake_on_lan(mac: String, home_address: Option<String>) -> anyhow::Result<()> {
    AsyncRuntime::run(async move { wol::wake(&mac, home_address.as_deref()).await }).await??;
    Ok(())
}
