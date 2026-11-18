//! The object the window talks to. It holds what the window shows, as
//! JSON text the QML reads, and does what the window asks by running the
//! `multiplex` command on another thread, so the window never waits.

/// The bridge between the window (QML) and Rust.
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        /// Qt's text type.
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, phones)]
        #[qproperty(QString, access)]
        #[qproperty(QString, checks)]
        #[qproperty(QString, kept)]
        #[qproperty(QString, pairing)]
        #[qproperty(QString, notice)]
        #[qproperty(QString, accent)]
        #[qproperty(QString, ink)]
        #[qproperty(i32, radius)]
        #[qproperty(bool, busy)]
        #[qproperty(QString, shot)]
        #[qproperty(QString, view)]
        type Backend = super::BackendRust;

        /// Reads the phones, their switches and the theme again.
        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        /// Reads the terminals the session server keeps.
        #[qinvokable]
        #[cxx_name = "readKept"]
        fn read_kept(self: Pin<&mut Self>);

        /// Opens one of them in a terminal window.
        #[qinvokable]
        #[cxx_name = "openKept"]
        fn open_kept(self: Pin<&mut Self>, id: &QString);

        /// Checks what this computer is ready for.
        #[qinvokable]
        #[cxx_name = "checkComputer"]
        fn check_computer(self: Pin<&mut Self>);

        /// Makes a phone ring.
        #[qinvokable]
        fn ring(self: Pin<&mut Self>, phone: &QString);

        /// Sends files (one path or file address per line) to a phone.
        #[qinvokable]
        #[cxx_name = "sendFiles"]
        fn send_files(self: Pin<&mut Self>, phone: &QString, files: &QString);

        /// Asks which files, then sends them.
        #[qinvokable]
        #[cxx_name = "chooseAndSend"]
        fn choose_and_send(self: Pin<&mut Self>, phone: &QString);

        /// Switches one thing a phone may do on or off.
        #[qinvokable]
        fn allow(self: Pin<&mut Self>, phone: &QString, what: &QString, on: bool);

        /// Removes a paired phone.
        #[qinvokable]
        fn unpair(self: Pin<&mut Self>, phone: &QString);

        /// Shows a pairing code and waits for a phone to use it.
        #[qinvokable]
        #[cxx_name = "startPairing"]
        fn start_pairing(self: Pin<&mut Self>);

        /// Takes the pairing code back.
        #[qinvokable]
        #[cxx_name = "cancelPairing"]
        fn cancel_pairing(self: Pin<&mut Self>);
    }

    impl cxx_qt::Threading for Backend {}
}

use core::pin::Pin;
use std::io::{BufRead, BufReader};
use std::process::{Command as Process, Stdio};
use std::sync::{Arc, Mutex};

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use crate::logic::{self, Command};

/// What the window shows. The lists are JSON text: QML reads JSON
/// natively, and it keeps this bridge to a handful of strings.
pub struct BackendRust {
    /// `[{name, connected, battery, charging}]`
    phones: QString,
    /// `{name: {desktop, input, files, clipboard, terminal, tunnels}}`
    access: QString,
    /// `[{name, ok, required, detail}]`, empty until asked for.
    checks: QString,
    kept: QString,
    /// `{}` when not pairing; `{code, qr, computer, expires}` while a code
    /// is shown; `{paired}`, `{expired}` or `{error}` at the end.
    pairing: QString,
    /// What the last action came to, in one line.
    notice: QString,
    /// The theme's accent, and black or white to write on it.
    accent: QString,
    ink: QString,
    /// Hyprland's window rounding.
    radius: i32,
    /// Something asked for is still being done.
    busy: bool,
    /// For pictures of the window: where to save one. Empty in normal use.
    shot: QString,
    /// What to do first, as a JSON list of actions (`logic::first_actions`).
    view: QString,

    command: Arc<Command>,
    /// The `multiplex pair` that is waiting, while one is.
    pairing_process: Arc<Mutex<Option<u32>>>,
}

impl Default for BackendRust {
    fn default() -> Self {
        let command = Arc::new(Command::from_env());
        let accent = if command.demo() { logic::DEFAULT_ACCENT.to_owned() } else { logic::accent() };
        Self {
            // Read at once (it takes a few milliseconds) so the window
            // opens with its phones, not empty.
            phones: QString::from(&command.phones()),
            access: QString::from(&command.access()),
            checks: QString::from("[]"),
            kept: QString::from("[]"),
            pairing: QString::from("{}"),
            notice: QString::default(),
            ink: QString::from(logic::ink_on(&accent)),
            accent: QString::from(&accent),
            radius: if command.demo() { 0 } else { logic::rounding() },
            busy: false,
            shot: QString::from(&std::env::var("MULTIPLEX_APP_SHOT").unwrap_or_default()),
            view: QString::from(&{
                // `main` has already refused a command line this cannot read.
                let args: Vec<String> = std::env::args().skip(1).collect();
                logic::first_actions(&args, &std::env::var("MULTIPLEX_APP_VIEW").unwrap_or_default()).unwrap_or_else(|_| "[]".to_owned())
            }),
            command,
            pairing_process: Arc::new(Mutex::new(None)),
        }
    }
}

/// Interrupts the `multiplex pair` that is waiting, if one is: it then
/// removes its one-time key and says so.
fn interrupt(waiting: &Mutex<Option<u32>>) -> bool {
    let pid = *waiting.lock().unwrap_or_else(|e| e.into_inner());
    match pid.and_then(|pid| i32::try_from(pid).ok()) {
        Some(pid) => {
            // SAFETY: a signal to a process this program started.
            unsafe { libc::kill(pid, libc::SIGINT) };
            true
        }
        None => false,
    }
}

impl Drop for BackendRust {
    /// The window is closing: a pairing code must not stay good behind it.
    fn drop(&mut self) {
        if interrupt(&self.pairing_process) {
            // Give it the moment it needs to remove its key.
            for _ in 0..20 {
                if self.pairing_process.lock().unwrap_or_else(|e| e.into_inner()).is_none() {
                    break;
                }
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
        }
    }
}

/// Sets what changed, and only that, so the window redraws only then.
fn show(mut backend: Pin<&mut qobject::Backend>, phones: &str, access: &str) {
    if backend.phones().to_string() != phones {
        backend.as_mut().set_phones(QString::from(phones));
    }
    if backend.access().to_string() != access {
        backend.as_mut().set_access(QString::from(access));
    }
}

/// A made-up pairing code for trying the window: a real QR picture of
/// words that pair nothing.
fn demo_pairing() -> String {
    let rows: Vec<String> = qrcode::QrCode::with_error_correction_level(b"This is a made-up code for a picture of the window. It pairs nothing.", qrcode::EcLevel::L)
        .map(|qr| {
            let width = qr.width();
            qr.to_colors().chunks(width).map(|row| row.iter().map(|c| if *c == qrcode::Color::Dark { '1' } else { '0' }).collect()).collect()
        })
        .unwrap_or_default();
    let expires = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0) + 272;
    serde_json::json!({ "code": "made-up", "qr": rows, "computer": "desk", "expires": expires }).to_string()
}

impl qobject::Backend {
    /// Reads the phones, their switches and the theme again.
    pub fn refresh(self: Pin<&mut Self>) {
        let command = self.rust().command.clone();
        let qt_thread = self.qt_thread();
        std::thread::spawn(move || {
            let (phones, access) = (command.phones(), command.access());
            let (accent, radius) = if command.demo() { (logic::DEFAULT_ACCENT.to_owned(), 0) } else { (logic::accent(), logic::rounding()) };
            let _ = qt_thread.queue(move |mut backend| {
                show(backend.as_mut(), &phones, &access);
                if backend.accent().to_string() != accent {
                    backend.as_mut().set_ink(QString::from(logic::ink_on(&accent)));
                    backend.as_mut().set_accent(QString::from(&accent));
                }
                if *backend.radius() != radius {
                    backend.as_mut().set_radius(radius);
                }
            });
        });
    }

    /// Reads the terminals the session server keeps.
    pub fn read_kept(self: Pin<&mut Self>) {
        let command = self.rust().command.clone();
        let qt_thread = self.qt_thread();
        std::thread::spawn(move || {
            let kept = command.kept();
            let _ = qt_thread.queue(move |mut backend| {
                if backend.kept().to_string() != kept {
                    backend.as_mut().set_kept(QString::from(&kept));
                }
            });
        });
    }

    /// Opens one of them in a terminal window.
    pub fn open_kept(mut self: Pin<&mut Self>, id: &QString) {
        let said = self.rust().command.open_kept(&id.to_string()).said;
        self.as_mut().set_notice(QString::from(&said));
    }

    /// Checks what this computer is ready for.
    pub fn check_computer(self: Pin<&mut Self>) {
        let command = self.rust().command.clone();
        let qt_thread = self.qt_thread();
        std::thread::spawn(move || {
            let checks = command.checks();
            let _ = qt_thread.queue(move |mut backend| backend.as_mut().set_checks(QString::from(&checks)));
        });
    }

    /// Runs the command, says what it said, and shows what it changed.
    fn act(mut self: Pin<&mut Self>, args: Vec<String>) {
        self.as_mut().set_busy(true);
        let command = self.rust().command.clone();
        let qt_thread = self.qt_thread();
        std::thread::spawn(move || {
            let reply = command.run(&args.iter().map(String::as_str).collect::<Vec<_>>());
            let (phones, access) = (command.phones(), command.access());
            let _ = qt_thread.queue(move |mut backend| {
                backend.as_mut().set_busy(false);
                backend.as_mut().set_notice(QString::from(&reply.said));
                show(backend.as_mut(), &phones, &access);
            });
        });
    }

    /// Makes a phone ring.
    pub fn ring(self: Pin<&mut Self>, phone: &QString) {
        self.act(vec!["ring".to_owned(), "--to".to_owned(), phone.to_string()]);
    }

    /// Sends files (one path or file address per line) to a phone.
    pub fn send_files(mut self: Pin<&mut Self>, phone: &QString, files: &QString) {
        let files = logic::files_in(&files.to_string());
        if files.is_empty() {
            self.as_mut().set_notice(QString::from("Those are not files on this computer."));
            return;
        }
        let mut args = vec!["send".to_owned(), "--to".to_owned(), phone.to_string()];
        args.extend(files.iter().map(|file| file.to_string_lossy().into_owned()));
        self.act(args);
    }

    /// Asks which files (the desktop's own file chooser), then sends them.
    pub fn choose_and_send(mut self: Pin<&mut Self>, phone: &QString) {
        if self.rust().command.demo() {
            self.as_mut().set_notice(QString::from("On its way to the phone."));
            return;
        }
        let phone = phone.to_string();
        let command = self.rust().command.clone();
        let qt_thread = self.qt_thread();
        std::thread::spawn(move || {
            let Some(files) = rfd::FileDialog::new().set_title(format!("Send to {phone}")).pick_files().filter(|files| !files.is_empty()) else {
                return;
            };
            let mut args = vec!["send".to_owned(), "--to".to_owned(), phone];
            args.extend(files.iter().map(|file| file.to_string_lossy().into_owned()));
            let reply = command.run(&args.iter().map(String::as_str).collect::<Vec<_>>());
            let _ = qt_thread.queue(move |mut backend| backend.as_mut().set_notice(QString::from(&reply.said)));
        });
    }

    /// Switches one thing a phone may do on or off.
    pub fn allow(self: Pin<&mut Self>, phone: &QString, what: &QString, on: bool) {
        self.act(vec!["access".to_owned(), phone.to_string(), what.to_string(), if on { "on" } else { "off" }.to_owned()]);
    }

    /// Removes a paired phone.
    pub fn unpair(self: Pin<&mut Self>, phone: &QString) {
        self.act(vec!["unpair".to_owned(), phone.to_string()]);
    }

    /// Shows a pairing code and waits for a phone to use it. The command
    /// says the code on its first line and how it ended on its second.
    pub fn start_pairing(mut self: Pin<&mut Self>) {
        if self.rust().command.demo() {
            self.as_mut().set_pairing(QString::from(&demo_pairing()));
            return;
        }
        let waiting = self.rust().pairing_process.clone();
        if waiting.lock().unwrap_or_else(|e| e.into_inner()).is_some() {
            return;
        }
        let command = self.rust().command.clone();
        let child = Process::new(command.bin()).args(["pair", "--json"]).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn();
        let mut child = match child {
            Ok(child) => child,
            Err(_) => {
                self.as_mut().set_pairing(QString::from(&serde_json::json!({ "error": "The multiplex command was not found." }).to_string()));
                return;
            }
        };
        *waiting.lock().unwrap_or_else(|e| e.into_inner()) = Some(child.id());
        let qt_thread = self.qt_thread();
        std::thread::spawn(move || {
            let mut ended = false;
            if let Some(out) = child.stdout.take() {
                for line in BufReader::new(out).lines().map_while(Result::ok) {
                    let Ok(said) = serde_json::from_str::<serde_json::Value>(&line) else { continue };
                    // Taken back by the user: the window is already as before.
                    let state = if said.get("cancelled").is_some() { "{}".to_owned() } else { line };
                    ended = said.get("code").is_none();
                    let _ = qt_thread.queue(move |mut backend| backend.as_mut().set_pairing(QString::from(&state)));
                }
            }
            let done = child.wait_with_output();
            *waiting.lock().unwrap_or_else(|e| e.into_inner()) = None;
            if !ended {
                // It stopped without saying how: say why, as far as it said.
                let why = done.map(|out| logic::sentence(&String::from_utf8_lossy(&out.stderr), "Pairing stopped.")).unwrap_or_else(|_| "Pairing stopped.".to_owned());
                let state = serde_json::json!({ "error": why }).to_string();
                let _ = qt_thread.queue(move |mut backend| backend.as_mut().set_pairing(QString::from(&state)));
            }
            let (phones, access) = (command.phones(), command.access());
            let _ = qt_thread.queue(move |backend| show(backend, &phones, &access));
        });
    }

    /// Takes the pairing code back: the command removes its one-time key
    /// when it is interrupted.
    pub fn cancel_pairing(mut self: Pin<&mut Self>) {
        if !interrupt(&self.rust().pairing_process) {
            self.as_mut().set_pairing(QString::from("{}"));
        }
    }
}
