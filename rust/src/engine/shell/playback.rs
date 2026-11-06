//! Recording a shell's output, and shells without a server that play a
//! recording back on the same emulator.

use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use tokio::sync::mpsc;

use super::{Screen, ShellSession, Shared};
use crate::api::terminal_types::{ShellEvent, TerminalPalette};
use crate::engine::events::SharedSink;
use crate::engine::terminal::cast::CastRecorder;
use crate::engine::terminal::{ColorResolver, TerminalEmulator};

impl Shared {
    /// Runs `f` on the recorder, if a recording is running.
    pub(super) fn record(&self, f: impl FnOnce(&mut CastRecorder)) {
        if let Some(recorder) = self.recorder.lock().unwrap_or_else(|p| p.into_inner()).as_mut() {
            f(recorder);
        }
    }
}

impl ShellSession {
    /// A shell with no server behind it, for playing a recording: output
    /// comes from [`ShellSession::feed`], input goes nowhere.
    pub fn offline(cols: u16, rows: u16, palette: TerminalPalette, events: SharedSink<ShellEvent>) -> Self {
        let shared = Arc::new(Shared {
            screen: Mutex::new(Screen {
                emulator: TerminalEmulator::new(rows, cols, 1000),
                colors: ColorResolver::new(palette),
            }),
            dirty: AtomicBool::new(false),
            closed: AtomicBool::new(false),
            events,
            generation: AtomicU64::new(0),
            recorder: Mutex::new(None),
        });
        // Nobody reads this queue, so keys and pastes are dropped.
        let (tx, _) = mpsc::unbounded_channel();
        Self { outgoing: Mutex::new(tx), shared }
    }

    /// Output to show, as if the server had sent it.
    pub fn feed(&self, data: &[u8]) {
        self.shared.screen().emulator.process(data);
        if !self.shared.dirty.swap(true, Ordering::SeqCst) {
            self.shared.events.emit(ShellEvent::Changed);
        }
    }

    /// Clears the screen and history, for playing from the start again.
    pub fn reset_screen(&self) {
        let mut screen = self.shared.screen();
        let (rows, cols) = screen.emulator.size();
        screen.emulator = TerminalEmulator::new(rows, cols, 1000);
        drop(screen);
        self.feed(b"");
    }

    /// Starts writing everything the server sends to an asciinema file
    /// at `path`. A running recording is finished first.
    pub fn start_recording(&self, path: &Path, title: &str) -> std::io::Result<()> {
        let (rows, cols) = self.shared.screen().emulator.size();
        let recorder = CastRecorder::create(path, cols, rows, title)?;
        let old = self.shared.recorder.lock().unwrap_or_else(|p| p.into_inner()).replace(recorder);
        if let Some(old) = old {
            old.finish()?;
        }
        Ok(())
    }

    /// Ends the recording and closes its file. False when none ran.
    pub fn stop_recording(&self) -> std::io::Result<bool> {
        let recorder = self.shared.recorder.lock().unwrap_or_else(|p| p.into_inner()).take();
        match recorder {
            Some(recorder) => recorder.finish().map(|_| true),
            None => Ok(false),
        }
    }

    pub fn is_recording(&self) -> bool {
        self.shared.recorder.lock().unwrap_or_else(|p| p.into_inner()).is_some()
    }

    /// Leaves output out of the recording while a password prompt shows.
    pub fn set_recording_paused(&self, paused: bool) {
        self.shared.record(|r| r.set_paused(paused));
    }
}
