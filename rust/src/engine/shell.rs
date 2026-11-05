//! An interactive shell: a remote terminal joined to the native emulator.
//!
//! Two background tasks run per shell:
//! - the reader takes server output, feeds it to the emulator and tells the
//!   app the screen changed;
//! - the writer sends keys, pastes and size changes to the server, in the
//!   order they happened.
//!
//! The app never waits on the network: sending a key just queues it, and
//! drawing just copies the current screen.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};

use russh::client::Msg;
use russh::{ChannelMsg, ChannelReadHalf, ChannelWriteHalf};
use tokio::sync::mpsc;

use crate::api::terminal_types::{
    KeyModifiers, ShellEvent, ShellOptions, TerminalFrame, TerminalKey, TerminalPalette,
};
use crate::engine::events::SharedSink;
use crate::engine::runtime::AsyncRuntime;
use crate::engine::ssh::Connection;
use crate::engine::terminal::{ColorResolver, FrameBuilder, InputModes, KeyEncoder, TerminalEmulator};

/// Work for the writer task.
enum Outgoing {
    Bytes(Vec<u8>),
    Resize { cols: u16, rows: u16 },
    Close,
}

/// The emulator and its colours, guarded together.
struct Screen {
    emulator: TerminalEmulator,
    colors: ColorResolver,
}

/// State shared between the app-facing handle and the background tasks.
struct Shared {
    screen: Mutex<Screen>,
    /// True while a "Changed" event is waiting to be picked up.
    dirty: AtomicBool,
    closed: AtomicBool,
}

impl Shared {
    fn screen(&self) -> MutexGuard<'_, Screen> {
        // A panic while holding the lock would poison it; the screen data
        // is still usable, so keep going instead of crashing the app.
        self.screen.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

/// Handle the app uses to drive one shell.
pub struct ShellSession {
    outgoing: mpsc::UnboundedSender<Outgoing>,
    shared: Arc<Shared>,
}

impl ShellSession {
    /// Mouse-wheel steps are sent as this many arrow presses in full-screen
    /// programs that do not understand the mouse (less, man).
    const ARROWS_PER_WHEEL_STEP: usize = 3;

    /// Opens a terminal on the server and starts the shell.
    pub async fn open(conn: &Connection, options: ShellOptions, events: SharedSink<ShellEvent>) -> anyhow::Result<Self> {
        let channel = conn.handle().channel_open_session().await?;
        channel
            .request_pty(true, &options.term, u32::from(options.cols), u32::from(options.rows), 0, 0, &[])
            .await?;
        for var in &options.env {
            // Servers often refuse custom variables; that is not fatal.
            let _ = channel.set_env(false, var.name.clone(), var.value.clone()).await;
        }
        channel.request_shell(true).await?;

        let shared = Arc::new(Shared {
            screen: Mutex::new(Screen {
                emulator: TerminalEmulator::new(options.rows, options.cols, options.scrollback_lines as usize),
                colors: ColorResolver::new(options.palette.clone()),
            }),
            dirty: AtomicBool::new(false),
            closed: AtomicBool::new(false),
        });
        let (tx, rx) = mpsc::unbounded_channel();
        let (reader, writer) = channel.split();

        AsyncRuntime::spawn(Self::write_loop(writer, rx));
        AsyncRuntime::spawn(Self::read_loop(reader, shared.clone(), tx.clone(), events));

        if let Some(command) = options.startup_command.filter(|c| !c.trim().is_empty()) {
            let _ = tx.send(Outgoing::Bytes(format!("{command}\r").into_bytes()));
        }
        Ok(Self { outgoing: tx, shared })
    }

    /// The current screen, ready to draw. Taking a frame re-arms the
    /// "Changed" event.
    pub fn frame(&self) -> TerminalFrame {
        self.shared.dirty.store(false, Ordering::SeqCst);
        let mut screen = self.shared.screen();
        let Screen { emulator, colors } = &mut *screen;
        FrameBuilder::new(colors).build(emulator)
    }

    /// Typed text. Jumps back to the live screen like real terminals do.
    pub fn send_text(&self, text: &str, mods: KeyModifiers) {
        let bytes = self.with_encoder(|encoder| encoder.text(text, mods));
        self.send(bytes);
    }

    pub fn send_key(&self, key: TerminalKey, mods: KeyModifiers) {
        let bytes = self.with_encoder(|encoder| encoder.key(key, mods));
        self.send(bytes);
    }

    pub fn paste(&self, text: &str) {
        let bytes = self.with_encoder(|encoder| encoder.paste(text));
        self.send(bytes);
    }

    /// New terminal size in cells (the phone rotated, the keyboard opened).
    pub fn resize(&self, cols: u16, rows: u16) {
        {
            let mut screen = self.shared.screen();
            if screen.emulator.size() == (rows, cols) {
                return;
            }
            screen.emulator.resize(rows, cols);
        }
        let _ = self.outgoing.send(Outgoing::Resize { cols, rows });
    }

    /// A scroll gesture of `lines` (positive = towards older output) at a
    /// cell. In full-screen programs it becomes mouse-wheel or arrow-key
    /// input; otherwise it moves through history. Returns true when the
    /// view itself moved and needs redrawing.
    pub fn scroll(&self, lines: i32, row: u16, col: u16) -> bool {
        let mut screen = self.shared.screen();
        let terminal = screen.emulator.screen();
        if !terminal.alternate_screen() {
            screen.emulator.scroll_by(lines);
            return true;
        }
        let modes = InputModes::from_screen(terminal);
        let encoder = KeyEncoder::new(modes);
        let up = lines > 0;
        let steps = lines.unsigned_abs() as usize;
        let mut bytes = Vec::new();
        for _ in 0..steps {
            match encoder.wheel(up, row, col) {
                Some(wheel) => bytes.extend(wheel),
                None => {
                    let key = if up { TerminalKey::Up } else { TerminalKey::Down };
                    for _ in 0..Self::ARROWS_PER_WHEEL_STEP {
                        bytes.extend(encoder.key(key, KeyModifiers::default()));
                    }
                }
            }
        }
        drop(screen);
        self.send_raw(bytes);
        false
    }

    /// A tap at a cell. Sent as a mouse click when the program asked for
    /// mouse input (htop, mc). Returns true if it was sent.
    pub fn click(&self, row: u16, col: u16) -> bool {
        let bytes = self.with_encoder(|encoder| encoder.click(row, col));
        match bytes {
            Some(bytes) => {
                self.send_raw(bytes);
                true
            }
            None => false,
        }
    }

    pub fn scroll_to_bottom(&self) {
        self.shared.screen().emulator.scroll_to_bottom();
    }

    /// Text between two visible cells, for copying.
    pub fn text_between(&self, start: (u16, u16), end: (u16, u16)) -> String {
        self.shared.screen().emulator.text_between(start, end)
    }

    /// Everything on the visible screen as plain text.
    pub fn visible_text(&self) -> String {
        self.shared.screen().emulator.screen().contents()
    }

    pub fn set_palette(&self, palette: TerminalPalette) {
        self.shared.screen().colors = ColorResolver::new(palette);
    }

    pub fn clear_history(&self) {
        self.shared.screen().emulator.clear_history();
    }

    pub fn is_closed(&self) -> bool {
        self.shared.closed.load(Ordering::SeqCst)
    }

    /// Ends the shell politely (EOF, then close).
    pub fn close(&self) {
        let _ = self.outgoing.send(Outgoing::Close);
    }

    fn with_encoder<T>(&self, f: impl FnOnce(&KeyEncoder) -> T) -> T {
        let mut screen = self.shared.screen();
        screen.emulator.scroll_to_bottom();
        let encoder = KeyEncoder::new(InputModes::from_screen(screen.emulator.screen()));
        f(&encoder)
    }

    fn send(&self, bytes: Vec<u8>) {
        self.send_raw(bytes);
    }

    fn send_raw(&self, bytes: Vec<u8>) {
        if !bytes.is_empty() {
            let _ = self.outgoing.send(Outgoing::Bytes(bytes));
        }
    }

    async fn write_loop(writer: ChannelWriteHalf<Msg>, mut rx: mpsc::UnboundedReceiver<Outgoing>) {
        while let Some(job) = rx.recv().await {
            let result = match job {
                Outgoing::Bytes(bytes) => writer.data_bytes(bytes).await,
                Outgoing::Resize { cols, rows } => writer.window_change(u32::from(cols), u32::from(rows), 0, 0).await,
                Outgoing::Close => {
                    let _ = writer.eof().await;
                    let _ = writer.close().await;
                    break;
                }
            };
            if result.is_err() {
                break;
            }
        }
    }

    async fn read_loop(
        mut reader: ChannelReadHalf,
        shared: Arc<Shared>,
        replies: mpsc::UnboundedSender<Outgoing>,
        events: SharedSink<ShellEvent>,
    ) {
        let mut exit_code = None;
        while let Some(msg) = reader.wait().await {
            let data = match msg {
                ChannelMsg::Data { data } => data,
                ChannelMsg::ExtendedData { data, .. } => data,
                ChannelMsg::ExitStatus { exit_status } => {
                    exit_code = Some(exit_status);
                    continue;
                }
                ChannelMsg::Close => break,
                _ => continue,
            };
            let signals = shared.screen().emulator.process(&data);
            if !signals.replies.is_empty() {
                let _ = replies.send(Outgoing::Bytes(signals.replies));
            }
            if let Some(title) = signals.title {
                events.emit(ShellEvent::Title(title));
            }
            if signals.bell {
                events.emit(ShellEvent::Bell);
            }
            if let Some(text) = signals.clipboard {
                events.emit(ShellEvent::Clipboard(text));
            }
            if !shared.dirty.swap(true, Ordering::SeqCst) && !events.emit(ShellEvent::Changed) {
                // Nobody is listening any more: the app closed this shell.
                break;
            }
        }
        shared.closed.store(true, Ordering::SeqCst);
        let _ = replies.send(Outgoing::Close);
        events.emit(match exit_code {
            Some(code) => ShellEvent::Exited { code: Some(code) },
            None => ShellEvent::Disconnected,
        });
    }
}
