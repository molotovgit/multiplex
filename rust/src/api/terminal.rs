//! The interactive shell Flutter draws and types into.
//!
//! Every method here is synchronous and fast: input is queued for the
//! network task and `frame` copies the current screen. That keeps typing
//! and scrolling smooth on the UI thread.

use std::sync::Arc;

use flutter_rust_bridge::frb;

use crate::api::terminal_types::{KeyModifiers, ShellEvent, TerminalFrame, TerminalKey, TerminalPalette};
use crate::engine::events::EventRelay;
use crate::engine::shell::ShellSession;
use crate::frb_generated::StreamSink;

/// A running shell on the server.
#[frb(opaque)]
pub struct RemoteShell {
    inner: Arc<ShellSession>,
    events: Arc<EventRelay<ShellEvent>>,
}

impl RemoteShell {
    pub(crate) fn new(inner: ShellSession, events: Arc<EventRelay<ShellEvent>>) -> Self {
        Self { inner: Arc::new(inner), events }
    }

    /// The engine shell, for other API objects (such as a new connection
    /// taking this shell over).
    pub(crate) fn engine(&self) -> Arc<ShellSession> {
        self.inner.clone()
    }

    /// Screen changes, title, bell, clipboard and exit, as a stream.
    /// Listen once per shell.
    pub fn events(&self, sink: StreamSink<ShellEvent>) {
        self.events.attach(Arc::new(move |event| sink.add(event).is_ok()));
    }

    /// The screen as it is now, ready to paint.
    #[frb(sync)]
    pub fn frame(&self) -> TerminalFrame {
        self.inner.frame()
    }

    #[frb(sync)]
    pub fn send_text(&self, text: String, mods: KeyModifiers) {
        self.inner.send_text(&text, mods);
    }

    #[frb(sync)]
    pub fn send_key(&self, key: TerminalKey, mods: KeyModifiers) {
        self.inner.send_key(key, mods);
    }

    #[frb(sync)]
    pub fn paste(&self, text: String) {
        self.inner.paste(&text);
    }

    #[frb(sync)]
    pub fn resize(&self, cols: u16, rows: u16) {
        self.inner.resize(cols, rows);
    }

    /// Scroll gesture of `lines` (positive = older output) over a cell.
    /// Returns true when the view moved and should be redrawn now.
    #[frb(sync)]
    pub fn scroll(&self, lines: i32, row: u16, col: u16) -> bool {
        self.inner.scroll(lines, row, col)
    }

    /// Tap on a cell; true if it was sent as a mouse click.
    #[frb(sync)]
    pub fn click(&self, row: u16, col: u16) -> bool {
        self.inner.click(row, col)
    }

    #[frb(sync)]
    pub fn scroll_to_bottom(&self) {
        self.inner.scroll_to_bottom();
    }

    /// Text between two visible cells (inclusive), for copying.
    #[frb(sync)]
    pub fn text_between(&self, start_row: u16, start_col: u16, end_row: u16, end_col: u16) -> String {
        self.inner.text_between((start_row, start_col), (end_row, end_col))
    }

    #[frb(sync)]
    pub fn visible_text(&self) -> String {
        self.inner.visible_text()
    }

    #[frb(sync)]
    pub fn set_palette(&self, palette: TerminalPalette) {
        self.inner.set_palette(palette);
    }

    #[frb(sync)]
    pub fn clear_history(&self) {
        self.inner.clear_history();
    }

    #[frb(sync)]
    pub fn is_closed(&self) -> bool {
        self.inner.is_closed()
    }

    #[frb(sync)]
    pub fn close(&self) {
        self.inner.close();
    }
}
