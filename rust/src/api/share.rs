//! Sharing with a paired computer. See [`crate::engine::share`].

use std::sync::Arc;

use flutter_rust_bridge::frb;
use multiplex_proto::share as proto;

use super::ssh::SshSession;
use super::watch::RemoteWatch;
use crate::engine::runtime::AsyncRuntime;
use crate::engine::share;
use crate::frb_generated::StreamSink;

/// Something the computer tells a connected phone.
#[derive(Debug, Clone)]
pub enum ShareEvent {
    /// A file is waiting for the phone (sent with `multiplex send`).
    File {
        id: String,
        name: String,
        size: u64,
        /// Where it is on the computer, for SFTP.
        path: String,
    },
    /// The computer's clipboard now holds this text.
    Clip { text: String },
    /// Someone at the computer is looking for the phone: ring, loudly, for
    /// at most this long.
    Ring { seconds: u32 },
    /// Send this text message from the phone (number and words already
    /// checked).
    Sms { to: String, text: String },
    /// A coding agent on the computer now waits for an answer
    /// (`waiting`), or has finished.
    Agent { name: String, title: String, workspace: String, waiting: bool },
    /// Someone at the computer asks the phone's owner to approve
    /// something (`reason`). Answer with [`SshSession::share_approved`].
    Approve { id: String, reason: String, challenge: String },
}

impl SshSession {
    /// The folder on the computer that files from the phone go to.
    pub async fn share_inbox(&self) -> anyhow::Result<String> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { share::inbox(&conn).await }).await?
    }

    /// Tells the computer which files arrived, so it can say so on screen.
    pub async fn share_received(&self, phone: String, names: Vec<String>) -> anyhow::Result<()> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { share::received(&conn, &phone, &names).await }).await?
    }

    /// Puts text on the computer's clipboard.
    pub async fn share_copy(&self, text: String) -> anyhow::Result<()> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { share::copy(&conn, &text).await }).await?
    }

    /// The text on the computer's clipboard, if it holds text.
    pub async fn share_paste(&self) -> anyhow::Result<Option<String>> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { share::paste(&conn).await }).await?
    }

    /// Opens a web link in the computer's browser.
    pub async fn share_open(&self, url: String) -> anyhow::Result<()> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { share::open(&conn, &url).await }).await?
    }

    /// The phone has a waiting file now: the computer forgets it.
    pub async fn share_done(&self, id: String) -> anyhow::Result<()> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { share::done(&conn, &id).await }).await?
    }

    /// Tells the computer the phone's battery level (0 to 100) and whether
    /// it is charging. `phone` is the name it paired under.
    pub async fn phone_status(&self, phone: String, battery: u8, charging: bool) -> anyhow::Result<()> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { share::status(&conn, &phone, &proto::PhoneStatus { battery, charging }).await }).await?
    }

    /// Shows one of the phone's notifications on the computer's screen.
    pub async fn phone_notice(&self, phone: String, app: String, title: String, text: String) -> anyhow::Result<()> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { share::notice(&conn, &phone, &proto::PhoneNotice { app, title, text }).await }).await?
    }

    /// A call on the phone began or ended: the computer pauses what is
    /// playing, and carries on with it afterwards.
    pub async fn phone_call(&self, phone: String, active: bool) -> anyhow::Result<()> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { share::call(&conn, &phone, active).await }).await?
    }

    /// Answers an approval the computer asked for: `answer` is what
    /// [`approval_sign`] made, or "no".
    pub async fn share_approved(&self, id: String, answer: String) -> anyhow::Result<()> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { share::approved(&conn, &id, &answer).await }).await?
    }

    /// Hears what the computer has for this phone: files waiting (also
    /// ones sent while the phone was away) and clipboard changes. `phone`
    /// is the name this phone paired under; empty when it is the only one.
    pub async fn share_link(&self, phone: String) -> anyhow::Result<ShareLink> {
        let conn = self.conn.clone();
        let inner = AsyncRuntime::run(RemoteWatch::start(conn, proto::link_command(&phone))).await??;
        Ok(ShareLink { inner })
    }
}

/// Signs an approval request with the phone's own key (its OpenSSH
/// private key). Only call this after the owner has confirmed with a
/// fingerprint: the signature is the "yes".
#[frb(sync)]
pub fn approval_sign(private_key: String, id: String, reason: String, challenge: String) -> anyhow::Result<String> {
    share::approval_signature(&private_key, &id, &reason, &challenge)
}

/// Whether text is a web link the computer would open.
#[frb(sync)]
pub fn share_is_link(text: String) -> bool {
    proto::clean_url(&text).is_ok()
}

/// What the computer has for this phone, as it comes.
#[frb(opaque)]
pub struct ShareLink {
    inner: RemoteWatch,
}

impl ShareLink {
    /// Listen once.
    pub fn events(&self, sink: StreamSink<ShareEvent>) {
        self.inner.lines.attach(Arc::new(move |line: String| match proto::parse_link_event(&line) {
            Ok(proto::LinkEvent::File(file)) => sink.add(ShareEvent::File { id: file.id, name: proto::clean_file_name(&file.name), size: file.size, path: file.path }).is_ok(),
            Ok(proto::LinkEvent::Clip { text }) => sink.add(ShareEvent::Clip { text }).is_ok(),
            Ok(proto::LinkEvent::Ring { seconds }) => sink.add(ShareEvent::Ring { seconds: seconds.min(120) }).is_ok(),
            // Checked again here: what reaches the phone's messaging is exact.
            Ok(proto::LinkEvent::Sms { to, text }) => match (proto::clean_phone_number(&to), proto::clean_sms_text(&text)) {
                (Ok(to), Ok(text)) => sink.add(ShareEvent::Sms { to, text }).is_ok(),
                _ => true,
            },
            Ok(proto::LinkEvent::Agent(agent)) => {
                let waiting = agent.status == multiplex_proto::agents::AgentStatus::Blocked;
                sink.add(ShareEvent::Agent { name: agent.name, title: agent.title, workspace: agent.workspace, waiting }).is_ok()
            }
            // The reason is shown to the owner: one tidy line.
            Ok(proto::LinkEvent::Approve { id, reason, challenge }) => match (proto::clean_id(&id), proto::clean_reason(&reason)) {
                (Ok(id), Ok(reason)) => sink.add(ShareEvent::Approve { id, reason, challenge }).is_ok(),
                _ => true,
            },
            // Not an event (a notice from the shell, say): keep listening.
            Err(_) => true,
        }));
    }

    #[frb(sync)]
    pub fn stop(&self) {
        self.inner.stop();
    }
}
