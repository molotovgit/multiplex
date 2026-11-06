//! Native terminal emulation: screen state, colours, frames and keys.

pub mod cast;
pub mod emulator;
pub mod frame;
pub mod keys;
pub mod palette;
pub mod search;

pub use emulator::{EmulatorSignals, ShellMark, TerminalEmulator};
pub use frame::FrameBuilder;
pub use keys::{InputModes, KeyEncoder};
pub use palette::ColorResolver;
pub use search::TextSearch;
