//! Everything in this module is visible to Flutter. flutter_rust_bridge
//! generates the matching Dart code from these files.
//!
//! Files ending in `_types` hold plain data (Dart gets ordinary classes).
//! The others hold the live objects Flutter keeps a handle to.

pub mod agents;
pub mod app;
pub mod desk;
pub mod desk_types;
pub mod desktop;
pub mod desktop_types;
pub mod herd;
pub mod herd_types;
pub mod keys;
pub mod pairing;
pub mod share;
pub mod screen;
pub mod sftp;
pub mod speaker;
pub mod sftp_types;
pub mod ssh;
pub mod ssh_types;
pub mod tailscale;
pub mod tailscale_types;
pub mod terminal;
pub mod terminal_types;
pub mod theme;
pub mod theme_types;
pub mod touchpad;
pub mod transfer;
pub mod transfer_types;
pub mod tunnel;
pub mod tunnel_types;
pub mod vault;
pub mod wake;
pub mod watch;
