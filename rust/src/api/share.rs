//! Sharing with a paired computer. See [`crate::engine::share`].

use std::sync::Arc;

use flutter_rust_bridge::frb;
use multiplex_proto::share as proto;

use super::herd_types::{tidy_asked, HerdAsked};
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
    /// The computer's clipboard now holds a picture; `mark` names exactly
    /// that picture. It is fetched with `share_paste_picture`.
    Picture { kind: String, size: u64, mark: String },
    /// Someone at the computer is looking for the phone: ring, loudly, for
    /// at most this long.
    Ring { seconds: u32 },
    /// Send this text message from the phone (number and words already
    /// checked).
    Sms { to: String, text: String },
    /// A coding agent on the computer now waits for an answer
    /// (`waiting`), or has finished. `session` and `pane` say where it
    /// is (empty when the computer's word for them was not in order);
    /// `asked` is its question and choices when it waits on a choice.
    Agent { name: String, title: String, workspace: String, waiting: bool, session: String, pane: String, asked: Option<HerdAsked> },
    /// That agent no longer waits and is no longer just done: what was
    /// shown about it can go.
    Settled { session: String, pane: String },
    /// Someone at the computer asks the phone's owner to approve
    /// something (`reason`). Answer with [`SshSession::share_approved`].
    Approve { id: String, reason: String, challenge: String },
    /// The computer's SSH agent asks the phone to sign with its key.
    /// [`signing_describe`] says what for; answer with
    /// [`SshSession::share_approved`] and what [`signing_sign`] made.
    Sign { id: String, data: String },
    /// The computer (an agent there) wants the phone to be keyboard and
    /// mouse of the device it is connected to: `keys` is keyboard
    /// reports of 8 bytes each, `pointer` mouse reports of 3 bytes each
    /// (already checked to be whole); with `look`, a picture from the
    /// camera is wanted back. Answer with [`SshSession::share_approved`]:
    /// "ok", the picture's place, or "no: " and why.
    Hands { id: String, keys: Vec<u8>, pointer: Vec<u8>, look: bool },
}

/// A picture from a clipboard.
pub struct ClipPictureData {
    /// `png`, `jpeg`, `webp` or `gif`.
    pub kind: String,
    pub bytes: Vec<u8>,
}

/// A short name for exactly this picture: the same on both sides, so a
/// picture that was just received is not sent straight back.
#[frb(sync)]
pub fn share_picture_mark(picture: Vec<u8>) -> String {
    proto::picture_mark(&picture)
}

/// The text a computer read in a picture.
pub struct TextFound {
    /// Empty: none could be read.
    pub text: String,
    /// The languages the computer reads (tesseract's names, such as `eng`).
    pub languages: Vec<String>,
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

    /// The picture on the computer's clipboard, if it holds one.
    pub async fn share_paste_picture(&self) -> anyhow::Result<Option<ClipPictureData>> {
        let conn = self.conn.clone();
        let picture = AsyncRuntime::run(async move { share::paste_picture(&conn).await }).await??;
        Ok(picture.map(|(kind, bytes)| ClipPictureData { kind, bytes }))
    }

    /// Puts a picture (`kind`: `png`, `jpeg`, `webp` or `gif`) on the
    /// computer's clipboard.
    pub async fn share_copy_picture(&self, kind: String, picture: Vec<u8>) -> anyhow::Result<()> {
        let conn = self.conn.clone();
        AsyncRuntime::run(async move { share::copy_picture(&conn, &kind, &picture).await }).await?
    }

    /// Has the computer read the text in a picture (a JPEG or PNG) and
    /// put it on its clipboard.
    pub async fn share_read_text(&self, picture: Vec<u8>) -> anyhow::Result<TextFound> {
        let conn = self.conn.clone();
        let read = AsyncRuntime::run(async move { share::read_text(&conn, &picture).await }).await??;
        Ok(TextFound { text: read.text, languages: read.languages })
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

/// What a signing request from the computer's SSH agent is for, as a
/// line for the fingerprint prompt: a login as some user, or an SSH
/// signature. `None` when it is neither; it must then be refused.
#[frb(sync)]
pub fn signing_describe(private_key: String, data: String) -> Option<String> {
    share::signing_request(&private_key, &data)
}

/// Signs such a request with the phone's key. Only after the owner has
/// confirmed with a fingerprint. Refuses what [`signing_describe`] would
/// not describe.
#[frb(sync)]
pub fn signing_sign(private_key: String, data: String) -> anyhow::Result<String> {
    share::signing_signature(&private_key, &data)
}

/// Whether text is a web link the computer would open.
#[frb(sync)]
pub fn share_is_link(text: String) -> bool {
    proto::clean_url(&text).is_ok()
}

/// News of an agent as the app takes it: where the agent is and what it
/// asks are checked, and left out when they are not in order, so that
/// the owner still hears of it but nothing can be answered blindly.
fn agent_event(agent: multiplex_proto::agents::Agent) -> ShareEvent {
    let waiting = agent.status == multiplex_proto::agents::AgentStatus::Blocked;
    let place = multiplex_proto::agents::clean_session_name(&agent.session).ok().zip(multiplex_proto::herd::clean_pane_id(&agent.id).ok());
    let asked = place.as_ref().filter(|_| waiting).and_then(|_| tidy_asked(&agent.question, &agent.choices, &agent.mark));
    let (session, pane) = place.unwrap_or_default();
    ShareEvent::Agent { name: agent.name, title: agent.title, workspace: agent.workspace, waiting, session, pane, asked }
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
            Ok(proto::LinkEvent::Picture { kind, size, mark }) => {
                // Only kinds that are shared, and of a size a clipboard takes.
                if proto::picture_mime(&kind).is_some() && size <= proto::MAX_CLIP_PICTURE as u64 && mark.len() <= 64 {
                    sink.add(ShareEvent::Picture { kind, size, mark }).is_ok()
                } else {
                    true
                }
            }
            Ok(proto::LinkEvent::Ring { seconds }) => sink.add(ShareEvent::Ring { seconds: seconds.min(120) }).is_ok(),
            // Checked again here: what reaches the phone's messaging is exact.
            Ok(proto::LinkEvent::Sms { to, text }) => match (proto::clean_phone_number(&to), proto::clean_sms_text(&text)) {
                (Ok(to), Ok(text)) => sink.add(ShareEvent::Sms { to, text }).is_ok(),
                _ => true,
            },
            Ok(proto::LinkEvent::Agent(agent)) => sink.add(agent_event(agent)).is_ok(),
            Ok(proto::LinkEvent::Settled { session, pane }) => match (multiplex_proto::agents::clean_session_name(&session), multiplex_proto::herd::clean_pane_id(&pane)) {
                (Ok(session), Ok(pane)) => sink.add(ShareEvent::Settled { session, pane }).is_ok(),
                _ => true,
            },
            // The reason is shown to the owner: one tidy line.
            Ok(proto::LinkEvent::Approve { id, reason, challenge }) => match (proto::clean_id(&id), proto::clean_reason(&reason)) {
                (Ok(id), Ok(reason)) => sink.add(ShareEvent::Approve { id, reason, challenge }).is_ok(),
                _ => true,
            },
            Ok(proto::LinkEvent::Sign { id, data }) => match proto::clean_id(&id) {
                Ok(id) if data.len() <= multiplex_proto::sign::MAX_SIGN * 2 => sink.add(ShareEvent::Sign { id, data }).is_ok(),
                _ => true,
            },
            Ok(proto::LinkEvent::Hands { id, keys, pointer, look }) => {
                match (proto::clean_id(&id), multiplex_proto::hid::from_hex::<8>(&keys), multiplex_proto::hid::from_hex::<3>(&pointer)) {
                    (Ok(id), Ok(keys), Ok(pointer)) => sink.add(ShareEvent::Hands { id, keys: keys.concat(), pointer: pointer.concat(), look }).is_ok(),
                    _ => true,
                }
            }
            // Not an event (a notice from the shell, say): keep listening.
            Err(_) => true,
        }));
    }

    #[frb(sync)]
    pub fn stop(&self) {
        self.inner.stop();
    }
}
