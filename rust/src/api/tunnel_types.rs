//! Plain data describing port forwards (tunnels).

/// The three kinds of SSH port forwarding.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TunnelKind {
    /// `ssh -L`: a port on this device leads to a host the server can reach.
    Local,
    /// `ssh -R`: a port on the server leads to a host this device can reach.
    Remote,
    /// `ssh -D`: a SOCKS5 proxy on this device; apps choose the target.
    Dynamic,
}

/// What to forward.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TunnelSpec {
    pub kind: TunnelKind,
    /// Address to listen on. For Local/Dynamic usually 127.0.0.1, for
    /// Remote the address on the server (127.0.0.1 or 0.0.0.0).
    pub bind_host: String,
    /// Port to listen on. 0 lets the system pick a free one.
    pub bind_port: u16,
    /// Where connections go. Not used for Dynamic.
    pub target_host: String,
    pub target_port: u16,
}

/// Traffic numbers of a running tunnel.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct TunnelStats {
    pub connections_total: u64,
    pub connections_active: u32,
    /// Bytes from this device to the far side (finished connections).
    pub bytes_sent: u64,
    pub bytes_received: u64,
}
