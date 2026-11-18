//! Reading the text in a picture (a photo of a page, taken with the
//! phone), with tesseract, in whatever languages it has installed here.

use std::io::Write;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};

use crate::system::on_path;

/// What is missing when it cannot work.
pub const NEEDS: &str = "needs tesseract and at least one language for it (sudo pacman -S tesseract tesseract-data-eng)";

/// A page is read in a few seconds; after this long something is wrong.
const PATIENCE: Duration = Duration::from_secs(60);

/// The languages tesseract can read here, from `tesseract --list-langs`:
/// a heading, then one per line. `osd` and `equ` are not languages (they
/// find a page's direction, and formulas).
fn languages_in(listing: &str) -> Vec<String> {
    listing.lines().skip(1).map(str::trim).filter(|l| !l.is_empty() && *l != "osd" && *l != "equ" && l.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')).map(str::to_owned).collect()
}

/// The languages installed here.
pub fn languages() -> Vec<String> {
    if !on_path("tesseract") {
        return Vec::new();
    }
    Command::new("tesseract").arg("--list-langs").output().map(|out| languages_in(&String::from_utf8_lossy(&out.stdout))).unwrap_or_default()
}

/// The text as a person would want it pasted: no trailing spaces, no page
/// break characters, at most one empty line in a row, nothing around it.
fn tidy(read: &str) -> String {
    let mut out = String::new();
    let mut empty = 0;
    for line in read.replace(['\r', '\u{c}'], "").lines() {
        let line = line.trim_end();
        if line.trim().is_empty() {
            empty += 1;
            continue;
        }
        if !out.is_empty() {
            out.push_str(if empty > 0 { "\n\n" } else { "\n" });
        }
        empty = 0;
        out.push_str(line);
    }
    out
}

/// The text in `picture` (a JPEG or PNG), and the languages it was read
/// in. An empty text: the picture has none that could be read.
pub fn text_in(picture: &[u8]) -> Result<(String, Vec<String>)> {
    let languages = languages();
    if languages.is_empty() {
        bail!("reading text {NEEDS}");
    }
    let mut reader = Command::new("tesseract")
        .args(["stdin", "stdout", "-l", &languages.join("+")])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .context("tesseract could not be started")?;
    // Written from its own thread: tesseract may start answering before it
    // has taken the whole picture.
    let mut input = reader.stdin.take().context("tesseract takes no input")?;
    let bytes = picture.to_vec();
    let writing = std::thread::spawn(move || input.write_all(&bytes).is_ok());
    let started = Instant::now();
    let (sent, received) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let _ = sent.send(reader.wait_with_output());
    });
    let out = match received.recv_timeout(PATIENCE.saturating_sub(started.elapsed())) {
        Ok(out) => out.context("tesseract did not finish")?,
        Err(_) => bail!("the picture could not be read in a minute"),
    };
    let _ = writing.join();
    if !out.status.success() {
        bail!("that is not a picture tesseract can read");
    }
    Ok((tidy(&String::from_utf8_lossy(&out.stdout)), languages))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_languages_are_taken_from_tesseracts_list() {
        assert_eq!(languages_in("List of available languages in \"/usr/share/tessdata/\" (4):\neng\nosd\nrus\nchi_sim\n"), ["eng", "rus", "chi_sim"]);
        assert!(languages_in("List of available languages (1):\nosd\n").is_empty());
        assert!(languages_in("").is_empty());
        // Nothing odd is passed on to a command line.
        assert_eq!(languages_in("heading\neng\n../x\na b\n"), ["eng"]);
    }

    #[test]
    fn text_is_tidied_for_pasting() {
        assert_eq!(tidy("Hello  \nworld\n\n\n\nNext part   \n \n\u{c}"), "Hello\nworld\n\nNext part");
        assert_eq!(tidy("\n\n  indented stays\r\n"), "  indented stays");
        assert_eq!(tidy(" \n\u{c}\n"), "");
    }
}
