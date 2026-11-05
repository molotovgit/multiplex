//! Native terminal emulation: screen state, colours, frames and keys.

pub mod emulator;
pub mod frame;
pub mod keys;
pub mod palette;

pub use emulator::{EmulatorSignals, TerminalEmulator};
pub use frame::FrameBuilder;
pub use keys::{InputModes, KeyEncoder};
pub use palette::ColorResolver;
