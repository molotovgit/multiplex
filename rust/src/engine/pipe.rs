//! A command on the computer that is fed bytes from the phone, over the
//! SSH connection that is already open (the phone's screen as a video
//! stream, for one).
//!
//! The command says `ready` on a line of its own once it can take the
//! bytes, and after that now and then how many it has taken. From that
//! the phone knows how much is still on its way ([`Pipe::in_flight`]),
//! wherever it is waiting: here, in SSH, or in the network.

use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use bytes::Bytes;
use multiplex_proto::share::{parse_fed, FEED_READY};
use russh::ChannelMsg;
use tokio::sync::{mpsc, Notify};

use super::events::{EventRelay, EventSink};
use super::runtime::AsyncRuntime;
use super::ssh::Connection;

/// More than this waiting here to be sent means the connection is far
/// too slow, and the pipe ends.
const MAX_WAITING: usize = 8 * 1024 * 1024;

const LOST: &str = "The connection to the computer was lost.";

pub struct Pipe {
    chunks: mpsc::UnboundedSender<Bytes>,
    shared: Arc<Shared>,
}

struct Shared {
    /// Queued here, not yet handed to SSH.
    waiting: AtomicUsize,
    /// Everything [`Pipe::write`] has accepted.
    sent: AtomicU64,
    /// What the command says it has taken.
    got: AtomicU64,
    /// The command reports what it has taken (an older one does not).
    reports: AtomicBool,
    /// Wakes the sending task to stop.
    stop: Notify,
    /// Why it ended, once it has (empty: closed, or simply finished).
    reason: Mutex<Option<String>>,
    ended: Arc<EventRelay<String>>,
}

impl Shared {
    /// Ends the pipe. The first reason given is the one that counts.
    fn finish(&self, reason: &str) {
        let first = {
            let mut slot = self.reason.lock().unwrap_or_else(|e| e.into_inner());
            slot.is_none().then(|| *slot = Some(reason.to_owned())).is_some()
        };
        if first {
            self.ended.emit(reason.to_owned());
        }
        self.stop.notify_one();
    }

    fn reason(&self) -> Option<String> {
        self.reason.lock().unwrap_or_else(|e| e.into_inner()).clone()
    }
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

/// Takes the complete lines out of what the command has said so far.
fn lines(said: &mut Vec<u8>) -> Vec<String> {
    let mut out = Vec::new();
    while let Some(end) = said.iter().position(|b| *b == b'\n') {
        let line: Vec<u8> = said.drain(..=end).collect();
        out.push(String::from_utf8_lossy(&line).trim().to_owned());
    }
    // Nothing the command says is long: a line that never ends is not ours.
    if said.len() > 4096 {
        said.clear();
    }
    out
}

impl Pipe {
    /// Starts `command` and waits until it is ready. `ended` hears, once,
    /// why it stopped (an empty reason when the phone closed it, or the
    /// command simply finished).
    pub async fn open(conn: Arc<Connection>, command: &str, ended: Arc<EventRelay<String>>) -> anyhow::Result<Self> {
        let channel = conn.handle().channel_open_session().await?;
        channel.exec(true, command.as_bytes()).await?;
        let (mut reader, writer) = channel.split();

        let (mut said, mut complained, mut exit_code) = (Vec::new(), Vec::new(), None);
        let ready = tokio::time::timeout(Duration::from_secs(15), async {
            while let Some(msg) = reader.wait().await {
                match msg {
                    ChannelMsg::Data { data } => {
                        said.extend_from_slice(&data);
                        if lines(&mut said).iter().any(|line| line == FEED_READY) {
                            return true;
                        }
                    }
                    ChannelMsg::ExtendedData { data, .. } => complained.extend_from_slice(&data),
                    ChannelMsg::ExitStatus { exit_status } => exit_code = Some(exit_status),
                    ChannelMsg::Close => break,
                    _ => {}
                }
            }
            false
        })
        .await;
        match ready {
            Ok(true) => {}
            Ok(false) => anyhow::bail!("{}", problem(exit_code, &complained, "The computer could not start it.")),
            Err(_) => anyhow::bail!("The computer did not answer."),
        }

        let (chunks, mut incoming) = mpsc::unbounded_channel::<Bytes>();
        let shared = Arc::new(Shared {
            waiting: AtomicUsize::new(0),
            sent: AtomicU64::new(0),
            got: AtomicU64::new(0),
            reports: AtomicBool::new(false),
            stop: Notify::new(),
            reason: Mutex::new(None),
            ended,
        });

        // Sending. Stopping does not wait for what is still queued, or for
        // a write the network is holding up: closing has to be immediate.
        let state = shared.clone();
        AsyncRuntime::spawn(async move {
            loop {
                tokio::select! {
                    biased;
                    () = state.stop.notified() => break,
                    chunk = incoming.recv() => {
                        let Some(chunk) = chunk else { break };
                        state.waiting.fetch_sub(chunk.len(), Ordering::Relaxed);
                        tokio::select! {
                            biased;
                            () = state.stop.notified() => break,
                            sent = writer.data_bytes(chunk) => if sent.is_err() {
                                state.finish(LOST);
                                break;
                            },
                        }
                    }
                }
            }
            let _ = writer.eof().await;
            let _ = writer.close().await;
        });

        // Listening: how much the command has taken, and how it ends.
        let state = shared.clone();
        AsyncRuntime::spawn(async move {
            let reason = loop {
                match reader.wait().await {
                    Some(ChannelMsg::Data { data }) => {
                        said.extend_from_slice(&data);
                        for line in lines(&mut said) {
                            if let Some(taken) = parse_fed(&line) {
                                state.got.fetch_max(taken, Ordering::Relaxed);
                                state.reports.store(true, Ordering::Relaxed);
                            }
                        }
                    }
                    Some(ChannelMsg::ExtendedData { data, .. }) => {
                        complained.extend_from_slice(&data);
                        if complained.len() > 8192 {
                            complained.drain(..4096);
                        }
                    }
                    Some(ChannelMsg::ExitStatus { exit_status }) => exit_code = Some(exit_status),
                    // The command ended by itself (its window was closed, say).
                    Some(ChannelMsg::Close) => break if exit_code.is_none_or(|c| c == 0) { String::new() } else { problem(exit_code, &complained, "It stopped on the computer.") },
                    None => break LOST.to_owned(),
                    _ => {}
                }
            };
            state.finish(&reason);
        });
        Ok(Self { chunks, shared })
    }

    /// Queues bytes. `Err` with the reason when the pipe has ended (an
    /// empty reason: it was closed, or the command finished).
    pub fn write(&self, bytes: Vec<u8>) -> Result<(), String> {
        if let Some(reason) = self.shared.reason() {
            return Err(reason);
        }
        let size = bytes.len();
        if self.shared.waiting.fetch_add(size, Ordering::Relaxed) > MAX_WAITING {
            self.shared.finish("The connection is too slow.");
            return Err(self.shared.reason().unwrap_or_default());
        }
        self.shared.sent.fetch_add(size as u64, Ordering::Relaxed);
        self.chunks.send(Bytes::from(bytes)).map_err(|_| self.shared.reason().unwrap_or_default())
    }

    /// Bytes written that the command has not taken yet. With a command
    /// that does not report, only what is still waiting here.
    pub fn in_flight(&self) -> u64 {
        if self.shared.reports.load(Ordering::Relaxed) {
            self.shared.sent.load(Ordering::Relaxed).saturating_sub(self.shared.got.load(Ordering::Relaxed))
        } else {
            self.shared.waiting.load(Ordering::Relaxed) as u64
        }
    }

    pub fn close(&self) {
        self.shared.finish("");
    }
}

impl Drop for Pipe {
    fn drop(&mut self) {
        self.close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn failures_are_put_in_words() {
        assert!(problem(Some(127), b"sh: multiplex: not found", "x").contains("Multiplex package"));
        assert_eq!(problem(Some(1), b"multiplex: mpv is needed to show the phone's screen: sudo pacman -S mpv\n", "x"), "Mpv is needed to show the phone's screen: sudo pacman -S mpv");
        assert_eq!(problem(Some(1), b"", "It stopped on the computer."), "It stopped on the computer.");
    }

    #[test]
    fn what_the_command_says_is_read_line_by_line_however_it_arrives() {
        let mut said = b"rea".to_vec();
        assert!(lines(&mut said).is_empty());
        said.extend_from_slice(b"dy\ngot 12\ngot 3");
        assert_eq!(lines(&mut said), ["ready", "got 12"]);
        said.extend_from_slice(b"4\r\n");
        assert_eq!(lines(&mut said), ["got 34"]);
        assert!(said.is_empty());
    }

    #[test]
    fn the_first_reason_for_ending_is_the_one_that_is_heard() {
        let heard = Arc::new(Mutex::new(Vec::new()));
        let relay = Arc::new(EventRelay::<String>::new());
        let sink = heard.clone();
        relay.attach(Arc::new(move |reason: String| {
            sink.lock().unwrap().push(reason);
            true
        }));
        let shared = Shared {
            waiting: AtomicUsize::new(0),
            sent: AtomicU64::new(0),
            got: AtomicU64::new(0),
            reports: AtomicBool::new(false),
            stop: Notify::new(),
            reason: Mutex::new(None),
            ended: relay,
        };
        shared.finish("The phone stopped sending its screen");
        shared.finish("");
        shared.finish(LOST);
        assert_eq!(*heard.lock().unwrap(), ["The phone stopped sending its screen"]);
        assert_eq!(shared.reason().as_deref(), Some("The phone stopped sending its screen"));
    }
}
