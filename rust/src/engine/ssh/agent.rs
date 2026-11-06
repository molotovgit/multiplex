//! Agent forwarding: lets `git` or `ssh` on the server use the phone's
//! key while the user is connected, without the key leaving the phone.
//!
//! The server opens an "agent" channel back to us for each program that
//! asks; we answer on it with the ssh-agent protocol (russh's agent
//! server) holding just this host's key. The server can list the key and
//! ask for signatures, nothing else: adding, removing or locking keys is
//! refused.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use futures::stream::{self, Stream};
use russh::client::Msg;
use russh::keys::agent::client::AgentClient;
use russh::keys::agent::server::{self, MessageType};
use russh::keys::PrivateKey;
use russh::Channel;
use tokio::io::DuplexStream;
use tokio::sync::mpsc;

/// What the agent allows. Only the app itself may add the key, before the
/// agent is sealed.
#[derive(Clone)]
struct Policy {
    sealed: Arc<AtomicBool>,
}

impl server::Agent for Policy {
    fn confirm_request(&self, msg: MessageType) -> impl std::future::Future<Output = bool> + Send {
        let allowed = match msg {
            MessageType::RequestKeys | MessageType::Sign => true,
            _ => !self.sealed.load(Ordering::SeqCst),
        };
        async move { allowed }
    }
}

/// An in-process ssh-agent holding one key, serving forwarded channels.
pub struct ForwardedAgent {
    streams: mpsc::UnboundedSender<std::io::Result<DuplexStream>>,
}

impl ForwardedAgent {
    /// Room for one agent message in each direction.
    const BUFFER: usize = 64 * 1024;

    /// Starts the agent with `key` in it.
    pub async fn start(key: &PrivateKey) -> anyhow::Result<Arc<Self>> {
        let (tx, rx) = mpsc::unbounded_channel();
        let sealed = Arc::new(AtomicBool::new(false));
        tokio::spawn(server::serve(Self::incoming(rx), Policy { sealed: sealed.clone() }));

        // The key goes in through a private connection, then the agent
        // takes no more keys.
        let (ours, theirs) = tokio::io::duplex(Self::BUFFER);
        tx.send(Ok(theirs)).map_err(|_| anyhow::anyhow!("the agent did not start"))?;
        AgentClient::connect(ours).add_identity(key, &[]).await?;
        sealed.store(true, Ordering::SeqCst);
        Ok(Arc::new(Self { streams: tx }))
    }

    /// Answers agent requests arriving on a channel the server opened.
    pub fn serve(&self, channel: Channel<Msg>) {
        let (ours, theirs) = tokio::io::duplex(Self::BUFFER);
        if self.streams.send(Ok(theirs)).is_err() {
            return;
        }
        tokio::spawn(async move {
            let mut ours = ours;
            let mut remote = channel.into_stream();
            let _ = tokio::io::copy_bidirectional(&mut remote, &mut ours).await;
        });
    }

    fn incoming(rx: mpsc::UnboundedReceiver<std::io::Result<DuplexStream>>) -> impl Stream<Item = std::io::Result<DuplexStream>> + Unpin {
        Box::pin(stream::unfold(rx, |mut rx| async move { rx.recv().await.map(|s| (s, rx)) }))
    }
}
