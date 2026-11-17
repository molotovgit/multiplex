//! `multiplex input`: a virtual touchpad and keyboard in the running
//! Hyprland session, driven by short lines on standard input (the phone
//! writes them over SSH; see `multiplex_proto::input`).
//!
//! It is an ordinary Wayland client using the two protocols made for
//! this: a virtual pointer (relative motion, buttons, scrolling) and a
//! virtual keyboard with a US keymap, which is what the phone's keyboard
//! assumes. No picture is involved, so it costs next to nothing.
//!
//! A key can never stay down: everything is released when the input ends,
//! and when the phone goes quiet while something is held.

use std::collections::BTreeSet;
use std::io::{BufRead, Write};
use std::os::fd::AsFd;
use std::os::unix::net::UnixStream;
use std::process::{Command, Stdio};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::time::{Duration, Instant};

use anyhow::{anyhow, bail, Context, Result};
use multiplex_proto::input::{Button, InputEvent, QUIET_MS, READY};
use wayland_client::globals::{registry_queue_init, GlobalListContents};
use wayland_client::protocol::wl_pointer::{Axis, AxisSource, ButtonState};
use wayland_client::protocol::wl_registry::WlRegistry;
use wayland_client::protocol::wl_seat::WlSeat;
use wayland_client::{delegate_noop, Connection, Dispatch, EventQueue, QueueHandle};
use wayland_protocols_misc::zwp_virtual_keyboard_v1::client::zwp_virtual_keyboard_manager_v1::ZwpVirtualKeyboardManagerV1;
use wayland_protocols_misc::zwp_virtual_keyboard_v1::client::zwp_virtual_keyboard_v1::ZwpVirtualKeyboardV1;
use wayland_protocols_wlr::virtual_pointer::v1::client::zwlr_virtual_pointer_manager_v1::ZwlrVirtualPointerManagerV1;
use wayland_protocols_wlr::virtual_pointer::v1::client::zwlr_virtual_pointer_v1::ZwlrVirtualPointerV1;

use crate::desk::Session;

/// Nothing the compositor tells this client matters to it.
struct Quiet;

impl Dispatch<WlRegistry, GlobalListContents> for Quiet {
    fn event(_: &mut Self, _: &WlRegistry, _: <WlRegistry as wayland_client::Proxy>::Event, _: &GlobalListContents, _: &Connection, _: &QueueHandle<Self>) {}
}
delegate_noop!(Quiet: ignore WlSeat);
delegate_noop!(Quiet: ZwlrVirtualPointerManagerV1);
delegate_noop!(Quiet: ZwlrVirtualPointerV1);
delegate_noop!(Quiet: ZwpVirtualKeyboardManagerV1);
delegate_noop!(Quiet: ZwpVirtualKeyboardV1);

/// Linux key codes of the modifiers, with their bit in an xkb modifier
/// mask (Shift, Lock, Control, Mod1, Mod2, Mod3, Mod4, Mod5 in that order).
const MODIFIERS: [(u16, u32); 8] = [(42, 1), (54, 1), (29, 4), (97, 4), (56, 8), (100, 8), (125, 64), (126, 64)];
const KEY_LEFTCTRL: u16 = 29;
const KEY_V: u16 = 47;

/// The modifier mask while these keys are down.
fn modifier_mask(down: &BTreeSet<u16>) -> u32 {
    MODIFIERS.iter().filter(|(code, _)| down.contains(code)).fold(0, |mask, (_, bit)| mask | bit)
}

struct Devices {
    conn: Connection,
    queue: EventQueue<Quiet>,
    pointer: ZwlrVirtualPointerV1,
    keyboard: ZwpVirtualKeyboardV1,
    started: Instant,
    keys: BTreeSet<u16>,
    buttons: BTreeSet<Button>,
    session: Session,
}

impl Devices {
    fn open() -> Result<Self> {
        let session = Session::find()?;
        let socket = session.wayland_socket();
        let stream = UnixStream::connect(&socket).with_context(|| format!("could not reach the desktop at {}", socket.display()))?;
        let conn = Connection::from_socket(stream).map_err(|err| anyhow!("the desktop refused the connection: {err}"))?;
        let (globals, mut queue) = registry_queue_init::<Quiet>(&conn).map_err(|err| anyhow!("the desktop did not answer: {err}"))?;
        let qh = queue.handle();
        let seat: WlSeat = globals.bind(&qh, 1..=7, ()).map_err(|_| anyhow!("the desktop has no seat"))?;
        let pointers: ZwlrVirtualPointerManagerV1 = globals.bind(&qh, 1..=2, ()).map_err(|_| anyhow!("this desktop does not take a virtual pointer"))?;
        let keyboards: ZwpVirtualKeyboardManagerV1 = globals.bind(&qh, 1..=1, ()).map_err(|_| anyhow!("this desktop does not take a virtual keyboard"))?;
        let pointer = pointers.create_virtual_pointer(Some(&seat), &qh, ());
        let keyboard = keyboards.create_virtual_keyboard(&seat, &qh, ());

        // The keyboard needs its keymap as a file the desktop can map.
        let keymap = us_keymap()?;
        let path = session.runtime_dir().join(format!("multiplex-keymap-{}", std::process::id()));
        let mut file = std::fs::File::options().read(true).write(true).create_new(true).open(&path).context("could not write the keymap")?;
        let _ = std::fs::remove_file(&path);
        file.write_all(keymap.as_bytes())?;
        file.write_all(&[0])?;
        file.flush()?;
        // 1: an xkb keymap, version 1.
        keyboard.keymap(1, file.as_fd(), keymap.len() as u32 + 1);
        queue.roundtrip(&mut Quiet).map_err(|err| anyhow!("the desktop refused the keyboard: {err}"))?;
        Ok(Self { conn, queue, pointer, keyboard, started: Instant::now(), keys: BTreeSet::new(), buttons: BTreeSet::new(), session })
    }

    fn time(&self) -> u32 {
        self.started.elapsed().as_millis() as u32
    }

    fn key(&mut self, code: u16, down: bool) {
        let changed = if down { self.keys.insert(code) } else { self.keys.remove(&code) };
        if !changed {
            return;
        }
        self.keyboard.key(self.time(), u32::from(code), u32::from(down));
        if MODIFIERS.iter().any(|(m, _)| *m == code) {
            self.keyboard.modifiers(modifier_mask(&self.keys), 0, 0, 0);
        }
    }

    fn button(&mut self, button: Button, down: bool) {
        let changed = if down { self.buttons.insert(button) } else { self.buttons.remove(&button) };
        if changed {
            self.pointer.button(self.time(), button.code(), if down { ButtonState::Pressed } else { ButtonState::Released });
            self.pointer.frame();
        }
    }

    fn release_all(&mut self) {
        for code in std::mem::take(&mut self.keys) {
            self.keyboard.key(self.time(), u32::from(code), 0);
        }
        self.keyboard.modifiers(0, 0, 0, 0);
        for button in std::mem::take(&mut self.buttons) {
            self.pointer.button(self.time(), button.code(), ButtonState::Released);
        }
        self.pointer.frame();
    }

    fn held(&self) -> bool {
        !self.keys.is_empty() || !self.buttons.is_empty()
    }

    fn apply(&mut self, event: InputEvent) {
        match event {
            InputEvent::Move { dx, dy } => {
                self.pointer.motion(self.time(), dx, dy);
                self.pointer.frame();
            }
            InputEvent::Scroll { dx, dy } => {
                self.pointer.axis_source(AxisSource::Finger);
                if dy != 0.0 {
                    self.pointer.axis(self.time(), Axis::VerticalScroll, dy);
                }
                if dx != 0.0 {
                    self.pointer.axis(self.time(), Axis::HorizontalScroll, dx);
                }
                self.pointer.frame();
            }
            InputEvent::Button { button, down } => self.button(button, down),
            InputEvent::Key { code, down } => self.key(code, down),
            InputEvent::Paste { text } => self.paste(&text),
            InputEvent::ReleaseAll => self.release_all(),
            InputEvent::Ping => {}
        }
    }

    /// Puts text on the clipboard (with `wl-copy`) and presses Ctrl+V.
    fn paste(&mut self, text: &str) {
        let copy = Command::new("wl-copy")
            .env("XDG_RUNTIME_DIR", self.session.runtime_dir())
            .env("WAYLAND_DISPLAY", self.session.wayland_socket())
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
        let Ok(mut copy) = copy else {
            eprintln!("multiplex: wl-copy is missing, so text outside the US keyboard cannot be typed");
            return;
        };
        if let Some(mut stdin) = copy.stdin.take() {
            let _ = stdin.write_all(text.as_bytes());
        }
        let _ = copy.wait();
        // The clipboard owner needs a moment before a program asks for it.
        let _ = self.conn.flush();
        std::thread::sleep(Duration::from_millis(80));
        self.release_all();
        for (code, down) in [(KEY_LEFTCTRL, true), (KEY_V, true), (KEY_V, false), (KEY_LEFTCTRL, false)] {
            self.key(code, down);
        }
    }

    fn flush(&mut self) -> Result<()> {
        self.conn.flush().map_err(|err| anyhow!("the desktop went away: {err}"))
    }
}

/// A complete US keymap, from xkbcommon's own tool.
fn us_keymap() -> Result<String> {
    let out = Command::new("xkbcli").args(["compile-keymap", "--layout", "us"]).output().context("xkbcli (from libxkbcommon) is needed for the keyboard")?;
    let text = String::from_utf8_lossy(&out.stdout).into_owned();
    if !out.status.success() || !text.contains("xkb_keymap") {
        bail!("xkbcli could not make a keymap");
    }
    Ok(text)
}

/// Whether the pointer and keyboard can be made here (for `multiplex doctor`).
pub fn available() -> bool {
    Devices::open().is_ok()
}

/// `check`: make the pointer and keyboard, say so, and leave without
/// sending anything (for `multiplex doctor`).
pub fn run(check: bool) -> Result<()> {
    let mut devices = Devices::open()?;
    println!("{READY}");
    std::io::stdout().flush()?;
    if check {
        return Ok(());
    }

    // Lines are read on their own thread, so silence can be noticed.
    let (lines, incoming) = mpsc::channel::<String>();
    std::thread::spawn(move || {
        for line in std::io::stdin().lock().lines() {
            let Ok(line) = line else { break };
            if lines.send(line).is_err() {
                break;
            }
        }
    });

    let quiet = Duration::from_millis(QUIET_MS);
    let mut heard = Instant::now();
    let mut checked = Instant::now();
    loop {
        match incoming.recv_timeout(Duration::from_millis(500)) {
            Ok(first) => {
                heard = Instant::now();
                // Everything that has arrived goes out in one write.
                for line in std::iter::once(first).chain(incoming.try_iter()) {
                    match InputEvent::parse_line(line.trim_end_matches('\r')) {
                        Ok(event) => devices.apply(event),
                        Err(err) => eprintln!("multiplex: ignored a line: {err}"),
                    }
                }
                devices.flush()?;
            }
            Err(RecvTimeoutError::Timeout) => {
                if devices.held() && heard.elapsed() > quiet {
                    eprintln!("multiplex: the phone went quiet: released everything");
                    devices.release_all();
                    devices.flush()?;
                }
            }
            // The phone hung up.
            Err(RecvTimeoutError::Disconnected) => break,
        }
        // Now and then, hear the desktop out (and notice if it is gone).
        if checked.elapsed() > Duration::from_secs(10) {
            devices.queue.roundtrip(&mut Quiet).map_err(|err| anyhow!("the desktop went away: {err}"))?;
            checked = Instant::now();
        }
    }
    devices.release_all();
    devices.flush()?;
    let _ = devices.queue.roundtrip(&mut Quiet);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn modifiers_make_the_mask_xkb_expects() {
        let down = |codes: &[u16]| codes.iter().copied().collect::<BTreeSet<_>>();
        assert_eq!(modifier_mask(&down(&[])), 0);
        assert_eq!(modifier_mask(&down(&[42])), 1, "Shift");
        assert_eq!(modifier_mask(&down(&[29, 56])), 4 | 8, "Ctrl and Alt");
        assert_eq!(modifier_mask(&down(&[125, 54, 30])), 64 | 1, "Super and right Shift; A is no modifier");
        assert_eq!(modifier_mask(&down(&[42, 54])), 1, "both Shifts are one Shift");
    }
}
