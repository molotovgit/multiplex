//! `multiplex herd pane <session> <pane>`: one of herdr's panes in the
//! terminal this runs in, at this terminal's own size.
//!
//! herdr can show a pane to a second viewer wrapped to that viewer's
//! columns and rows while the pane itself, and what the computer's own
//! screen shows of it, keep their size (`herdr terminal session control`).
//! It speaks lines of JSON; this turns them into what a terminal expects:
//! the picture as it is drawn, keys as they are typed, a new size when
//! the terminal changes. So the phone's ordinary terminal is all it takes
//! to sit in front of one agent.
//!
//! Ctrl+\ leaves (the pane keeps running); Shift+PageUp and
//! Shift+PageDown move through the pane's earlier output.

use std::io::{BufRead, BufReader, Read, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use anyhow::{anyhow, bail, Context, Result};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use multiplex_proto::agents::clean_session_name;
use multiplex_proto::herd::clean_pane_id;
use serde_json::{json, Value};

/// The key that leaves: Ctrl+\.
const LEAVE: u8 = 0x1c;
const SCROLL_UP: &[u8] = b"\x1b[5;2~";
const SCROLL_DOWN: &[u8] = b"\x1b[6;2~";

/// What to make of the bytes a terminal sent: typed into the pane,
/// moving through its earlier output, or leaving.
#[derive(Debug, PartialEq, Eq)]
pub enum Typed {
    Input(Vec<u8>),
    Scroll { up: bool },
    Leave,
}

/// Splits what was read into what it means, in order. Everything after
/// the key that leaves is dropped.
pub fn typed(bytes: &[u8]) -> Vec<Typed> {
    let mut out = Vec::new();
    let mut plain: Vec<u8> = Vec::new();
    let mut rest = bytes;
    while let Some(&first) = rest.first() {
        let scroll = if rest.starts_with(SCROLL_UP) {
            Some(true)
        } else if rest.starts_with(SCROLL_DOWN) {
            Some(false)
        } else {
            None
        };
        if first != LEAVE && scroll.is_none() {
            plain.push(first);
            rest = &rest[1..];
            continue;
        }
        if !plain.is_empty() {
            out.push(Typed::Input(std::mem::take(&mut plain)));
        }
        match scroll {
            Some(up) => {
                out.push(Typed::Scroll { up });
                rest = &rest[SCROLL_UP.len()..];
            }
            None => {
                out.push(Typed::Leave);
                return out;
            }
        }
    }
    if !plain.is_empty() {
        out.push(Typed::Input(plain));
    }
    out
}

/// The line for herdr that says it.
pub fn command(what: &Typed) -> Value {
    match what {
        Typed::Input(bytes) => json!({ "type": "terminal.input", "bytes": STANDARD.encode(bytes) }),
        Typed::Scroll { up } => json!({ "type": "terminal.scroll", "direction": if *up { "up" } else { "down" } }),
        Typed::Leave => json!({ "type": "terminal.release" }),
    }
}

pub fn resize(cols: u16, rows: u16) -> Value {
    json!({ "type": "terminal.resize", "cols": cols, "rows": rows })
}

/// The picture in one of herdr's lines, as bytes for a terminal; none in
/// a line that is not a picture.
pub fn frame(line: &str) -> Option<Vec<u8>> {
    let message: Value = serde_json::from_str(line.trim()).ok()?;
    if message["type"].as_str()? != "terminal.frame" {
        return None;
    }
    STANDARD.decode(message["bytes"].as_str()?).ok()
}

/// Why herdr ended the view, when one of its lines says so: the pane is
/// not there, or it closed.
pub fn closed(line: &str) -> Option<String> {
    let message: Value = serde_json::from_str(line.trim()).ok()?;
    if message["type"].as_str()? != "terminal.closed" {
        return None;
    }
    let reason = message["reason"].as_str().unwrap_or("the pane closed").trim();
    // herdr names its own command first; the reason is what follows.
    Some(reason.rsplit("failed: ").next().unwrap_or(reason).to_owned())
}

/// A terminal's size, kept within what a pane can sensibly be drawn at.
pub fn sensible(cols: u16, rows: u16) -> (u16, u16) {
    (cols.clamp(20, 500), rows.clamp(5, 300))
}

/// The size of the terminal this runs in; none when it is not one.
pub(crate) fn terminal_size() -> Option<(u16, u16)> {
    let mut size: libc::winsize = unsafe { std::mem::zeroed() };
    let ok = unsafe { libc::ioctl(libc::STDOUT_FILENO, libc::TIOCGWINSZ, &mut size) } == 0;
    (ok && size.ws_col > 0 && size.ws_row > 0).then(|| sensible(size.ws_col, size.ws_row))
}

/// The terminal handing over every key as it is typed, until dropped.
pub(crate) struct Raw {
    before: libc::termios,
}

impl Raw {
    pub(crate) fn on() -> Option<Self> {
        if unsafe { libc::isatty(libc::STDIN_FILENO) } != 1 {
            return None;
        }
        let mut before: libc::termios = unsafe { std::mem::zeroed() };
        if unsafe { libc::tcgetattr(libc::STDIN_FILENO, &mut before) } != 0 {
            return None;
        }
        let mut raw = before;
        unsafe { libc::cfmakeraw(&mut raw) };
        (unsafe { libc::tcsetattr(libc::STDIN_FILENO, libc::TCSANOW, &raw) } == 0).then_some(Raw { before })
    }
}

impl Drop for Raw {
    fn drop(&mut self) {
        unsafe { libc::tcsetattr(libc::STDIN_FILENO, libc::TCSANOW, &self.before) };
    }
}

static RESIZED: AtomicBool = AtomicBool::new(false);

extern "C" fn on_resize(_: libc::c_int) {
    RESIZED.store(true, Ordering::SeqCst);
}

fn say(to: &mut ChildStdin, line: &Value) -> Result<()> {
    writeln!(to, "{line}")?;
    to.flush()?;
    Ok(())
}

/// Ends herdr's side when this ends, however it ends.
struct Viewer(Child);

impl Drop for Viewer {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

pub struct Options {
    pub session: String,
    pub pane: String,
    /// Only look: nothing typed reaches the pane.
    pub watch: bool,
    /// The size to draw at, for when this does not run in a terminal.
    pub size: Option<(u16, u16)>,
}

/// Reads the words after `multiplex herd pane`.
pub fn options(args: &[&str]) -> Result<Options> {
    let usage = || anyhow!("usage: multiplex herd pane <session> <pane> [--watch] [--cols N --rows N]");
    let [session, pane, rest @ ..] = args else { return Err(usage()) };
    let mut options = Options { session: clean_session_name(session).map_err(|e| anyhow!("{e}"))?, pane: clean_pane_id(pane).map_err(|e| anyhow!("{e}"))?, watch: false, size: None };
    let (mut cols, mut rows) = (None, None);
    let mut rest = rest.iter();
    while let Some(word) = rest.next() {
        match *word {
            "--watch" => options.watch = true,
            "--cols" => cols = Some(rest.next().and_then(|n| n.parse::<u16>().ok()).ok_or_else(usage)?),
            "--rows" => rows = Some(rest.next().and_then(|n| n.parse::<u16>().ok()).ok_or_else(usage)?),
            _ => return Err(usage()),
        }
    }
    options.size = match (cols, rows) {
        (Some(cols), Some(rows)) => Some(sensible(cols, rows)),
        (None, None) => None,
        _ => return Err(usage()),
    };
    Ok(options)
}

pub fn run(args: &[&str]) -> Result<()> {
    let options = options(args)?;
    let (cols, rows) = options.size.or_else(terminal_size).unwrap_or((80, 24));
    let mut child = Command::new("herdr")
        .args(["--session", &options.session, "terminal", "session", if options.watch { "observe" } else { "control" }, &options.pane, "--cols", &cols.to_string(), "--rows", &rows.to_string()])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("herdr could not be run")?;
    let mut to_herdr = child.stdin.take().context("no way to talk to herdr")?;
    let from_herdr = child.stdout.take().context("no way to hear herdr")?;
    let mut complaints = child.stderr.take().context("no way to hear herdr")?;
    let mut viewer = Viewer(child);

    // The picture, as herdr draws it, straight to the terminal.
    let ended = Arc::new(AtomicBool::new(false));
    let drew = Arc::new(AtomicBool::new(false));
    let why: Arc<Mutex<Option<String>>> = Arc::new(Mutex::new(None));
    let (ended_there, drew_there, why_there) = (ended.clone(), drew.clone(), why.clone());
    std::thread::spawn(move || {
        let mut out = std::io::stdout();
        for line in BufReader::new(from_herdr).lines() {
            let Ok(line) = line else { break };
            if let Some(picture) = frame(&line) {
                drew_there.store(true, Ordering::SeqCst);
                if out.write_all(&picture).and_then(|()| out.flush()).is_err() {
                    break;
                }
            } else if let Some(reason) = closed(&line) {
                *why_there.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(reason);
            }
        }
        ended_there.store(true, Ordering::SeqCst);
    });

    let raw = Raw::on();
    unsafe { libc::signal(libc::SIGWINCH, on_resize as extern "C" fn(libc::c_int) as libc::sighandler_t) };
    let mut size = (cols, rows);
    let mut buffer = [0u8; 4096];
    let mut stdin = std::io::stdin();
    let mut left = false;
    'typing: while !ended.load(Ordering::SeqCst) {
        if RESIZED.swap(false, Ordering::SeqCst) {
            if let Some(now) = terminal_size().filter(|now| *now != size) {
                size = now;
                say(&mut to_herdr, &resize(now.0, now.1))?;
            }
        }
        // Waits a moment for a key, so a new size and herdr going away
        // are noticed while nothing is typed.
        let mut waiting = libc::pollfd { fd: libc::STDIN_FILENO, events: libc::POLLIN, revents: 0 };
        if unsafe { libc::poll(&mut waiting, 1, 100) } <= 0 {
            continue;
        }
        let count = match stdin.read(&mut buffer) {
            Ok(0) | Err(_) => break,
            Ok(count) => count,
        };
        for what in typed(&buffer[..count]) {
            let leaving = what == Typed::Leave;
            // Watching only: keys go nowhere, but leaving and moving
            // through the output still work.
            if !(options.watch && matches!(what, Typed::Input(_))) && say(&mut to_herdr, &command(&what)).is_err() {
                break 'typing;
            }
            if leaving {
                left = true;
                break 'typing;
            }
        }
    }
    if !left {
        let _ = say(&mut to_herdr, &command(&Typed::Leave));
    }
    drop(to_herdr);
    drop(raw);
    // herdr's last word, if it had one, arrives as it goes.
    for _ in 0..20 {
        if ended.load(Ordering::SeqCst) {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(25));
    }
    let why = why.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).take();
    if drew.load(Ordering::SeqCst) {
        // Leave the terminal as a terminal: the cursor back, colours off,
        // the picture gone.
        let mut out = std::io::stdout();
        let _ = out.write_all(b"\x1b[?25h\x1b[0m\x1b[2J\x1b[H");
        // It was herdr that ended it (the pane closed), not the one watching.
        if let Some(why) = why.filter(|_| !left) {
            let _ = writeln!(out, "herdr: {why}\r");
        }
        let _ = out.flush();
        return Ok(());
    }
    // Nothing was ever drawn: herdr said why, in its last line or its complaints.
    let _ = viewer.0.kill();
    let mut said = String::new();
    let _ = complaints.read_to_string(&mut said);
    let said = said.lines().rev().find(|line| !line.trim().is_empty()).map(|line| line.trim().to_owned());
    let message = why.or(said).unwrap_or_else(|| "it showed nothing".to_owned());
    bail!("herdr: {}", message.strip_prefix("herdr: ").unwrap_or(&message))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn what_is_typed_is_input_scrolling_or_leaving() {
        assert_eq!(typed(b"ls -la\r"), [Typed::Input(b"ls -la\r".to_vec())]);
        assert!(typed(b"").is_empty());
        // Keys an agent needs go through as they are: Esc, Ctrl+C, arrows, a paste.
        assert_eq!(typed(b"\x1b\x03\x1b[A\x1b[200~hi\x1b[201~"), [Typed::Input(b"\x1b\x03\x1b[A\x1b[200~hi\x1b[201~".to_vec())]);
        // Plain PageUp is the pane's own; with Shift it moves through earlier output.
        assert_eq!(typed(b"\x1b[5~"), [Typed::Input(b"\x1b[5~".to_vec())]);
        assert_eq!(typed(b"a\x1b[5;2~b\x1b[6;2~"), [Typed::Input(b"a".to_vec()), Typed::Scroll { up: true }, Typed::Input(b"b".to_vec()), Typed::Scroll { up: false }]);
        // Ctrl+\ leaves, and what came after it in the same read is not typed.
        assert_eq!(typed(b"yes\r\x1crm -rf\r"), [Typed::Input(b"yes\r".to_vec()), Typed::Leave]);
        assert_eq!(typed(b"\x1c"), [Typed::Leave]);
    }

    #[test]
    fn each_becomes_the_line_herdr_expects() {
        assert_eq!(command(&Typed::Input(b"ok\r".to_vec())).to_string(), r#"{"bytes":"b2sN","type":"terminal.input"}"#);
        // Bytes that are not text stay what they were.
        let odd = command(&Typed::Input(vec![0xff, 0x00, 0x1b]));
        assert_eq!(STANDARD.decode(odd["bytes"].as_str().unwrap()).unwrap(), [0xff, 0x00, 0x1b]);
        assert_eq!(command(&Typed::Scroll { up: true }).to_string(), r#"{"direction":"up","type":"terminal.scroll"}"#);
        assert_eq!(command(&Typed::Scroll { up: false })["direction"], "down");
        assert_eq!(command(&Typed::Leave).to_string(), r#"{"type":"terminal.release"}"#);
        assert_eq!(resize(52, 30).to_string(), r#"{"cols":52,"rows":30,"type":"terminal.resize"}"#);
    }

    #[test]
    fn a_picture_is_taken_out_of_herdrs_line() {
        let line = r#"{"bytes":"G1sySmhp","encoding":"ansi","full":true,"height":20,"seq":1,"type":"terminal.frame","width":50}"#;
        assert_eq!(frame(line).unwrap(), b"\x1b[2Jhi");
        assert!(frame(r#"{"type":"terminal.closed"}"#).is_none());
        assert!(frame(r#"{"type":"terminal.frame","bytes":"not base64 !"}"#).is_none());
        assert!(frame("herdr: something went wrong").is_none());
        assert!(frame("").is_none());
    }

    #[test]
    fn herdrs_reason_for_ending_is_read() {
        assert_eq!(closed(r#"{"reason":"terminal session control failed: terminal target w9:p9 not found","type":"terminal.closed"}"#).unwrap(), "terminal target w9:p9 not found");
        assert_eq!(closed(r#"{"reason":"pane exited","type":"terminal.closed"}"#).unwrap(), "pane exited");
        assert_eq!(closed(r#"{"type":"terminal.closed"}"#).unwrap(), "the pane closed");
        assert!(closed(r#"{"type":"terminal.frame","bytes":"aGk="}"#).is_none());
        assert!(closed("not json").is_none());
    }

    #[test]
    fn the_words_after_pane_are_checked() {
        let plain = options(&["default", "w1:p3"]).unwrap();
        assert_eq!((plain.session.as_str(), plain.pane.as_str(), plain.watch, plain.size), ("default", "w1:p3", false, None));
        let sized = options(&["night", "w2:p1", "--watch", "--cols", "52", "--rows", "30"]).unwrap();
        assert_eq!((sized.watch, sized.size), (true, Some((52, 30))));
        // A size no pane can be drawn at is brought within reason.
        assert_eq!(options(&["a", "w1:p1", "--cols", "3", "--rows", "9000"]).unwrap().size, Some((20, 300)));
        assert_eq!(sensible(0, 0), (20, 5));
        for bad in [&[][..], &["default"], &["default", "w1:t1"], &["bad name", "w1:p1"], &["default", "w1:p1;ls"], &["default", "w1:p1", "--cols", "50"], &["default", "w1:p1", "--cols", "x", "--rows", "2"], &["default", "w1:p1", "--loud"]] {
            assert!(options(bad).is_err(), "{bad:?}");
        }
    }
}
