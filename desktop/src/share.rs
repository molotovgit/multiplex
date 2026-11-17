//! Sharing with a paired phone: files it sends land in the inbox (the
//! Downloads folder), text on the clipboard, links in the browser; files
//! for the phone wait in an outbox until it is connected.
//!
//! The phone drives all of it over SSH (see `multiplex_proto::share`).
//! `multiplex send` is the one command here that the computer's user
//! runs.

use std::collections::HashSet;
use std::io::{BufRead, BufReader, ErrorKind, Read, Write};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::mpsc::{self, RecvTimeoutError};
use std::time::{Duration, Instant};

use anyhow::{anyhow, bail, Context, Result};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use multiplex_proto::share::{
    approval_message, clean_file_name, clean_id, clean_phone_number, clean_reason, clean_sms_text, clean_url, Clipboard, LinkEvent, OutFile, PhoneNotice, PhoneStatus, APPROVE_SECONDS, MAX_CLIP,
    RING_SECONDS,
};
use multiplex_proto::ed25519_key_bytes;
use multiplex_proto::clean_device_name;
use serde::{Deserialize, Serialize};

use crate::desk::{lua_string, Session};
use crate::store::Store;

/// A file waiting for a phone.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
struct Waiting {
    id: String,
    /// The phone it is for.
    phone: String,
    name: String,
    path: String,
    size: u64,
    /// An archive made for sending: removed once delivered.
    #[serde(default)]
    made_here: bool,
}

/// Files for the phones, each with a small note beside it. It is also the
/// queue: what is sent while a phone is away waits here.
pub struct Outbox {
    dir: PathBuf,
}

fn state_dir() -> PathBuf {
    std::env::var_os("XDG_STATE_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state"))
        .join("multiplex")
}

fn random_id() -> Result<String> {
    let mut bytes = [0u8; 8];
    std::fs::File::open("/dev/urandom")?.read_exact(&mut bytes)?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}

impl Outbox {
    pub fn open() -> Result<Self> {
        Self::at(state_dir().join("outbox"))
    }

    fn at(dir: PathBuf) -> Result<Self> {
        std::fs::create_dir_all(dir.join("files")).context("could not make the outbox")?;
        Ok(Self { dir })
    }

    fn note(&self, id: &str) -> PathBuf {
        self.dir.join(format!("{id}.json"))
    }

    /// Queues a file or a folder for a phone. A folder goes as one archive.
    fn add(&self, phone: &str, path: &Path) -> Result<Waiting> {
        let path = path.canonicalize().with_context(|| format!("{} is not there", path.display()))?;
        let id = random_id()?;
        let base = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| "folder".to_owned());
        let (name, file, made_here) = if path.is_dir() {
            let name = format!("{}.tar.gz", clean_file_name(&base));
            let archive = self.dir.join("files").join(format!("{id}-{name}"));
            let parent = path.parent().unwrap_or(Path::new("/"));
            let ok = std::process::Command::new("tar").arg("-czf").arg(&archive).arg("-C").arg(parent).arg("--").arg(&base).status().is_ok_and(|s| s.success());
            if !ok {
                let _ = std::fs::remove_file(&archive);
                bail!("could not pack the folder {}", path.display());
            }
            (name, archive, true)
        } else if path.is_file() {
            (clean_file_name(&base), path.clone(), false)
        } else {
            bail!("{} is not a file or a folder", path.display());
        };
        let size = std::fs::metadata(&file)?.len();
        let waiting = Waiting { id: id.clone(), phone: phone.to_owned(), name, path: file.to_string_lossy().into_owned(), size, made_here };
        let temp = self.dir.join(format!(".{id}.tmp"));
        std::fs::write(&temp, serde_json::to_vec(&waiting)?)?;
        std::fs::rename(&temp, self.note(&id))?;
        Ok(waiting)
    }

    /// Everything waiting, oldest first.
    fn all(&self) -> Vec<Waiting> {
        let mut notes: Vec<(std::time::SystemTime, Waiting)> = std::fs::read_dir(&self.dir)
            .into_iter()
            .flatten()
            .flatten()
            .filter(|e| e.path().extension().is_some_and(|x| x == "json"))
            .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, serde_json::from_slice(&std::fs::read(e.path()).ok()?).ok()?)))
            .collect();
        notes.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.id.cmp(&b.1.id)));
        notes.into_iter().map(|(_, w)| w).collect()
    }

    /// What waits for this phone. A file that has gone missing is dropped.
    fn waiting_for(&self, phone: &str) -> Vec<Waiting> {
        self.all()
            .into_iter()
            .filter(|w| w.phone == phone)
            .filter(|w| {
                let there = Path::new(&w.path).is_file();
                if !there {
                    let _ = std::fs::remove_file(self.note(&w.id));
                }
                there
            })
            .collect()
    }

    /// The phone has it: forget it (and the archive made for it).
    fn done(&self, id: &str) -> Result<Waiting> {
        let note = self.note(id);
        let waiting: Waiting = serde_json::from_slice(&std::fs::read(&note).map_err(|_| anyhow!("nothing with that id is waiting"))?)?;
        std::fs::remove_file(&note)?;
        if waiting.made_here && Path::new(&waiting.path).starts_with(self.dir.join("files")) {
            let _ = std::fs::remove_file(&waiting.path);
        }
        Ok(waiting)
    }
}

fn bytes(size: u64) -> String {
    match size {
        s if s >= 1 << 30 => format!("{:.1} GB", s as f64 / (1u64 << 30) as f64),
        s if s >= 1 << 20 => format!("{:.1} MB", s as f64 / (1u64 << 20) as f64),
        s if s >= 1 << 10 => format!("{:.0} KB", s as f64 / 1024.0),
        s => format!("{s} bytes"),
    }
}

/// The paired phone a name means; with nothing said, the only one.
fn phone_named(given: Option<&str>) -> Result<Vec<String>> {
    let paired: Vec<String> = Store::open()?.devices()?.into_iter().map(|d| d.name).collect();
    if paired.is_empty() {
        bail!("no phone is paired: run `multiplex pair` first");
    }
    match given {
        None => Ok(paired),
        Some(name) => match paired.iter().find(|p| p.eq_ignore_ascii_case(name)) {
            Some(found) => Ok(vec![found.clone()]),
            None => bail!("no paired phone is called \"{name}\" (see `multiplex devices`)"),
        },
    }
}

/// The paired phone that is speaking. A phone paired before names were
/// kept says nothing, and is then the only one paired.
fn the_phone(said: &str) -> Result<String> {
    let phones = phone_named(if said.is_empty() { None } else { Some(said) })?;
    match phones.as_slice() {
        [one] => Ok(one.clone()),
        _ => bail!("several phones are paired: this one has to say its name"),
    }
}

/// `multiplex send [--to <phone>] <file or folder>…`, and with nothing to
/// send, what is waiting.
pub fn send(args: &[&str]) -> Result<()> {
    let (to, paths) = match args {
        ["--to", name, rest @ ..] => (Some(*name), rest),
        rest => (None, rest),
    };
    let outbox = Outbox::open()?;
    if paths.is_empty() {
        let all = outbox.all();
        if all.is_empty() {
            println!("Nothing is waiting. Send with: multiplex send <file or folder>");
        }
        for w in all {
            println!("{}  {}  for {}", w.name, bytes(w.size), w.phone);
        }
        return Ok(());
    }
    let phones = phone_named(to)?;
    for path in paths {
        for phone in &phones {
            let w = outbox.add(phone, Path::new(path))?;
            println!("{} ({}) is on its way to {phone}. It arrives as soon as the phone is connected.", w.name, bytes(w.size));
        }
    }
    Ok(())
}

fn notify(session: Option<&Session>, title: &str, body: &str) {
    let mut command = match session {
        Some(session) => session.command("notify-send"),
        None => std::process::Command::new("notify-send"),
    };
    if !crate::desk::utf8_locale() {
        command.env("LC_ALL", "C.UTF-8");
    }
    let _ = command.args(["--app-name=Multiplex", "--icon=phone", "--", title, body]).stdout(Stdio::null()).stderr(Stdio::null()).status();
}

/// The folder files from the phone go to.
fn inbox() -> Result<PathBuf> {
    let home = PathBuf::from(std::env::var_os("HOME").ok_or_else(|| anyhow!("no home folder"))?);
    let asked = std::process::Command::new("xdg-user-dir").arg("DOWNLOAD").output().ok().map(|o| String::from_utf8_lossy(&o.stdout).trim().to_owned());
    // Without a Downloads folder xdg-user-dir answers with the home folder.
    let dir = asked.map(PathBuf::from).filter(|p| p.is_absolute() && *p != home).unwrap_or_else(|| home.join("Downloads"));
    std::fs::create_dir_all(&dir).with_context(|| format!("could not make {}", dir.display()))?;
    Ok(dir)
}

/// Whether what is on the clipboard came from a password manager, which
/// marks it so that it is not kept or passed on.
fn clipboard_is_secret(session: &Session) -> bool {
    session
        .command("wl-paste")
        .arg("--list-types")
        .stderr(Stdio::null())
        .output()
        .is_ok_and(|o| String::from_utf8_lossy(&o.stdout).lines().any(|t| t.contains("x-kde-passwordManagerHint")))
}

/// The clipboard's text, when it holds text that may be passed on.
fn clipboard_text(session: &Session) -> Option<String> {
    if clipboard_is_secret(session) {
        return None;
    }
    let out = session.command("wl-paste").args(["--no-newline", "--type", "text"]).stderr(Stdio::null()).output().ok()?;
    if !out.status.success() || out.stdout.is_empty() || out.stdout.len() > MAX_CLIP {
        return None;
    }
    String::from_utf8(out.stdout).ok()
}

fn set_clipboard(session: &Session, text: &str) -> Result<()> {
    let mut copy = session.command("wl-copy").stdin(Stdio::piped()).stdout(Stdio::null()).stderr(Stdio::null()).spawn().context("wl-copy (from wl-clipboard) is needed for the clipboard")?;
    copy.stdin.take().ok_or_else(|| anyhow!("wl-copy did not take the text"))?.write_all(text.as_bytes())?;
    if !copy.wait()?.success() {
        bail!("the clipboard did not take the text");
    }
    Ok(())
}

/// `multiplex share …`: what the phone asks for.
pub fn share(args: &[&str]) -> Result<()> {
    match args {
        ["inbox"] => println!("{}", inbox()?.display()),
        ["received", phone, names @ ..] if !names.is_empty() => {
            let phone = clean_device_name(phone).unwrap_or_else(|| "the phone".to_owned());
            let names: Vec<String> = names.iter().map(|n| clean_file_name(n)).collect();
            let title = if names.len() == 1 { format!("{} from {phone}", names[0]) } else { format!("{} files from {phone}", names.len()) };
            let mut body = format!("In {}", inbox()?.display());
            if names.len() > 1 {
                let shown = names.iter().take(3).cloned().collect::<Vec<_>>().join(", ");
                body = format!("{shown}{}\n{body}", if names.len() > 3 { format!(" and {} more", names.len() - 3) } else { String::new() });
            }
            notify(Session::find().ok().as_ref(), &title, &body);
        }
        ["clip"] => {
            let mut text = String::new();
            std::io::stdin().lock().take(MAX_CLIP as u64 + 1).read_to_string(&mut text).map_err(|_| anyhow!("the clipboard only takes text"))?;
            if text.len() > MAX_CLIP {
                bail!("that is too much text for a clipboard");
            }
            set_clipboard(&Session::find()?, &text)?;
            println!("ok");
        }
        ["paste"] => println!("{}", serde_json::to_string(&Clipboard { text: clipboard_text(&Session::find()?) })?),
        ["open", url] => {
            let url = clean_url(url).map_err(|err| anyhow!("{err}"))?;
            // Started by Hyprland, so the browser opens in the session.
            Session::find()?.dispatch_either(&format!("hl.dsp.exec_cmd({})", lua_string(&format!("xdg-open '{url}'"))), ("exec", &format!("xdg-open '{url}'")))?;
            println!("ok");
        }
        ["approved", id] => {
            let id = clean_id(id).map_err(|err| anyhow!("{err}"))?;
            let dir = runtime_dir().join("approvals");
            if !dir.join(format!("{id}.pending")).is_file() {
                bail!("nothing with that id is waiting for an answer");
            }
            let mut answer = String::new();
            std::io::stdin().lock().take(512).read_to_string(&mut answer)?;
            // Written beside it, then moved: the one waiting never reads half an answer.
            let temp = dir.join(format!(".{id}.tmp"));
            std::fs::write(&temp, answer.trim())?;
            std::fs::rename(&temp, dir.join(&id))?;
            println!("ok");
        }
        ["done", id] => {
            let waiting = Outbox::open()?.done(&clean_id(id).map_err(|err| anyhow!("{err}"))?)?;
            notify(Session::find().ok().as_ref(), &format!("{} is on {}", waiting.name, waiting.phone), "Delivered.");
            println!("ok");
        }
        _ => bail!("use: multiplex share inbox | received <phone> <name>… | clip | paste | open <url> | done <id>"),
    }
    Ok(())
}

/// Things that only matter while the session runs: which phones are
/// linked, what they last said about themselves, what is asked of them,
/// their answers. Always a folder only this user can reach: an answer to
/// an approval is read from here.
pub(crate) fn runtime_dir() -> PathBuf {
    use std::os::unix::fs::{DirBuilderExt, MetadataExt};
    let base = std::env::var_os("XDG_RUNTIME_DIR").filter(|v| !v.is_empty()).map(PathBuf::from).or_else(|| {
        // Without a session's variables (some SSH setups), the user's own
        // runtime folder is still where systemd keeps it.
        let uid = std::fs::metadata("/proc/self").ok()?.uid();
        Some(PathBuf::from(format!("/run/user/{uid}"))).filter(|p| p.is_dir())
    });
    let dir = base.unwrap_or_else(state_dir).join("multiplex");
    let _ = std::fs::DirBuilder::new().recursive(true).mode(0o700).create(&dir);
    // Also when it was there already, from an older version.
    let _ = std::fs::set_permissions(&dir, std::os::unix::fs::PermissionsExt::from_mode(0o700));
    dir
}

/// A phone's name as a file name.
fn file_name_of(phone: &str) -> String {
    phone.chars().map(|c| if c.is_alphanumeric() || matches!(c, '-' | '_' | '.') { c } else { '_' }).collect()
}

fn unix_now() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// What a phone last said about itself, with when.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct Seen {
    pub battery: u8,
    pub charging: bool,
    /// Unix seconds.
    pub at: u64,
}

/// The phone's last word about itself, if it was recent.
pub fn seen(phone: &str) -> Option<Seen> {
    let seen: Seen = serde_json::from_slice(&std::fs::read(runtime_dir().join("phones").join(format!("{}.json", file_name_of(phone)))).ok()?).ok()?;
    (unix_now().saturating_sub(seen.at) < 15 * 60).then_some(seen)
}

/// Whether a `multiplex link` for this phone is running right now.
pub fn linked(phone: &str) -> bool {
    std::fs::metadata(runtime_dir().join("linked").join(file_name_of(phone)))
        .and_then(|m| m.modified())
        .is_ok_and(|at| at.elapsed().is_ok_and(|age| age < Duration::from_secs(5)))
}

fn read_json<T: serde::de::DeserializeOwned>(most: u64) -> Result<T> {
    let mut text = String::new();
    std::io::stdin().lock().take(most).read_to_string(&mut text)?;
    serde_json::from_str(&text).map_err(|_| anyhow!("that was not understood"))
}

/// `multiplex phone …`: what the phone says about itself.
pub fn phone(args: &[&str]) -> Result<()> {
    match args {
        ["status", phone] => {
            let phone = the_phone(phone)?;
            let status = read_json::<PhoneStatus>(4096)?.cleaned();
            let dir = runtime_dir().join("phones");
            std::fs::create_dir_all(&dir)?;
            let seen = Seen { battery: status.battery, charging: status.charging, at: unix_now() };
            std::fs::write(dir.join(format!("{}.json", file_name_of(&phone))), serde_json::to_vec(&seen)?)?;
            println!("ok");
        }
        ["notify", phone] => {
            let phone = the_phone(phone)?;
            let notice = read_json::<PhoneNotice>(16 * 1024)?.cleaned();
            if notice.title.is_empty() && notice.text.is_empty() {
                bail!("an empty notification");
            }
            let from = if notice.app.is_empty() { phone } else { format!("{} · {phone}", notice.app) };
            let session = Session::find().ok();
            let mut command = match &session {
                Some(session) => session.command("notify-send"),
                None => std::process::Command::new("notify-send"),
            };
            if !crate::desk::utf8_locale() {
                command.env("LC_ALL", "C.UTF-8");
            }
            // "--": the words that follow are never read as options.
            let shown = command.arg(format!("--app-name={from}")).args(["--icon=phone", "--"]).arg(if notice.title.is_empty() { &from } else { &notice.title }).arg(&notice.text).stdout(Stdio::null()).stderr(Stdio::null()).status();
            if !shown.is_ok_and(|s| s.success()) {
                bail!("the notification could not be shown (is libnotify installed?)");
            }
            println!("ok");
        }
        ["call", phone, state @ ("start" | "end")] => {
            the_phone(phone)?;
            let session = Session::find()?;
            // What was paused for the call is written down, to carry on with after it.
            let note = runtime_dir().join("paused-for-a-call.json");
            if *state == "start" {
                let paused = session.pause_playing();
                if !paused.is_empty() {
                    std::fs::create_dir_all(runtime_dir())?;
                    std::fs::write(&note, serde_json::to_vec(&paused)?)?;
                }
                println!("{}", paused.len());
            } else {
                let paused: Vec<String> = std::fs::read(&note).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
                let _ = std::fs::remove_file(&note);
                session.resume(&paused);
                println!("{}", paused.len());
            }
        }
        _ => bail!("use: multiplex phone status <phone> | notify <phone> | call <phone> start|end"),
    }
    Ok(())
}

/// `multiplex ring [--to <phone>]`: the phone rings, wherever it is lying.
pub fn ring(args: &[&str]) -> Result<()> {
    let to = match args {
        [] => None,
        ["--to", name] => Some(*name),
        _ => bail!("use: multiplex ring [--to <phone>]"),
    };
    let mut rang = false;
    for phone in phone_named(to)? {
        if !ask(&phone, &LinkEvent::Ring { seconds: RING_SECONDS })? {
            println!("{phone} is not connected right now, so it cannot be rung.");
            continue;
        }
        println!("Ringing {phone}…");
        rang = true;
    }
    if !rang {
        bail!("no phone could be rung");
    }
    Ok(())
}

/// Hands a connected phone something to do. False when it is not
/// connected (asks are for now, not for later).
fn ask(phone: &str, event: &LinkEvent) -> Result<bool> {
    if !linked(phone) {
        return Ok(false);
    }
    let dir = runtime_dir().join("asks").join(file_name_of(phone));
    std::fs::create_dir_all(&dir)?;
    std::fs::write(dir.join(format!("{}.json", random_id()?)), serde_json::to_vec(event)?)?;
    Ok(true)
}

/// `multiplex sms [--to <phone>] <number> <text…>`: the phone sends a text
/// message, if its owner has allowed this computer to.
pub fn sms(args: &[&str]) -> Result<()> {
    let (to, rest) = match args {
        ["--to", name, rest @ ..] => (Some(*name), rest),
        rest => (None, rest),
    };
    let [number, words @ ..] = rest else { bail!("use: multiplex sms [--to <phone>] <number> <text>") };
    let number = clean_phone_number(number).map_err(|err| anyhow!("{err}"))?;
    let text = clean_sms_text(&words.join(" ")).map_err(|err| anyhow!("{err}"))?;
    let phone = match phone_named(to)?.as_slice() {
        [one] => one.clone(),
        _ => bail!("several phones are paired: say which with --to <name>"),
    };
    if !ask(&phone, &LinkEvent::Sms { to: number.clone(), text })? {
        bail!("{phone} is not connected right now, so it cannot send a message");
    }
    println!("Asked {phone} to send it to {number}. It says here when it has (or why not).");
    Ok(())
}

/// Whether an answer approves this request: a signature over exactly
/// this request, made with the paired phone's own key.
fn check_answer(phone_key: &[u8; 32], id: &str, reason: &str, challenge: &str, answer: &str) -> std::result::Result<(), &'static str> {
    let answer = answer.trim();
    if answer == "no" {
        return Err("it was refused on the phone");
    }
    let signature: [u8; 64] = STANDARD.decode(answer).ok().and_then(|bytes| bytes.try_into().ok()).ok_or("the answer was not understood")?;
    let key = ed25519_dalek::VerifyingKey::from_bytes(phone_key).map_err(|_| "the phone's key could not be read")?;
    key.verify_strict(&approval_message(id, reason, challenge), &ed25519_dalek::Signature::from_bytes(&signature)).map_err(|_| "the answer did not come from the paired phone")
}

/// `multiplex approve [--to <phone>] <what>`: asks the phone's owner to
/// approve something, with a fingerprint there. Succeeds only with an
/// answer signed by the paired phone's key for exactly this request, so
/// nothing running on the computer can say yes in its place.
pub fn approve(args: &[&str]) -> Result<()> {
    let (to, words) = match args {
        ["--to", name, rest @ ..] => (Some(*name), rest),
        rest => (None, rest),
    };
    let reason = clean_reason(&words.join(" ")).map_err(|err| anyhow!("{err}"))?;
    let phone = match phone_named(to)?.as_slice() {
        [one] => one.clone(),
        _ => bail!("several phones are paired: say which with --to <name>"),
    };
    let key = Store::open()?.devices()?.into_iter().find(|d| d.name == phone).and_then(|d| ed25519_key_bytes(&d.key)).ok_or_else(|| anyhow!("{phone}'s key could not be read"))?;
    let mut challenge = [0u8; 32];
    std::fs::File::open("/dev/urandom")?.read_exact(&mut challenge)?;
    let challenge = STANDARD.encode(challenge);
    eprintln!("Waiting for {phone} to approve: {reason}");
    let (id, answer) = ask_and_wait(&phone, |id| LinkEvent::Approve { id: id.to_owned(), reason: reason.clone(), challenge: challenge.clone() })?;
    let Some(answer) = answer else { bail!("not approved: {phone} did not answer in time") };
    match check_answer(&key, &id, &reason, &challenge, &answer) {
        Ok(()) => {
            println!("Approved on {phone}.");
            Ok(())
        }
        Err(why) => bail!("not approved: {why}"),
    }
}

/// Asks a connected phone something that needs an answer, and waits for
/// it. The answer (through `multiplex share approved <id>`) is only taken
/// while the request waits. `None`: no answer in time.
pub(crate) fn ask_and_wait(phone: &str, event: impl FnOnce(&str) -> LinkEvent) -> Result<(String, Option<String>)> {
    let id = random_id()?;
    let dir = runtime_dir().join("approvals");
    std::fs::create_dir_all(&dir)?;
    let (pending, answered) = (dir.join(format!("{id}.pending")), dir.join(&id));
    std::fs::write(&pending, b"")?;
    let finish = || {
        let _ = std::fs::remove_file(&pending);
        let _ = std::fs::remove_file(&answered);
    };
    if !ask(phone, &event(&id))? {
        finish();
        bail!("{phone} is not connected right now");
    }
    let until = Instant::now() + Duration::from_secs(APPROVE_SECONDS);
    while Instant::now() < until {
        if let Ok(answer) = std::fs::read_to_string(&answered) {
            finish();
            return Ok((id, Some(answer)));
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    finish();
    Ok((id, None))
}

/// What has been asked of a phone since the last look; each ask is handed
/// over once.
fn asks_for(phone: &str) -> Vec<LinkEvent> {
    let dir = runtime_dir().join("asks").join(file_name_of(phone));
    let mut files: Vec<PathBuf> = std::fs::read_dir(&dir).into_iter().flatten().flatten().map(|e| e.path()).filter(|p| p.extension().is_some_and(|x| x == "json")).collect();
    files.sort();
    files
        .into_iter()
        .filter_map(|path| {
            let event = serde_json::from_slice(&std::fs::read(&path).ok()?).ok();
            let _ = std::fs::remove_file(&path);
            event
        })
        .collect()
}

/// `multiplex link <phone>`: prints what waits for the phone, now and as
/// it comes, and the clipboard's text when it changes, one line of JSON
/// each, until the phone hangs up.
pub fn link(phone: &str) -> Result<()> {
    let phone = &the_phone(phone)?;
    let outbox = Outbox::open()?;
    // A phone whose access is limited gets only what it may have.
    let allowed = |what: &str| std::env::var(format!("MULTIPLEX_LINK_{what}")).map_or(true, |v| v != "off");
    let (files, clipboard) = (allowed("FILES"), allowed("CLIPBOARD"));
    let session = Session::find().ok().filter(|_| clipboard);

    // The clipboard is watched by wl-paste, which says a word per change.
    let (changes, changed) = mpsc::channel::<()>();
    let mut watcher = session.as_ref().and_then(|s| s.command("wl-paste").args(["--watch", "echo", "changed"]).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().ok());
    if let Some(out) = watcher.as_mut().and_then(|w| w.stdout.take()) {
        std::thread::spawn(move || {
            for line in BufReader::new(out).lines() {
                if line.is_err() || changes.send(()).is_err() {
                    break;
                }
            }
        });
    }

    let run = || -> Result<()> {
        let mut out = std::io::stdout().lock();
        // One line per event; an empty line just shows the link is alive.
        let mut say = |event: Option<&LinkEvent>| -> Result<()> {
            match event {
                Some(event) => writeln!(out, "{}", serde_json::to_string(event)?)?,
                None => writeln!(out)?,
            }
            Ok(out.flush()?)
        };
        let mut told = HashSet::new();
        // While this runs, the phone counts as connected (for `multiplex ring`
        // and `multiplex devices`); asks from before it connected are stale.
        let here = runtime_dir().join("linked");
        std::fs::create_dir_all(&here)?;
        let here = here.join(file_name_of(phone));
        // The newest link for a phone is the one that counts: it writes its
        // process id here, and an older one (the phone reconnected before
        // the old connection was noticed gone) then steps aside instead of
        // taking requests it can no longer deliver.
        let me = std::process::id().to_string();
        std::fs::write(&here, &me)?;
        let _ = asks_for(phone);
        // What is on the clipboard when the phone connects is not news.
        let mut last_clip = session.as_ref().and_then(clipboard_text);
        let mut alive = Instant::now();
        // Coding agents (under herdr): the phone hears when one starts
        // waiting for an answer or finishes. Looked at every few seconds.
        let mut agents: std::collections::HashMap<String, multiplex_proto::agents::AgentStatus> = std::collections::HashMap::new();
        let mut agents_at: Option<Instant> = None;
        loop {
            if std::fs::read_to_string(&here).ok().as_deref() != Some(me.as_str()) {
                return Ok(());
            }
            std::fs::write(&here, &me)?;
            if agents_at.is_none_or(|at| at.elapsed() > Duration::from_secs(3)) {
                let now = crate::agents::list();
                if agents_at.is_some() {
                    for agent in crate::agents::news(&agents, &now) {
                        say(Some(&LinkEvent::Agent(agent)))?;
                        alive = Instant::now();
                    }
                }
                agents = now.into_iter().map(|a| (a.id, a.status)).collect();
                agents_at = Some(Instant::now());
            }
            for ask in asks_for(phone) {
                say(Some(&ask))?;
                alive = Instant::now();
            }
            for w in outbox.waiting_for(phone).into_iter().filter(|_| files) {
                if told.insert(w.id.clone()) {
                    say(Some(&LinkEvent::File(OutFile { id: w.id, name: w.name, size: w.size, path: w.path })))?;
                    alive = Instant::now();
                }
            }
            match changed.recv_timeout(Duration::from_secs(1)) {
                Ok(()) => {
                    // Let a burst of changes settle, then look once.
                    std::thread::sleep(Duration::from_millis(60));
                    while changed.try_recv().is_ok() {}
                    let now = session.as_ref().and_then(clipboard_text);
                    if now != last_clip {
                        if let Some(text) = now.clone() {
                            say(Some(&LinkEvent::Clip { text }))?;
                            alive = Instant::now();
                        }
                        last_clip = now;
                    }
                }
                Err(RecvTimeoutError::Timeout) => {}
                // No clipboard watcher (or it ended): files still go.
                Err(RecvTimeoutError::Disconnected) => std::thread::sleep(Duration::from_secs(1)),
            }
            // So that a phone that left is noticed.
            if alive.elapsed() > Duration::from_secs(10) {
                say(None)?;
                alive = Instant::now();
            }
        }
    };
    let result = run();
    // The marker goes with this link, unless a newer one has taken over.
    let marker = runtime_dir().join("linked").join(file_name_of(phone));
    if std::fs::read_to_string(&marker).ok().as_deref() == Some(std::process::id().to_string().as_str()) {
        let _ = std::fs::remove_file(&marker);
    }
    if let Some(mut watcher) = watcher {
        let _ = watcher.kill();
        let _ = watcher.wait();
    }
    match result {
        // The phone hung up: that is how a link ends.
        Err(err) if err.downcast_ref::<std::io::Error>().is_some_and(|e| e.kind() == ErrorKind::BrokenPipe) => Ok(()),
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_file_waits_for_its_phone_until_it_is_done() {
        let dir = tempfile::tempdir().unwrap();
        let outbox = Outbox::at(dir.path().join("outbox")).unwrap();
        let file = dir.path().join("notes.txt");
        std::fs::write(&file, b"hello").unwrap();
        let w = outbox.add("Phone A", &file).unwrap();
        assert_eq!((w.name.as_str(), w.size, w.made_here), ("notes.txt", 5, false));
        assert_eq!(outbox.waiting_for("Phone A"), vec![w.clone()]);
        assert!(outbox.waiting_for("Phone B").is_empty());
        assert_eq!(outbox.done(&w.id).unwrap(), w);
        assert!(outbox.waiting_for("Phone A").is_empty());
        assert!(file.exists(), "the user's own file is never removed");
        assert!(outbox.done(&w.id).is_err());
    }

    #[test]
    fn a_folder_goes_as_one_archive_which_is_removed_when_delivered() {
        let dir = tempfile::tempdir().unwrap();
        let outbox = Outbox::at(dir.path().join("outbox")).unwrap();
        let folder = dir.path().join("Holiday photos");
        std::fs::create_dir_all(folder.join("day 1")).unwrap();
        std::fs::write(folder.join("day 1/a.jpg"), b"picture").unwrap();
        let w = outbox.add("Phone", &folder).unwrap();
        assert_eq!(w.name, "Holiday photos.tar.gz");
        assert!(w.made_here && w.size > 0);
        let listing = std::process::Command::new("tar").arg("-tzf").arg(&w.path).output().unwrap();
        assert!(String::from_utf8_lossy(&listing.stdout).contains("Holiday photos/day 1/a.jpg"));
        outbox.done(&w.id).unwrap();
        assert!(!Path::new(&w.path).exists());
        assert!(folder.join("day 1/a.jpg").exists());
    }

    #[test]
    fn what_has_gone_missing_stops_waiting() {
        let dir = tempfile::tempdir().unwrap();
        let outbox = Outbox::at(dir.path().join("outbox")).unwrap();
        let file = dir.path().join("gone.txt");
        std::fs::write(&file, b"x").unwrap();
        outbox.add("Phone", &file).unwrap();
        std::fs::remove_file(&file).unwrap();
        assert!(outbox.waiting_for("Phone").is_empty());
        assert!(outbox.all().is_empty());
        assert!(outbox.add("Phone", &file).is_err());
    }

    #[test]
    fn only_the_phones_own_signature_over_this_very_request_approves() {
        use ed25519_dalek::Signer;
        let phone = ed25519_dalek::SigningKey::from_bytes(&[5u8; 32]);
        let key = phone.verifying_key().to_bytes();
        let (id, reason, challenge) = ("00112233aabbccdd", "sudo pacman -Syu", "Y2hhbGxlbmdl");
        let sign = |who: &ed25519_dalek::SigningKey, id: &str, reason: &str, challenge: &str| STANDARD.encode(who.sign(&approval_message(id, reason, challenge)).to_bytes());

        assert_eq!(check_answer(&key, id, reason, challenge, &sign(&phone, id, reason, challenge)), Ok(()));
        assert_eq!(check_answer(&key, id, reason, challenge, &format!("  {}\n", sign(&phone, id, reason, challenge))), Ok(()));
        assert_eq!(check_answer(&key, id, reason, challenge, "no"), Err("it was refused on the phone"));
        // Another key, another reason, another request, an old challenge: all refused.
        let stranger = ed25519_dalek::SigningKey::from_bytes(&[6u8; 32]);
        let forged = Err("the answer did not come from the paired phone");
        assert_eq!(check_answer(&key, id, reason, challenge, &sign(&stranger, id, reason, challenge)), forged);
        assert_eq!(check_answer(&key, id, reason, challenge, &sign(&phone, id, "sudo rm -rf /", challenge)), forged);
        assert_eq!(check_answer(&key, id, reason, challenge, &sign(&phone, "ffffffffffffffff", reason, challenge)), forged);
        assert_eq!(check_answer(&key, id, reason, challenge, &sign(&phone, id, reason, "b2xk")), forged);
        for nonsense in ["", "yes", "true", "AAAA", &STANDARD.encode([0u8; 64])] {
            assert!(check_answer(&key, id, reason, challenge, nonsense).is_err(), "{nonsense}");
        }
    }

    #[test]
    fn a_phones_name_is_a_safe_file_name() {
        assert_eq!(file_name_of("Sam's S21 FE"), "Sam_s_S21_FE");
        assert_eq!(file_name_of("../../etc"), ".._.._etc");
        assert!(!file_name_of("a/b").contains('/'));
    }

    #[test]
    fn sizes_read_naturally() {
        assert_eq!((bytes(12), bytes(2048), bytes(5 << 20), bytes(3 << 30)), ("12 bytes".into(), "2 KB".into(), "5.0 MB".into(), "3.0 GB".into()));
    }
}
