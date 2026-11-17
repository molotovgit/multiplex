//! A long-running command on the server whose output arrives line by line
//! (for example a watcher that reports when something changes).

use std::sync::Arc;

use flutter_rust_bridge::frb;
use russh::ChannelMsg;
use tokio::sync::Notify;

use crate::engine::events::{EventRelay, EventSink};
use crate::engine::runtime::AsyncRuntime;
use crate::engine::ssh::Connection;
use crate::frb_generated::StreamSink;

/// A running remote command. Its output lines come through [`lines`];
/// [`stop`] ends it (closing the channel ends the command on the server).
#[frb(opaque)]
pub struct RemoteWatch {
    lines: Arc<EventRelay<String>>,
    stop: Arc<Notify>,
}

impl RemoteWatch {
    pub(crate) async fn start(conn: Arc<Connection>, command: String) -> anyhow::Result<Self> {
        let channel = conn.handle().channel_open_session().await?;
        channel.exec(true, command.as_bytes()).await?;
        let lines = Arc::new(EventRelay::<String>::new());
        let stop = Arc::new(Notify::new());
        let (out, stopped) = (lines.clone(), stop.clone());
        AsyncRuntime::spawn(async move {
            let (mut reader, writer) = channel.split();
            let mut pending = Vec::new();
            loop {
                tokio::select! {
                    _ = stopped.notified() => break,
                    msg = reader.wait() => match msg {
                        Some(ChannelMsg::Data { data }) => {
                            pending.extend_from_slice(&data);
                            while let Some(nl) = pending.iter().position(|&b| b == b'\n') {
                                let line: Vec<u8> = pending.drain(..=nl).collect();
                                let text = String::from_utf8_lossy(&line[..line.len() - 1]).trim().to_owned();
                                if !text.is_empty() && !out.emit(text) {
                                    break;
                                }
                            }
                            // A runaway command without newlines must not grow forever.
                            if pending.len() > 64 * 1024 {
                                pending.clear();
                            }
                        }
                        Some(ChannelMsg::Close | ChannelMsg::Eof) | None => break,
                        _ => {}
                    },
                }
            }
            let _ = writer.close().await;
        });
        Ok(Self { lines, stop })
    }

    /// The command's output, one line at a time. Listen once.
    pub fn lines(&self, sink: StreamSink<String>) {
        self.lines.attach(Arc::new(move |line| sink.add(line).is_ok()));
    }

    /// Ends the command.
    #[frb(sync)]
    pub fn stop(&self) {
        self.stop.notify_one();
    }
}
