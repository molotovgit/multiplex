//! The phone's own screen, shown in a window on a paired computer. The
//! phone captures and encodes it (Android's part); this carries the
//! stream to `multiplex screen` on the computer and keeps it live.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use flutter_rust_bridge::frb;
use multiplex_proto::share::{camera_command, mic_command, screen_command};

use super::ssh::SshSession;
use crate::engine::events::EventRelay;
use crate::engine::pipe::Pipe;
use crate::engine::runtime::AsyncRuntime;
use crate::engine::screen::{completed, kind, Pace, DELIMITER, START_BITRATE};
use crate::frb_generated::StreamSink;

/// The bitrate the encoder starts at, in bits per second (the stream's
/// pacing starts from the same one).
#[frb(sync)]
pub fn screen_start_bitrate() -> u32 {
    START_BITRATE
}

impl SshSession {
    /// Opens the window on the computer. It is there when this returns.
    /// `phone` (the name this phone paired under, or empty) goes in its
    /// title.
    pub async fn open_screen(&self, phone: String) -> anyhow::Result<ScreenStream> {
        let conn = self.conn.clone();
        let ended = Arc::new(EventRelay::<String>::new());
        let relay = ended.clone();
        let inner = AsyncRuntime::run(async move { Pipe::open(conn, &screen_command(&phone), relay).await }).await??;
        let now = Instant::now();
        Ok(ScreenStream { inner, ended, state: Mutex::new(State { pace: Pace::new(now), last_sent: now }) })
    }

    /// Makes the phone's camera a webcam of the computer. It is there
    /// (once the first picture has arrived) for as long as the stream is
    /// open. `turn`: degrees the picture is turned clockwise to stand
    /// upright.
    pub async fn open_camera(&self, phone: String, turn: u32) -> anyhow::Result<ScreenStream> {
        let conn = self.conn.clone();
        let ended = Arc::new(EventRelay::<String>::new());
        let relay = ended.clone();
        let inner = AsyncRuntime::run(async move { Pipe::open(conn, &camera_command(&phone, turn), relay).await }).await??;
        let now = Instant::now();
        Ok(ScreenStream { inner, ended, state: Mutex::new(State { pace: Pace::new(now), last_sent: now }) })
    }
}

impl SshSession {
    /// Makes the phone's microphone a microphone of the computer, for as
    /// long as the stream is open.
    pub async fn open_mic(&self, phone: String) -> anyhow::Result<SoundStream> {
        let conn = self.conn.clone();
        let ended = Arc::new(EventRelay::<String>::new());
        let relay = ended.clone();
        let inner = AsyncRuntime::run(async move { Pipe::open(conn, &mic_command(&phone), relay).await }).await??;
        Ok(SoundStream { inner, ended, skipped: AtomicU64::new(0) })
    }
}

/// More sound than this on its way (a second of it, at 64 kbit/s) would
/// only arrive late.
const LATE_SOUND: u64 = 8_000;

/// A sound stream to the computer (the phone's microphone): AAC frames,
/// each one whole.
#[frb(opaque)]
pub struct SoundStream {
    inner: Pipe,
    ended: Arc<EventRelay<String>>,
    skipped: AtomicU64,
}

impl SoundStream {
    /// Sends the next frame. When the connection is behind, the frame is
    /// left out instead: sound that arrives a second late is of no use,
    /// and each frame stands by itself.
    #[frb(sync)]
    pub fn write(&self, bytes: Vec<u8>) -> ScreenWrite {
        if self.inner.in_flight() > LATE_SOUND {
            self.skipped.fetch_add(1, Ordering::Relaxed);
            return ScreenWrite { ended: false, reason: String::new(), bitrate: None, key_frame: false };
        }
        match self.inner.write(bytes) {
            Ok(()) => ScreenWrite { ended: false, reason: String::new(), bitrate: None, key_frame: false },
            Err(reason) => ScreenWrite { ended: true, reason, bitrate: None, key_frame: false },
        }
    }

    #[frb(sync)]
    pub fn status(&self) -> ScreenStatus {
        ScreenStatus { bitrate: 64_000, in_flight: self.inner.in_flight(), skipped: self.skipped.load(Ordering::Relaxed), skipping: self.inner.in_flight() > LATE_SOUND }
    }

    /// Hears once why the stream ended (empty when it was closed from
    /// here). Listen once.
    pub fn ended(&self, sink: StreamSink<String>) {
        self.ended.attach(Arc::new(move |reason| sink.add(reason).is_ok()));
    }

    #[frb(sync)]
    pub fn close(&self) {
        self.inner.close();
    }
}

/// A picture stream to the computer (the phone's screen for a window,
/// its camera for a webcam): H.264, as the encoder gives it.
#[frb(opaque)]
pub struct ScreenStream {
    inner: Pipe,
    ended: Arc<EventRelay<String>>,
    state: Mutex<State>,
}

struct State {
    pace: Pace,
    last_sent: Instant,
}

/// What came of a piece, and what the encoder should do next.
pub struct ScreenWrite {
    /// The stream has ended (`reason` says why; empty when it was closed
    /// or the window was closed).
    pub ended: bool,
    pub reason: String,
    /// Set the encoder to this many bits per second.
    pub bitrate: Option<u32>,
    /// Ask the encoder for a full picture now.
    pub key_frame: bool,
}

/// How the stream is doing, for the log.
pub struct ScreenStatus {
    pub bitrate: u32,
    /// Bytes sent that the computer has not taken yet.
    pub in_flight: u64,
    /// Pieces skipped because the connection could not keep up.
    pub skipped: u64,
    pub skipping: bool,
}

impl ScreenStream {
    /// Sends the next piece from the encoder, or skips it when the
    /// connection is behind (the window then catches up instead of
    /// showing the past).
    #[frb(sync)]
    pub fn write(&self, bytes: Vec<u8>) -> ScreenWrite {
        let now = Instant::now();
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        let piece = kind(&bytes);
        let step = state.pace.next(self.inner.in_flight(), piece, now);
        let sent = if step.send {
            self.inner.write(completed(bytes, piece))
        } else if now.duration_since(state.last_sent) >= Duration::from_secs(1) {
            // Nothing has gone out for a while: say the phone is still here.
            self.inner.write(DELIMITER.to_vec())
        } else {
            return ScreenWrite { ended: false, reason: String::new(), bitrate: step.bitrate, key_frame: step.key_frame };
        };
        state.last_sent = now;
        match sent {
            Ok(()) => ScreenWrite { ended: false, reason: String::new(), bitrate: step.bitrate, key_frame: step.key_frame },
            Err(reason) => ScreenWrite { ended: true, reason, bitrate: None, key_frame: false },
        }
    }

    #[frb(sync)]
    pub fn status(&self) -> ScreenStatus {
        let state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        ScreenStatus { bitrate: state.pace.bitrate(), in_flight: self.inner.in_flight(), skipped: state.pace.skipped(), skipping: state.pace.skipping() }
    }

    /// Hears once why the stream ended (empty when it was closed from
    /// here or the window was closed). Listen once.
    pub fn ended(&self, sink: StreamSink<String>) {
        self.ended.attach(Arc::new(move |reason| sink.add(reason).is_ok()));
    }

    #[frb(sync)]
    pub fn close(&self) {
        self.inner.close();
    }
}
