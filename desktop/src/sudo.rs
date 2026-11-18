//! `sudo` approved with the phone's fingerprint.
//!
//! sudo's login step (PAM) runs `multiplex approve --pam` before it asks
//! for the password. That asks the user's linked phone for a yes, which
//! the phone signs with its own key after a fingerprint. A good answer
//! lets sudo through; anything else (no phone linked, a no, no answer in
//! half a minute) falls through to the password as before.
//!
//! What it rests on:
//!
//! - The phone's key that answers are checked against is a copy in
//!   `/etc/multiplex/sudo-keys`, which only root can change. The copy in
//!   the user's own `authorized_keys` is not used: anything running as
//!   the user could put another key there.
//! - The request is made up here (a fresh random challenge, the words
//!   shown on the phone) and the signature is checked over exactly that.
//!   The request and the answer travel through files in the user's
//!   runtime folder; changing them only makes the check fail.
//! - The command PAM runs must itself be a file only root can change.
//!   `multiplex setup --sudo` installs a root-owned copy when the one in
//!   use is not.
//! - It runs with root's effective rights (so the user's programs cannot
//!   touch it), and takes on the user's for everything it does in the
//!   user's folders.

use std::io::{Read, Write};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, bail, Context, Result};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use multiplex_proto::ed25519_key_bytes;
use multiplex_proto::share::LinkEvent;

use crate::share::{ask_and_wait_for, check_answer, linked};
use crate::store::Device;

/// The phones that may approve sudo, one per line: the user, then the
/// phone's key line as in `authorized_keys`. Root's file.
pub const KEYS: &str = "/etc/multiplex/sudo-keys";

/// Where the root-owned copy of this command goes when the one in use
/// could be changed by the user.
pub const ROOT_COPY: &str = "/usr/local/lib/multiplex/multiplex";

pub const PAM_FILE: &str = "/etc/pam.d/sudo";

/// Marks the line this adds to sudo's PAM file, so it can be found again.
const MARK: &str = "# multiplex: sudo approved on the phone (multiplex setup --sudo-off removes this)";

/// How long the phone has to answer before the password is asked.
const WAIT_SECONDS: u64 = 30;

/// One phone that may approve sudo for one user.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Enrolled {
    user: String,
    phone: String,
    key: [u8; 32],
}

/// The line for one user's phone.
pub fn key_line(user: &str, phone: &Device) -> String {
    format!("{user} {} multiplex:{}", phone.key, phone.name)
}

/// Reads the keys file. Lines that are not understood are passed over.
fn enrolled(text: &str) -> Vec<Enrolled> {
    text.lines()
        .filter_map(|line| {
            let line = line.trim();
            let (user, key_line) = line.split_once(char::is_whitespace)?;
            if user.starts_with('#') {
                return None;
            }
            let key_line = key_line.trim();
            let key = ed25519_key_bytes(key_line)?;
            let phone = key_line.splitn(3, char::is_whitespace).nth(2)?.trim().strip_prefix("multiplex:")?.trim();
            (!phone.is_empty()).then(|| Enrolled { user: user.to_owned(), phone: phone.to_owned(), key })
        })
        .collect()
}

/// Whether a file can only be changed by root.
fn only_roots(owner: u32, mode: u32) -> bool {
    owner == 0 && mode & 0o022 == 0
}

/// The line that has PAM ask the phone first.
fn pam_line(command: &str) -> String {
    format!("auth\t\tsufficient\tpam_exec.so quiet stdout seteuid {command} approve --pam")
}

/// sudo's PAM file without this command's line.
pub fn without_line(pam: &str) -> String {
    let kept: Vec<&str> = pam.lines().filter(|line| *line != MARK && !(line.contains("pam_exec.so") && line.trim_end().ends_with("approve --pam"))).collect();
    kept.join("\n") + "\n"
}

/// sudo's PAM file with this command's line before its first `auth`
/// line, so the phone is asked before the password.
pub fn with_line(pam: &str, command: &str) -> String {
    let clean = without_line(pam);
    let mut out = String::new();
    let mut added = false;
    for line in clean.lines() {
        if !added && line.trim_start().starts_with("auth") {
            out.push_str(MARK);
            out.push('\n');
            out.push_str(&pam_line(command));
            out.push('\n');
            added = true;
        }
        out.push_str(line);
        out.push('\n');
    }
    if !added {
        out.push_str(MARK);
        out.push('\n');
        out.push_str(&pam_line(command));
        out.push('\n');
    }
    out
}

/// The words shown on the phone.
fn reason(host: &str, terminal: Option<&str>) -> String {
    let host = host.trim();
    let on = if host.is_empty() { "this computer".to_owned() } else { host.to_owned() };
    match terminal.map(str::trim).filter(|t| !t.is_empty() && t.len() <= 32 && t.chars().all(|c| c.is_ascii_alphanumeric() || c == '/')) {
        Some(terminal) => format!("Use sudo on {on} ({})", terminal.trim_start_matches("/dev/")),
        None => format!("Use sudo on {on}"),
    }
}

/// A user's numbers and home folder, from the system's list of users.
fn user_entry(passwd: &str, user: &str) -> Option<(u32, u32, PathBuf)> {
    passwd.lines().find_map(|line| {
        let fields: Vec<&str> = line.split(':').collect();
        (fields.len() >= 6 && fields[0] == user).then(|| Some((fields[2].parse().ok()?, fields[3].parse().ok()?, PathBuf::from(fields[5]))))?
    })
}

/// `multiplex approve --pam`: true only when the phone approved.
/// Everything else is false, said nowhere: PAM then asks the password.
pub fn pam(args: &[&str]) -> bool {
    matches!(try_pam(args), Ok(true))
}

fn try_pam(args: &[&str]) -> Result<bool> {
    // SAFETY: a call without arguments that cannot fail.
    let as_root = unsafe { libc::geteuid() } == 0;
    let keys_file = match args {
        [] if as_root => PathBuf::from(KEYS),
        // For trying it without root: the words come from the command
        // line, which for PAM is root's own file.
        ["--test-keys", file] if !as_root => PathBuf::from(file),
        _ => bail!("this is for sudo's PAM file (with seteuid)"),
    };
    if std::env::var("PAM_TYPE").ok().as_deref() != Some("auth") {
        bail!("not asked by PAM to check who it is");
    }
    let user = std::env::var("PAM_USER").ok().filter(|u| !u.is_empty() && u.chars().all(|c| c.is_ascii_alphanumeric() || "_-.".contains(c))).context("no user")?;
    let (uid, gid, home) = user_entry(&std::fs::read_to_string("/etc/passwd")?, &user).context("an unknown user")?;

    let about = std::fs::metadata(&keys_file)?;
    if as_root && !only_roots(about.uid(), about.mode()) {
        bail!("{} can be changed by others than root", keys_file.display());
    }
    let mine: Vec<Enrolled> = enrolled(&std::fs::read_to_string(&keys_file)?).into_iter().filter(|e| e.user == user).collect();
    if mine.is_empty() {
        return Ok(false);
    }
    let mut challenge = [0u8; 32];
    std::fs::File::open("/dev/urandom")?.read_exact(&mut challenge)?;
    let challenge = STANDARD.encode(challenge);
    let host = std::fs::read_to_string("/etc/hostname").unwrap_or_default();
    let reason = reason(&host, std::env::var("PAM_TTY").ok().as_deref());

    // From here on, in the user's folders, as the user.
    std::env::set_var("XDG_RUNTIME_DIR", format!("/run/user/{uid}"));
    std::env::set_var("HOME", &home);
    if as_root {
        // SAFETY: plain calls; their results are checked, and nothing is
        // done as root after this point.
        if unsafe { libc::setegid(gid) } != 0 || unsafe { libc::seteuid(uid) } != 0 {
            bail!("could not act as {user}");
        }
    }
    let Some(phone) = mine.iter().find(|e| linked(&e.phone)) else {
        return Ok(false);
    };
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "Waiting for {} to approve. (The password is asked after {WAIT_SECONDS} seconds without an answer.)", phone.phone);
    let _ = out.flush();
    let (id, answer) = ask_and_wait_for(&phone.phone, WAIT_SECONDS, |id| LinkEvent::Approve { id: id.to_owned(), reason: reason.clone(), challenge: challenge.clone() })?;
    Ok(answer.is_some_and(|answer| check_answer(&phone.key, &id, &reason, &challenge, &answer).is_ok()))
}

/// One argument for a POSIX shell.
fn quoted(arg: &str) -> String {
    format!("'{}'", arg.replace('\'', r"'\''"))
}

/// The command PAM should run: the one in use when only root can change
/// it, otherwise a root-owned copy that the script makes.
pub fn pam_command(exe: &Path, owner: u32, mode: u32) -> (String, bool) {
    let system = ["/usr/bin/", "/usr/local/bin/", "/usr/lib/", "/usr/local/lib/"].iter().any(|dir| exe.starts_with(dir));
    if system && only_roots(owner, mode) {
        (exe.to_string_lossy().into_owned(), false)
    } else {
        (ROOT_COPY.to_owned(), true)
    }
}

/// What `multiplex setup --sudo` runs as root, as one script: everything
/// is put in place, the user tries sudo in another terminal, and unless
/// they say it worked the PAM file is put back as it was. One script,
/// because once the PAM file is changed a second `sudo` might not work.
pub fn on_script(user: &str, phone: &Device, exe: &Path, copy_exe: bool, command: &str, pam_now: &str) -> String {
    let mut lines = vec!["set -e".to_owned(), "umask 022".to_owned(), "install -d -m 755 /etc/multiplex".to_owned()];
    if copy_exe {
        lines.push(format!("install -D -o root -g root -m 755 {} {}", quoted(&exe.to_string_lossy()), quoted(command)));
    }
    // Other users' phones stay; this user's line is replaced.
    lines.push(format!("{{ grep -v {} {KEYS} 2>/dev/null || true; printf '%s\\n' {}; }} > {KEYS}.new", quoted(&format!("^{user} ")), quoted(&key_line(user, phone))));
    lines.push(format!("chown root:root {KEYS}.new && chmod 644 {KEYS}.new && mv {KEYS}.new {KEYS}"));
    lines.push(format!("cp -p {PAM_FILE} {PAM_FILE}.before-multiplex"));
    lines.push(format!("printf '%s' {} > {PAM_FILE}.multiplex-new", quoted(&with_line(pam_now, command))));
    lines.push(format!("chown root:root {PAM_FILE}.multiplex-new && chmod 644 {PAM_FILE}.multiplex-new && mv {PAM_FILE}.multiplex-new {PAM_FILE}"));
    lines.push("echo".to_owned());
    lines.push(format!("echo {}", quoted(&format!("Now try it. In ANOTHER terminal run:   sudo -k; sudo true   and approve on {}.", phone.name))));
    lines.push("echo 'Keep this one open: if sudo does not work there, answering no here puts everything back.'".to_owned());
    lines.push("printf 'Did sudo work in the other terminal? [y/N] '".to_owned());
    lines.push("read answer".to_owned());
    lines.push(format!(
        "case \"$answer\" in y|Y|yes|Yes) echo 'Kept. To undo later: multiplex setup --sudo-off';; *) cp -p {PAM_FILE}.before-multiplex {PAM_FILE}; echo 'Put back as it was.';; esac"
    ));
    lines.join("\n")
}

/// What `multiplex setup --sudo-off` runs as root.
pub fn off_script(user: &str, pam_now: &str) -> String {
    [
        "set -e".to_owned(),
        "umask 022".to_owned(),
        format!("printf '%s' {} > {PAM_FILE}.multiplex-new", quoted(&without_line(pam_now))),
        format!("chown root:root {PAM_FILE}.multiplex-new && chmod 644 {PAM_FILE}.multiplex-new && mv {PAM_FILE}.multiplex-new {PAM_FILE}"),
        format!("if [ -f {KEYS} ]; then {{ grep -v {} {KEYS} || true; }} > {KEYS}.new; mv {KEYS}.new {KEYS}; fi", quoted(&format!("^{user} "))),
        "echo 'sudo asks only for the password again.'".to_owned(),
    ]
    .join("\n")
}

/// `multiplex setup --sudo [<phone>]` and `--sudo-off`, with `--dry-run`.
/// How sudo by the phone stands, for `multiplex doctor`: from sudo's PAM
/// file, the phones named in root's keys file, and whether the command
/// PAM runs is this version (None: there is no separate copy to compare).
pub fn standing(pam: &str, phones: &[String], copy_is_this_version: Option<bool>) -> (bool, String) {
    let on = pam.lines().any(|line| !line.trim_start().starts_with('#') && line.contains("pam_exec.so") && line.trim_end().ends_with("approve --pam"));
    if !on {
        return (false, "off: `multiplex setup --sudo` has sudo ask the phone first (a fingerprint there instead of the password)".to_owned());
    }
    if phones.is_empty() {
        return (false, "on, but no phone of yours is named for it: run `multiplex setup --sudo` again".to_owned());
    }
    if copy_is_this_version == Some(false) {
        return (true, format!("on ({}), with an older copy of this command: run `multiplex setup --sudo` again after an update", phones.join(", ")));
    }
    (true, format!("on: sudo asks {} first, the password when it does not answer", phones.join(", ")))
}

/// The same, read from this computer for the user at the keyboard.
pub fn standing_here() -> Option<(bool, String)> {
    let pam = std::fs::read_to_string(PAM_FILE).ok()?;
    let user = std::env::var("USER").ok()?;
    let phones: Vec<String> = std::fs::read_to_string(KEYS).map(|text| enrolled(&text).into_iter().filter(|e| e.user == user).map(|e| e.phone).collect()).unwrap_or_default();
    let same = match (std::fs::read(ROOT_COPY), std::env::current_exe().and_then(std::fs::read)) {
        (Ok(copy), Ok(this)) if pam.contains(ROOT_COPY) => Some(copy == this),
        _ => None,
    };
    Some(standing(&pam, &phones, same))
}

/// What a dry run ends with: that nothing happened, and the one line that
/// does it. Said because the plan is a page of shell, and the natural next
/// step after reading one is to put `sudo` in front, which is the one
/// thing that does not work (seen with the owner at the keyboard).
pub fn only_a_plan(command: &str) -> String {
    format!("That was only the plan: nothing was changed.\nTo do it, run:   {command}\nas yourself, without sudo in front. It asks for your password itself when it gets there.")
}

/// Refuses to set things up as root: it would be for root, not for the
/// person at the keyboard, and the setup calls sudo itself where it needs
/// to.
pub fn as_yourself() -> Result<()> {
    // SAFETY: a call without arguments that cannot fail.
    refuse_root(unsafe { libc::geteuid() } == 0)
}

fn refuse_root(root: bool) -> Result<()> {
    if root {
        bail!("run this as yourself, without sudo in front: it asks for your password itself when it needs it (as root it would set things up for root, not for you)");
    }
    Ok(())
}

pub fn setup(on: bool, phone: Option<&str>, dry_run: bool) -> Result<()> {
    as_yourself()?;
    let user = std::env::var("USER").ok().filter(|u| !u.is_empty()).context("who is this? ($USER is not set)")?;
    let pam_now = std::fs::read_to_string(PAM_FILE).with_context(|| format!("{PAM_FILE} could not be read"))?;
    let script = if on {
        if !Path::new("/usr/lib/security/pam_exec.so").exists() && !Path::new("/lib/security/pam_exec.so").exists() {
            bail!("PAM's pam_exec.so was not found: it comes with the pam package");
        }
        let devices = crate::store::Store::open()?.devices()?;
        let device = match (phone, devices.as_slice()) {
            (Some(name), all) => all.iter().find(|d| d.name == name).ok_or_else(|| anyhow!("no phone is paired as {name}"))?,
            (None, [one]) => one,
            (None, []) => bail!("no phone is paired yet: multiplex pair"),
            (None, _) => bail!("several phones are paired: multiplex setup --sudo <name>"),
        };
        ed25519_key_bytes(&device.key).with_context(|| format!("{}'s key could not be read", device.name))?;
        let exe = std::env::current_exe()?;
        let about = std::fs::metadata(&exe)?;
        let (command, copy_exe) = pam_command(&exe, about.uid(), about.mode());
        println!("sudo will ask {} first, and the password when it does not answer.", device.name);
        if copy_exe {
            println!("A copy of this command that only root can change goes to {command}: PAM must not run one that your own programs could replace. After updating Multiplex, run this again.");
        }
        on_script(&user, device, &exe, copy_exe, &command, &pam_now)
    } else {
        off_script(&user, &pam_now)
    };
    if dry_run {
        println!("\nThis would run as root:\n\n{script}\n");
        println!("{}", only_a_plan(if on { "multiplex setup --sudo" } else { "multiplex setup --sudo-off" }));
        return Ok(());
    }
    println!("\nsudo now asks for your password, once.\n");
    let done = std::process::Command::new("sudo").args(["sh", "-c", &script]).status().context("sudo could not be run")?;
    if !done.success() {
        bail!("it did not finish; look at {PAM_FILE} and {PAM_FILE}.before-multiplex");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_doctor_is_told_how_sudo_by_the_phone_stands() {
        let plain = "#%PAM-1.0\nauth\t\tinclude\t\tsystem-auth\n";
        let ours = with_line(plain, ROOT_COPY);
        let phones = vec!["Sam's phone".to_owned()];
        let (on, said) = standing(plain, &phones, None);
        assert!(!on && said.starts_with("off") && said.contains("multiplex setup --sudo"), "{said}");
        let (on, said) = standing(&ours, &phones, Some(true));
        assert!(on && said.contains("sudo asks Sam's phone first"), "{said}");
        // The copy PAM runs is from before an update: still on, and said.
        let (on, said) = standing(&ours, &phones, Some(false));
        assert!(on && said.contains("older copy") && said.contains("again"), "{said}");
        // The line is there but nobody is named for this user: not really on.
        let (on, said) = standing(&ours, &[], Some(true));
        assert!(!on && said.contains("no phone"), "{said}");
        // A line that is commented out is off.
        let commented = ours.replace("auth\t\tsufficient\tpam_exec.so", "#auth\t\tsufficient\tpam_exec.so");
        assert!(!standing(&commented, &phones, None).0);
    }

    #[test]
    fn a_plan_says_it_was_one_and_how_to_do_it_without_sudo_in_front() {
        let said = only_a_plan("multiplex setup --sudo");
        assert!(said.contains("nothing was changed"));
        assert!(said.contains("multiplex setup --sudo\n"));
        assert!(said.contains("without sudo in front"));
        // Asked for as root, the setup says the same instead of setting up root.
        assert!(refuse_root(false).is_ok());
        let refused = refuse_root(true).unwrap_err().to_string();
        assert!(refused.contains("without sudo in front") && refused.contains("for root, not for you"), "{refused}");
    }

    /// A key line as the store keeps it: `ssh-ed25519 <base64>`.
    fn key() -> String {
        multiplex_proto::ed25519_line(&[7u8; 32])
    }

    fn phone() -> Device {
        Device { name: "Sam's phone".to_owned(), key: key() }
    }

    #[test]
    fn the_keys_file_names_a_phone_per_user() {
        let key = key();
        let line = key_line("sam", &phone());
        assert_eq!(line, format!("sam {key} multiplex:Sam's phone"));
        let text = format!("# who may approve sudo\n{line}\nalex {key} multiplex:Alex phone\n\nbroken line\nsam ssh-rsa AAAA multiplex:Old\nsam {key} someone-else\nsam {key}\n");
        let all = enrolled(&text);
        assert_eq!(all.iter().map(|e| (e.user.as_str(), e.phone.as_str())).collect::<Vec<_>>(), [("sam", "Sam's phone"), ("alex", "Alex phone")]);
        assert_eq!(all[0].key, [7u8; 32]);
        assert!(enrolled("").is_empty());
    }

    #[test]
    fn only_a_file_that_root_alone_can_change_is_believed() {
        assert!(only_roots(0, 0o100644));
        assert!(only_roots(0, 0o100755));
        assert!(!only_roots(1000, 0o100644), "the user's own file");
        assert!(!only_roots(0, 0o100664), "writable by a group");
        assert!(!only_roots(0, 0o100646), "writable by everyone");
    }

    const ARCH: &str = "#%PAM-1.0\nauth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\n";

    #[test]
    fn the_phone_is_asked_before_the_password_and_the_line_comes_out_again() {
        let with = with_line(ARCH, "/usr/bin/multiplex");
        let lines: Vec<&str> = with.lines().collect();
        assert_eq!(lines[0], "#%PAM-1.0");
        assert_eq!(lines[1], MARK);
        assert_eq!(lines[2], "auth\t\tsufficient\tpam_exec.so quiet stdout seteuid /usr/bin/multiplex approve --pam");
        assert_eq!(lines[3], "auth\t\tinclude\t\tsystem-auth");
        // Sufficient: a no from this line never refuses, it only passes on.
        assert!(lines[2].contains("sufficient") && !lines[2].contains("required"));
        // Doing it twice (after an update, with a new path) leaves one line.
        let again = with_line(&with, ROOT_COPY);
        assert_eq!(again.matches("approve --pam").count(), 1);
        assert!(again.contains(ROOT_COPY));
        // Off: exactly as it was.
        assert_eq!(without_line(&again), ARCH);
        assert_eq!(without_line(ARCH), ARCH);
        // A file with no auth line still gets the line.
        assert!(with_line("#%PAM-1.0\n", "/usr/bin/multiplex").contains("approve --pam"));
    }

    #[test]
    fn the_words_on_the_phone_say_where() {
        assert_eq!(reason("desk\n", Some("/dev/pts/3")), "Use sudo on desk (pts/3)");
        assert_eq!(reason("desk", None), "Use sudo on desk");
        assert_eq!(reason("", Some("")), "Use sudo on this computer");
        // Nothing odd from the environment gets onto the phone's screen.
        assert_eq!(reason("desk", Some("pts/3; approve everything")), "Use sudo on desk");
    }

    #[test]
    fn a_user_is_found_in_the_systems_list() {
        let passwd = "root:x:0:0::/root:/usr/bin/bash\nsam:x:1000:1001:Sam:/home/sam:/usr/bin/bash\n";
        assert_eq!(user_entry(passwd, "sam"), Some((1000, 1001, PathBuf::from("/home/sam"))));
        assert_eq!(user_entry(passwd, "sa"), None);
        assert_eq!(user_entry(passwd, "alex"), None);
    }

    #[test]
    fn pam_only_ever_runs_a_command_root_alone_can_change() {
        // The packaged one, owned by root: used as it is.
        assert_eq!(pam_command(Path::new("/usr/bin/multiplex"), 0, 0o100755), ("/usr/bin/multiplex".to_owned(), false));
        // One in the user's home, or a system one the user could write: a root-owned copy.
        assert_eq!(pam_command(Path::new("/home/sam/.local/bin/multiplex"), 1000, 0o100755), (ROOT_COPY.to_owned(), true));
        assert_eq!(pam_command(Path::new("/usr/bin/multiplex"), 1000, 0o100755), (ROOT_COPY.to_owned(), true));
        assert_eq!(pam_command(Path::new("/home/sam/.local/bin/multiplex"), 0, 0o100755), (ROOT_COPY.to_owned(), true), "root's file, but in a folder the user owns");
    }

    #[test]
    fn the_setup_script_can_put_everything_back() {
        let script = on_script("sam", &phone(), Path::new("/home/sam/.local/bin/multiplex"), true, ROOT_COPY, ARCH);
        assert!(script.starts_with("set -e\n"));
        assert!(script.contains("install -D -o root -g root -m 755 '/home/sam/.local/bin/multiplex' '/usr/local/lib/multiplex/multiplex'"));
        // The phone's name has an apostrophe: it cannot end a quoted word early.
        assert!(script.contains(r"multiplex:Sam'\''s phone'"), "{script}");
        assert!(script.contains("cp -p /etc/pam.d/sudo /etc/pam.d/sudo.before-multiplex"));
        // The question comes after the change, and anything but yes undoes it.
        let asked = script.find("read answer").unwrap();
        assert!(script.find("mv /etc/pam.d/sudo.multiplex-new /etc/pam.d/sudo").unwrap() < asked);
        assert!(script[asked..].contains("*) cp -p /etc/pam.d/sudo.before-multiplex /etc/pam.d/sudo"));
        // With the packaged command nothing is copied.
        assert!(!on_script("sam", &phone(), Path::new("/usr/bin/multiplex"), false, "/usr/bin/multiplex", ARCH).contains("install -D"));
        let off = off_script("sam", &with_line(ARCH, ROOT_COPY));
        assert!(!off.contains("approve --pam"), "{off}");
        assert!(off.contains("grep -v '^sam ' /etc/multiplex/sudo-keys"));
    }
}
