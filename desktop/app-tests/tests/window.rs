//! Drives the real window, without a screen, against a stand-in for the
//! `multiplex` command, and checks what the window asked of it.
//!
//! The window is told what to do through `MULTIPLEX_APP_VIEW` (the same
//! names its keys use) and takes a picture of itself at the end
//! (`MULTIPLEX_APP_SHOT`), which also makes it run offscreen: nothing is
//! shown on the desktop these tests run on.

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

const PHONES: &str = r#"[{"name":"Sam's Pixel","connected":true,"battery":81,"charging":true},{"name":"Old tablet","connected":false,"battery":null,"charging":null}]"#;
const ACCESS: &str = r#"{"Sam's Pixel":{"desktop":true,"input":true,"files":true,"clipboard":true,"terminal":true,"tunnels":true},"Old tablet":{"desktop":true,"input":false,"files":true,"clipboard":false,"terminal":false,"tunnels":false}}"#;

/// A `multiplex` that answers the lists from fixed text and writes down
/// everything else it is asked.
fn stand_in(dir: &Path, phones: &str, pairing: &str) -> PathBuf {
    let bin = dir.join("multiplex");
    let script = format!(
        "#!/bin/sh\ncase \"$1 $2\" in\n  'devices --json') echo '{}';;\n  'access --json') echo '{}';;\n  'doctor --json') echo '[]';;\n  'pair --json') {};;\n  *) line=''; for word in \"$@\"; do line=\"$line[$word]\"; done; echo \"$line\" >> '{}'; echo 'Done as asked.';;\nesac\n",
        phones.replace('\'', r"'\''"),
        ACCESS.replace('\'', r"'\''"),
        pairing,
        dir.join("asked").display(),
    );
    std::fs::write(&bin, script).unwrap();
    std::fs::set_permissions(&bin, std::fs::Permissions::from_mode(0o755)).unwrap();
    bin
}

/// The built window: `MULTIPLEX_APP_BIN`, or the debug build beside this
/// package.
fn window() -> PathBuf {
    let built = std::env::var_os("MULTIPLEX_APP_BIN").map(PathBuf::from).unwrap_or_else(|| Path::new(env!("CARGO_MANIFEST_DIR")).join("../app/target/debug/multiplex-app"));
    assert!(built.is_file(), "build the window first: cargo build in desktop/app (looked for {})", built.display());
    built
}

/// Runs the window, has it do `first`, and gives back what the stand-in
/// was asked and whether a picture was taken.
fn run(dir: &Path, bin: &Path, first: &str) -> (Vec<String>, bool) {
    let shot = dir.join("window.png");
    let done = Command::new(window())
        .env("MULTIPLEX_BIN", bin)
        .env("MULTIPLEX_APP_VIEW", first)
        .env("MULTIPLEX_APP_SHOT", &shot)
        .env_remove("MULTIPLEX_APP_DEMO")
        .output()
        .expect("the window starts");
    assert!(done.status.success(), "the window ended badly: {}", String::from_utf8_lossy(&done.stderr));
    // The window does each thing on its own thread: the order they reach
    // the command in is not fixed, so they are compared sorted.
    let mut asked: Vec<String> = std::fs::read_to_string(dir.join("asked")).unwrap_or_default().lines().map(str::to_owned).collect();
    asked.sort();
    (asked, std::fs::metadata(&shot).is_ok_and(|picture| picture.len() > 5_000))
}

#[test]
fn the_window_asks_the_command_for_what_its_keys_say() {
    let dir = tempfile::tempdir().unwrap();
    let bin = stand_in(dir.path(), PHONES, "true");
    // Ring the first phone; switch Files off for it; pick the second and
    // switch its Input (off there) on.
    let (asked, pictured) = run(dir.path(), &bin, "ring,switch:3,down,switch:2");
    assert!(pictured);
    assert_eq!(asked, ["[access][Old tablet][input][on]", "[access][Sam's Pixel][files][off]", "[ring][--to][Sam's Pixel]"]);
}

#[test]
fn unpairing_is_asked_about_first() {
    let dir = tempfile::tempdir().unwrap();
    let bin = stand_in(dir.path(), PHONES, "true");
    // Delete alone only opens the question.
    let (asked, _) = run(dir.path(), &bin, "down,unpair");
    assert!(asked.is_empty(), "{asked:?}");
    // Closing it keeps the phone; nothing else happens while it is open.
    let (asked, _) = run(dir.path(), &bin, "down,unpair,ring,close");
    assert!(asked.is_empty(), "{asked:?}");
    // Confirmed: that phone, by name.
    let (asked, _) = run(dir.path(), &bin, "down,unpair,confirm");
    assert_eq!(asked, ["[unpair][Old tablet]"]);
}

#[test]
fn dropped_files_are_sent_to_the_picked_phone() {
    let dir = tempfile::tempdir().unwrap();
    let bin = stand_in(dir.path(), PHONES, "true");
    let (asked, _) = run(dir.path(), &bin, "drop:file:///home/sam/My%20notes.txt");
    assert_eq!(asked, ["[send][--to][Sam's Pixel][/home/sam/My notes.txt]"]);
    // What is not a file on this computer is not handed on.
    let dir = tempfile::tempdir().unwrap();
    let bin = stand_in(dir.path(), PHONES, "true");
    let (asked, _) = run(dir.path(), &bin, "drop:https://example.com/page");
    assert!(asked.is_empty(), "{asked:?}");
}

#[test]
fn with_no_phone_paired_nothing_can_be_asked_but_pairing() {
    let dir = tempfile::tempdir().unwrap();
    let bin = stand_in(dir.path(), "[]", "true");
    let (asked, pictured) = run(dir.path(), &bin, "ring,send,unpair,confirm,switch:1");
    assert!(pictured);
    assert!(asked.is_empty(), "{asked:?}");
}

#[test]
fn pairing_shows_the_code_and_ends_when_the_phone_has_paired() {
    let dir = tempfile::tempdir().unwrap();
    // The code at once, the phone a moment later.
    let pairing = r#"{ echo '{"code":"abc","qr":["101","010","101"],"computer":"desk","expires":4102444800}'; sleep 0.3; echo '{"paired":"New phone"}'; }"#;
    let bin = stand_in(dir.path(), PHONES, pairing);
    let (asked, pictured) = run(dir.path(), &bin, "pair");
    assert!(pictured);
    assert!(asked.is_empty(), "pairing changes nothing else: {asked:?}");
}
