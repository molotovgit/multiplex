//! Shared pieces for every kind of tunnel: traffic counters and the code
//! that copies bytes between a local socket and an SSH channel.

use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};

use tokio::io::{AsyncRead, AsyncWrite};

use crate::api::tunnel_types::TunnelStats;

/// Live numbers about a tunnel. Updated from many tasks at once, so every
/// field is atomic.
#[derive(Default)]
pub struct TunnelCounters {
    total: AtomicU64,
    active: AtomicU32,
    bytes_out: AtomicU64,
    bytes_in: AtomicU64,
}

impl TunnelCounters {
    pub fn snapshot(&self) -> TunnelStats {
        TunnelStats {
            connections_total: self.total.load(Ordering::Relaxed),
            connections_active: self.active.load(Ordering::Relaxed),
            bytes_sent: self.bytes_out.load(Ordering::Relaxed),
            bytes_received: self.bytes_in.load(Ordering::Relaxed),
        }
    }

    fn opened(&self) {
        self.total.fetch_add(1, Ordering::Relaxed);
        self.active.fetch_add(1, Ordering::Relaxed);
    }

    fn closed(&self, sent: u64, received: u64) {
        self.active.fetch_sub(1, Ordering::Relaxed);
        self.bytes_out.fetch_add(sent, Ordering::Relaxed);
        self.bytes_in.fetch_add(received, Ordering::Relaxed);
    }
}

/// Copies bytes both ways until either side closes.
pub struct Pipe;

impl Pipe {
    /// `local` is the socket on this device, `remote` the SSH channel.
    /// Traffic is added to `counters` when the connection ends.
    pub async fn run<L, R>(mut local: L, mut remote: R, counters: &TunnelCounters)
    where
        L: AsyncRead + AsyncWrite + Unpin,
        R: AsyncRead + AsyncWrite + Unpin,
    {
        counters.opened();
        let (sent, received) = tokio::io::copy_bidirectional(&mut local, &mut remote)
            .await
            .unwrap_or((0, 0));
        counters.closed(sent, received);
    }
}
