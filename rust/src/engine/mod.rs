//! The engine: all real work happens here, independent of Flutter.
//!
//! The `api` module is a thin layer on top that Flutter calls. Keeping the
//! engine free of Flutter types means it can be tested with plain Rust.

pub mod events;
pub mod runtime;
pub mod terminal;
