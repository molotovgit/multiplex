//! Plain data for the remote desktop (gliff) feature.

/// Which screen of the remote machine to show.
#[derive(Debug, Clone, PartialEq)]
pub enum DesktopMode {
    /// A private screen created for this phone, sized to fit it. The
    /// remote's own monitors are left alone.
    Fitted,
    /// The remote's focused monitor, as it is.
    Mirror,
    /// One named monitor of the remote (for example `DP-1`).
    Output { name: String },
}

/// How to start a remote desktop.
#[derive(Debug, Clone)]
pub struct DesktopOptions {
    pub mode: DesktopMode,
    /// The size of the view on the phone, in physical pixels. A fitted
    /// screen is created at this size; a mirrored one is scaled down to it.
    pub width: u32,
    pub height: u32,
    /// How large things look on a fitted screen (1.0 = 100 %).
    pub scale: f64,
    /// Ask the server for a smaller stream (slow networks).
    pub low_bandwidth: bool,
    /// The texture the video is drawn into (from the platform side).
    pub texture_id: i64,
    /// The command that starts the server. Empty means `gliff-server`.
    pub server_command: String,
}

/// What the remote desktop tells the app.
#[derive(Debug, Clone)]
pub enum DesktopEvent {
    /// The server accepted us.
    Started {
        /// True when the screen is a private one made for this phone.
        fitted: bool,
        output: String,
        /// The remote's monitors.
        outputs: Vec<DesktopOutput>,
    },
    /// The video's shape. Sent first and again whenever it changes.
    Stream {
        /// Video size in pixels.
        width: u32,
        height: u32,
        /// Remote scale: logical size = video size / scale.
        scale: f64,
        /// True when the remote encodes on its graphics card.
        hardware: bool,
    },
    /// The decoder's pictures: `width` x `height` pixels, of which the
    /// top-left `visible_width` x `visible_height` is the screen. The rest
    /// is padding (H.264 codes in 16-pixel blocks) and must not be shown.
    Picture { width: u32, height: u32, visible_width: u32, visible_height: u32 },
    /// A new mouse cursor picture: tightly packed 32-bit BGRA pixels.
    CursorShape {
        id: u32,
        width: u32,
        height: u32,
        hot_x: i32,
        hot_y: i32,
        bgra: Vec<u8>,
    },
    /// Where the remote's cursor is, in logical remote pixels.
    CursorMoved { x: f64, y: f64, shape_id: u32, visible: bool },
    /// Text the remote copied.
    Clipboard { text: String },
    /// Health numbers, about once a second.
    Stats(DesktopStats),
    /// The session is over.
    Ended {
        reason: String,
        /// True when trying again may work (network trouble, a busy
        /// server); false for problems that need fixing first.
        retryable: bool,
    },
}

/// One monitor of the remote machine.
#[derive(Debug, Clone)]
pub struct DesktopOutput {
    pub name: String,
    pub width: u32,
    pub height: u32,
    pub scale: f64,
}

/// How the stream is doing.
#[derive(Debug, Clone, Default)]
pub struct DesktopStats {
    /// Pictures shown per second.
    pub fps: f64,
    /// Video data received, in kilobits per second.
    pub kbps: f64,
    /// Network round trip, in milliseconds.
    pub rtt_ms: f64,
    /// Time from a picture arriving to it being on screen, in milliseconds.
    pub decode_ms: f64,
}

/// Mouse buttons, as the remote expects them (Linux input codes).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DesktopButton {
    Left,
    Right,
    Middle,
    Back,
    Forward,
}

impl DesktopButton {
    pub(crate) fn code(self) -> u32 {
        match self {
            DesktopButton::Left => 0x110,
            DesktopButton::Right => 0x111,
            DesktopButton::Middle => 0x112,
            DesktopButton::Back => 0x113,
            DesktopButton::Forward => 0x114,
        }
    }
}
