//! Everything in this module is visible to Flutter. flutter_rust_bridge
//! generates the matching Dart code from these files.
//!
//! Files ending in `_types` hold plain data (Dart gets ordinary classes).
//! The others hold the live objects Flutter keeps a handle to.

pub mod app;
pub mod keys;
pub mod sftp;
pub mod sftp_types;
pub mod ssh;
pub mod ssh_types;
pub mod terminal;
pub mod terminal_types;
pub mod tunnel;
pub mod tunnel_types;
pub mod vault;
