//! `multiplex`: the Omarchy side of Multiplex.
//!
//! - `multiplex pair` shows a QR code; scanning it with the phone app pairs
//!   the phone (see multiplex-proto for how).
//! - `multiplex devices` and `multiplex unpair <name>` list and remove
//!   paired phones.
//! - `multiplex setup` prepares the computer once; `multiplex doctor`
//!   checks it.

mod desk;
mod input;
mod share;
mod store;
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
  multiplex devices           List the paired phones
  multiplex unpair <name>     Remove a paired phone
  multiplex setup [--dry-run] Prepare this computer once (asks for sudo)
  multiplex send <file>…      Send files or folders to the phone (add --to <name> with several phones)
  multiplex ring              Make the phone ring, to find it
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
";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    let result = match args.as_slice() {
        ["pair"] => pair(false),
        ["pair", "--code-only"] => pair(true),
        ["pair-accept", id] => accept(id),
        ["devices"] => devices(),
        ["unpair", name] => unpair(name),
        ["setup"] => setup(false),
        ["setup", "--dry-run"] => setup(true),
        ["doctor"] => doctor(),
        ["desk", rest @ ..] => desk::run(rest),
        ["send", rest @ ..] => share::send(rest),
        ["ring", rest @ ..] => share::ring(rest),
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

fn pair(code_only: bool) -> anyhow::Result<()> {
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
    let picture = qr.render::<Dense1x2>().dark_color(Dense1x2::Light).light_color(Dense1x2::Dark).quiet_zone(true).build();
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

    // Ctrl+C ends the pairing at once instead of leaving the key to expire.
    let stop = Arc::new(AtomicBool::new(false));
    let flag = stop.clone();
    let _ = ctrlc::set_handler(move || flag.store(true, Ordering::SeqCst));
    loop {
        if let Some(name) = store.take_done(&id) {
            println!("\r  \x1b[32m✓\x1b[0m Paired with \x1b[1m{name}\x1b[0m.                         \n");
            return Ok(());
        }
        let left = expires.saturating_sub(now_unix());
        if left == 0 || stop.load(Ordering::SeqCst) {
            store.remove_pairing(&id)?;
            println!("\r  {}                              \n", if left == 0 { "The code has expired. Run `multiplex pair` for a new one." } else { "Pairing cancelled." });
            return Ok(());
        }
        print!("\r  Waiting for the phone… the code works for {}:{:02} more. Ctrl+C cancels. ", left / 60, left % 60);
        let _ = std::io::stdout().flush();
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

fn unpair(name: &str) -> anyhow::Result<()> {
    match Store::open()?.unpair(name)? {
        0 => bail!("no paired phone is called \"{name}\" (see `multiplex devices`)"),
        _ => println!("{name} can no longer log in. Connections it has open stay until they close."),
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

fn setup(dry_run: bool) -> anyhow::Result<()> {
    let steps = system::setup_steps();
    println!("multiplex setup prepares this computer for the phone app:\n");
    for (what, command) in &steps {
        println!("  • {what}");
        if dry_run {
            println!("      {}", command.join(" "));
        }
    }
    if dry_run {
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
    Ok(())
}
