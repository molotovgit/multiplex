//! Recording terminal output as an asciinema v2 ".cast" file.
//!
//! The format is one JSON header line, then one line per event:
//! `[seconds, "o", "text"]` for output and `[seconds, "r", "80x24"]` for a
//! new size. Any asciinema player (and the app's own) can play it back.

use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::Path;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

/// Writes one recording while it runs.
pub struct CastRecorder {
    out: BufWriter<File>,
    started: Instant,
    /// The end of a character that was cut in two between reads.
    partial: Vec<u8>,
    paused: bool,
}

impl CastRecorder {
    /// Creates the file and writes the header.
    pub fn create(path: &Path, cols: u16, rows: u16, title: &str) -> std::io::Result<Self> {
        let mut out = BufWriter::new(File::create(path)?);
        let timestamp = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
        writeln!(
            out,
            "{{\"version\": 2, \"width\": {cols}, \"height\": {rows}, \"timestamp\": {timestamp}, \"title\": {}, \"env\": {{\"TERM\": \"xterm-256color\"}}}}",
            Self::json_string(title)
        )?;
        Ok(Self { out, started: Instant::now(), partial: Vec::new(), paused: false })
    }

    /// While paused (a password prompt is on screen), output is left out.
    pub fn set_paused(&mut self, paused: bool) {
        self.paused = paused;
        self.partial.clear();
    }

    pub fn paused(&self) -> bool {
        self.paused
    }

    /// Output from the server, as it came.
    pub fn output(&mut self, data: &[u8]) {
        if self.paused {
            return;
        }
        self.partial.extend_from_slice(data);
        let text = match std::str::from_utf8(&self.partial) {
            Ok(text) => text.to_owned(),
            Err(e) if e.error_len().is_none() => {
                // The last character is not complete yet: keep its start.
                let valid = e.valid_up_to();
                let text = String::from_utf8_lossy(&self.partial[..valid]).into_owned();
                self.partial.drain(..valid);
                self.write_event("o", &text);
                return;
            }
            Err(_) => String::from_utf8_lossy(&self.partial).into_owned(),
        };
        self.partial.clear();
        self.write_event("o", &text);
    }

    /// The terminal got a new size.
    pub fn resize(&mut self, cols: u16, rows: u16) {
        self.write_event("r", &format!("{cols}x{rows}"));
    }

    /// Writes what is buffered to the file.
    pub fn finish(mut self) -> std::io::Result<()> {
        self.out.flush()
    }

    fn write_event(&mut self, kind: &str, text: &str) {
        if text.is_empty() {
            return;
        }
        let at = self.started.elapsed().as_secs_f64();
        // A failed write (disk full) must never stop the terminal.
        let _ = writeln!(self.out, "[{at:.6}, \"{kind}\", {}]", Self::json_string(text));
    }

    /// `text` as a JSON string, quotes included.
    pub fn json_string(text: &str) -> String {
        let mut out = String::with_capacity(text.len() + 2);
        out.push('"');
        for c in text.chars() {
            match c {
                '"' => out.push_str("\\\""),
                '\\' => out.push_str("\\\\"),
                '\n' => out.push_str("\\n"),
                '\r' => out.push_str("\\r"),
                '\t' => out.push_str("\\t"),
                c if (c as u32) < 0x20 || c == '\u{7f}' => out.push_str(&format!("\\u{:04x}", c as u32)),
                c => out.push(c),
            }
        }
        out.push('"');
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escapes_control_characters_for_json() {
        assert_eq!(CastRecorder::json_string("a\"b\\c\r\n\x1b[0m"), "\"a\\\"b\\\\c\\r\\n\\u001b[0m\"");
    }

    #[test]
    fn writes_header_events_and_keeps_split_characters_whole() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("t.cast");
        let mut rec = CastRecorder::create(&path, 80, 24, "web \"1\"").unwrap();
        let euro = "€".as_bytes();
        rec.output(b"hi ");
        rec.output(&euro[..1]);
        rec.output(&euro[1..]);
        rec.resize(100, 30);
        rec.set_paused(true);
        rec.output(b"secret");
        rec.set_paused(false);
        rec.output(b"\r\n");
        rec.finish().unwrap();

        let text = std::fs::read_to_string(&path).unwrap();
        let lines: Vec<&str> = text.lines().collect();
        assert!(lines[0].starts_with("{\"version\": 2, \"width\": 80, \"height\": 24,"), "{}", lines[0]);
        assert!(lines[0].contains("\"title\": \"web \\\"1\\\"\""));
        let events: Vec<&str> = lines[1..].iter().map(|l| &l[l.find(',').unwrap() + 2..]).collect();
        assert_eq!(events, vec!["\"o\", \"hi \"]", "\"o\", \"€\"]", "\"r\", \"100x30\"]", "\"o\", \"\\r\\n\"]"]);
        assert!(!text.contains("secret"));
    }
}
