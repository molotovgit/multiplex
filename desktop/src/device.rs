//! `multiplex device …`: the phone as the keyboard and mouse of whatever
//! device it is connected to, for an agent (or a person) at this computer
//! to use that device: type a text, press keys, move and click the
//! pointer, and look at its screen through the phone's camera.
//!
//! What to send is worked out here, as the reports a keyboard and a mouse
//! send (`multiplex_proto::hid`); the phone only passes them on, over
//! Bluetooth or its cable, if its owner has switched that on for this
//! computer. The phone answers each ask, so the command says whether it
//! was done.

use anyhow::{bail, Result};
use multiplex_proto::hid;
use multiplex_proto::share::LinkEvent;

use crate::share::{ask_and_wait_for, linked, the_phone};

/// How long the phone has to say it is done (a long text takes a while
/// to type; a picture a moment to take and send).
const PATIENCE: u64 = 60;

/// What is asked of the phone, from the words after `multiplex device`.
#[derive(Debug, PartialEq, Eq, Default)]
pub struct Asked {
    pub keys: String,
    pub pointer: String,
    pub look: bool,
}

pub fn asked(args: &[&str]) -> Result<Asked> {
    let invalid = |err: multiplex_proto::ProtoError| anyhow::anyhow!("{err}");
    Ok(match args {
        ["type", words @ ..] if !words.is_empty() => Asked { keys: hid::to_hex(&hid::reports(&hid::strokes(&words.join(" ")).map_err(invalid)?)), ..Asked::default() },
        ["keys", names @ ..] if !names.is_empty() && names.len() <= 64 => {
            let strokes = names.iter().map(|name| hid::stroke_named(name)).collect::<Result<Vec<_>, _>>().map_err(invalid)?;
            Asked { keys: hid::to_hex(&hid::reports(&strokes)), ..Asked::default() }
        }
        ["move", dx, dy] => match (dx.parse::<i32>(), dy.parse::<i32>()) {
            (Ok(dx), Ok(dy)) => Asked { pointer: hid::to_hex(&hid::pointer_reports(dx, dy, 0)), ..Asked::default() },
            _ => bail!("multiplex device move takes two whole numbers: right and down"),
        },
        ["click"] | ["click", "left"] => Asked { pointer: hid::to_hex(&hid::click_reports(1)), ..Asked::default() },
        ["click", "right"] => Asked { pointer: hid::to_hex(&hid::click_reports(2)), ..Asked::default() },
        ["look"] => Asked { look: true, ..Asked::default() },
        _ => bail!("usage: multiplex device [--to <phone>] type <text> | keys <key…> | move <right> <down> | click [left|right] | look"),
    })
}

/// What the command says for the phone's answer; an error when it was
/// not done.
pub fn said(phone: &str, answer: Option<&str>, look: bool) -> Result<String> {
    match answer.map(str::trim) {
        None => bail!("{phone} did not answer in time."),
        Some("ok") => Ok("Done.".to_owned()),
        Some(answer) => match answer.strip_prefix("no:") {
            Some(why) => bail!("{phone} did not do it: {}", why.trim()),
            // A picture's place on this computer.
            None if look && !answer.is_empty() => Ok(answer.to_owned()),
            None => bail!("{phone}'s answer was not understood."),
        },
    }
}

pub fn run(args: &[&str]) -> Result<()> {
    let (to, rest) = match args {
        ["--to", name, rest @ ..] => (*name, rest),
        rest => ("", rest),
    };
    let asked = asked(rest)?;
    let phone = the_phone(to)?;
    if !linked(&phone) {
        bail!("{phone} is not connected to this computer right now.");
    }
    let look = asked.look;
    let (_, answer) = ask_and_wait_for(&phone, PATIENCE, |id| LinkEvent::Hands { id: id.to_owned(), keys: asked.keys, pointer: asked.pointer, look })?;
    println!("{}", said(&phone, answer.as_deref(), look)?);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn words_become_what_the_phone_is_asked() {
        // Text, with its blanks: each key down and up.
        let typed = asked(&["type", "Hi", "there"]).unwrap();
        assert_eq!(typed.keys.len(), "Hi there".len() * 2 * 16);
        assert!(typed.keys.starts_with("0200" ) && typed.pointer.is_empty() && !typed.look);
        // Keys by name.
        assert_eq!(asked(&["keys", "tab", "ctrl+a", "enter"]).unwrap().keys, "00002b00000000000000000000000000010004000000000000000000000000000000280000000000".to_owned() + "0000000000000000");
        // The pointer.
        assert_eq!(asked(&["move", "5", "-3"]).unwrap().pointer, "0005fd");
        assert_eq!(asked(&["click"]).unwrap().pointer, "010000000000");
        assert_eq!(asked(&["click", "right"]).unwrap().pointer, "020000000000");
        assert!(asked(&["look"]).unwrap().look);
        // What cannot be typed or is not a key is said, and nothing is asked.
        for odd in [&["type"][..], &["type", "naïve"], &["keys", "hyper+x"], &["move", "far", "away"], &["click", "both"], &["dance"], &[]] {
            assert!(asked(odd).is_err(), "{odd:?}");
        }
    }

    #[test]
    fn the_phones_answer_is_said_plainly() {
        assert_eq!(said("Sam's Pixel", Some("ok\n"), false).unwrap(), "Done.");
        assert_eq!(said("Sam's Pixel", Some("/home/sam/inbox/look-1.jpg"), true).unwrap(), "/home/sam/inbox/look-1.jpg");
        assert!(said("Sam's Pixel", Some("no: it is switched off for this computer"), false).unwrap_err().to_string().contains("Sam's Pixel did not do it: it is switched off for this computer"));
        assert!(said("Sam's Pixel", None, false).unwrap_err().to_string().contains("did not answer in time"));
        assert!(said("Sam's Pixel", Some("something"), false).is_err());
    }
}
