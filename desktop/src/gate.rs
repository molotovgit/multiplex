//! What each paired phone may do on this computer.
//!
//! A phone's key normally logs in like any other key of the user. When
//! something is switched off for a phone (`multiplex access <phone> <what>
//! off`), its line in `authorized_keys` gets `restrict` and a forced
//! command, `multiplex gate <phone>`. sshd then runs the gate instead of
//! whatever the phone asked for; the gate reads what was asked (from
//! `SSH_ORIGINAL_COMMAND`), and either runs it or says no.
//!
//! The gate only lets through what it recognises exactly. Anything else,
//! including anything written for a shell, counts as "terminal".

use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{anyhow, bail, Context, Result};
use serde::{Deserialize, Serialize};

use crate::store::Store;

/// The switches, with what each one covers.
pub const SWITCHES: [(&str, &str); 6] = [
    ("desktop", "see the screen (the remote desktop also needs input)"),
    ("input", "act on the desktop: keys, pointer, workspaces, media"),
    ("files", "browse, send and fetch files"),
    ("clipboard", "share the clipboard, open links"),
    ("terminal", "a shell, and any other command"),
    ("tunnels", "forward ports"),
];

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(default)]
pub struct Access {
    pub desktop: bool,
    pub input: bool,
    pub files: bool,
    pub clipboard: bool,
    pub terminal: bool,
    pub tunnels: bool,
}

impl Default for Access {
    fn default() -> Self {
        Self { desktop: true, input: true, files: true, clipboard: true, terminal: true, tunnels: true }
    }
}

/// One argument for a POSIX shell.
fn shell_quote(arg: &str) -> String {
    format!("'{}'", arg.replace('\'', r"'\''"))
}

fn file_name_of(phone: &str) -> String {
    phone.chars().map(|c| if c.is_alphanumeric() || matches!(c, '-' | '_' | '.') { c } else { '_' }).collect()
}

impl Access {
    fn switch(&mut self, what: &str) -> Option<&mut bool> {
        Some(match what {
            "desktop" => &mut self.desktop,
            "input" => &mut self.input,
            "files" => &mut self.files,
            "clipboard" => &mut self.clipboard,
            "terminal" => &mut self.terminal,
            "tunnels" => &mut self.tunnels,
            _ => return None,
        })
    }

    fn is(&self, what: &str) -> bool {
        let mut copy = *self;
        copy.switch(what).is_some_and(|on| *on)
    }

    /// Nothing is switched off: the key needs no gate.
    pub fn everything(&self) -> bool {
        *self == Self::default()
    }

    fn file(dir: &Path, phone: &str) -> PathBuf {
        dir.join(format!("{}.json", file_name_of(phone)))
    }

    pub fn load(dir: &Path, phone: &str) -> Self {
        std::fs::read(Self::file(dir, phone)).ok().and_then(|bytes| serde_json::from_slice(&bytes).ok()).unwrap_or_default()
    }

    fn save(&self, dir: &Path, phone: &str) -> Result<()> {
        let file = Self::file(dir, phone);
        if self.everything() {
            let _ = std::fs::remove_file(file);
            return Ok(());
        }
        std::fs::create_dir_all(dir)?;
        std::fs::write(file, serde_json::to_vec(self)?).context("could not save the switches")
    }

    /// The options the phone's key carries in authorized_keys, or `None`
    /// when nothing is limited.
    pub fn key_options(&self, exe: &Path, phone: &str) -> Option<String> {
        if self.everything() {
            return None;
        }
        // `restrict` turns everything off; what is allowed is turned back on.
        let mut options = "restrict".to_owned();
        if self.terminal {
            options.push_str(",pty");
        }
        if self.tunnels {
            options.push_str(",port-forwarding");
        }
        // Inside the quotes sshd only reads \" specially.
        let command = format!("{} gate {}", shell_quote(&exe.to_string_lossy()), shell_quote(phone)).replace('"', "\\\"");
        options.push_str(&format!(",command=\"{command}\""));
        Some(options)
    }
}

/// What a phone asked for, as far as the gate can tell.
#[derive(Debug, PartialEq, Eq)]
pub enum Wanted {
    /// A login shell.
    Shell,
    /// File transfer (the sftp subsystem).
    Sftp,
    /// The remote desktop: gliff-server with these arguments.
    Desktop(Vec<String>),
    /// This command with these arguments.
    Multiplex(Vec<String>),
    /// Something for a shell to run.
    Other,
}

/// How the app spells "gliff-server, the fast build if there is one".
const FAST_GLIFF: &str = r#""$( [ -x "$HOME/.local/bin/gliff-server-fast" ] && echo "$HOME/.local/bin/gliff-server-fast" || echo gliff-server )""#;
/// How the app makes sure a hand-installed `multiplex` is found.
const PATH_PREFIX: &str = r#"PATH="$PATH:$HOME/.local/bin" "#;

/// Words made of characters that mean nothing to a shell.
fn plain_words(text: &str) -> Option<Vec<String>> {
    text.split_whitespace()
        .map(|w| w.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | ':' | '=')).then(|| w.to_owned()))
        .collect()
}

/// Splits what the app sends after `multiplex`: words separated by one
/// space, each either plain or in single quotes (with `'\''` for a
/// quote). Anything else is not for the gate to interpret.
fn quoted_words(text: &str) -> Option<Vec<String>> {
    let mut words = Vec::new();
    let mut rest = text;
    loop {
        let mut word = String::new();
        if let Some(mut quoted) = rest.strip_prefix('\'') {
            loop {
                let end = quoted.find('\'')?;
                word.push_str(&quoted[..end]);
                quoted = &quoted[end + 1..];
                // '\'' inside a quoted word is a quote; the word goes on.
                match quoted.strip_prefix(r"\''") {
                    Some(more) => {
                        word.push('\'');
                        quoted = more;
                    }
                    None => break,
                }
            }
            rest = quoted;
        } else {
            let end = rest.find(' ').unwrap_or(rest.len());
            let plain = &rest[..end];
            if plain.is_empty() || !plain.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | ':' | '/' | '+' | '=' | ',' | '@' | '%')) {
                return None;
            }
            word.push_str(plain);
            rest = &rest[end..];
        }
        words.push(word);
        match rest.strip_prefix(' ') {
            Some(more) if !more.is_empty() => rest = more,
            Some(_) => return None,
            None if rest.is_empty() => return Some(words),
            None => return None,
        }
    }
}

pub fn classify(asked: &str) -> Wanted {
    let asked = asked.trim();
    if asked.is_empty() {
        return Wanted::Shell;
    }
    if asked == "internal-sftp" || (asked.ends_with("/sftp-server") && asked.starts_with('/') && !asked.contains(char::is_whitespace)) {
        return Wanted::Sftp;
    }
    for start in [FAST_GLIFF, "gliff-server"] {
        if let Some(rest) = asked.strip_prefix(start) {
            if rest.is_empty() || rest.starts_with(' ') {
                return plain_words(rest).map_or(Wanted::Other, Wanted::Desktop);
            }
        }
    }
    let body = asked.strip_prefix(PATH_PREFIX).unwrap_or(asked);
    if let Some(rest) = body.strip_prefix("multiplex ") {
        if let Some(words) = quoted_words(rest) {
            return Wanted::Multiplex(words);
        }
    }
    Wanted::Other
}

/// Whether the switches allow it; if not, what is missing.
pub fn permits(access: &Access, wanted: &Wanted) -> Result<(), &'static str> {
    let need = |on: bool, what: &'static str| if on { Ok(()) } else { Err(what) };
    match wanted {
        Wanted::Shell | Wanted::Other => need(access.terminal, "terminal"),
        Wanted::Sftp => need(access.files, "files"),
        // gliff cannot show the screen without also taking keys and the pointer.
        Wanted::Desktop(_) => need(access.desktop, "desktop").and(need(access.input, "input")),
        Wanted::Multiplex(words) => match words.iter().map(String::as_str).collect::<Vec<_>>().as_slice() {
            ["desk", "state" | "watch" | "binds"] => need(access.desktop || access.input, "desktop"),
            // Reading which agents run says what the user works on: like seeing the screen.
            ["agents"] => need(access.desktop || access.terminal, "desktop"),
            ["desk", "do", ..] | ["input"] => need(access.input, "input"),
            // The phone showing its own screen here opens a window: part of the desktop.
            ["screen" | "camera" | "mic" | "speaker", ..] => need(access.desktop, "desktop"),
            ["share", "inbox" | "received" | "done", ..] => need(access.files, "files"),
            ["share", "clip" | "paste" | "open" | "read" | "paste-picture" | "clip-picture", ..] => need(access.clipboard, "clipboard"),
            ["link", ..] => need(access.files || access.clipboard, "files"),
            // What the phone says about itself changes nothing here.
            ["phone", "status" | "notify" | "call", ..] => Ok(()),
            // Its answer to an approval asked of it (worthless unless signed with its key).
            ["share", "approved", _] => Ok(()),
            // Everything else this command can do (pairing, these very
            // switches, setup) is the owner's.
            _ => need(access.terminal, "terminal"),
        },
    }
}

fn access_dir() -> PathBuf {
    std::env::var_os("XDG_STATE_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state"))
        .join("multiplex/access")
}

/// `multiplex gate <phone>`: sshd runs this for a phone whose access is
/// limited. Runs what was asked, or refuses.
pub fn gate(phone: &str) -> Result<()> {
    let asked = std::env::var("SSH_ORIGINAL_COMMAND").unwrap_or_default();
    let access = Access::load(&access_dir(), phone);
    let wanted = classify(&asked);
    if let Err(missing) = permits(&access, &wanted) {
        eprintln!("multiplex: this phone may not do that here: \"{missing}\" is switched off for it (`multiplex access` on the computer shows and changes this).");
        std::process::exit(77);
    }
    let shell = std::env::var("SHELL").ok().filter(|s| s.starts_with('/')).unwrap_or_else(|| "/bin/sh".to_owned());
    let failed = match wanted {
        Wanted::Shell => Command::new(&shell).arg("-l").exec(),
        Wanted::Other => Command::new(&shell).arg("-c").arg(&asked).exec(),
        Wanted::Sftp => {
            let server = ["/usr/lib/ssh/sftp-server", "/usr/lib/openssh/sftp-server", "/usr/libexec/openssh/sftp-server", "/usr/libexec/sftp-server"]
                .into_iter()
                .find(|p| Path::new(p).is_file())
                .ok_or_else(|| anyhow!("the file transfer server was not found on this computer"))?;
            Command::new(server).exec()
        }
        Wanted::Desktop(args) => {
            let fast = PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/bin/gliff-server-fast");
            let program = if fast.is_file() { fast } else { PathBuf::from("gliff-server") };
            Command::new(program).args(args).exec()
        }
        Wanted::Multiplex(args) => {
            let mut command = Command::new(std::env::current_exe()?);
            // A link carries files and the clipboard; each only if allowed.
            if args.first().is_some_and(|a| a == "link") {
                if !access.files {
                    command.env("MULTIPLEX_LINK_FILES", "off");
                }
                if !access.clipboard {
                    command.env("MULTIPLEX_LINK_CLIPBOARD", "off");
                }
            }
            command.args(args).exec()
        }
    };
    // exec only returns when it failed.
    Err(failed).context("could not start what was asked for")
}

/// `multiplex access …`: show and change what each phone may do.
pub fn access(args: &[&str]) -> Result<()> {
    let store = Store::open()?;
    let phones: Vec<String> = store.devices()?.into_iter().map(|d| d.name).collect();
    let dir = access_dir();
    let named = |name: &str| -> Result<String> {
        phones.iter().find(|p| p.eq_ignore_ascii_case(name)).cloned().ok_or_else(|| anyhow!("no paired phone is called \"{name}\" (see `multiplex devices`)"))
    };
    let summary = |access: &Access| -> String {
        let off: Vec<&str> = SWITCHES.iter().map(|(name, _)| *name).filter(|name| !access.is(name)).collect();
        if off.is_empty() {
            "everything".to_owned()
        } else {
            format!("everything except {}", off.join(", "))
        }
    };
    // Sets one switch (or, with `None`, all of them back on).
    let change = |phone: &str, switch: Option<(&str, bool)>| -> Result<()> {
        let mut access = Access::load(&dir, phone);
        match switch {
            None => access = Access::default(),
            Some((what, on)) => {
                *access.switch(what).ok_or_else(|| anyhow!("there is no switch called \"{what}\": they are {}", SWITCHES.map(|(n, _)| n).join(", ")))? = on;
            }
        }
        // The key's options first: if that fails, nothing has changed.
        let exe = std::env::current_exe().context("could not find the multiplex command's own path")?;
        store.set_options(phone, access.key_options(&exe, phone).as_deref())?;
        access.save(&dir, phone)?;
        println!("{phone} may now do {}.", summary(&access));
        println!("Connections it has open keep what they had until they close.");
        Ok(())
    };
    match args {
        [] => {
            if phones.is_empty() {
                println!("No phone is paired.");
            }
            for phone in &phones {
                println!("{phone}: {}", summary(&Access::load(&dir, phone)));
            }
        }
        [phone] => {
            let phone = named(phone)?;
            let access = Access::load(&dir, &phone);
            println!("{phone} may:");
            for (name, what) in SWITCHES {
                println!("  {:<10} {:<4} {what}", name, if access.is(name) { "on" } else { "off" });
            }
            println!("Change one with: multiplex access {} <what> on|off", shell_quote(&phone));
        }
        [phone, "everything"] => change(&named(phone)?, None)?,
        [phone, what, state @ ("on" | "off")] => change(&named(phone)?, Some((what, *state == "on")))?,
        _ => bail!("use: multiplex access [<phone> [<what> on|off | everything]]"),
    }
    Ok(())
}

/// A phone was unpaired: its switches go with it.
pub fn forget(phone: &str) {
    let _ = std::fs::remove_file(Access::file(&access_dir(), phone));
}

#[cfg(test)]
mod tests {
    use super::*;

    fn words(list: &[&str]) -> Vec<String> {
        list.iter().map(|w| (*w).to_owned()).collect()
    }

    #[test]
    fn what_the_app_sends_is_recognised_exactly() {
        assert_eq!(classify(""), Wanted::Shell);
        assert_eq!(classify("/usr/lib/ssh/sftp-server"), Wanted::Sftp);
        assert_eq!(classify("internal-sftp"), Wanted::Sftp);
        assert_eq!(classify(r#"PATH="$PATH:$HOME/.local/bin" multiplex desk state"#), Wanted::Multiplex(words(&["desk", "state"])));
        assert_eq!(
            classify(r#"PATH="$PATH:$HOME/.local/bin" multiplex desk do 'bind' 'SUPER + '\'''"#),
            Wanted::Multiplex(words(&["desk", "do", "bind", "SUPER + '"]))
        );
        assert_eq!(classify(r#"PATH="$PATH:$HOME/.local/bin" multiplex 'link' 'Sam'\''s phone'"#), Wanted::Multiplex(words(&["link", "Sam's phone"])));
        assert_eq!(classify(&format!("{FAST_GLIFF} --stdio --output DP-1 --low-bandwidth")), Wanted::Desktop(words(&["--stdio", "--output", "DP-1", "--low-bandwidth"])));
        assert_eq!(classify("gliff-server --stdio --headless"), Wanted::Desktop(words(&["--stdio", "--headless"])));
    }

    #[test]
    fn space_around_what_was_asked_changes_nothing() {
        assert_eq!(classify("  multiplex desk state \n"), Wanted::Multiplex(words(&["desk", "state"])));
    }

    #[test]
    fn anything_a_shell_would_read_into_is_not_let_through_as_something_else() {
        for sly in [
            "multiplex desk state; rm -rf ~",
            "multiplex desk state && id",
            "multiplex desk do 'x' $(id)",
            "multiplex desk state | sh",
            "multiplex  desk state",
            "multiplex desk state  x",
            "multiplex desk 'state",
            "multiplex desk state\nid",
            "gliff-server --stdio; id",
            "gliff-server --stdio $(id)",
            "gliff-serverx --stdio",
            "/usr/lib/ssh/sftp-server; id",
            "sftp-server",
            "/tmp/x/sftp-server -x",
            "echo hi",
            "sh -c 'multiplex desk state'",
        ] {
            assert_eq!(classify(sly), Wanted::Other, "{sly}");
        }
    }

    #[test]
    fn the_switches_decide() {
        let all = Access::default();
        let multiplex = |list: &[&str]| Wanted::Multiplex(words(list));
        assert!(permits(&all, &Wanted::Other).is_ok() && permits(&all, &Wanted::Desktop(vec![])).is_ok());

        let no_terminal = Access { terminal: false, ..all };
        assert_eq!(permits(&no_terminal, &Wanted::Shell), Err("terminal"));
        assert_eq!(permits(&no_terminal, &Wanted::Other), Err("terminal"));
        assert!(permits(&no_terminal, &Wanted::Sftp).is_ok());
        assert!(permits(&no_terminal, &multiplex(&["desk", "do", "close"])).is_ok());
        // A limited phone cannot lift its own limits, pair others, or run setup.
        for owners in [&["access", "Phone", "terminal", "on"][..], &["pair"], &["unpair", "Phone"], &["setup"], &["gate", "Other phone"], &["send", "/etc/passwd"]] {
            assert_eq!(permits(&no_terminal, &multiplex(owners)), Err("terminal"), "{owners:?}");
        }

        let no_input = Access { input: false, terminal: false, ..all };
        assert_eq!(permits(&no_input, &multiplex(&["desk", "do", "close"])), Err("input"));
        assert_eq!(permits(&no_input, &multiplex(&["input"])), Err("input"));
        assert_eq!(permits(&no_input, &Wanted::Desktop(vec![])), Err("input"), "gliff would control too");
        assert!(permits(&no_input, &multiplex(&["desk", "watch"])).is_ok(), "looking is still allowed");

        // The phone's own screen in a window here: that opens a window.
        let no_desktop = Access { desktop: false, terminal: false, ..all };
        assert_eq!(permits(&no_desktop, &multiplex(&["screen", "Phone"])), Err("desktop"));
        assert!(permits(&no_terminal, &multiplex(&["screen", "Phone"])).is_ok());
        assert_eq!(permits(&no_desktop, &multiplex(&["camera", "--turn", "90", "Phone"])), Err("desktop"));
        assert!(permits(&no_terminal, &multiplex(&["camera", "Phone"])).is_ok());
        assert_eq!(permits(&no_desktop, &multiplex(&["mic", "Phone"])), Err("desktop"));
        assert!(permits(&no_terminal, &multiplex(&["mic"])).is_ok());
        // Hearing what the computer plays is a kind of seeing its desktop.
        assert_eq!(permits(&no_desktop, &multiplex(&["speaker", "--default", "Phone"])), Err("desktop"));
        assert!(permits(&no_terminal, &multiplex(&["speaker"])).is_ok());

        let no_files = Access { files: false, terminal: false, ..all };
        assert_eq!(permits(&no_files, &Wanted::Sftp), Err("files"));
        assert_eq!(permits(&no_files, &multiplex(&["share", "inbox"])), Err("files"));
        assert!(permits(&no_files, &multiplex(&["share", "clip"])).is_ok());
        assert!(permits(&no_files, &multiplex(&["link", "Phone"])).is_ok(), "the clipboard still travels");
        assert!(permits(&no_files, &multiplex(&["phone", "status", "Phone"])).is_ok());
    }

    #[test]
    fn the_keys_options_follow_the_switches() {
        let exe = Path::new("/usr/bin/multiplex");
        assert_eq!(Access::default().key_options(exe, "Phone"), None);
        let limited = Access { terminal: false, tunnels: false, ..Access::default() };
        assert_eq!(limited.key_options(exe, "Sam's phone").unwrap(), r#"restrict,command="'/usr/bin/multiplex' gate 'Sam'\''s phone'""#);
        let files_off = Access { files: false, ..Access::default() };
        assert_eq!(files_off.key_options(exe, "Phone").unwrap(), r#"restrict,pty,port-forwarding,command="'/usr/bin/multiplex' gate 'Phone'""#);
    }

    #[test]
    fn switches_are_kept_per_phone_and_go_when_everything_is_on_again() {
        let dir = tempfile::tempdir().unwrap();
        let mut access = Access::load(dir.path(), "Sam's phone");
        assert!(access.everything());
        *access.switch("files").unwrap() = false;
        access.save(dir.path(), "Sam's phone").unwrap();
        assert!(!Access::load(dir.path(), "Sam's phone").files);
        assert!(Access::load(dir.path(), "Another").everything());
        assert!(access.switch("everything-else").is_none());
        Access::default().save(dir.path(), "Sam's phone").unwrap();
        assert!(std::fs::read_dir(dir.path()).unwrap().next().is_none());
    }
}
