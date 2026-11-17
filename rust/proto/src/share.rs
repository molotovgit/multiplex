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

/// The biggest picture that is taken for reading its text.
pub const MAX_PICTURE: usize = 20 * 1024 * 1024;

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
    /// Send this text message from the phone.
    Sms { to: String, text: String },
    /// A coding agent on the computer now waits for an answer, or is done.
    Agent(crate::agents::Agent),
    /// Someone at the computer asks the phone's owner to approve
    /// something. The phone answers by signing [`approval_message`] with
    /// its own key, which nothing on the computer can do in its place.
    Approve { id: String, reason: String, challenge: String },
    /// The computer's SSH agent asks the phone to sign with its key: a
    /// login, or an SSH signature (see [`crate::sign`]). `data` is the
    /// request in base64; the phone reads it itself.
    Sign { id: String, data: String },
}

/// What `multiplex share paste` prints.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct Clipboard {
    /// None: the clipboard is empty, or holds something that is not text.
    pub text: Option<String>,
}

/// What `multiplex share read` prints: the text found in a picture.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct TextRead {
    /// Empty: no text could be read in the picture.
    pub text: String,
    /// The languages the computer read it in (tesseract's names).
    pub languages: Vec<String>,
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

/// Reads the text in the picture on standard input (a JPEG or PNG),
/// puts it on the computer's clipboard, and prints it as [`TextRead`].
pub fn read_command() -> String {
    command(&["share", "read"])
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

/// The longest text message taken (a few joined messages' worth).
pub const MAX_SMS: usize = 1000;

/// A phone number as people write it: digits, with an optional leading
/// plus, and spaces, dashes, dots or brackets between them. The answer
/// has only the plus and the digits.
pub fn clean_phone_number(number: &str) -> Result<String, ProtoError> {
    let number = number.trim();
    let allowed = number.chars().all(|c| c.is_ascii_digit() || matches!(c, '+' | ' ' | '-' | '.' | '(' | ')'));
    let plus_only_first = number.chars().skip(1).all(|c| c != '+');
    let digits: String = number.chars().filter(char::is_ascii_digit).collect();
    if allowed && plus_only_first && (3..=20).contains(&digits.len()) {
        Ok(if number.starts_with('+') { format!("+{digits}") } else { digits })
    } else {
        Err(ProtoError::Invalid("this is not a phone number"))
    }
}

/// A text message's words: not empty, not longer than [`MAX_SMS`], no
/// control characters except line breaks.
pub fn clean_sms_text(text: &str) -> Result<String, ProtoError> {
    let text: String = text.chars().filter(|c| !c.is_control() || *c == '\n').collect();
    let text = text.trim();
    if text.is_empty() || text.chars().count() > MAX_SMS {
        Err(ProtoError::Invalid("a text message has between 1 and 1000 characters"))
    } else {
        Ok(text.to_owned())
    }
}

/// How long the computer waits for an approval.
pub const APPROVE_SECONDS: u64 = 60;

/// What is being approved, as one line that fits a fingerprint prompt.
pub fn clean_reason(reason: &str) -> Result<String, ProtoError> {
    let tidy = one_line(reason, 200);
    if tidy.is_empty() {
        Err(ProtoError::Invalid("say what is to be approved"))
    } else {
        Ok(tidy)
    }
}

/// The bytes the phone signs to approve: the request's id, a random
/// challenge made for this one request, and the reason as it was shown.
/// Signing them says "yes, to exactly this, now".
pub fn approval_message(id: &str, reason: &str, challenge: &str) -> Vec<u8> {
    format!("multiplex-approve-v1\n{id}\n{challenge}\n{reason}").into_bytes()
}

/// Reads the phone's answer from standard input: the signature in
/// base64, or "no".
pub fn approved_command(id: &str) -> Result<String, ProtoError> {
    Ok(command(&["share", "approved", &clean_id(id)?]))
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

/// Shows the picture the phone then writes to standard input (its own
/// screen, as H.264) in a window on the computer. `phone` names it in
/// the window's title.
pub fn screen_command(phone: &str) -> String {
    if phone.is_empty() {
        command(&["screen"])
    } else {
        command(&["screen", phone])
    }
}

/// Offers the picture the phone then writes to standard input (its
/// camera, as H.264) to the computer's programs as a webcam. `turn` is
/// how far the picture has to be turned clockwise to stand upright, in
/// degrees; `phone` names the camera.
pub fn camera_command(phone: &str, turn: u32) -> String {
    let turn = (turn % 360 / 90 * 90).to_string();
    if phone.is_empty() {
        command(&["camera", "--turn", &turn])
    } else {
        command(&["camera", "--turn", &turn, phone])
    }
}

/// Offers the sound the phone then writes to standard input (its
/// microphone, as AAC frames with ADTS headers) to the computer's
/// programs as a microphone. `phone` names it.
pub fn mic_command(phone: &str) -> String {
    if phone.is_empty() {
        command(&["mic"])
    } else {
        command(&["mic", phone])
    }
}

/// Gives the computer one more sound output, named after `phone`, and
/// writes what is played into it to standard output (AAC frames with
/// ADTS headers) after a `ready` line. With `everything` that output
/// becomes the computer's default while the command runs. The phone
/// writes a byte to it once a second; the command ends when that stops.
pub fn speaker_command(phone: &str, everything: bool) -> String {
    let mut words = vec!["speaker"];
    if everything {
        words.push("--default");
    }
    if !phone.is_empty() {
        words.push(phone);
    }
    command(&words)
}

/// What a command that is fed bytes says once it can take them.
pub const FEED_READY: &str = "ready";

/// What it says now and then after that: how many bytes it has taken so
/// far. The sender knows from this how far behind the other end is.
pub fn fed_line(bytes: u64) -> String {
    format!("got {bytes}")
}

/// Reads a [`fed_line`].
pub fn parse_fed(line: &str) -> Option<u64> {
    line.trim().strip_prefix("got ")?.parse().ok()
}

/// A call on the phone began or ended (the computer pauses what is
/// playing, and carries on afterwards).
pub fn call_command(phone: &str, active: bool) -> String {
    command(&["phone", "call", phone, if active { "start" } else { "end" }])
}

pub fn done_command(id: &str) -> Result<String, ProtoError> {
    Ok(command(&["share", "done", &clean_id(id)?]))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_speaker_is_asked_for_with_or_without_all_of_the_sound() {
        assert!(speaker_command("", false).ends_with("multiplex 'speaker'"));
        assert!(speaker_command("", true).ends_with("multiplex 'speaker' '--default'"));
        assert!(speaker_command("Sam's phone", true).ends_with(r"'speaker' '--default' 'Sam'\''s phone'"), "{}", speaker_command("Sam's phone", true));
        assert!(speaker_command("Phone", false).ends_with("'speaker' 'Phone'"));
    }

    #[test]
    fn the_camera_is_asked_for_with_its_turn_in_quarter_turns() {
        assert!(camera_command("", 90).ends_with("multiplex 'camera' '--turn' '90'"), "{}", camera_command("", 90));
        assert!(camera_command("Sam's phone", 270).ends_with(r"'--turn' '270' 'Sam'\''s phone'"), "{}", camera_command("Sam's phone", 270));
        // Anything else is brought to a quarter turn.
        assert!(camera_command("", 450).contains("'--turn' '90'"));
        assert!(camera_command("", 100).contains("'--turn' '90'"));
        assert!(camera_command("", 0).contains("'--turn' '0'"));
    }

    #[test]
    fn the_count_of_bytes_taken_reads_back() {
        assert_eq!(parse_fed(&fed_line(0)), Some(0));
        assert_eq!(parse_fed("got 1234567\n"), Some(1_234_567));
        for wrong in ["ready", "got", "got x", "got -1", ""] {
            assert_eq!(parse_fed(wrong), None, "{wrong}");
        }
    }

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
    fn phone_numbers_and_messages_are_checked() {
        assert_eq!(clean_phone_number(" +44 (20) 7946-0018 ").unwrap(), "+442079460018");
        assert_eq!(clean_phone_number("555.0100").unwrap(), "5550100");
        for bad in ["", "12", "+", "44+20", "call me", "123; rm -rf", "1".repeat(21).as_str()] {
            assert!(clean_phone_number(bad).is_err(), "{bad}");
        }
        assert_eq!(clean_sms_text("  On my way\u{7}\nBack at 5 ").unwrap(), "On my way\nBack at 5");
        assert!(clean_sms_text("  ").is_err() && clean_sms_text(&"x".repeat(1001)).is_err());
        let sms = LinkEvent::Sms { to: "+15550100".into(), text: "hi".into() };
        assert_eq!(parse_link_event(&serde_json::to_string(&sms).unwrap()).unwrap(), sms);
    }

    #[test]
    fn an_approval_is_for_exactly_one_request() {
        let message = approval_message("00112233aabbccdd", "sudo pacman -Syu", "Y2hhbGxlbmdl");
        assert_eq!(message, b"multiplex-approve-v1\n00112233aabbccdd\nY2hhbGxlbmdl\nsudo pacman -Syu");
        assert_ne!(message, approval_message("00112233aabbccdd", "sudo rm -rf /", "Y2hhbGxlbmdl"));
        assert_ne!(message, approval_message("00112233aabbccdd", "sudo pacman -Syu", "b3RoZXI="));
        assert_eq!(clean_reason("  sudo\npacman  -Syu ").unwrap(), "sudo pacman -Syu");
        assert!(clean_reason(" \n ").is_err());
        assert!(approved_command("nope").is_err());
        let ask = LinkEvent::Approve { id: "00112233aabbccdd".into(), reason: "x".into(), challenge: "Yw==".into() };
        assert_eq!(parse_link_event(&serde_json::to_string(&ask).unwrap()).unwrap(), ask);
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
