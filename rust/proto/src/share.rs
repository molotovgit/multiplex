//! Sharing between the phone and the computer: files, the clipboard,
//! links. As with everything else, the phone runs `multiplex …` on the
//! computer over SSH; nothing listens on the network.
//!
//! From the phone: files go up by SFTP into the computer's inbox (its
//! Downloads folder), text goes to its clipboard, a link opens in its
//! browser.
//!
//! From the computer: `multiplex send <file>` puts the file in an outbox.
//! The phone, while connected, runs `multiplex link`, which prints one
//! line of JSON per waiting file (and per clipboard change); it fetches
//! the file by SFTP and says `multiplex share done <id>`. An outbox is
//! also the queue: what is sent while the phone is away waits in it.

use serde::{Deserialize, Serialize};

use crate::ProtoError;

/// How the phone starts the computer's side.
pub const SHARE_COMMAND: &str = r#"PATH="$PATH:$HOME/.local/bin" multiplex"#;

/// A clipboard's worth of text, not a file.
pub const MAX_CLIP: usize = 256 * 1024;

/// A file waiting on the computer for the phone.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct OutFile {
    /// Sixteen hex digits.
    pub id: String,
    /// What the phone should call it.
    pub name: String,
    pub size: u64,
    /// Where it is on the computer, for SFTP.
    pub path: String,
}

/// One line `multiplex link` prints.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum LinkEvent {
    /// A file is waiting.
    File(OutFile),
    /// The computer's clipboard now holds this text.
    Clip { text: String },
    /// Someone at the computer is looking for the phone: ring, loudly, for
    /// at most this long.
    Ring { seconds: u32 },
}

/// What `multiplex share paste` prints.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct Clipboard {
    /// None: the clipboard is empty, or holds something that is not text.
    pub text: Option<String>,
}

pub fn parse_link_event(line: &str) -> Result<LinkEvent, ProtoError> {
    serde_json::from_str(line.trim()).map_err(|_| ProtoError::Damaged)
}

/// An outbox id as `multiplex send` makes them.
pub fn clean_id(id: &str) -> Result<String, ProtoError> {
    if id.len() == 16 && id.bytes().all(|b| b.is_ascii_hexdigit()) {
        Ok(id.to_ascii_lowercase())
    } else {
        Err(ProtoError::Invalid("this is not a file's id"))
    }
}

/// A web link, and nothing a shell or a browser could read as more.
pub fn clean_url(url: &str) -> Result<String, ProtoError> {
    let url = url.trim();
    let web = url.starts_with("https://") || url.starts_with("http://");
    let plain = url.chars().all(|c| !c.is_control() && !c.is_whitespace() && !matches!(c, '\'' | '"' | '`' | '\\' | '<' | '>'));
    if web && plain && url.len() <= 2048 && url.split("://").nth(1).is_some_and(|rest| !rest.is_empty()) {
        Ok(url.to_owned())
    } else {
        Err(ProtoError::Invalid("only web links (http or https) can be opened"))
    }
}

/// A file name the other side can safely create: no folders, no dots-only
/// names, nothing hidden, no control characters.
pub fn clean_file_name(name: &str) -> String {
    let last = name.rsplit(['/', '\\']).next().unwrap_or_default();
    let tidy: String = last.chars().filter(|c| !c.is_control()).collect();
    let tidy = tidy.trim().trim_start_matches('.').trim();
    if tidy.is_empty() {
        "file".to_owned()
    } else {
        tidy.chars().take(200).collect()
    }
}

/// One argument for a POSIX shell.
fn quoted(arg: &str) -> String {
    format!("'{}'", arg.replace('\'', r"'\''"))
}

fn command(words: &[&str]) -> String {
    let mut line = SHARE_COMMAND.to_owned();
    for word in words {
        line.push(' ');
        line.push_str(&quoted(word));
    }
    line
}

/// Prints the folder files from the phone go to.
pub fn inbox_command() -> String {
    command(&["share", "inbox"])
}

/// Tells the computer what arrived, so it can say so on screen.
pub fn received_command(phone: &str, names: &[String]) -> String {
    let mut words = vec!["share", "received", phone];
    words.extend(names.iter().map(String::as_str));
    command(&words)
}

/// Reads text from standard input onto the computer's clipboard.
pub fn copy_command() -> String {
    command(&["share", "clip"])
}

/// Prints the computer's clipboard as [`Clipboard`].
pub fn paste_command() -> String {
    command(&["share", "paste"])
}

pub fn open_command(url: &str) -> Result<String, ProtoError> {
    Ok(command(&["share", "open", &clean_url(url)?]))
}

/// Prints what waits for this phone, now and as it comes.
pub fn link_command(phone: &str) -> String {
    command(&["link", phone])
}

/// How long a phone rings at most when the computer looks for it.
pub const RING_SECONDS: u32 = 30;

/// What the phone tells the computer about itself now and then.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct PhoneStatus {
    /// 0 to 100.
    pub battery: u8,
    pub charging: bool,
}

/// A notification from the phone, for the computer's screen.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct PhoneNotice {
    /// The app it is from, as the phone names it ("Messages").
    pub app: String,
    pub title: String,
    pub text: String,
}

/// One line of ordinary characters, cut to a length.
fn one_line(text: &str, most: usize) -> String {
    let flat: String = text.chars().map(|c| if c.is_control() { ' ' } else { c }).collect();
    flat.split_whitespace().collect::<Vec<_>>().join(" ").chars().take(most).collect()
}

impl PhoneNotice {
    /// The notice as it may be shown: single lines, sensible lengths.
    pub fn cleaned(&self) -> Self {
        Self { app: one_line(&self.app, 60), title: one_line(&self.title, 120), text: one_line(&self.text, 500) }
    }
}

impl PhoneStatus {
    pub fn cleaned(&self) -> Self {
        Self { battery: self.battery.min(100), charging: self.charging }
    }
}

/// Reads the phone's status from standard input.
pub fn status_command(phone: &str) -> String {
    command(&["phone", "status", phone])
}

/// Reads a notification from standard input and shows it.
pub fn notice_command(phone: &str) -> String {
    command(&["phone", "notify", phone])
}

pub fn done_command(id: &str) -> Result<String, ProtoError> {
    Ok(command(&["share", "done", &clean_id(id)?]))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn link_lines_read_back() {
        let file = LinkEvent::File(OutFile { id: "00112233aabbccdd".into(), name: "notes.pdf".into(), size: 12, path: "/home/me/notes.pdf".into() });
        let line = serde_json::to_string(&file).unwrap();
        assert!(line.starts_with(r#"{"file":{"#), "{line}");
        assert_eq!(parse_link_event(&line).unwrap(), file);
        let clip = LinkEvent::Clip { text: "héllo\n".into() };
        assert_eq!(parse_link_event(&serde_json::to_string(&clip).unwrap()).unwrap(), clip);
        assert!(parse_link_event("").is_err() && parse_link_event("{\"other\":1}").is_err());
    }

    #[test]
    fn a_ring_and_the_phones_news_read_back_and_are_tidied() {
        let ring = LinkEvent::Ring { seconds: RING_SECONDS };
        assert_eq!(serde_json::to_string(&ring).unwrap(), r#"{"ring":{"seconds":30}}"#);
        assert_eq!(parse_link_event(r#"{"ring":{"seconds":30}}"#).unwrap(), ring);
        let notice = PhoneNotice { app: "Messages\n".into(), title: "  Sam \t Lee ".into(), text: "x".repeat(900) }.cleaned();
        assert_eq!((notice.app.as_str(), notice.title.as_str(), notice.text.chars().count()), ("Messages", "Sam Lee", 500));
        assert_eq!(PhoneStatus { battery: 250, charging: true }.cleaned(), PhoneStatus { battery: 100, charging: true });
    }

    #[test]
    fn only_plain_web_links_open() {
        assert_eq!(clean_url(" https://example.com/a?b=c#d ").unwrap(), "https://example.com/a?b=c#d");
        for bad in ["", "https://", "ftp://example.com", "file:///etc/passwd", "javascript:alert(1)", "https://a b", "https://a'b", "https://a\nb", "https://a`b`", "-h https://x"] {
            assert!(clean_url(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn file_names_stay_inside_their_folder() {
        assert_eq!(clean_file_name("../../etc/passwd"), "passwd");
        assert_eq!(clean_file_name("C:\\Users\\me\\photo.jpg"), "photo.jpg");
        assert_eq!(clean_file_name(".bashrc"), "bashrc");
        assert_eq!(clean_file_name(".."), "file");
        assert_eq!(clean_file_name("a\nb.txt"), "ab.txt");
        assert_eq!(clean_file_name(""), "file");
    }

    #[test]
    fn ids_and_commands_are_checked_and_quoted() {
        assert_eq!(clean_id("00112233AABBCCDD").unwrap(), "00112233aabbccdd");
        assert!(clean_id("0011").is_err() && clean_id("0011223344556677; rm").is_err());
        assert!(done_command("zz").is_err());
        assert!(received_command("Sam's phone", &["a b.txt".into()]).ends_with(r#"multiplex 'share' 'received' 'Sam'\''s phone' 'a b.txt'"#));
        assert!(link_command("Phone").ends_with("multiplex 'link' 'Phone'"));
    }
}
