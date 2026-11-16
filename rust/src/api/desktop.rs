//! The remote desktop Flutter shows and sends input to.
//!
//! Every input method is synchronous and only queues a message, so touch
//! and typing never wait on the network. The video never comes through
//! here: it goes from the network straight to the hardware decoder, which
//! draws into the texture the app passed in [`DesktopOptions::texture_id`].

use std::sync::Arc;

use flutter_rust_bridge::frb;

use crate::api::desktop_types::{DesktopButton, DesktopEvent};
use crate::engine::desktop::DesktopSession;
use crate::engine::events::EventRelay;
use crate::frb_generated::StreamSink;

/// A running remote desktop.
#[frb(opaque)]
pub struct RemoteDesktop {
    inner: Arc<DesktopSession>,
    events: Arc<EventRelay<DesktopEvent>>,
}

impl RemoteDesktop {
    pub(crate) fn new(inner: DesktopSession, events: Arc<EventRelay<DesktopEvent>>) -> Self {
        Self { inner: Arc::new(inner), events }
    }

    /// Stream shape, cursor, clipboard, stats and the end, as a stream.
    /// Listen once per desktop.
    pub fn events(&self, sink: StreamSink<DesktopEvent>) {
        self.events.attach(Arc::new(move |event| sink.add(event).is_ok()));
    }

    /// Moves the remote pointer to `x`, `y` (logical remote pixels).
    #[frb(sync)]
    pub fn pointer_move(&self, x: f64, y: f64) {
        self.inner.pointer_move(x, y);
    }

    #[frb(sync)]
    pub fn button(&self, button: DesktopButton, pressed: bool) {
        self.inner.pointer_button(button.code(), pressed);
    }

    /// Presses and releases a button (a click).
    #[frb(sync)]
    pub fn click(&self, button: DesktopButton) {
        self.inner.pointer_button(button.code(), true);
        self.inner.pointer_button(button.code(), false);
    }

    /// Scrolls by logical pixels; `wheel` sends mouse-wheel steps.
    #[frb(sync)]
    pub fn scroll(&self, dx: f64, dy: f64, wheel: bool) {
        self.inner.scroll(dx, dy, wheel);
    }

    #[frb(sync)]
    pub fn scroll_stop(&self) {
        self.inner.scroll_stop();
    }

    /// Presses or releases a key (Linux input code, US layout).
    #[frb(sync)]
    pub fn key(&self, code: u32, pressed: bool) {
        self.inner.key(code, pressed);
    }

    /// Taps a key while holding `modifiers` (Linux input codes), for
    /// example Super+Enter.
    #[frb(sync)]
    pub fn chord(&self, modifiers: Vec<u32>, code: u32) {
        for m in &modifiers {
            self.inner.key(*m, true);
        }
        self.inner.key(code, true);
        self.inner.key(code, false);
        for m in modifiers.iter().rev() {
            self.inner.key(*m, false);
        }
    }

    /// The view changed size (rotation, split screen) or the text size
    /// changed.
    #[frb(sync)]
    pub fn resize(&self, width: u32, height: u32, scale: f64) {
        self.inner.resize(width, height, scale);
    }

    /// Asks for a full picture (after the view was rebuilt).
    #[frb(sync)]
    pub fn refresh(&self) {
        self.inner.request_keyframe();
    }

    /// Puts text on the remote clipboard.
    #[frb(sync)]
    pub fn set_clipboard(&self, text: String) {
        self.inner.set_clipboard(text);
    }

    #[frb(sync)]
    pub fn is_closed(&self) -> bool {
        self.inner.is_closed()
    }

    /// Ends the desktop. The connection stays open.
    #[frb(sync)]
    pub fn close(&self) {
        self.inner.close();
    }
}
