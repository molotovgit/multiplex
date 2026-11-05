//! VaultTerm's native core.
//!
//! - `api`: the functions and types Flutter calls (bridged by
//!   flutter_rust_bridge).
//! - `engine`: the actual SSH, SFTP, tunnel, terminal, key and encryption
//!   code, written without any Flutter types so it is easy to test.

pub mod api;
pub mod engine;
mod frb_generated;
