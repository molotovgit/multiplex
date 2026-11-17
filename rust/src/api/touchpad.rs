//! The computer's pointer and keys from the phone, without its picture.
//! See [`crate::engine::touchpad`].

use std::sync::Arc;

use flutter_rust_bridge::frb;
use multiplex_proto::input::{Button, InputEvent, MAX_KEY};

use super::ssh::SshSession;
use crate::engine::events::EventRelay;
use crate::engine::runtime::AsyncRuntime;
use crate::engine::touchpad::Touchpad;
use crate::frb_generated::StreamSink;

#[derive(Debug, Clone, Copy)]
pub enum TouchpadButton {
    Left,
    Right,
    Middle,
}

impl SshSession {
    /// Starts a touchpad and keyboard on the computer. It is ready when
    /// this returns.
    pub async fn open_touchpad(&self) -> anyhow::Result<RemoteTouchpad> {
        let conn = self.conn.clone();
        let ended = Arc::new(EventRelay::<String>::new());
        let relay = ended.clone();
        let inner = AsyncRuntime::run(async move { Touchpad::open(conn, relay).await }).await??;
        Ok(RemoteTouchpad { inner, ended })
    }
}

/// A touchpad and keyboard on the computer. Every call returns at once;
/// events go out in order, movements that pile up joined into one.
#[frb(opaque)]
pub struct RemoteTouchpad {
    inner: Touchpad,
    ended: Arc<EventRelay<String>>,
}

impl RemoteTouchpad {
    /// Moves the pointer by this much.
    #[frb(sync)]
    pub fn move_by(&self, dx: f64, dy: f64) {
        self.inner.send(InputEvent::Move { dx, dy });
    }

    #[frb(sync)]
    pub fn scroll(&self, dx: f64, dy: f64) {
        self.inner.send(InputEvent::Scroll { dx, dy });
    }

    #[frb(sync)]
    pub fn button(&self, button: TouchpadButton, down: bool) {
        let button = match button {
            TouchpadButton::Left => Button::Left,
            TouchpadButton::Right => Button::Right,
            TouchpadButton::Middle => Button::Middle,
        };
        self.inner.send(InputEvent::Button { button, down });
    }

    /// A key by its Linux code, pressed or released.
    #[frb(sync)]
    pub fn key(&self, code: u32, down: bool) {
        if (1..=u32::from(MAX_KEY)).contains(&code) {
            self.inner.send(InputEvent::Key { code: code as u16, down });
        }
    }

    /// Puts text on the computer's clipboard and pastes it (for text the
    /// US keyboard cannot type).
    #[frb(sync)]
    pub fn paste(&self, text: String) {
        self.inner.send(InputEvent::Paste { text });
    }

    #[frb(sync)]
    pub fn release_all(&self) {
        self.inner.send(InputEvent::ReleaseAll);
    }

    /// Hears once why the touchpad stopped (empty when it was closed from
    /// here). Listen once.
    pub fn ended(&self, sink: StreamSink<String>) {
        self.ended.attach(Arc::new(move |reason| sink.add(reason).is_ok()));
    }

    #[frb(sync)]
    pub fn close(&self) {
        self.inner.close();
    }
}
