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

    /// Hears what the computer has for this phone: files waiting (also
    /// ones sent while the phone was away) and clipboard changes. `phone`
    /// is the name this phone paired under; empty when it is the only one.
    pub async fn share_link(&self, phone: String) -> anyhow::Result<ShareLink> {
        let conn = self.conn.clone();
        let inner = AsyncRuntime::run(RemoteWatch::start(conn, proto::link_command(&phone))).await??;
        Ok(ShareLink { inner })
    }
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
            // Not an event (a notice from the shell, say): keep listening.
            Err(_) => true,
        }));
    }

    #[frb(sync)]
    pub fn stop(&self) {
        self.inner.stop();
    }
}
