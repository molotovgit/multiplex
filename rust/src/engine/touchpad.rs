//! The computer's pointer and keys from the phone, without its picture:
//! the phone writes short lines to `multiplex input` on the computer (a
//! virtual touchpad and keyboard there), over the SSH connection that is
//! already open. The lines and their limits are in `multiplex-proto`.
//!
//! No video means nothing to decode and a few bytes per event, so this is
//! the lightest way to steer the computer when its screen is in sight.

use std::collections::HashSet;
use std::sync::Arc;
use std::time::Duration;

use bytes::Bytes;
use multiplex_proto::input::{InputEvent, INPUT_COMMAND, PING_MS, READY};
use russh::ChannelMsg;
use tokio::sync::mpsc;

use super::events::{EventRelay, EventSink};
use super::runtime::AsyncRuntime;
use super::ssh::Connection;

/// A running touchpad. Dropping it (or [`Touchpad::close`]) ends the
/// command on the computer, which releases every key and button.
pub struct Touchpad {
    events: mpsc::UnboundedSender<Option<InputEvent>>,
}

/// Why the computer's side could not start or stopped, as a sentence.
fn problem(exit_code: Option<u32>, stderr: &[u8]) -> String {
    if exit_code == Some(127) {
        return "This computer does not have the Multiplex package (or it is an old one). Install it there, then try again.".to_owned();
    }
    let text = String::from_utf8_lossy(stderr);
    let said = text.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or_default().trim();
    let said = said.strip_prefix("multiplex: ").unwrap_or(said);
    if said.is_empty() {
        return "The computer's touchpad stopped.".to_owned();
    }
    let mut out = said.to_owned();
    if let Some(first) = out.get_mut(..1) {
        first.make_ascii_uppercase();
    }
    out
}

/// Joins movements that arrived together: ten small moves become one, in
/// order with the clicks and keys between them.
pub fn coalesce(events: Vec<InputEvent>) -> Vec<InputEvent> {
    let mut out: Vec<InputEvent> = Vec::with_capacity(events.len());
    for event in events {
        match (out.last_mut(), &event) {
            (Some(InputEvent::Move { dx, dy }), InputEvent::Move { dx: mx, dy: my }) => {
                *dx += mx;
                *dy += my;
            }
            (Some(InputEvent::Scroll { dx, dy }), InputEvent::Scroll { dx: sx, dy: sy }) => {
                *dx += sx;
                *dy += sy;
            }
            _ => out.push(event),
        }
    }
    out
}

/// What is held down after these events, so the phone knows to keep
/// telling the computer it is still there.
fn track(held: &mut HashSet<(bool, u32)>, event: &InputEvent) {
    match event {
        InputEvent::Key { code, down } => {
            let key = (true, u32::from(*code));
            if *down {
                held.insert(key);
            } else {
                held.remove(&key);
            }
        }
        InputEvent::Button { button, down } => {
            let key = (false, button.code());
            if *down {
                held.insert(key);
            } else {
                held.remove(&key);
            }
        }
        InputEvent::ReleaseAll | InputEvent::Paste { .. } => held.clear(),
        _ => {}
    }
}

impl Touchpad {
    /// Starts the computer's side and waits until its pointer and keyboard
    /// exist. `ended` hears, once, why it stopped (an empty reason when
    /// the phone closed it).
    pub async fn open(conn: Arc<Connection>, ended: Arc<EventRelay<String>>) -> anyhow::Result<Self> {
        let channel = conn.handle().channel_open_session().await?;
        channel.exec(true, INPUT_COMMAND.as_bytes()).await?;
        let (mut reader, writer) = channel.split();

        let mut said = Vec::new();
        let mut complained = Vec::new();
        let mut exit_code = None;
        let ready = tokio::time::timeout(Duration::from_secs(10), async {
            while let Some(msg) = reader.wait().await {
                match msg {
                    ChannelMsg::Data { data } => {
                        said.extend_from_slice(&data);
                        if said.split(|b| *b == b'\n').any(|line| line == READY.as_bytes()) {
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
            Ok(false) => anyhow::bail!("{}", problem(exit_code, &complained)),
            Err(_) => anyhow::bail!("The computer did not answer."),
        }

        let (events, mut incoming) = mpsc::unbounded_channel::<Option<InputEvent>>();
        AsyncRuntime::spawn(async move {
            let mut held = HashSet::new();
            let mut complained = Vec::new();
            let mut exit_code = None;
            let mut alive = tokio::time::interval(Duration::from_millis(PING_MS));
            alive.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
            let reason = loop {
                tokio::select! {
                    first = incoming.recv() => {
                        // None: every sender is gone. Some(None): closed on purpose.
                        let Some(Some(first)) = first else { break String::new() };
                        let mut batch = vec![first];
                        let mut closing = false;
                        while let Ok(next) = incoming.try_recv() {
                            match next {
                                Some(event) => batch.push(event),
                                None => {
                                    closing = true;
                                    break;
                                }
                            }
                        }
                        let mut text = String::new();
                        for event in coalesce(batch) {
                            track(&mut held, &event);
                            text.push_str(&event.to_line());
                            text.push('\n');
                        }
                        if writer.data_bytes(Bytes::from(text)).await.is_err() {
                            break "The connection to the computer was lost.".to_owned();
                        }
                        alive.reset();
                        if closing {
                            break String::new();
                        }
                    }
                    _ = alive.tick(), if !held.is_empty() => {
                        if writer.data_bytes(Bytes::from(format!("{}\n", InputEvent::Ping.to_line()))).await.is_err() {
                            break "The connection to the computer was lost.".to_owned();
                        }
                    }
                    msg = reader.wait() => match msg {
                        Some(ChannelMsg::ExtendedData { data, .. }) => {
                            complained.extend_from_slice(&data);
                            // Notices pile up only if something is wrong; keep the last of them.
                            if complained.len() > 8192 {
                                complained.drain(..4096);
                            }
                        }
                        Some(ChannelMsg::ExitStatus { exit_status }) => exit_code = Some(exit_status),
                        Some(ChannelMsg::Close) | None => break problem(exit_code, &complained),
                        _ => {}
                    },
                }
            };
            // Ending the input makes the computer let go of everything.
            let _ = writer.eof().await;
            let _ = writer.close().await;
            ended.emit(reason);
        });
        Ok(Self { events })
    }

    /// Queues an event. False once the touchpad has ended.
    pub fn send(&self, event: InputEvent) -> bool {
        self.events.send(Some(event)).is_ok()
    }

    pub fn close(&self) {
        let _ = self.events.send(None);
    }
}

impl Drop for Touchpad {
    fn drop(&mut self) {
        self.close();
    }
}

#[cfg(test)]
mod tests {
    use multiplex_proto::input::Button;

    use super::*;

    #[test]
    fn movements_that_arrive_together_become_one() {
        let joined = coalesce(vec![
            InputEvent::Move { dx: 1.0, dy: 2.0 },
            InputEvent::Move { dx: 0.5, dy: -1.0 },
            InputEvent::Button { button: Button::Left, down: true },
            InputEvent::Move { dx: 3.0, dy: 0.0 },
            InputEvent::Scroll { dx: 0.0, dy: 4.0 },
            InputEvent::Scroll { dx: 0.0, dy: 6.0 },
            InputEvent::Move { dx: 1.0, dy: 1.0 },
        ]);
        assert_eq!(
            joined,
            vec![
                InputEvent::Move { dx: 1.5, dy: 1.0 },
                InputEvent::Button { button: Button::Left, down: true },
                InputEvent::Move { dx: 3.0, dy: 0.0 },
                InputEvent::Scroll { dx: 0.0, dy: 10.0 },
                InputEvent::Move { dx: 1.0, dy: 1.0 },
            ]
        );
    }

    #[test]
    fn what_is_held_is_followed() {
        let mut held = HashSet::new();
        track(&mut held, &InputEvent::Key { code: 125, down: true });
        track(&mut held, &InputEvent::Button { button: Button::Left, down: true });
        track(&mut held, &InputEvent::Move { dx: 1.0, dy: 1.0 });
        assert_eq!(held.len(), 2);
        track(&mut held, &InputEvent::Key { code: 125, down: false });
        assert_eq!(held.len(), 1);
        track(&mut held, &InputEvent::ReleaseAll);
        assert!(held.is_empty());
    }

    #[test]
    fn failures_are_put_in_words() {
        assert!(problem(Some(127), b"sh: multiplex: not found").contains("Multiplex package"));
        assert_eq!(problem(Some(1), b"multiplex: Hyprland is not running for this user\n"), "Hyprland is not running for this user");
        assert_eq!(problem(None, b""), "The computer's touchpad stopped.");
    }
}
