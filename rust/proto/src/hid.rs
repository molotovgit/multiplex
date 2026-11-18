//! The phone as a keyboard and a mouse for another device: text, keys and
//! pointer moves as the reports a USB or Bluetooth keyboard and mouse
//! send (the HID boot protocol, which every device with an input field
//! understands). The same reports go over whichever carrier there is.
//!
//! The device decides which letter a key is, by the layout it is set to;
//! this speaks the US layout. A character that layout has no key for is
//! refused, not guessed at.

use crate::ProtoError;

/// The longest text typed in one go.
pub const MAX_TEXT: usize = 8 * 1024;

pub const LEFT_CTRL: u8 = 0x01;
pub const LEFT_SHIFT: u8 = 0x02;
pub const LEFT_ALT: u8 = 0x04;
pub const LEFT_GUI: u8 = 0x08;

/// What a keyboard says: which modifier keys are held, and one key.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Stroke {
    pub modifiers: u8,
    pub key: u8,
}

impl Stroke {
    /// The report for the key held down: modifiers, a reserved byte, and
    /// up to six keys (one here).
    pub fn down(self) -> [u8; 8] {
        [self.modifiers, 0, self.key, 0, 0, 0, 0, 0]
    }
}

/// Every key let go.
pub const UP: [u8; 8] = [0; 8];

/// The key a character is on a US keyboard, and whether Shift is held.
pub fn stroke_for(c: char) -> Option<Stroke> {
    let plain = |key: u8| Some(Stroke { modifiers: 0, key });
    let shifted = |key: u8| Some(Stroke { modifiers: LEFT_SHIFT, key });
    match c {
        'a'..='z' => plain(0x04 + (c as u8 - b'a')),
        'A'..='Z' => shifted(0x04 + (c as u8 - b'A')),
        '1'..='9' => plain(0x1e + (c as u8 - b'1')),
        '0' => plain(0x27),
        '\n' => plain(0x28),
        '\t' => plain(0x2b),
        ' ' => plain(0x2c),
        _ => {
            const PLAIN: &str = r"-=[]\;'`,./";
            const PLAIN_KEYS: [u8; 11] = [0x2d, 0x2e, 0x2f, 0x30, 0x31, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38];
            const SHIFTED: &str = "!@#$%^&*()_+{}|:\"~<>?";
            const SHIFTED_KEYS: [u8; 21] = [0x1e, 0x1f, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2d, 0x2e, 0x2f, 0x30, 0x31, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38];
            if let Some(at) = PLAIN.find(c) {
                plain(PLAIN_KEYS[at])
            } else if let Some(at) = SHIFTED.find(c) {
                shifted(SHIFTED_KEYS[at])
            } else {
                None
            }
        }
    }
}

/// A key by its name, with any modifiers before it ("enter", "tab",
/// "ctrl+a", "shift+tab", "alt+f4", "gui+l").
pub fn stroke_named(name: &str) -> Result<Stroke, ProtoError> {
    let mut modifiers = 0;
    let mut parts: Vec<&str> = name.split('+').collect();
    let key = parts.pop().filter(|key| !key.is_empty()).ok_or(ProtoError::Invalid("a key has a name"))?;
    for held in parts {
        modifiers |= match held {
            "ctrl" => LEFT_CTRL,
            "shift" => LEFT_SHIFT,
            "alt" => LEFT_ALT,
            "gui" | "super" | "win" | "cmd" => LEFT_GUI,
            _ => return Err(ProtoError::Invalid("the keys held with a key are ctrl, shift, alt and gui")),
        };
    }
    let code = match key {
        "enter" | "return" => 0x28,
        "esc" | "escape" => 0x29,
        "backspace" => 0x2a,
        "tab" => 0x2b,
        "space" => 0x2c,
        "delete" => 0x4c,
        "right" => 0x4f,
        "left" => 0x50,
        "down" => 0x51,
        "up" => 0x52,
        "home" => 0x4a,
        "end" => 0x4d,
        "pageup" => 0x4b,
        "pagedown" => 0x4e,
        _ => {
            let mut chars = key.chars();
            match (chars.next(), chars.next()) {
                // A single letter, digit or sign: the key it is on.
                (Some(c), None) => {
                    let stroke = stroke_for(c.to_ascii_lowercase()).ok_or(ProtoError::Invalid("that key is not on a US keyboard"))?;
                    modifiers |= stroke.modifiers;
                    stroke.key
                }
                // f1 to f12.
                (Some('f'), Some(_)) => match key[1..].parse::<u8>() {
                    Ok(n @ 1..=12) => 0x3a + n - 1,
                    _ => return Err(ProtoError::Invalid("that is not a key Multiplex knows")),
                },
                _ => return Err(ProtoError::Invalid("that is not a key Multiplex knows")),
            }
        }
    };
    Ok(Stroke { modifiers, key: code })
}

/// The strokes that type a text, in order. Fails, naming nothing but the
/// fact, when a character has no key on a US keyboard: half a text typed
/// into someone's form is worse than none.
pub fn strokes(text: &str) -> Result<Vec<Stroke>, ProtoError> {
    if text.is_empty() || text.len() > MAX_TEXT {
        return Err(ProtoError::Invalid("text to type is 1 to 8192 bytes"));
    }
    text.chars().filter(|c| *c != '\r').map(|c| stroke_for(c).ok_or(ProtoError::Invalid("the text has a character that is not on a US keyboard"))).collect()
}

/// The reports that make a run of strokes: each key down, then up. A key
/// pressed twice in a row needs the "up" between, so it is always sent.
pub fn reports(strokes: &[Stroke]) -> Vec<[u8; 8]> {
    strokes.iter().flat_map(|stroke| [stroke.down(), UP]).collect()
}

/// What a mouse says: buttons held (1 left, 2 right, 4 middle), and how
/// far it moved, each step at most 127 either way.
pub fn pointer_reports(dx: i32, dy: i32, buttons: u8) -> Vec<[u8; 3]> {
    let (mut dx, mut dy) = (dx.clamp(-20_000, 20_000), dy.clamp(-20_000, 20_000));
    let mut out = Vec::new();
    loop {
        let (step_x, step_y) = (dx.clamp(-127, 127), dy.clamp(-127, 127));
        out.push([buttons & 0x07, step_x as i8 as u8, step_y as i8 as u8]);
        dx -= step_x;
        dy -= step_y;
        if dx == 0 && dy == 0 {
            return out;
        }
    }
}

/// A click: the button down where the pointer is, then up.
pub fn click_reports(button: u8) -> [[u8; 3]; 2] {
    [[button & 0x07, 0, 0], [0, 0, 0]]
}

/// Reports as they travel in a line of the link: hex, nothing else.
pub fn to_hex<const N: usize>(reports: &[[u8; N]]) -> String {
    reports.iter().flatten().map(|byte| format!("{byte:02x}")).collect()
}

/// Read back, checked: whole reports of `N` bytes each, and not more of
/// them than a long text makes.
pub fn from_hex<const N: usize>(hex: &str) -> Result<Vec<[u8; N]>, ProtoError> {
    let bad = ProtoError::Invalid("these are not keyboard or mouse reports");
    if hex.len() % (2 * N) != 0 || hex.len() > 2 * N * 2 * (MAX_TEXT + 64) || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(bad);
    }
    hex.as_bytes()
        .chunks(2 * N)
        .map(|chunk| {
            let mut report = [0u8; N];
            for (at, pair) in chunk.chunks(2).enumerate() {
                report[at] = u8::from_str_radix(std::str::from_utf8(pair).map_err(|_| ProtoError::Invalid("these are not keyboard or mouse reports"))?, 16).map_err(|_| ProtoError::Invalid("these are not keyboard or mouse reports"))?;
            }
            Ok(report)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn text_becomes_the_keys_of_a_us_keyboard() {
        let typed = strokes("Hi, it's 5!\n").unwrap();
        assert_eq!(typed[0], Stroke { modifiers: LEFT_SHIFT, key: 0x0b }, "H is Shift and h");
        assert_eq!(typed[1], Stroke { modifiers: 0, key: 0x0c });
        assert_eq!(typed[2], Stroke { modifiers: 0, key: 0x36 }, "the comma");
        assert_eq!(typed[6], Stroke { modifiers: 0, key: 0x34 }, "the apostrophe");
        assert_eq!(typed[9], Stroke { modifiers: 0, key: 0x22 }, "5");
        assert_eq!(typed[10], Stroke { modifiers: LEFT_SHIFT, key: 0x1e }, "! is Shift and 1");
        assert_eq!(typed[11], Stroke { modifiers: 0, key: 0x28 }, "a new line is Enter");
        // Every printable ASCII character has a key.
        for c in (0x20u8..0x7f).map(char::from) {
            assert!(stroke_for(c).is_some(), "{c:?}");
        }
        // A carriage return is dropped; what has no key stops the whole text.
        assert_eq!(strokes("a\r\nb").unwrap().len(), 3);
        assert!(strokes("naïve").is_err());
        assert!(strokes("").is_err());
        assert!(strokes(&"x".repeat(MAX_TEXT + 1)).is_err());
    }

    #[test]
    fn each_key_goes_down_and_up() {
        let made = reports(&strokes("aa").unwrap());
        assert_eq!(made, [[0, 0, 0x04, 0, 0, 0, 0, 0], UP, [0, 0, 0x04, 0, 0, 0, 0, 0], UP]);
        assert_eq!(reports(&[stroke_named("ctrl+a").unwrap()])[0], [LEFT_CTRL, 0, 0x04, 0, 0, 0, 0, 0]);
    }

    #[test]
    fn reports_travel_as_hex_and_only_whole_ones_come_back() {
        let made = reports(&strokes("Ok").unwrap());
        let hex = to_hex(&made);
        assert_eq!(&hex[..16], "0200120000000000");
        assert_eq!(from_hex::<8>(&hex).unwrap(), made);
        assert_eq!(from_hex::<3>(&to_hex(&click_reports(1))).unwrap(), click_reports(1));
        assert!(from_hex::<8>("").unwrap().is_empty());
        for odd in ["02", "zz00120000000000", "0200120000000000ff"] {
            assert!(from_hex::<8>(odd).is_err(), "{odd}");
        }
    }

    #[test]
    fn keys_have_names() {
        assert_eq!(stroke_named("enter").unwrap(), Stroke { modifiers: 0, key: 0x28 });
        assert_eq!(stroke_named("shift+tab").unwrap(), Stroke { modifiers: LEFT_SHIFT, key: 0x2b });
        assert_eq!(stroke_named("ctrl+alt+delete").unwrap(), Stroke { modifiers: LEFT_CTRL | LEFT_ALT, key: 0x4c });
        assert_eq!(stroke_named("gui+l").unwrap(), Stroke { modifiers: LEFT_GUI, key: 0x0f });
        assert_eq!(stroke_named("alt+f4").unwrap(), Stroke { modifiers: LEFT_ALT, key: 0x3d });
        assert_eq!(stroke_named("f12").unwrap().key, 0x45);
        assert_eq!(stroke_named("A").unwrap(), stroke_named("a").unwrap(), "a key is a key; Shift is said by name");
        for odd in ["", "ctrl+", "hyper+a", "f13", "enterr", "é"] {
            assert!(stroke_named(odd).is_err(), "{odd:?}");
        }
    }

    #[test]
    fn the_pointer_moves_in_steps_a_mouse_can_say() {
        assert_eq!(pointer_reports(5, -3, 0), [[0, 5, 0xfd]]);
        let far = pointer_reports(300, 0, 1);
        assert_eq!(far, [[1, 127, 0], [1, 127, 0], [1, 46, 0]]);
        assert_eq!(pointer_reports(0, 0, 0), [[0, 0, 0]]);
        assert_eq!(click_reports(1), [[1, 0, 0], [0, 0, 0]]);
        assert_eq!(click_reports(0xff)[0][0], 7, "only the three buttons a mouse has");
    }
}
