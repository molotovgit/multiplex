//! `multiplex`: the Omarchy side of Multiplex.
//!
//! - `multiplex pair` shows a QR code; scanning it with the phone app pairs
//!   the phone (see multiplex-proto for how).
//! - `multiplex devices` and `multiplex unpair <name>` list and remove
//!   paired phones.
//! - `multiplex setup` prepares the computer once; `multiplex doctor`
//!   checks it.

mod agent;
mod agents;
mod bar;
mod camera;
mod desk;
mod feed;
mod gate;
mod h264;
mod herd;
mod sessions;
mod input;
mod mic;
mod pane;
mod read;
mod screen;
mod share;
mod speaker;
mod store;
mod sudo;
mod system;

use std::io::Write;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use anyhow::{bail, Context};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use multiplex_proto::{PairingCode, RegisterReply, PAIRING_SECONDS};
use qrcode::render::unicode::Dense1x2;
use qrcode::{EcLevel, QrCode};

use store::{now_unix, Store};
use system::Computer;

const HELP: &str = "multiplex: the Omarchy side of Multiplex

  multiplex pair              Show a QR code to pair a phone (scan it in the app)
  multiplex pair --code-only  Print only the pairing code, for scripts
  multiplex open              Open the Multiplex window (--pair, --phone <name>, --send <name>)
  multiplex bar [on|off]      Put Multiplex in the Omarchy bar, or take it out
  multiplex devices           List the paired phones
  multiplex devices --json    The same as a list a script or a bar widget can read
  multiplex unpair <name>     Remove a paired phone
  multiplex access [<name>]   What each phone may do here; `multiplex access <name> <what> on|off`
  multiplex setup [--dry-run] Prepare this computer once. Run it as yourself, without sudo in front: it asks for your password itself
  multiplex send <file>…      Send files or folders to the phone (add --to <name> with several phones)
  multiplex ring              Make the phone ring, to find it
  multiplex approve <what>    Ask for a yes on the phone (fingerprint there); succeeds only with it
  multiplex setup --sudo      Have sudo ask the phone first. Also run as yourself (--dry-run only shows the plan; --sudo-off undoes it)
  multiplex agent             An SSH agent whose key lives on the phone (each use confirmed there)
  multiplex key [<name>]      The phones' public keys, for servers and for Git signing
  multiplex sms <number> <text>  Send a text message from the phone (it has to allow this computer to)
  multiplex doctor            Check that everything is ready

The paired phone uses these over SSH:
  multiplex desk state        The desktop's state as one line of JSON
  multiplex desk watch        The same, again whenever it changes
  multiplex desk binds        Every key binding with a description
  multiplex desk do <action>  Switch workspace, move focus, media keys, …
  multiplex input             A touchpad and keyboard, driven by lines on standard input
  multiplex share …           The inbox, the clipboard, opening a link
  multiplex link [<phone>]    What waits for the phone, and clipboard changes, as lines
  multiplex phone …           The phone's battery, and its notifications for this screen
  multiplex agents            Coding agents in the terminals Multiplex keeps, with their state
  multiplex herd …            What the session server keeps, for the phone: state, watch (again on every change), news, do
  multiplex here              This terminal, kept running by Multiplex and reachable from the phone
  multiplex sessions …        The terminals Multiplex keeps: serve, list, attach <id>, kill <id>
  multiplex herd pane <session> <pane>   One pane in this terminal, at this terminal's size (Ctrl+\\ leaves)
  multiplex screen            The phone's screen in a window (the phone sends the picture)
  multiplex camera            The phone's camera as a camera of this computer (the phone sends the picture)
  multiplex mic               The phone's microphone as a microphone of this computer (the phone sends the sound)
  multiplex speaker           The phone as a loudspeaker of this computer (the phone plays the sound)
";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    let result = match args.as_slice() {
        ["pair"] => pair(PairAs::Terminal),
        ["pair", "--code-only"] => pair(PairAs::CodeOnly),
        ["pair", "--json"] => pair(PairAs::Json),
        ["open", how @ ..] => open_app(how),
        ["bar", how @ ..] => bar::run(how),
        ["pair-accept", id] => accept(id),
        ["devices"] => devices(),
        ["devices", "--json"] => devices_json(),
        ["unpair", name] => unpair(name),
        ["setup"] => setup(false),
        ["setup", "--dry-run"] => setup(true),
        // sudo approved on the phone: asked for by name, never part of plain setup.
        ["setup", "--sudo"] => sudo::setup(true, None, false),
        ["setup", "--sudo", "--dry-run"] => sudo::setup(true, None, true),
        ["setup", "--sudo", phone] => sudo::setup(true, Some(phone), false),
        ["setup", "--sudo", phone, "--dry-run"] => sudo::setup(true, Some(phone), true),
        ["setup", "--sudo-off"] => sudo::setup(false, None, false),
        ["setup", "--sudo-off", "--dry-run"] => sudo::setup(false, None, true),
        // What sudo's PAM file runs. It says nothing and only ever answers yes or no.
        ["approve", "--pam", rest @ ..] => std::process::exit(if sudo::pam(rest) { 0 } else { 1 }),
        ["doctor"] => doctor(),
        ["doctor", "--json"] => doctor_json(),
        ["desk", rest @ ..] => desk::run(rest),
        ["access", rest @ ..] => gate::access(rest),
        ["gate", phone] => gate::gate(phone),
        ["agents"] => agents::run(),
        ["herd", rest @ ..] => herd::run(rest),
        ["sessions", rest @ ..] => sessions::run(rest),
        ["here"] => sessions::here(false),
        ["here", "--window"] => sessions::here(true),
        ["setup", "--terminals"] => sessions::setup_terminals(true, false),
        ["setup", "--terminals", "--dry-run"] => sessions::setup_terminals(true, true),
        ["setup", "--terminals-off"] => sessions::setup_terminals(false, false),
        ["setup", "--terminals-off", "--dry-run"] => sessions::setup_terminals(false, true),
        ["screen", rest @ ..] => screen::run(rest),
        ["camera", rest @ ..] => camera::run(rest),
        ["mic", rest @ ..] => mic::run(rest),
        ["speaker", rest @ ..] => speaker::run(rest),
        ["agent", rest @ ..] => agent::run(rest),
        ["key", rest @ ..] => agent::key(rest),
        ["send", rest @ ..] => share::send(rest),
        ["ring", rest @ ..] => share::ring(rest),
        ["approve", rest @ ..] => share::approve(rest),
        ["sms", rest @ ..] => share::sms(rest),
        ["phone", rest @ ..] => share::phone(rest),
        ["share", rest @ ..] => share::share(rest),
        ["link"] => share::link(""),
        ["link", phone] => share::link(phone),
        ["input"] => input::run(false),
        ["input", "--check"] => input::run(true),
        ["--version" | "version"] => {
            println!("multiplex {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        [] | ["help" | "--help" | "-h"] => {
            print!("{HELP}");
            Ok(())
        }
        _ => {
            eprint!("{HELP}");
            std::process::exit(2);
        }
    };
    if let Err(err) = result {
        eprintln!("multiplex: {err:#}");
        std::process::exit(1);
    }
}

/// 32 random bytes from the kernel.
fn random32() -> anyhow::Result<[u8; 32]> {
    use std::io::Read;
    let mut bytes = [0u8; 32];
    std::fs::File::open("/dev/urandom")?.read_exact(&mut bytes)?;
    Ok(bytes)
}

/// How `multiplex pair` shows the code and says what became of it.
#[derive(Clone, Copy, PartialEq, Eq)]
enum PairAs {
    /// A QR code in the terminal, and a line that counts down.
    Terminal,
    /// The code alone, without waiting.
    CodeOnly,
    /// For the app: one line of JSON with the code and its QR picture,
    /// then one more when the phone has paired or the code is over.
    Json,
}

/// The QR code's squares, row by row: `1` is dark.
fn qr_rows(qr: &QrCode) -> Vec<String> {
    let width = qr.width();
    qr.to_colors().chunks(width).map(|row| row.iter().map(|c| if *c == qrcode::Color::Dark { '1' } else { '0' }).collect()).collect()
}

/// `multiplex open`: the window (the `multiplex-app` program beside this
/// one, or on the path).
fn open_app(how: &[&str]) -> anyhow::Result<()> {
    use std::os::unix::process::CommandExt;
    let beside = std::env::current_exe().ok().and_then(|exe| exe.parent().map(|dir| dir.join("multiplex-app"))).filter(|app| app.is_file());
    let app = beside.unwrap_or_else(|| "multiplex-app".into());
    // Replaces this command with the app; only returns when that failed.
    // `--pair`, `--phone <name>`, `--send <name>`: the window reads them.
    let err = std::process::Command::new(&app).args(how).exec();
    bail!("the Multiplex window could not be started ({err}); it is the `multiplex-app` program from the same package")
}

fn pair(how: PairAs) -> anyhow::Result<()> {
    let code_only = how == PairAs::CodeOnly;
    let store = Store::open()?;
    let computer = Computer::detect()?;
    if computer.addresses.is_empty() && computer.tailscale.is_none() {
        bail!("this computer has no network address the phone could reach");
    }
    let seed = random32()?;
    let id: String = random32()?[..8].iter().map(|b| format!("{b:02x}")).collect();
    let public = ed25519_dalek::SigningKey::from_bytes(&seed).verifying_key().to_bytes();
    let expires = now_unix() + PAIRING_SECONDS;
    let exe = std::env::current_exe().context("could not find the multiplex command's own path")?;
    store.add_pairing(&id, &public, expires, &format!("{} pair-accept {id}", exe.display()))?;

    let code = PairingCode {
        v: 1,
        id: id.clone(),
        n: computer.name.clone(),
        u: computer.user.clone(),
        p: computer.port,
        a: computer.addresses.clone(),
        t: computer.tailscale.clone(),
        h: computer.host_key.clone(),
        k: STANDARD.encode(seed),
        x: expires,
        m: computer.mac.clone(),
    }
    .encode();
    if code_only {
        println!("{code}");
        return Ok(());
    }

    let qr = QrCode::with_error_correction_level(code.as_bytes(), EcLevel::L).context("the pairing code did not fit a QR code")?;
    if how == PairAs::Json {
        println!("{}", serde_json::json!({ "code": code, "qr": qr_rows(&qr), "computer": computer.name, "expires": expires }));
        std::io::stdout().flush()?;
    }
    let json = how == PairAs::Json;
    let picture = qr.render::<Dense1x2>().dark_color(Dense1x2::Light).light_color(Dense1x2::Dark).quiet_zone(true).build();
    if !json {
        println!("\n  Pair a phone with \x1b[1m{}\x1b[0m\n", computer.name);
        println!("  In Multiplex on the phone: \x1b[1mPair a computer\x1b[0m, then scan this code.\n");
        for line in picture.lines() {
            println!("  {line}");
        }
        let reach = match (&computer.addresses.first(), &computer.tailscale) {
            (Some(a), Some(t)) => format!("on the home network ({a}) or over Tailscale ({t})"),
            (Some(a), None) => format!("on the home network ({a}); the phone must be on the same Wi-Fi"),
            (None, Some(t)) => format!("over Tailscale ({t})"),
            (None, None) => unreachable!("checked above"),
        };
        println!("\n  The phone reaches this computer {reach}.");
        println!("  No camera? Paste this code in the app instead:\n\n  {code}\n");
    }

    // Ctrl+C ends the pairing at once instead of leaving the key to expire.
    let stop = Arc::new(AtomicBool::new(false));
    let flag = stop.clone();
    let _ = ctrlc::set_handler(move || flag.store(true, Ordering::SeqCst));
    loop {
        if let Some(name) = store.take_done(&id) {
            if json {
                println!("{}", serde_json::json!({ "paired": name }));
            } else {
                println!("\r  \x1b[32m✓\x1b[0m Paired with \x1b[1m{name}\x1b[0m.                         \n");
            }
            return Ok(());
        }
        let left = expires.saturating_sub(now_unix());
        if left == 0 || stop.load(Ordering::SeqCst) {
            store.remove_pairing(&id)?;
            if json {
                println!("{}", if left == 0 { serde_json::json!({ "expired": true }) } else { serde_json::json!({ "cancelled": true }) });
            } else {
                println!("\r  {}                              \n", if left == 0 { "The code has expired. Run `multiplex pair` for a new one." } else { "Pairing cancelled." });
            }
            return Ok(());
        }
        if !json {
            print!("\r  Waiting for the phone… the code works for {}:{:02} more. Ctrl+C cancels. ", left / 60, left % 60);
            let _ = std::io::stdout().flush();
        }
        std::thread::sleep(Duration::from_millis(300));
    }
}

/// Runs as the forced command of a one-time key: the phone's request is in
/// SSH_ORIGINAL_COMMAND. Prints one line of JSON either way.
fn accept(id: &str) -> anyhow::Result<()> {
    let request = std::env::var("SSH_ORIGINAL_COMMAND").unwrap_or_default();
    let computer = std::fs::read_to_string("/proc/sys/kernel/hostname").map(|s| s.trim().to_owned()).unwrap_or_default();
    let reply = match Store::open().and_then(|s| s.accept(id, &request)) {
        Ok(device) => {
            notify(&format!("{} is now paired with this computer.", device.name));
            RegisterReply { ok: true, computer, error: String::new(), features: system::features() }
        }
        Err(err) => RegisterReply { ok: false, computer, error: format!("{err:#}"), features: Vec::new() },
    };
    println!("{}", serde_json::to_string(&reply)?);
    if !reply.ok {
        std::process::exit(1);
    }
    Ok(())
}

/// A desktop notification, when a desktop is there to show it.
fn notify(text: &str) {
    let runtime = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| {
        let uid = std::process::Command::new("id").arg("-u").output().map(|o| String::from_utf8_lossy(&o.stdout).trim().to_owned()).unwrap_or_default();
        format!("/run/user/{uid}")
    });
    let mut command = std::process::Command::new("notify-send");
    // Reached over SSH (a phone pairing), there may be no locale, and the
    // phone's name need not be ASCII.
    if !desk::utf8_locale() {
        command.env("LC_ALL", "C.UTF-8");
    }
    let _ = command
        .args(["--app-name=Multiplex", "--icon=phone", "--", "Multiplex", text])
        .env("DBUS_SESSION_BUS_ADDRESS", format!("unix:path={runtime}/bus"))
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();
}

fn devices() -> anyhow::Result<()> {
    let devices = Store::open()?.devices()?;
    if devices.is_empty() {
        println!("No phone is paired. Run `multiplex pair` and scan the code in the app.");
    }
    for d in devices {
        // With what the phone last said about itself, when that is recent.
        let mut line = d.name.clone();
        if share::linked(&d.name) {
            line.push_str("  connected");
        }
        if let Some(seen) = share::seen(&d.name) {
            line.push_str(&format!("  battery {}%{}", seen.battery, if seen.charging { ", charging" } else { "" }));
        }
        println!("{line}");
    }
    Ok(())
}

/// One paired phone, as `multiplex devices --json` prints it.
#[derive(serde::Serialize, Debug, PartialEq)]
struct DeviceState {
    name: String,
    /// The phone is linked right now.
    connected: bool,
    /// What it last said about itself, when that is recent.
    battery: Option<u8>,
    charging: Option<bool>,
}

fn device_state(name: &str, connected: bool, seen: Option<(u8, bool)>) -> DeviceState {
    DeviceState { name: name.to_owned(), connected, battery: seen.map(|(battery, _)| battery), charging: seen.map(|(_, charging)| charging) }
}

/// `multiplex devices --json`: the same as `devices`, for a bar widget or
/// a script to read. Always a list, also when no phone is paired.
fn devices_json() -> anyhow::Result<()> {
    let states: Vec<DeviceState> = Store::open()?.devices()?.iter().map(|d| device_state(&d.name, share::linked(&d.name), share::seen(&d.name).map(|seen| (seen.battery, seen.charging)))).collect();
    println!("{}", serde_json::to_string(&states)?);
    Ok(())
}

fn unpair(name: &str) -> anyhow::Result<()> {
    match Store::open()?.unpair(name)? {
        0 => bail!("no paired phone is called \"{name}\" (see `multiplex devices`)"),
        _ => {
            gate::forget(name);
            println!("{name} can no longer log in. Connections it has open stay until they close.");
        }
    }
    Ok(())
}

fn doctor() -> anyhow::Result<()> {
    Store::open()?.sweep()?;
    let checks = system::doctor();
    for c in &checks {
        let mark = match (c.ok, c.required) {
            (Some(true), _) => "\x1b[32m ok \x1b[0m",
            (Some(false), true) => "\x1b[31mfail\x1b[0m",
            (Some(false), false) => "\x1b[33m off\x1b[0m",
            (None, _) => "\x1b[33m  ? \x1b[0m",
        };
        println!("[{mark}] {:<18} {}", c.name, c.detail);
    }
    if checks.iter().any(|c| c.required && c.ok == Some(false)) {
        bail!("something needed is missing (see above)");
    }
    Ok(())
}

/// `multiplex doctor --json`: the same checks as a list, for the app.
fn doctor_json() -> anyhow::Result<()> {
    println!("{}", serde_json::to_string(&system::doctor())?);
    Ok(())
}

fn setup(dry_run: bool) -> anyhow::Result<()> {
    sudo::as_yourself()?;
    let steps = system::setup_steps();
    println!("multiplex setup prepares this computer for the phone app:\n");
    for (what, command) in &steps {
        println!("  • {what}");
        if dry_run {
            println!("      {}", command.join(" "));
        }
    }
    if dry_run {
        println!("\n{}", sudo::only_a_plan("multiplex setup"));
        return Ok(());
    }
    println!("\nThese need administrator rights; sudo asks for your password.\n");
    for (what, command) in &steps {
        println!("→ {what}");
        let status = std::process::Command::new(&command[0]).args(&command[1..]).status().with_context(|| format!("could not run {}", command[0]))?;
        if !status.success() {
            bail!("\"{what}\" failed; nothing after it was run");
        }
    }
    println!("\nDone. `multiplex doctor` checks the result; `multiplex pair` pairs a phone.");
    if system::on_path("omarchy-shell") {
        println!("`multiplex bar on` puts Multiplex in the Omarchy bar.");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_qr_picture_is_given_as_rows_of_squares() {
        let qr = QrCode::with_error_correction_level(b"multiplex", EcLevel::L).unwrap();
        let rows = qr_rows(&qr);
        assert_eq!(rows.len(), qr.width());
        assert!(rows.iter().all(|row| row.len() == qr.width() && row.chars().all(|c| c == '0' || c == '1')));
        // The corner mark every QR code has: seven dark squares, then a light one.
        assert!(rows[0].starts_with("11111110"), "{}", rows[0]);
        assert_eq!(&rows[1][..8], "10000010");
    }

    #[test]
    fn a_phones_state_reads_the_same_for_a_script_every_time() {
        let linked = serde_json::to_string(&device_state("Sam's phone", true, Some((81, true)))).unwrap();
        assert_eq!(linked, r#"{"name":"Sam's phone","connected":true,"battery":81,"charging":true}"#);
        // Not heard from lately: the fields are there, and say so.
        let away = serde_json::to_string(&device_state("Old phone", false, None)).unwrap();
        assert_eq!(away, r#"{"name":"Old phone","connected":false,"battery":null,"charging":null}"#);
    }
}
