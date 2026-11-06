//! Plain data that describes what the terminal shows and what the user
//! pressed. Flutter gets these as normal Dart classes.

/// A ready-to-draw picture of the terminal screen.
#[derive(Debug, Clone, PartialEq)]
pub struct TerminalFrame {
    pub rows: u16,
    pub cols: u16,
    /// One entry per visible row, top to bottom.
    pub lines: Vec<TerminalLine>,
    pub cursor: TerminalCursor,
    /// How many lines the view is scrolled back into history (0 = live).
    pub scroll_offset: u32,
    /// How many lines of history exist.
    pub scrollback_len: u32,
    /// True while a full-screen program (vim, htop, less) is running.
    pub alternate_screen: bool,
    /// True when the program wants mouse clicks and wheel events.
    pub mouse_reporting: bool,
    /// Window title set by the remote program, empty if none.
    pub title: String,
    /// Default background colour as 0xAARRGGBB.
    pub background: u32,
    /// Default text colour as 0xAARRGGBB.
    pub foreground: u32,
}

/// One row of the screen, cut into pieces that share the same style.
#[derive(Debug, Clone, PartialEq)]
pub struct TerminalLine {
    /// Changes whenever the content of the row changes. Flutter uses it to
    /// reuse the text it already laid out.
    pub key: u64,
    pub runs: Vec<TextRun>,
}

/// A piece of text with one style, placed at a column.
#[derive(Debug, Clone, PartialEq)]
pub struct TextRun {
    /// Column where the piece starts (0-based).
    pub col: u16,
    /// How many cells the piece covers. Wide characters (CJK, emoji) take 2.
    pub width: u16,
    pub text: String,
    /// Text colour as 0xAARRGGBB.
    pub fg: u32,
    /// Background colour as 0xAARRGGBB, or 0 when it is the default
    /// background (nothing to paint).
    pub bg: u32,
    /// Bit flags, see [`RunStyle`].
    pub style: u8,
}

/// Bits used in [`TextRun::style`].
pub struct RunStyle;

impl RunStyle {
    pub const BOLD: u8 = 1;
    pub const ITALIC: u8 = 2;
    pub const UNDERLINE: u8 = 4;
    /// The piece holds a single wide character.
    pub const WIDE: u8 = 8;
}

/// Where the cursor is and how it looks.
#[derive(Debug, Clone, PartialEq)]
pub struct TerminalCursor {
    pub row: u16,
    pub col: u16,
    pub visible: bool,
    pub shape: CursorShape,
    pub color: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CursorShape {
    Block,
    Underline,
    Bar,
}

/// Special keys that are not plain text.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TerminalKey {
    Enter,
    Tab,
    Backspace,
    Escape,
    Up,
    Down,
    Left,
    Right,
    Home,
    End,
    PageUp,
    PageDown,
    Insert,
    Delete,
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
}

/// Which modifier keys are held.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct KeyModifiers {
    pub ctrl: bool,
    pub alt: bool,
    pub shift: bool,
}

/// Colours of a terminal theme, all as 0xAARRGGBB.
#[derive(Debug, Clone, PartialEq)]
pub struct TerminalPalette {
    /// The 16 basic colours: black, red, green, yellow, blue, magenta,
    /// cyan, white, then the 8 bright versions.
    pub ansi: Vec<u32>,
    pub foreground: u32,
    pub background: u32,
    pub cursor: u32,
    /// Show bold text in the bright colour, like many classic terminals.
    pub bold_is_bright: bool,
}

impl Default for TerminalPalette {
    /// A calm dark theme, used until the app sends its own.
    fn default() -> Self {
        Self {
            ansi: vec![
                0xFF1B1D1E, 0xFFE0605A, 0xFF8FBF6A, 0xFFE2B65C, 0xFF6B9BD8, 0xFFB78AD6,
                0xFF5FB8B2, 0xFFD4D0C8, 0xFF5C6166, 0xFFF07F78, 0xFFA9D88A, 0xFFF3CD7E,
                0xFF8DB6EA, 0xFFCDA8E6, 0xFF82D2CC, 0xFFF4F1EA,
            ],
            foreground: 0xFFE6E1D6,
            background: 0xFF141618,
            cursor: 0xFFF2B33D,
            bold_is_bright: false,
        }
    }
}

/// Settings for opening an interactive shell.
#[derive(Debug, Clone, PartialEq)]
pub struct ShellOptions {
    pub cols: u16,
    pub rows: u16,
    /// Terminal type announced to the server, usually `xterm-256color`.
    pub term: String,
    /// Lines of history to keep.
    pub scrollback_lines: u32,
    /// Environment variables to ask the server to set (many servers only
    /// allow a few, such as LANG).
    pub env: Vec<EnvVar>,
    /// Command typed automatically once the shell is ready.
    pub startup_command: Option<String>,
    /// Run this command instead of the login shell (for example tmux).
    pub command: Option<String>,
    pub palette: TerminalPalette,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EnvVar {
    pub name: String,
    pub value: String,
}

/// Things a running shell reports to the app.
#[derive(Debug, Clone, PartialEq)]
pub enum ShellEvent {
    /// The screen changed; ask for a new frame when ready to draw. Sent
    /// once until the next frame is taken, so a flood of output never
    /// floods the app.
    Changed,
    /// The remote program set the window title.
    Title(String),
    /// The remote program rang the bell.
    Bell,
    /// The remote program asked to copy text to the clipboard.
    Clipboard(String),
    /// The shell ended. `code` is its exit code if the server sent one.
    Exited { code: Option<u32> },
    /// The connection dropped.
    Disconnected,
    /// Shell integration (OSC 133): a command started running.
    CommandStarted,
    /// Shell integration (OSC 133): the command ended.
    CommandFinished { exit_code: Option<i32> },
}
