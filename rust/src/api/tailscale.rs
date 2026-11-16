//! Tailscale built into Multiplex: sign in, see the tailnet's devices, and
//! connect to them from anywhere without the Tailscale VPN app.

use flutter_rust_bridge::frb;

use crate::api::tailscale_types::TailscaleStatus;
use crate::engine::runtime::AsyncRuntime;
use crate::engine::tailscale;

/// True when this build of the app includes Tailscale.
#[frb(sync)]
pub fn tailscale_available() -> bool {
    tailscale::available()
}

/// Starts the app's Tailscale node. Its state lives in `dir`, so a phone
/// that signed in once stays signed in. `hostname` is the name this phone
/// gets on the tailnet.
pub async fn tailscale_start(dir: String, hostname: String) -> anyhow::Result<()> {
    AsyncRuntime::run(async move { tokio::task::spawn_blocking(move || tailscale::start(&dir, &hostname)).await? }).await?
}

/// The node's state and the tailnet's devices.
pub async fn tailscale_status() -> anyhow::Result<TailscaleStatus> {
    let json = AsyncRuntime::run(async { tokio::task::spawn_blocking(tailscale::status_json).await? }).await??;
    Ok(serde_json::from_str(&json)?)
}

/// Begins signing in; the page to open appears as `auth_url` in the status.
pub async fn tailscale_login() -> anyhow::Result<()> {
    AsyncRuntime::run(async { tokio::task::spawn_blocking(tailscale::login).await? }).await?
}

/// Signs this phone out of the tailnet.
pub async fn tailscale_logout() -> anyhow::Result<()> {
    AsyncRuntime::run(async { tokio::task::spawn_blocking(tailscale::logout).await? }).await?
}
