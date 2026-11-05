//! Turns key presses into the bytes a remote program expects.
//!
//! Terminals do not send "the up arrow was pressed". They send short byte
//! sequences such as `ESC [ A`. Which sequence depends on the key, on the
//! modifier keys and on modes the program switched on (for example vim
//! asks for "application cursor keys"). This file knows those rules.

use crate::api::terminal_types::{KeyModifiers, TerminalKey};

/// Terminal modes that change how keys are encoded.
#[derive(Debug, Clone, Copy, Default)]
pub struct InputModes {
    pub application_cursor: bool,
    pub bracketed_paste: bool,
    pub mouse: MouseMode,
}

/// How (and whether) the program wants mouse events.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum MouseMode {
    #[default]
    Off,
    /// Classic encoding: each value is one byte (limited to 223 columns).
    Classic,
    /// SGR encoding: values are written as decimal numbers.
    Sgr,
}

impl InputModes {
    /// Reads the current modes from the screen.
    pub fn from_screen(screen: &vt100::Screen) -> Self {
        let mouse = if screen.mouse_protocol_mode() == vt100::MouseProtocolMode::None {
            MouseMode::Off
        } else if screen.mouse_protocol_encoding() == vt100::MouseProtocolEncoding::Sgr {
            MouseMode::Sgr
        } else {
            MouseMode::Classic
        };
        Self {
            application_cursor: screen.application_cursor(),
            bracketed_paste: screen.bracketed_paste(),
            mouse,
        }
    }
}

/// Encodes keys, text, paste and mouse events.
pub struct KeyEncoder {
    modes: InputModes,
}

impl KeyEncoder {
    pub fn new(modes: InputModes) -> Self {
        Self { modes }
    }

    /// Bytes for a special key.
    pub fn key(&self, key: TerminalKey, mods: KeyModifiers) -> Vec<u8> {
        let modifier = Self::modifier_code(mods);
        let mut out = match key {
            TerminalKey::Enter => b"\r".to_vec(),
            TerminalKey::Tab if mods.shift => b"\x1b[Z".to_vec(),
            TerminalKey::Tab => b"\t".to_vec(),
            TerminalKey::Backspace if mods.ctrl => b"\x08".to_vec(),
            TerminalKey::Backspace => b"\x7f".to_vec(),
            TerminalKey::Escape => b"\x1b".to_vec(),
            TerminalKey::Up => self.cursor_key(b'A', modifier),
            TerminalKey::Down => self.cursor_key(b'B', modifier),
            TerminalKey::Right => self.cursor_key(b'C', modifier),
            TerminalKey::Left => self.cursor_key(b'D', modifier),
            TerminalKey::Home => self.cursor_key(b'H', modifier),
            TerminalKey::End => self.cursor_key(b'F', modifier),
            TerminalKey::Insert => Self::tilde_key(2, modifier),
            TerminalKey::Delete => Self::tilde_key(3, modifier),
            TerminalKey::PageUp => Self::tilde_key(5, modifier),
            TerminalKey::PageDown => Self::tilde_key(6, modifier),
            TerminalKey::F1 => Self::ss3_key(b'P', modifier),
            TerminalKey::F2 => Self::ss3_key(b'Q', modifier),
            TerminalKey::F3 => Self::ss3_key(b'R', modifier),
            TerminalKey::F4 => Self::ss3_key(b'S', modifier),
            TerminalKey::F5 => Self::tilde_key(15, modifier),
            TerminalKey::F6 => Self::tilde_key(17, modifier),
            TerminalKey::F7 => Self::tilde_key(18, modifier),
            TerminalKey::F8 => Self::tilde_key(19, modifier),
            TerminalKey::F9 => Self::tilde_key(20, modifier),
            TerminalKey::F10 => Self::tilde_key(21, modifier),
            TerminalKey::F11 => Self::tilde_key(23, modifier),
            TerminalKey::F12 => Self::tilde_key(24, modifier),
        };
        // Alt on keys without a modifier code is sent as an ESC prefix.
        let has_code = matches!(
            key,
            TerminalKey::Up
                | TerminalKey::Down
                | TerminalKey::Left
                | TerminalKey::Right
                | TerminalKey::Home
                | TerminalKey::End
                | TerminalKey::Insert
                | TerminalKey::Delete
                | TerminalKey::PageUp
                | TerminalKey::PageDown
        ) || matches!(key, TerminalKey::F1 | TerminalKey::F2 | TerminalKey::F3 | TerminalKey::F4)
            || Self::is_tilde_function_key(key);
        if mods.alt && !has_code {
            out.insert(0, 0x1b);
        }
        out
    }

    /// Bytes for typed text. Ctrl turns letters into control characters
    /// (Ctrl+C becomes byte 3), Alt adds an ESC in front.
    pub fn text(&self, text: &str, mods: KeyModifiers) -> Vec<u8> {
        let mut out = Vec::with_capacity(text.len() + 1);
        for ch in text.chars() {
            if mods.alt {
                out.push(0x1b);
            }
            match (mods.ctrl, Self::control_byte(ch)) {
                (true, Some(byte)) => out.push(byte),
                _ => {
                    let mut buf = [0u8; 4];
                    out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                }
            }
        }
        out
    }

    /// Bytes for pasted text. When the program asked for bracketed paste,
    /// the text is wrapped in markers so it is not run line by line.
    pub fn paste(&self, text: &str) -> Vec<u8> {
        // Line breaks from other apps are \n or \r\n; terminals use \r.
        let normalized = text.replace("\r\n", "\r").replace('\n', "\r");
        if !self.modes.bracketed_paste {
            return normalized.into_bytes();
        }
        // Remove any end marker inside the text so it cannot escape the paste.
        let safe = normalized.replace("\x1b[201~", "");
        let mut out = b"\x1b[200~".to_vec();
        out.extend_from_slice(safe.as_bytes());
        out.extend_from_slice(b"\x1b[201~");
        out
    }

    /// Bytes for a mouse wheel step at a cell (0-based), or `None` when the
    /// program does not want mouse events.
    pub fn wheel(&self, up: bool, row: u16, col: u16) -> Option<Vec<u8>> {
        let button = if up { 64 } else { 65 };
        self.mouse_event(button, row, col, true)
    }

    /// Bytes for a left click (press and release) at a cell (0-based).
    pub fn click(&self, row: u16, col: u16) -> Option<Vec<u8>> {
        let mut out = self.mouse_event(0, row, col, true)?;
        out.extend(self.mouse_event(3, row, col, false)?);
        Some(out)
    }

    fn mouse_event(&self, button: u16, row: u16, col: u16, press: bool) -> Option<Vec<u8>> {
        match self.modes.mouse {
            MouseMode::Off => None,
            MouseMode::Sgr => {
                // SGR release keeps the button number (0) and ends with 'm'.
                let code = if !press && button == 3 { 0 } else { button };
                let end = if press { 'M' } else { 'm' };
                Some(format!("\x1b[<{};{};{}{}", code, col + 1, row + 1, end).into_bytes())
            }
            MouseMode::Classic => {
                let clamp = |v: u16| (v + 1).min(223) as u8 + 32;
                Some(vec![0x1b, b'[', b'M', 32 + button as u8, clamp(col), clamp(row)])
            }
        }
    }

    /// Arrow keys and Home/End: `ESC [ A` normally, `ESC O A` in
    /// application mode, `ESC [ 1 ; m A` with modifiers.
    fn cursor_key(&self, letter: u8, modifier: u8) -> Vec<u8> {
        if modifier > 1 {
            return format!("\x1b[1;{}{}", modifier, letter as char).into_bytes();
        }
        if self.modes.application_cursor {
            vec![0x1b, b'O', letter]
        } else {
            vec![0x1b, b'[', letter]
        }
    }

    fn tilde_key(number: u8, modifier: u8) -> Vec<u8> {
        if modifier > 1 {
            format!("\x1b[{number};{modifier}~").into_bytes()
        } else {
            format!("\x1b[{number}~").into_bytes()
        }
    }

    fn ss3_key(letter: u8, modifier: u8) -> Vec<u8> {
        if modifier > 1 {
            format!("\x1b[1;{}{}", modifier, letter as char).into_bytes()
        } else {
            vec![0x1b, b'O', letter]
        }
    }

    fn is_tilde_function_key(key: TerminalKey) -> bool {
        matches!(
            key,
            TerminalKey::F5
                | TerminalKey::F6
                | TerminalKey::F7
                | TerminalKey::F8
                | TerminalKey::F9
                | TerminalKey::F10
                | TerminalKey::F11
                | TerminalKey::F12
        )
    }

    /// xterm modifier number: 1 + shift(1) + alt(2) + ctrl(4).
    fn modifier_code(mods: KeyModifiers) -> u8 {
        1 + u8::from(mods.shift) + 2 * u8::from(mods.alt) + 4 * u8::from(mods.ctrl)
    }

    /// The control byte for Ctrl+<char>, if that combination has one.
    fn control_byte(ch: char) -> Option<u8> {
        match ch {
            'a'..='z' => Some(ch as u8 - b'a' + 1),
            'A'..='Z' => Some(ch as u8 - b'A' + 1),
            '@' | ' ' | '2' => Some(0),
            '[' | '3' => Some(0x1b),
            '\\' | '4' => Some(0x1c),
            ']' | '5' => Some(0x1d),
            '^' | '6' => Some(0x1e),
            '_' | '7' | '/' => Some(0x1f),
            '?' | '8' => Some(0x7f),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NONE: KeyModifiers = KeyModifiers { ctrl: false, alt: false, shift: false };
    const CTRL: KeyModifiers = KeyModifiers { ctrl: true, alt: false, shift: false };
    const ALT: KeyModifiers = KeyModifiers { ctrl: false, alt: true, shift: false };

    fn plain() -> KeyEncoder {
        KeyEncoder::new(InputModes::default())
    }

    #[test]
    fn encodes_arrows_in_normal_and_application_mode() {
        assert_eq!(plain().key(TerminalKey::Up, NONE), b"\x1b[A");
        let app = KeyEncoder::new(InputModes { application_cursor: true, ..Default::default() });
        assert_eq!(app.key(TerminalKey::Up, NONE), b"\x1bOA");
        assert_eq!(plain().key(TerminalKey::Right, CTRL), b"\x1b[1;5C");
    }

    #[test]
    fn encodes_editing_and_function_keys() {
        assert_eq!(plain().key(TerminalKey::Delete, NONE), b"\x1b[3~");
        assert_eq!(plain().key(TerminalKey::PageDown, NONE), b"\x1b[6~");
        assert_eq!(plain().key(TerminalKey::F1, NONE), b"\x1bOP");
        assert_eq!(plain().key(TerminalKey::F12, NONE), b"\x1b[24~");
        assert_eq!(plain().key(TerminalKey::Backspace, NONE), b"\x7f");
        assert_eq!(plain().key(TerminalKey::Escape, ALT), b"\x1b\x1b");
    }

    #[test]
    fn ctrl_and_alt_change_typed_text() {
        assert_eq!(plain().text("c", CTRL), vec![3]);
        assert_eq!(plain().text("[", CTRL), vec![0x1b]);
        assert_eq!(plain().text("x", ALT), b"\x1bx");
        assert_eq!(plain().text("é", NONE), "é".as_bytes());
    }

    #[test]
    fn paste_uses_brackets_only_when_asked() {
        assert_eq!(plain().paste("a\nb"), b"a\rb");
        let bracketed = KeyEncoder::new(InputModes { bracketed_paste: true, ..Default::default() });
        assert_eq!(bracketed.paste("ls\x1b[201~"), b"\x1b[200~ls\x1b[201~");
    }

    #[test]
    fn mouse_events_follow_the_requested_encoding() {
        assert_eq!(plain().wheel(true, 0, 0), None);
        let sgr = KeyEncoder::new(InputModes { mouse: MouseMode::Sgr, ..Default::default() });
        assert_eq!(sgr.wheel(true, 4, 9).unwrap(), b"\x1b[<64;10;5M");
        assert_eq!(sgr.click(0, 0).unwrap(), b"\x1b[<0;1;1M\x1b[<0;1;1m");
        let classic = KeyEncoder::new(InputModes { mouse: MouseMode::Classic, ..Default::default() });
        assert_eq!(classic.wheel(false, 0, 0).unwrap(), vec![0x1b, b'[', b'M', 97, 33, 33]);
    }

    #[test]
    fn reads_modes_from_the_screen() {
        let mut parser = vt100::Parser::default();
        parser.process(b"\x1b[?1h\x1b[?2004h\x1b[?1000h\x1b[?1006h");
        let modes = InputModes::from_screen(parser.screen());
        assert!(modes.application_cursor);
        assert!(modes.bracketed_paste);
        assert_eq!(modes.mouse, MouseMode::Sgr);
    }
}
