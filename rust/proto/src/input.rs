//! What the phone sends to `multiplex input`, the computer's virtual
//! touchpad and keyboard: one short line per event, over the standard
//! input of an SSH command.
//!
//! ```text
//! m <dx> <dy>      move the pointer by this much
//! s <dx> <dy>      scroll by this much
//! b <1|2|3> <0|1>  left, right or middle button, released or pressed
//! k <code> <0|1>   a key by its Linux (evdev) code, released or pressed
//! v <base64>       put this text on the clipboard and paste it
//! r                release every key and button
//! p                nothing: the phone is still there
//! ```
//!
//! The computer releases everything by itself when the phone goes quiet
//! while something is held, so a lost connection cannot leave a key down.

use base64::engine::general_purpose::STANDARD;
use base64::Engine;

use crate::ProtoError;

/// How the phone starts the computer's side.
pub const INPUT_COMMAND: &str = r#"PATH="$PATH:$HOME/.local/bin" multiplex input"#;

/// The first line the computer prints once its pointer and keyboard exist.
pub const READY: &str = "ready";

/// While something is held the phone sends a line at least this often…
pub const PING_MS: u64 = 1000;
/// …and the computer lets go of everything after this much silence.
pub const QUIET_MS: u64 = 3500;

/// The highest Linux key code (`KEY_MAX`).
pub const MAX_KEY: u16 = 767;
/// More than any real movement between two events.
const MAX_STEP: f64 = 20_000.0;
/// A clipboard's worth of text, not a file.
pub const MAX_PASTE: usize = 256 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Button {
    Left,
    Right,
    Middle,
}

impl Button {
    /// The Linux code (`BTN_LEFT` and so on).
    pub fn code(self) -> u32 {
        match self {
            Button::Left => 0x110,
            Button::Right => 0x111,
            Button::Middle => 0x112,
        }
    }

    fn number(self) -> u8 {
        match self {
            Button::Left => 1,
            Button::Right => 2,
            Button::Middle => 3,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum InputEvent {
    Move { dx: f64, dy: f64 },
    Scroll { dx: f64, dy: f64 },
    Button { button: Button, down: bool },
    Key { code: u16, down: bool },
    Paste { text: String },
    ReleaseAll,
    Ping,
}

fn step(text: &str) -> Result<f64, ProtoError> {
    match text.parse::<f64>() {
        Ok(v) if v.is_finite() && v.abs() <= MAX_STEP => Ok(v),
        _ => Err(ProtoError::Invalid("a movement is a modest number")),
    }
}

fn pressed(text: &str) -> Result<bool, ProtoError> {
    match text {
        "1" => Ok(true),
        "0" => Ok(false),
        _ => Err(ProtoError::Invalid("pressed is 1, released is 0")),
    }
}

/// Short and exact enough: a hundredth of a pixel.
fn short(v: f64) -> String {
    let rounded = (v * 100.0).round() / 100.0;
    if rounded == rounded.trunc() {
        format!("{}", rounded as i64)
    } else {
        format!("{rounded}")
    }
}

impl InputEvent {
    /// The line for this event, without the line break.
    pub fn to_line(&self) -> String {
        match self {
            InputEvent::Move { dx, dy } => format!("m {} {}", short(*dx), short(*dy)),
            InputEvent::Scroll { dx, dy } => format!("s {} {}", short(*dx), short(*dy)),
            InputEvent::Button { button, down } => format!("b {} {}", button.number(), u8::from(*down)),
            InputEvent::Key { code, down } => format!("k {code} {}", u8::from(*down)),
            InputEvent::Paste { text } => format!("v {}", STANDARD.encode(text)),
            InputEvent::ReleaseAll => "r".to_owned(),
            InputEvent::Ping => "p".to_owned(),
        }
    }

    /// Reads one line. Anything that is not exactly an event is refused.
    pub fn parse_line(line: &str) -> Result<Self, ProtoError> {
        let words: Vec<&str> = line.split(' ').collect();
        Ok(match words.as_slice() {
            ["m", dx, dy] => InputEvent::Move { dx: step(dx)?, dy: step(dy)? },
            ["s", dx, dy] => InputEvent::Scroll { dx: step(dx)?, dy: step(dy)? },
            ["b", button, down] => InputEvent::Button {
                button: match *button {
                    "1" => Button::Left,
                    "2" => Button::Right,
                    "3" => Button::Middle,
                    _ => return Err(ProtoError::Invalid("a button is 1, 2 or 3")),
                },
                down: pressed(down)?,
            },
            ["k", code, down] => match code.parse::<u16>() {
                Ok(code) if (1..=MAX_KEY).contains(&code) => InputEvent::Key { code, down: pressed(down)? },
                _ => return Err(ProtoError::Invalid("this is not a key")),
            },
            ["v", data] if data.len() <= MAX_PASTE * 4 / 3 + 4 => {
                let bytes = STANDARD.decode(data).map_err(|_| ProtoError::Damaged)?;
                InputEvent::Paste { text: String::from_utf8(bytes).map_err(|_| ProtoError::Damaged)? }
            }
            ["r"] => InputEvent::ReleaseAll,
            ["p"] => InputEvent::Ping,
            _ => return Err(ProtoError::Invalid("this is not an input event")),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_event_survives_the_trip_as_a_line() {
        let all = [
            InputEvent::Move { dx: -3.25, dy: 12.0 },
            InputEvent::Scroll { dx: 0.0, dy: -40.5 },
            InputEvent::Button { button: Button::Left, down: true },
            InputEvent::Button { button: Button::Middle, down: false },
            InputEvent::Key { code: 125, down: true },
            InputEvent::Paste { text: "héllo\n'quoted' 😀".into() },
            InputEvent::ReleaseAll,
            InputEvent::Ping,
        ];
        for event in all {
            let line = event.to_line();
            assert!(!line.contains('\n'), "{line}");
            assert_eq!(InputEvent::parse_line(&line).unwrap(), event, "{line}");
        }
        assert_eq!(InputEvent::Move { dx: 1.0, dy: -0.004 }.to_line(), "m 1 0");
    }

    #[test]
    fn anything_else_is_refused() {
        for bad in ["", "m", "m 1", "m 1 2 3", "m nan 1", "m inf 1", "m 1e9 1", "b 4 1", "b 1 2", "k 0 1", "k 768 1", "k -1 1", "k 30 down", "v !!!", "x", "r 1", " m 1 2", "m  1 2"] {
            assert!(InputEvent::parse_line(bad).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn buttons_have_their_linux_codes() {
        assert_eq!((Button::Left.code(), Button::Right.code(), Button::Middle.code()), (0x110, 0x111, 0x112));
    }
}
