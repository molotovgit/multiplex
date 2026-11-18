//! The files Multiplex keeps on the computer: paired phones in
//! `~/.ssh/authorized_keys`, and pairings in progress under the state
//! directory.
//!
//! `authorized_keys` is the only source of truth for who may log in. Every
//! change rewrites it in one step (write a new file next to it, then
//! rename), keeps every line that is not ours exactly as it was, and never
//! writes anything from a phone except a re-encoded ed25519 key and a
//! name made of plain characters.

use std::fs;
use std::io::Write;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{bail, Context};
use multiplex_proto::{ed25519_key_bytes, ed25519_line, RegisterRequest};
use serde::{Deserialize, Serialize};

/// Comment prefix of a paired phone's key.
const DEVICE: &str = "multiplex:";
/// Comment prefix of a one-time pairing key.
const PAIRING: &str = "multiplex-pairing-";

pub fn now_unix() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// A pairing in progress, kept until it is used or expires.
#[derive(Debug, Serialize, Deserialize)]
pub struct Pending {
    pub id: String,
    pub expires: u64,
}

/// A paired phone.
#[derive(Debug, Clone, PartialEq)]
pub struct Device {
    pub name: String,
    pub key: String,
}

pub struct Store {
    ssh_dir: PathBuf,
    state_dir: PathBuf,
}

impl Store {
    /// The real locations: `~/.ssh` and `$XDG_STATE_HOME/multiplex`.
    pub fn open() -> anyhow::Result<Self> {
        let home = PathBuf::from(std::env::var_os("HOME").context("HOME is not set")?);
        let state = std::env::var_os("XDG_STATE_HOME").map(PathBuf::from).unwrap_or_else(|| home.join(".local/state"));
        Ok(Self::at(home.join(".ssh"), state.join("multiplex")))
    }

    pub fn at(ssh_dir: PathBuf, state_dir: PathBuf) -> Self {
        Self { ssh_dir, state_dir }
    }

    fn keys_file(&self) -> PathBuf {
        self.ssh_dir.join("authorized_keys")
    }

    fn pending_file(&self, id: &str) -> PathBuf {
        self.state_dir.join("pairings").join(format!("{id}.json"))
    }

    fn done_file(&self, id: &str) -> PathBuf {
        self.state_dir.join("pairings").join(format!("{id}.done"))
    }

    fn lines(&self) -> anyhow::Result<Vec<String>> {
        match fs::read_to_string(self.keys_file()) {
            Ok(text) => Ok(text.lines().map(str::to_owned).collect()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Vec::new()),
            Err(e) => Err(e).context("could not read authorized_keys"),
        }
    }

    /// Replaces authorized_keys in one step, readable by the owner only.
    fn write(&self, lines: &[String]) -> anyhow::Result<()> {
        fs::create_dir_all(&self.ssh_dir)?;
        fs::set_permissions(&self.ssh_dir, fs::Permissions::from_mode(0o700))?;
        let tmp = self.ssh_dir.join(format!(".authorized_keys.multiplex.{}", std::process::id()));
        {
            let mut f = fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&tmp)?;
            for line in lines {
                writeln!(f, "{line}")?;
            }
            f.sync_all()?;
        }
        fs::rename(&tmp, self.keys_file()).context("could not replace authorized_keys")?;
        Ok(())
    }

    /// Adds a one-time key that may only run `accept_command`, until
    /// `expires` (sshd refuses it afterwards, and so do we).
    pub fn add_pairing(&self, id: &str, public_key: &[u8; 32], expires: u64, accept_command: &str) -> anyhow::Result<()> {
        if accept_command.contains(['"', '\n', '\\']) {
            bail!("the path of the multiplex command has characters that cannot go into authorized_keys");
        }
        self.sweep()?;
        let mut lines = self.lines()?;
        lines.push(format!(
            "restrict,expiry-time=\"{}\",command=\"{accept_command}\" {} {PAIRING}{id}",
            expiry_time(expires),
            ed25519_line(public_key)
        ));
        self.write(&lines)?;
        let file = self.pending_file(id);
        fs::create_dir_all(file.parent().expect("has a parent"))?;
        fs::write(&file, serde_json::to_vec(&Pending { id: id.to_owned(), expires })?)?;
        Ok(())
    }

    /// Ends a pairing: its one-time key and its state go away.
    pub fn remove_pairing(&self, id: &str) -> anyhow::Result<()> {
        let marker = format!("{PAIRING}{id}");
        let lines = self.lines()?;
        let kept: Vec<String> = lines.iter().filter(|l| !l.trim_end().ends_with(&marker)).cloned().collect();
        if kept.len() != lines.len() {
            self.write(&kept)?;
        }
        let _ = fs::remove_file(self.pending_file(id));
        Ok(())
    }

    /// Removes one-time keys whose pairing expired or lost its state (a
    /// `multiplex pair` that was killed).
    pub fn sweep(&self) -> anyhow::Result<()> {
        let now = now_unix();
        let lines = self.lines()?;
        let kept: Vec<String> = lines
            .iter()
            .filter(|l| match l.rsplit(' ').next().and_then(|c| c.strip_prefix(PAIRING)) {
                Some(id) => self.pending(id).is_some_and(|p| p.expires >= now),
                None => true,
            })
            .cloned()
            .collect();
        if kept.len() != lines.len() {
            self.write(&kept)?;
        }
        Ok(())
    }

    fn pending(&self, id: &str) -> Option<Pending> {
        serde_json::from_slice(&fs::read(self.pending_file(id)).ok()?).ok()
    }

    /// The phone's request arrived through the one-time key `id`: check
    /// everything again, add its key, and end the pairing. A used or
    /// expired pairing is refused.
    pub fn accept(&self, id: &str, command_line: &str) -> anyhow::Result<Device> {
        if !id.chars().all(|c| c.is_ascii_hexdigit()) || id.is_empty() {
            bail!("bad pairing id");
        }
        let pending = self.pending(id).context("this pairing code was already used or has ended")?;
        if now_unix() > pending.expires {
            self.remove_pairing(id)?;
            bail!("this pairing code has expired; show a new one on the computer");
        }
        let request = RegisterRequest::parse(command_line)?;
        let key = ed25519_key_bytes(&request.key).context("not an ed25519 key")?;
        // The same phone pairing again replaces its old entry.
        let marker = format!("{PAIRING}{id}");
        let mut lines: Vec<String> = self
            .lines()?
            .into_iter()
            .filter(|l| !l.trim_end().ends_with(&marker))
            .filter(|l| !(is_device_line(l) && (ed25519_key_bytes(l) == Some(key) || device_name(l) == Some(request.name.as_str()))))
            .collect();
        lines.push(format!("{} {DEVICE}{}", request.key, request.name));
        self.write(&lines)?;
        let _ = fs::remove_file(self.pending_file(id));
        let _ = fs::write(self.done_file(id), &request.name);
        Ok(Device { name: request.name, key: request.key })
    }

    /// The phone that used pairing `id`, once it has (read by the waiting
    /// `multiplex pair`).
    pub fn take_done(&self, id: &str) -> Option<String> {
        let file = self.done_file(id);
        let name = fs::read_to_string(&file).ok()?;
        let _ = fs::remove_file(file);
        Some(name)
    }

    /// The paired phones.
    pub fn devices(&self) -> anyhow::Result<Vec<Device>> {
        Ok(self
            .lines()?
            .iter()
            .filter_map(|l| Some(Device { name: device_name(l)?.to_owned(), key: ed25519_line(&ed25519_key_bytes(key_part(l)?)?) }))
            .collect())
    }

    /// Sets the options a phone's key carries in authorized_keys (what it
    /// may do), or with `None` removes them. Returns whether the phone
    /// is paired.
    pub fn set_options(&self, name: &str, options: Option<&str>) -> anyhow::Result<bool> {
        let mut found = false;
        let lines: Vec<String> = self
            .lines()?
            .into_iter()
            .map(|line| match (device_name(&line) == Some(name), key_part(&line)) {
                (true, Some(key)) => {
                    found = true;
                    match options {
                        Some(options) => format!("{options} {key}"),
                        None => key.to_owned(),
                    }
                }
                _ => line,
            })
            .collect();
        if found {
            self.write(&lines)?;
        }
        Ok(found)
    }

    /// Removes a paired phone by name. Returns how many keys went.
    pub fn unpair(&self, name: &str) -> anyhow::Result<usize> {
        let lines = self.lines()?;
        let kept: Vec<String> = lines.iter().filter(|l| device_name(l) != Some(name)).cloned().collect();
        let removed = lines.len() - kept.len();
        if removed > 0 {
            self.write(&kept)?;
        }
        Ok(removed)
    }
}

fn is_device_line(line: &str) -> bool {
    device_name(line).is_some()
}

/// The phone's name when the line is one of ours: `ssh-ed25519 <key> multiplex:<name>`.
fn device_name(line: &str) -> Option<&str> {
    let comment = key_part(line)?.splitn(3, ' ').nth(2)?;
    comment.strip_prefix(DEVICE).filter(|n| !n.is_empty())
}

/// The key itself (`ssh-ed25519 AAAA… comment`), without the options a
/// line may start with (a phone whose access is limited has some).
fn key_part(line: &str) -> Option<&str> {
    let line = line.trim();
    if line.starts_with("ssh-ed25519 ") {
        return Some(line);
    }
    // Options may hold spaces inside quotes; the key type follows the
    // last unquoted one.
    let mut quoted = false;
    let mut previous = '\0';
    for (at, c) in line.char_indices() {
        match c {
            '"' if previous != '\\' => quoted = !quoted,
            ' ' if !quoted && line[at + 1..].starts_with("ssh-ed25519 ") => return Some(&line[at + 1..]),
            _ => {}
        }
        previous = c;
    }
    None
}

/// `YYYYMMDDHHMMSSZ` (UTC), as sshd's `expiry-time` wants it.
fn expiry_time(unix: u64) -> String {
    let (days, secs) = (unix / 86400, unix % 86400);
    // Civil date from days since 1970-01-01 (Howard Hinnant's algorithm).
    let z = days as i64 + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let (d, m) = (doy - (153 * mp + 2) / 5 + 1, if mp < 10 { mp + 3 } else { mp - 9 });
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}{m:02}{d:02}{:02}{:02}{:02}Z", secs / 3600, secs % 3600 / 60, secs % 60)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> (tempfile::TempDir, Store) {
        let dir = tempfile::tempdir().unwrap();
        let s = Store::at(dir.path().join(".ssh"), dir.path().join("state"));
        (dir, s)
    }

    fn request(key: u8, name: &str) -> String {
        RegisterRequest { key: ed25519_line(&[key; 32]), name: name.into() }.command_line()
    }

    const OTHER: &str = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7 me@laptop";

    #[test]
    fn a_phones_options_come_and_go_and_it_stays_a_phone() {
        let dir = tempfile::tempdir().unwrap();
        let store = Store::at(dir.path().join("ssh"), dir.path().join("state"));
        let key = ed25519_line(&[7u8; 32]);
        store.write(&["ssh-rsa AAAA someone-else".to_owned(), format!("{key} multiplex:Sam's phone")]).unwrap();
        let options = r#"restrict,pty,command="/usr/bin/multiplex gate 'Sam'\''s phone'""#;
        assert!(store.set_options("Sam's phone", Some(options)).unwrap());
        let lines = store.lines().unwrap();
        assert_eq!(lines[0], "ssh-rsa AAAA someone-else");
        assert_eq!(lines[1], format!("{options} {key} multiplex:Sam's phone"));
        // Still listed, still removable, and the key is read through the options.
        assert_eq!(store.devices().unwrap().iter().map(|d| (d.name.as_str(), d.key.as_str())).collect::<Vec<_>>(), [("Sam's phone", key.as_str())]);
        assert!(store.set_options("Sam's phone", None).unwrap());
        assert_eq!(store.lines().unwrap()[1], format!("{key} multiplex:Sam's phone"));
        assert!(!store.set_options("Nobody", Some("restrict")).unwrap());
        store.set_options("Sam's phone", Some(options)).unwrap();
        assert_eq!(store.unpair("Sam's phone").unwrap(), 1);
        assert_eq!(store.lines().unwrap(), ["ssh-rsa AAAA someone-else"]);
    }

    #[test]
    fn expiry_time_is_utc_in_sshd_form() {
        assert_eq!(expiry_time(0), "19700101000000Z");
        assert_eq!(expiry_time(1_763_383_504), "20251117124504Z");
        assert_eq!(expiry_time(951_782_400), "20000229000000Z");
    }

    #[test]
    fn pairing_adds_the_phone_and_ends_the_one_time_key() {
        let (_dir, s) = store();
        s.write(&[OTHER.to_owned()]).unwrap();
        s.add_pairing("abcd1234", &[1; 32], now_unix() + 300, "/usr/bin/multiplex pair-accept abcd1234").unwrap();
        let text = fs::read_to_string(s.keys_file()).unwrap();
        assert!(text.contains("restrict,expiry-time=\""), "{text}");
        assert!(text.contains("command=\"/usr/bin/multiplex pair-accept abcd1234\""));

        let device = s.accept("abcd1234", &request(5, "My phone")).unwrap();
        assert_eq!(device.name, "My phone");
        let lines = s.lines().unwrap();
        assert_eq!(lines.len(), 2, "{lines:?}");
        assert_eq!(lines[0], OTHER, "other keys are untouched");
        assert_eq!(lines[1], format!("{} multiplex:My phone", ed25519_line(&[5; 32])));
        assert_eq!(s.take_done("abcd1234").as_deref(), Some("My phone"));
        assert_eq!(fs::metadata(s.keys_file()).unwrap().permissions().mode() & 0o777, 0o600);
    }

    #[test]
    fn a_code_works_once() {
        let (_dir, s) = store();
        s.add_pairing("abcd1234", &[1; 32], now_unix() + 300, "/usr/bin/multiplex pair-accept abcd1234").unwrap();
        s.accept("abcd1234", &request(5, "phone")).unwrap();
        assert!(s.accept("abcd1234", &request(6, "intruder")).is_err());
        assert_eq!(s.devices().unwrap().len(), 1);
    }

    #[test]
    fn an_expired_code_is_refused_and_swept() {
        let (_dir, s) = store();
        s.add_pairing("abcd1234", &[1; 32], now_unix() - 1, "/usr/bin/multiplex pair-accept abcd1234").unwrap();
        assert!(s.accept("abcd1234", &request(5, "phone")).is_err());
        assert!(s.lines().unwrap().is_empty(), "the one-time key is gone");
        // A killed `multiplex pair` leaves a key without state: the next sweep removes it.
        s.add_pairing("eeee0000", &[2; 32], now_unix() + 300, "/usr/bin/multiplex pair-accept eeee0000").unwrap();
        fs::remove_file(s.pending_file("eeee0000")).unwrap();
        s.sweep().unwrap();
        assert!(s.lines().unwrap().is_empty());
    }

    #[test]
    fn malformed_requests_change_nothing() {
        let (_dir, s) = store();
        s.write(&[OTHER.to_owned()]).unwrap();
        s.add_pairing("abcd1234", &[1; 32], now_unix() + 300, "/usr/bin/multiplex pair-accept abcd1234").unwrap();
        let before = s.lines().unwrap();
        for bad in ["", "ls", "register", "register %%%", &RegisterRequest { key: "ssh-ed25519 AAAA".into(), name: "x".into() }.command_line(), &RegisterRequest { key: ed25519_line(&[5; 32]), name: "a\nssh-ed25519 AAAA evil".into() }.command_line()] {
            assert!(s.accept("abcd1234", bad).is_err(), "accepted {bad:?}");
            assert_eq!(s.lines().unwrap(), before);
        }
        assert!(s.accept("../../etc", &request(5, "phone")).is_err());
    }

    #[test]
    fn pairing_again_replaces_and_unpair_removes() {
        let (_dir, s) = store();
        for (id, key) in [("aaaa1111", 5u8), ("bbbb2222", 6u8)] {
            s.add_pairing(id, &[1; 32], now_unix() + 300, "/usr/bin/multiplex pair-accept x").unwrap();
            s.accept(id, &request(key, "phone")).unwrap();
        }
        let devices = s.devices().unwrap();
        assert_eq!(devices, vec![Device { name: "phone".into(), key: ed25519_line(&[6; 32]) }], "the newer key replaced the older");
        assert_eq!(s.unpair("phone").unwrap(), 1);
        assert_eq!(s.unpair("phone").unwrap(), 0);
        assert!(s.devices().unwrap().is_empty());
    }

    #[test]
    fn the_command_path_cannot_break_out_of_its_quotes() {
        let (_dir, s) = store();
        assert!(s.add_pairing("abcd1234", &[1; 32], now_unix() + 300, "/tmp/x\" ssh-ed25519").is_err());
    }
}
