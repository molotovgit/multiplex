//! The terminal emulator: reads what the server sends and keeps the screen.
//!
//! The heavy lifting (escape codes, cursor moves, colours, scrollback) is
//! done by the `vt100` crate. This type adds what an interactive terminal
//! also needs: answering the server's questions ("where is the cursor?"),
//! remembering the window title, the bell and clipboard requests.

use std::num::NonZeroU16;

use base64::Engine as _;

/// Things that happened while processing output, for the app to react to.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct EmulatorSignals {
    /// Bytes the terminal must send back to the server (answers to queries).
    pub replies: Vec<u8>,
    /// A new window title, if the program set one.
    pub title: Option<String>,
    /// The program rang the bell.
    pub bell: bool,
    /// The program asked to copy this text to the clipboard (OSC 52).
    pub clipboard: Option<String>,
    /// Shell integration marks (OSC 133), in the order they came.
    pub marks: Vec<ShellMark>,
}

/// What a shell set up for "shell integration" reports with OSC 133.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShellMark {
    /// "C": the command line was accepted and the command runs now.
    CommandStarted,
    /// "D": the command ended, with its exit code when the shell sent one.
    CommandFinished(Option<i32>),
}

/// Receives callbacks from the vt100 parser and collects [`EmulatorSignals`].
#[derive(Default)]
struct SignalCollector {
    signals: EmulatorSignals,
}

impl vt100::Callbacks for SignalCollector {
    fn audible_bell(&mut self, _: &mut vt100::Screen) {
        self.signals.bell = true;
    }

    fn set_window_title(&mut self, _: &mut vt100::Screen, title: &[u8]) {
        self.signals.title = Some(String::from_utf8_lossy(title).into_owned());
    }

    fn copy_to_clipboard(&mut self, _: &mut vt100::Screen, _ty: &[u8], data: &[u8]) {
        // OSC 52 sends the text base64-encoded.
        if let Ok(bytes) = base64::engine::general_purpose::STANDARD.decode(data) {
            self.signals.clipboard = Some(String::from_utf8_lossy(&bytes).into_owned());
        }
    }

    fn unhandled_osc(&mut self, _: &mut vt100::Screen, params: &[&[u8]]) {
        if params.first() != Some(&&b"133"[..]) {
            return;
        }
        match params.get(1).copied() {
            Some(b"C") => self.signals.marks.push(ShellMark::CommandStarted),
            Some(b"D") => {
                let code = params.get(2).and_then(|c| std::str::from_utf8(c).ok()).and_then(|c| c.parse().ok());
                self.signals.marks.push(ShellMark::CommandFinished(code));
            }
            _ => {}
        }
    }

    fn unhandled_csi(
        &mut self,
        screen: &mut vt100::Screen,
        i1: Option<u8>,
        _i2: Option<u8>,
        params: &[&[u16]],
        c: char,
    ) {
        let first = params.first().and_then(|p| p.first()).copied().unwrap_or(0);
        match (i1, c, first) {
            // "Where is the cursor?" (DSR 6) - answer with row;col, 1-based.
            (None, 'n', 6) => {
                let (row, col) = screen.cursor_position();
                let answer = format!("\x1b[{};{}R", row + 1, col + 1);
                self.signals.replies.extend_from_slice(answer.as_bytes());
            }
            // "Are you OK?" (DSR 5) - yes.
            (None, 'n', 5) => self.signals.replies.extend_from_slice(b"\x1b[0n"),
            // "What kind of terminal are you?" (DA1) - a VT220-class terminal.
            (None, 'c', 0) => self.signals.replies.extend_from_slice(b"\x1b[?62;22c"),
            // Secondary device attributes (DA2).
            (Some(b'>'), 'c', 0) => self.signals.replies.extend_from_slice(b"\x1b[>1;10;0c"),
            _ => {}
        }
    }
}

/// Screen state of one terminal session.
pub struct TerminalEmulator {
    parser: vt100::Parser<SignalCollector>,
    title: String,
}

impl TerminalEmulator {
    /// A new, empty screen of `rows` x `cols` that keeps `scrollback` lines
    /// of history.
    pub fn new(rows: u16, cols: u16, scrollback: usize) -> Self {
        let parser = vt100::Parser::new_with_callbacks(
            Self::non_zero(rows),
            Self::non_zero(cols),
            scrollback,
            SignalCollector::default(),
        );
        Self {
            parser,
            title: String::new(),
        }
    }

    /// Feeds bytes from the server into the screen and reports what
    /// happened along the way.
    pub fn process(&mut self, bytes: &[u8]) -> EmulatorSignals {
        self.parser.process(bytes);
        let signals = std::mem::take(&mut self.parser.callbacks_mut().signals);
        if let Some(title) = &signals.title {
            self.title.clone_from(title);
        }
        signals
    }

    /// Changes the screen size (for example when the phone rotates).
    pub fn resize(&mut self, rows: u16, cols: u16) {
        self.parser.set_size(Self::non_zero(rows), Self::non_zero(cols));
    }

    pub fn screen(&self) -> &vt100::Screen {
        self.parser.screen()
    }

    pub fn title(&self) -> &str {
        &self.title
    }

    /// Current size as (rows, cols).
    pub fn size(&self) -> (u16, u16) {
        let (rows, cols) = self.parser.screen().size();
        (rows.get(), cols.get())
    }

    /// Moves the view through history. Positive = further back.
    /// Returns the new offset.
    pub fn scroll_by(&mut self, lines: i32) -> usize {
        let screen = self.parser.screen_mut();
        let current = screen.scrollback() as i64;
        let wanted = (current + i64::from(lines)).max(0) as usize;
        screen.set_scrollback(wanted);
        screen.scrollback()
    }

    /// Jumps back to the live screen.
    pub fn scroll_to_bottom(&mut self) {
        self.parser.screen_mut().set_scrollback(0);
    }

    /// How many lines of history exist. vt100 does not expose this
    /// directly, so we ask for "as far back as possible" and look where
    /// the view ends up, then restore the old position.
    pub fn history_len(&mut self) -> usize {
        let screen = self.parser.screen_mut();
        let current = screen.scrollback();
        screen.set_scrollback(usize::MAX);
        let len = screen.scrollback();
        screen.set_scrollback(current);
        len
    }

    /// Plain text between two screen positions (inclusive), for copying.
    pub fn text_between(&self, start: (u16, u16), end: (u16, u16)) -> String {
        let (start, end) = if start <= end { (start, end) } else { (end, start) };
        self.parser
            .screen()
            .contents_between(start.0, start.1, end.0, end.1.saturating_add(1))
    }

    /// Erases all history but keeps what is on screen.
    pub fn clear_history(&mut self) {
        self.parser.screen_mut().clear_scrollback();
    }

    fn non_zero(value: u16) -> NonZeroU16 {
        NonZeroU16::new(value.max(1)).unwrap_or(NonZeroU16::MIN)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_text_and_moves_the_cursor() {
        let mut term = TerminalEmulator::new(5, 20, 100);
        term.process(b"hello\r\nworld");
        assert_eq!(term.screen().contents(), "hello\nworld");
        assert_eq!(term.screen().cursor_position(), (1, 5));
    }

    #[test]
    fn answers_cursor_position_and_device_queries() {
        let mut term = TerminalEmulator::new(5, 20, 100);
        term.process(b"abc");
        let signals = term.process(b"\x1b[6n");
        assert_eq!(signals.replies, b"\x1b[1;4R");
        let signals = term.process(b"\x1b[c");
        assert_eq!(signals.replies, b"\x1b[?62;22c");
    }

    #[test]
    fn remembers_title_bell_and_clipboard() {
        let mut term = TerminalEmulator::new(5, 20, 100);
        let signals = term.process(b"\x1b]0;my title\x07\x07");
        assert_eq!(signals.title.as_deref(), Some("my title"));
        assert!(signals.bell);
        assert_eq!(term.title(), "my title");
        // "aGk=" is base64 for "hi".
        let signals = term.process(b"\x1b]52;c;aGk=\x07");
        assert_eq!(signals.clipboard.as_deref(), Some("hi"));
    }

    #[test]
    fn reports_shell_integration_marks() {
        let mut term = TerminalEmulator::new(5, 20, 100);
        let signals = term.process(b"]133;A$ ]133;B");
        assert!(signals.marks.is_empty());
        let signals = term.process(b"]133;Coutput
]133;D;2]133;D");
        assert_eq!(signals.marks, vec![ShellMark::CommandStarted, ShellMark::CommandFinished(Some(2)), ShellMark::CommandFinished(None)]);
        assert!(term.screen().contents().contains("output"));
    }

    #[test]
    fn scrolls_through_history() {
        let mut term = TerminalEmulator::new(3, 10, 100);
        for i in 0..10 {
            term.process(format!("line{i}\r\n").as_bytes());
        }
        assert_eq!(term.history_len(), 8);
        assert_eq!(term.scroll_by(2), 2);
        assert!(term.screen().contents().starts_with("line6"));
        assert_eq!(term.scroll_by(100), 8);
        assert_eq!(term.scroll_by(-100), 0);
    }

    #[test]
    fn copies_text_between_positions_in_any_order() {
        let mut term = TerminalEmulator::new(3, 20, 10);
        term.process(b"first line\r\nsecond line");
        assert_eq!(term.text_between((0, 6), (1, 5)), "line\nsecond");
        assert_eq!(term.text_between((1, 5), (0, 6)), "line\nsecond");
    }
}
