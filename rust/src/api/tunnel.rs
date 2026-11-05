//! Running port forwards, as Flutter sees them.

use std::sync::Arc;

use flutter_rust_bridge::frb;

use crate::api::tunnel_types::{TunnelSpec, TunnelStats};
use crate::engine::runtime::AsyncRuntime;
use crate::engine::tunnel::Tunnel;

#[frb(opaque)]
pub struct ActiveTunnel {
    inner: Arc<Tunnel>,
}

impl ActiveTunnel {
    pub(crate) fn new(inner: Tunnel) -> Self {
        Self { inner: Arc::new(inner) }
    }

    #[frb(sync)]
    pub fn spec(&self) -> TunnelSpec {
        self.inner.spec().clone()
    }

    /// The port in use (the system picks one when 0 was requested).
    #[frb(sync)]
    pub fn bound_port(&self) -> u16 {
        self.inner.bound_port()
    }

    #[frb(sync)]
    pub fn stats(&self) -> TunnelStats {
        self.inner.stats()
    }

    #[frb(sync)]
    pub fn is_running(&self) -> bool {
        self.inner.is_running()
    }

    pub async fn stop(&self) {
        let inner = self.inner.clone();
        let _ = AsyncRuntime::run(async move { inner.stop().await }).await;
    }
}
