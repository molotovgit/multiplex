//! What the window knows and does, without any Qt in it.
//!
//! The window is a thin layer: everything is done by the `multiplex`
//! command, asked for JSON where there is something to show. This file
//! finds that command, runs it, and turns what it says into the few
//! strings the window binds to.

use std::path::{Path, PathBuf};
use std::process::Command as Process;

/// The accent when Omarchy's theme cannot be read (Omarchy's own apps
/// fall back to the same).
pub const DEFAULT_ACCENT: &str = "#FFD60A";

/// The `multiplex` command, or made-up data for trying the window and
/// for its pictures.
pub struct Command {
    bin: PathBuf,
    demo: bool,
}

/// What the command answered.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Reply {
    pub ok: bool,
    /// Its standard output.
    pub out: String,
    /// One line for the person at the window: the last thing it said.
    pub said: String,
}

impl Command {
    /// `MULTIPLEX_BIN` if set; otherwise the `multiplex` beside this
    /// program, or the one on the path. `MULTIPLEX_APP_DEMO=1` shows
    /// made-up phones and changes nothing.
    pub fn from_env() -> Self {
        let named = std::env::var_os("MULTIPLEX_BIN").map(PathBuf::from);
        let beside = std::env::current_exe().ok().and_then(|exe| exe.parent().map(|dir| dir.join("multiplex"))).filter(|bin| bin.is_file());
        Self { bin: named.or(beside).unwrap_or_else(|| PathBuf::from("multiplex")), demo: std::env::var("MULTIPLEX_APP_DEMO").is_ok_and(|v| v == "1") }
    }

    #[cfg(test)]
    pub fn at(bin: &Path) -> Self {
        Self { bin: bin.to_owned(), demo: false }
    }

    pub fn demo(&self) -> bool {
        self.demo
    }

    pub fn bin(&self) -> &Path {
        &self.bin
    }

    pub fn run(&self, args: &[&str]) -> Reply {
        if self.demo {
            return Reply { ok: true, out: String::new(), said: demo_said(args) };
        }
        match Process::new(&self.bin).args(args).output() {
            Ok(done) => {
                let out = String::from_utf8_lossy(&done.stdout).into_owned();
                let said = if done.status.success() { last_line(&out) } else { sentence(&String::from_utf8_lossy(&done.stderr), "That did not work.") };
                Reply { ok: done.status.success(), out, said }
            }
            Err(_) => Reply { ok: false, out: String::new(), said: "The multiplex command was not found. It comes with the same package as this window.".to_owned() },
        }
    }

    /// Asks for JSON; `otherwise` when the command fails or says something
    /// that is not JSON.
    fn json(&self, args: &[&str], demo: &str, otherwise: &str) -> String {
        if self.demo {
            return demo.to_owned();
        }
        let reply = self.run(args);
        let text = reply.out.trim();
        if reply.ok && serde_json::from_str::<serde_json::Value>(text).is_ok() {
            text.to_owned()
        } else {
            otherwise.to_owned()
        }
    }

    /// The paired phones: `[{name, connected, battery, charging}]`.
    pub fn phones(&self) -> String {
        self.json(&["devices", "--json"], DEMO_PHONES, "[]")
    }

    /// What each phone may do: `{name: {desktop, input, files, clipboard, terminal, tunnels}}`.
    pub fn access(&self) -> String {
        self.json(&["access", "--json"], DEMO_ACCESS, "{}")
    }

    /// What this computer is ready for: `[{name, ok, required, detail}]`.
    pub fn checks(&self) -> String {
        self.json(&["doctor", "--json"], DEMO_CHECKS, "[]")
    }
}

const DEMO_PHONES: &str = r#"[{"name":"Sam's Pixel","connected":true,"battery":81,"charging":true},{"name":"Old tablet","connected":false,"battery":null,"charging":null}]"#;
const DEMO_ACCESS: &str = r#"{"Sam's Pixel":{"desktop":true,"input":true,"files":true,"clipboard":true,"terminal":true,"tunnels":true},"Old tablet":{"desktop":true,"input":false,"files":true,"clipboard":false,"terminal":false,"tunnels":false}}"#;
const DEMO_CHECKS: &str = r#"[{"name":"SSH server","ok":true,"required":true,"detail":"running"},{"name":"Key-only logins","ok":true,"required":true,"detail":"password logins are off"},{"name":"Tailscale","ok":true,"required":false,"detail":"connected as desk"},{"name":"Wake-on-LAN","ok":false,"required":false,"detail":"off: run `multiplex setup`, and allow it in the firmware's settings"},{"name":"Phone screen","ok":true,"required":false,"detail":"showing the phone's screen in a window needs mpv"},{"name":"Firewall","ok":null,"required":false,"detail":"ufw is on; `sudo ufw status` shows whether SSH is open to the home network"}]"#;

/// What the made-up command "says" for each action.
fn demo_said(args: &[&str]) -> String {
    match args.first().copied() {
        Some("ring") => "The phone is ringing.".to_owned(),
        Some("send") => "On its way to the phone.".to_owned(),
        Some("access") => "Changed.".to_owned(),
        Some("unpair") => "It can no longer log in.".to_owned(),
        _ => String::new(),
    }
}

/// The last line that says something.
fn last_line(text: &str) -> String {
    text.lines().rev().map(str::trim).find(|line| !line.is_empty()).unwrap_or_default().to_owned()
}

/// What went wrong, as a sentence: the command's last line, without its
/// own name in front, starting with a capital.
pub fn sentence(stderr: &str, otherwise: &str) -> String {
    let line = last_line(stderr);
    let line = line.strip_prefix("multiplex: ").unwrap_or(&line);
    if line.is_empty() {
        return otherwise.to_owned();
    }
    let mut out = line.to_owned();
    if let Some(first) = out.get_mut(..1) {
        first.make_ascii_uppercase();
    }
    out
}

/// Where Omarchy keeps the theme in use.
pub fn theme_colors_file() -> PathBuf {
    let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
    home.join(".local/state/omarchy/current/theme/colors.toml")
}

/// The theme's accent, from its `colors.toml` (`accent = "#rrggbb"`).
pub fn accent_in(colors: &str) -> Option<String> {
    colors.lines().find_map(|line| {
        let (key, value) = line.split_once('=')?;
        if key.trim() != "accent" {
            return None;
        }
        let value = value.trim().trim_matches(|c| c == '"' || c == '\'');
        (value.len() == 7 && value.starts_with('#') && value[1..].chars().all(|c| c.is_ascii_hexdigit())).then(|| value.to_owned())
    })
}

/// The accent in use now.
pub fn accent() -> String {
    std::fs::read_to_string(theme_colors_file()).ok().and_then(|colors| accent_in(&colors)).unwrap_or_else(|| DEFAULT_ACCENT.to_owned())
}

/// Black or white, whichever reads on this colour (by its luminance).
pub fn ink_on(colour: &str) -> &'static str {
    let part = |at: usize| u8::from_str_radix(colour.get(at..at + 2).unwrap_or("00"), 16).unwrap_or(0);
    let linear = |v: u8| {
        let v = f64::from(v) / 255.0;
        if v <= 0.04045 {
            v / 12.92
        } else {
            ((v + 0.055) / 1.055).powf(2.4)
        }
    };
    let luminance = 0.2126 * linear(part(1)) + 0.7152 * linear(part(3)) + 0.0722 * linear(part(5));
    if luminance > 0.179 {
        "black"
    } else {
        "white"
    }
}

/// Hyprland's window rounding, from `hyprctl -j getoption decoration:rounding`.
pub fn rounding_in(answer: &str) -> Option<i32> {
    let value: serde_json::Value = serde_json::from_str(answer).ok()?;
    i32::try_from(value.get("int")?.as_i64()?).ok().filter(|r| (0..=64).contains(r))
}

/// The corners in use now: sharp without Hyprland, as Omarchy's default.
pub fn rounding() -> i32 {
    if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_none() {
        return 0;
    }
    Process::new("hyprctl").args(["-j", "getoption", "decoration:rounding"]).output().ok().and_then(|out| rounding_in(&String::from_utf8_lossy(&out.stdout))).unwrap_or(0)
}

/// The files in what was dropped on the window or picked: one per line,
/// as a path or a `file://` address.
pub fn files_in(text: &str) -> Vec<PathBuf> {
    text.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .filter_map(|line| match line.strip_prefix("file://") {
            Some(rest) => {
                // After the two slashes comes a host (empty, or this computer), then the path.
                let path = &rest[rest.find('/')?..];
                Some(PathBuf::from(unescaped(path)))
            }
            None if line.starts_with('/') => Some(PathBuf::from(line)),
            None => None,
        })
        .collect()
}

/// `%20` and the like back into the characters they stand for.
fn unescaped(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut at = 0;
    while at < bytes.len() {
        let pair = (bytes[at] == b'%').then(|| text.get(at + 1..at + 3)).flatten().and_then(|hex| u8::from_str_radix(hex, 16).ok());
        match pair {
            Some(byte) => {
                out.push(byte);
                at += 3;
            }
            None => {
                out.push(bytes[at]);
                at += 1;
            }
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// What `multiplex-app --help` prints.
pub const USAGE: &str = "\
multiplex-app: the Multiplex window (also: `multiplex open`)

  multiplex-app                   open the window
  multiplex-app --pair            open it showing a pairing code
  multiplex-app --phone <name>    open it with this phone picked
  multiplex-app --send <name>     open it and choose files to send to this phone
  multiplex-app --version
";

/// What the window does first, from how it was started: a JSON list of
/// the same actions its keys ask for. `--pair`, `--phone <name>` and
/// `--send <name>` come from the command line (the bar widget and
/// `multiplex open` use them); `view` is the comma-separated list the
/// tests give in `MULTIPLEX_APP_VIEW`. An argument that is not known is an
/// error, so a typo does not silently open a plain window.
pub fn first_actions(args: &[String], view: &str) -> Result<String, String> {
    let mut actions: Vec<String> = Vec::new();
    let mut rest = args.iter();
    while let Some(arg) = rest.next() {
        match arg.as_str() {
            "--pair" => actions.push("pair".to_owned()),
            "--phone" | "--send" => {
                let name = rest.next().filter(|name| !name.is_empty()).ok_or_else(|| format!("{arg} needs the phone's name"))?;
                actions.push(format!("phone:{name}"));
                if arg == "--send" {
                    actions.push("send".to_owned());
                }
            }
            other => return Err(format!("`{other}` is not something the window can be started with")),
        }
    }
    actions.extend(view.split(',').filter(|one| !one.is_empty()).map(str::to_owned));
    Ok(serde_json::to_string(&actions).unwrap_or_else(|_| "[]".to_owned()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    /// A stand-in for the `multiplex` command.
    fn fake(script: &str) -> (tempfile::TempDir, Command) {
        let dir = tempfile::tempdir().unwrap();
        let bin = dir.path().join("multiplex");
        std::fs::write(&bin, format!("#!/bin/sh\n{script}\n")).unwrap();
        std::fs::set_permissions(&bin, std::fs::Permissions::from_mode(0o755)).unwrap();
        let command = Command::at(&bin);
        (dir, command)
    }

    #[test]
    fn what_the_command_says_becomes_one_line_for_the_window() {
        let (_dir, ok) = fake("echo; echo 'The phone is asked to ring.'; echo");
        assert_eq!(ok.run(&["ring"]), Reply { ok: true, out: "\nThe phone is asked to ring.\n\n".to_owned(), said: "The phone is asked to ring.".to_owned() });
        let (_dir, failed) = fake("echo 'multiplex: no paired phone is called \"X\"' >&2; exit 1");
        let reply = failed.run(&["ring", "--to", "X"]);
        assert!(!reply.ok);
        assert_eq!(reply.said, "No paired phone is called \"X\"");
        let (_dir, silent) = fake("exit 3");
        assert_eq!(silent.run(&[]).said, "That did not work.");
        let missing = Command::at(Path::new("/nonexistent/multiplex"));
        assert!(missing.run(&["devices"]).said.contains("was not found"));
    }

    #[test]
    fn lists_are_always_something_the_window_can_read() {
        let (_dir, good) = fake(r#"[ "$1 $2" = "devices --json" ] && echo '[{"name":"A","connected":true,"battery":50,"charging":false}]'"#);
        assert_eq!(good.phones(), r#"[{"name":"A","connected":true,"battery":50,"charging":false}]"#);
        // Not JSON, or a failure: an empty list, never something that breaks the window.
        let (_dir, noisy) = fake("echo 'usage: multiplex ...'");
        assert_eq!(noisy.phones(), "[]");
        assert_eq!(noisy.access(), "{}");
        let (_dir, failing) = fake("echo '[]'; exit 1");
        assert_eq!(failing.checks(), "[]");
    }

    #[test]
    fn the_made_up_data_is_what_the_window_expects() {
        let demo = Command { bin: PathBuf::from("/nonexistent"), demo: true };
        let phones: Vec<serde_json::Value> = serde_json::from_str(&demo.phones()).unwrap();
        assert_eq!(phones.len(), 2);
        assert!(phones.iter().all(|p| p["name"].is_string() && p["connected"].is_boolean()));
        let access: serde_json::Value = serde_json::from_str(&demo.access()).unwrap();
        for phone in &phones {
            let switches = &access[phone["name"].as_str().unwrap()];
            for switch in ["desktop", "input", "files", "clipboard", "terminal", "tunnels"] {
                assert!(switches[switch].is_boolean(), "{switch}");
            }
        }
        assert!(serde_json::from_str::<Vec<serde_json::Value>>(&demo.checks()).unwrap().len() >= 4);
        // Nothing is run, and something is said.
        assert_eq!(demo.run(&["ring", "--to", "Sam's Pixel"]).said, "The phone is ringing.");
    }

    #[test]
    fn the_accent_is_read_from_the_theme() {
        assert_eq!(accent_in("background = \"#000000\"\naccent = \"#8d8d8d\"\n"), Some("#8d8d8d".to_owned()));
        assert_eq!(accent_in("  accent   =   '#FFD60A'  "), Some("#FFD60A".to_owned()));
        for wrong in ["", "accent = \"blue\"", "accent = \"#12345\"", "accent_dim = \"#111111\"", "accent = \"#12345g\""] {
            assert_eq!(accent_in(wrong), None, "{wrong}");
        }
    }

    #[test]
    fn text_on_the_accent_stays_readable() {
        assert_eq!(ink_on("#FFD60A"), "black");
        assert_eq!(ink_on("#ffffff"), "black");
        assert_eq!(ink_on("#000000"), "white");
        assert_eq!(ink_on("#1e66f5"), "white");
        assert_eq!(ink_on("nonsense"), "white");
    }

    #[test]
    fn the_corners_follow_hyprland() {
        assert_eq!(rounding_in(r#"{"option":"decoration:rounding","int":8,"set":true}"#), Some(8));
        assert_eq!(rounding_in(r#"{"option":"decoration:rounding","int":0,"set":false}"#), Some(0));
        assert_eq!(rounding_in("no such option"), None);
        assert_eq!(rounding_in(r#"{"int":-3}"#), None);
    }

    #[test]
    fn dropped_files_become_paths() {
        let dropped = "file:///home/sam/My%20notes.txt\n/home/sam/photo.jpg\n\nfile://desk/tmp/a%2Bb.pdf\nhttps://example.com/x\nrelative.txt\n";
        assert_eq!(files_in(dropped), [PathBuf::from("/home/sam/My notes.txt"), PathBuf::from("/home/sam/photo.jpg"), PathBuf::from("/tmp/a+b.pdf")]);
        assert!(files_in("").is_empty());
        // A stray percent sign is left as it is.
        assert_eq!(files_in("file:///tmp/100%.txt"), [PathBuf::from("/tmp/100%.txt")]);
    }

    #[test]
    fn the_command_line_becomes_what_the_window_does_first() {
        let args = |list: &[&str]| list.iter().map(|one| (*one).to_owned()).collect::<Vec<_>>();
        assert_eq!(first_actions(&[], "").unwrap(), "[]");
        assert_eq!(first_actions(&args(&["--pair"]), "").unwrap(), r#"["pair"]"#);
        assert_eq!(first_actions(&args(&["--phone", "Sam's Pixel"]), "").unwrap(), r#"["phone:Sam's Pixel"]"#);
        // A name keeps its commas and quotes: it is one action, not several.
        assert_eq!(first_actions(&args(&["--send", "A, \"B\""]), "").unwrap(), r#"["phone:A, \"B\"","send"]"#);
        // The tests' list comes after, as before.
        assert_eq!(first_actions(&args(&["--pair"]), "close,down").unwrap(), r#"["pair","close","down"]"#);
        assert!(first_actions(&args(&["--send"]), "").unwrap_err().contains("needs the phone's name"));
        assert!(first_actions(&args(&["--phone", ""]), "").is_err());
        assert!(first_actions(&args(&["--pear"]), "").unwrap_err().contains("--pear"));
    }
}
