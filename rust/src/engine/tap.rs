//! A command on the computer whose output the phone takes as a stream of
//! bytes, over the SSH connection that is already open (the computer's
//! sound, for the phone to play).
//!
//! The command says `ready` on a line of its own; everything after that
//! line is the stream. The phone writes a byte to it once a second for
//! as long as it is taking the stream: a command whose phone has gone
//! without a word must not carry on (the computer's sound would be going
//! nowhere).

use std::sync::{Arc, Mutex};
use std::time::Duration;

use multiplex_proto::share::FEED_READY;
use russh::ChannelMsg;
use tokio::sync::Notify;

use super::events::{EventRelay, EventSink};
use super::runtime::AsyncRuntime;
use super::ssh::Connection;

const LOST: &str = "The connection to the computer was lost.";

pub struct Tap {
    stop: Arc<Notify>,
    closed: Arc<Mutex<bool>>,
}

/// Why the computer's side could not start or stopped, as a sentence.
fn problem(exit_code: Option<u32>, stderr: &[u8], otherwise: &str) -> String {
    if exit_code == Some(127) {
        return "This computer does not have the Multiplex package (or it is an old one). Install it there, then try again.".to_owned();
    }
    let text = String::from_utf8_lossy(stderr);
    let said = text.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or_default().trim();
    let said = said.strip_prefix("multiplex: ").unwrap_or(said);
    if said.is_empty() {
        return otherwise.to_owned();
    }
    let mut out = said.to_owned();
    if let Some(first) = out.get_mut(..1) {
        first.make_ascii_uppercase();
    }
    out
}

/// Splits what has arrived so far at the `ready` line: `Some(rest)` once
/// the line is there, with whatever of the stream came along with it.
fn after_ready(said: &[u8]) -> Option<&[u8]> {
    let mut start = 0;
    while let Some(end) = said[start..].iter().position(|b| *b == b'\n') {
        let line = &said[start..start + end];
        let line = line.strip_suffix(b"\r").unwrap_or(line);
        start += end + 1;
        if line == FEED_READY.as_bytes() {
            return Some(&said[start..]);
        }
    }
    None
}

impl Tap {
    /// Starts `command` and waits until it is ready. `bytes` then gets the
    /// stream as it arrives; `ended` hears, once, why it stopped (an empty
    /// reason when the phone closed it, or the command simply finished).
    pub async fn open(conn: Arc<Connection>, command: &str, bytes: Arc<EventRelay<Vec<u8>>>, ended: Arc<EventRelay<String>>) -> anyhow::Result<Self> {
        let channel = conn.handle().channel_open_session().await?;
        channel.exec(true, command.as_bytes()).await?;
        let (mut reader, writer) = channel.split();

        let (mut said, mut complained, mut exit_code) = (Vec::new(), Vec::new(), None);
        let first = tokio::time::timeout(Duration::from_secs(15), async {
            while let Some(msg) = reader.wait().await {
                match msg {
                    ChannelMsg::Data { data } => {
                        said.extend_from_slice(&data);
                        if let Some(rest) = after_ready(&said) {
                            return Some(rest.to_vec());
                        }
                        if said.len() > 4096 {
                            return None;
                        }
                    }
                    ChannelMsg::ExtendedData { data, .. } => complained.extend_from_slice(&data),
                    ChannelMsg::ExitStatus { exit_status } => exit_code = Some(exit_status),
                    ChannelMsg::Close => break,
                    _ => {}
                }
            }
            None
        })
        .await;
        let first = match first {
            Ok(Some(first)) => first,
            Ok(None) => anyhow::bail!("{}", problem(exit_code, &complained, "The computer could not start it.")),
            Err(_) => anyhow::bail!("The computer did not answer."),
        };
        if !first.is_empty() {
            bytes.emit(first);
        }

        let stop = Arc::new(Notify::new());
        let closed = Arc::new(Mutex::new(false));
        let (stopping, closing) = (stop.clone(), closed.clone());
        AsyncRuntime::spawn(async move {
            let mut still_here = tokio::time::interval(Duration::from_secs(1));
            let reason = loop {
                tokio::select! {
                    biased;
                    () = stopping.notified() => break String::new(),
                    _ = still_here.tick() => {
                        if writer.data(&b"\n"[..]).await.is_err() {
                            break LOST.to_owned();
                        }
                    }
                    msg = reader.wait() => match msg {
                        Some(ChannelMsg::Data { data }) => {
                            // Nobody is taking it any more: stop.
                            if !bytes.emit(data.to_vec()) {
                                break String::new();
                            }
                        }
                        Some(ChannelMsg::ExtendedData { data, .. }) => {
                            complained.extend_from_slice(&data);
                            if complained.len() > 8192 {
                                complained.drain(..4096);
                            }
                        }
                        Some(ChannelMsg::ExitStatus { exit_status }) => exit_code = Some(exit_status),
                        Some(ChannelMsg::Close) => break if exit_code.is_none_or(|c| c == 0) { String::new() } else { problem(exit_code, &complained, "It stopped on the computer.") },
                        None => break LOST.to_owned(),
                        _ => {}
                    },
                }
            };
            let _ = writer.eof().await;
            let _ = writer.close().await;
            let by_us = std::mem::replace(&mut *closing.lock().unwrap_or_else(|e| e.into_inner()), true);
            ended.emit(if by_us { String::new() } else { reason });
        });
        Ok(Self { stop, closed })
    }

    pub fn close(&self) {
        *self.closed.lock().unwrap_or_else(|e| e.into_inner()) = true;
        self.stop.notify_one();
    }
}

impl Drop for Tap {
    fn drop(&mut self) {
        self.close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_stream_begins_right_after_the_ready_line() {
        assert_eq!(after_ready(b"rea"), None);
        assert_eq!(after_ready(b"ready"), None, "the line is not complete yet");
        assert_eq!(after_ready(b"ready\n"), Some(&b""[..]));
        // Stream bytes that came along with the line are not lost, whatever they are.
        assert_eq!(after_ready(b"ready\n\xFF\xF1\x4C\n\x00"), Some(&b"\xFF\xF1\x4C\n\x00"[..]));
        assert_eq!(after_ready(b"ready\r\nabc"), Some(&b"abc"[..]));
        // Something else first (a notice from the shell, say) is passed over.
        assert_eq!(after_ready(b"motd\nready\nxy"), Some(&b"xy"[..]));
        assert_eq!(after_ready(b"not ready\n"), None);
    }

    #[test]
    fn failures_are_put_in_words() {
        assert!(problem(Some(127), b"", "x").contains("Multiplex package"));
        assert_eq!(problem(Some(1), b"multiplex: the phone as a speaker needs ffmpeg and pactl\n", "x"), "The phone as a speaker needs ffmpeg and pactl");
        assert_eq!(problem(None, b"", "It stopped on the computer."), "It stopped on the computer.");
    }
}
