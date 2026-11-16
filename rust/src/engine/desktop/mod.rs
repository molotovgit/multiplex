//! Remote desktop: a gliff session carried on our own SSH connection.
//!
//! The remote runs `gliff-server --stdio`; its stdin and stdout are the
//! protocol, so the whole session is one SSH exec channel (no terminal).
//! The server encodes the screen as H.264 and we send mouse, keyboard and
//! clipboard input back.
//!
//! Three things run per session:
//! - the reader takes server messages: video goes straight to the video
//!   decoder (never through Flutter), the rest becomes [`DesktopEvent`]s;
//! - the writer sends input, acks and pings, in the order they happened;
//! - the decoder (see [`video`]) reports each picture it put on screen, and
//!   that report becomes the frame ack the server paces its stream by.
//!
//! The app never waits on the network: input calls only queue a message.

pub mod h264;
pub mod video;

#[cfg(target_os = "android")]
pub mod android;

use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use gliff_proto::clipboard::{is_text_mime, CHUNK, TEXT_MIMES};
use gliff_proto::{
    is_incompatible, version_mismatch, Axis, ChromaMode, ClientCaps, ClientMsg, ClipboardItem, Codec, ServerMsg,
    VideoPipeline, PROTOCOL_VERSION,
};
use gliff_transport::Framed;
use tokio::io::{ReadHalf, WriteHalf};
use tokio::sync::mpsc;

use self::video::{EncodedFrame, VideoReport, VideoSink};
use crate::api::desktop_types::{DesktopEvent, DesktopMode, DesktopOptions, DesktopOutput, DesktopStats};
use crate::engine::events::SharedSink;
use crate::engine::runtime::AsyncRuntime;
use crate::engine::ssh::Connection;

/// The longest text we take from the remote clipboard.
const MAX_CLIPBOARD_TEXT: u64 = 4 * 1024 * 1024;
/// The largest stream we accept (4K); the resolution setting picks below it.
const MAX_STREAM: (u32, u32) = (3840, 2160);
/// How often we measure the round trip.
const PING_EVERY: Duration = Duration::from_secs(1);
/// With the radio kept warm: a tiny ping this often. Mobile radios sleep
/// (DRX) after a few tens of milliseconds without traffic and the next
/// packet then waits for them to wake (often 10-40 ms); a steady trickle
/// keeps them awake, as cloud-gaming clients do. With every header
/// (SSH, TCP, WireGuard) about 130 kbit/s in all, ~60 MB an hour.
const WARM_PING_EVERY: Duration = Duration::from_millis(15);
/// No answer to our pings for this long means the link is dead (for
/// example a network switch left a connection that looks open).
const SILENCE_LIMIT: Duration = Duration::from_secs(6);
/// How long the server may take to answer our hello.
const HELLO_TIMEOUT: Duration = Duration::from_secs(20);

type Reader = Framed<ReadHalf<russh::ChannelStream<russh::client::Msg>>>;
type Writer = Framed<WriteHalf<russh::ChannelStream<russh::client::Msg>>>;

/// Work for the writer task.
enum Outgoing {
    Msg(ClientMsg),
    /// Clipboard bytes for a request the server made.
    ClipboardData { id: u32, data: Vec<u8> },
    Close,
}

/// State shared by the app-facing handle and the background tasks.
struct Shared {
    closed: AtomicBool,
    events: SharedSink<DesktopEvent>,
    /// Our clipboard offers count up from here.
    clip_serial: AtomicU32,
    /// Our clipboard requests use odd ids (the server's are even).
    next_request: AtomicU32,
    /// The text we last offered, served when the server asks for it.
    offered_text: std::sync::Mutex<Option<(u32, String)>>,
}

impl Shared {
    /// Sends `Ended` once, however many tasks notice the end.
    fn end(&self, reason: impl Into<String>, retryable: bool) {
        if !self.closed.swap(true, Ordering::SeqCst) {
            self.events.emit(DesktopEvent::Ended { reason: reason.into(), retryable });
        }
    }
}

/// A running remote desktop.
pub struct DesktopSession {
    tx: mpsc::UnboundedSender<Outgoing>,
    shared: Arc<Shared>,
}

impl DesktopSession {
    /// Starts gliff-server on the remote and the tasks that serve it.
    /// `video` receives the encoded pictures; `reports` is where it says
    /// what it did with them.
    pub async fn open(
        conn: &Connection,
        options: DesktopOptions,
        events: SharedSink<DesktopEvent>,
        video: Box<dyn VideoSink>,
        reports: mpsc::UnboundedReceiver<VideoReport>,
    ) -> anyhow::Result<Self> {
        let command = Self::command(&options);
        let channel = conn.handle().channel_open_session().await?;
        channel.exec(true, command.as_bytes()).await?;
        let (read, write) = tokio::io::split(channel.into_stream());
        let mut reader: Reader = Framed::new(read);
        let mut writer: Writer = Framed::new(write);

        let width = options.width.max(320);
        let height = options.height.max(240);
        writer
            .write_msg(&ClientMsg::Hello {
                version: PROTOCOL_VERSION,
                // Empty means the server's default (US) layout; the app
                // sends US key codes.
                keymap: String::new(),
                caps: ClientCaps {
                    codecs: vec![Codec::H264],
                    // The ceiling; the size actually streamed is what
                    // Resize asks for (the resolution setting).
                    max_width: MAX_STREAM.0.max(width),
                    max_height: MAX_STREAM.1.max(height),
                    // Phones decode one ordinary 4:2:0 stream in hardware.
                    chroma: vec![ChromaMode::Single420],
                    features: gliff_proto::features(),
                },
            })
            .await?;

        let started = match tokio::time::timeout(HELLO_TIMEOUT, Self::await_hello(&mut reader, &mut writer)).await {
            Ok(Ok(started)) => started,
            Ok(Err(err)) => return Err(Self::explain(conn, err).await),
            Err(_) => anyhow::bail!("The desktop did not answer in time."),
        };

        // Size the stream (and a fitted screen) to the phone right away.
        writer
            .write_msg(&ClientMsg::Resize { width, height, scale: options.scale.clamp(0.5, 4.0) as f32 })
            .await?;

        let shared = Arc::new(Shared {
            closed: AtomicBool::new(false),
            events,
            clip_serial: AtomicU32::new(1),
            next_request: AtomicU32::new(1),
            offered_text: std::sync::Mutex::new(None),
        });
        shared.events.emit(started);

        let (tx, rx) = mpsc::unbounded_channel();
        let video: Arc<dyn VideoSink> = Arc::from(video);
        let stats = Arc::new(StatsCounter::default());
        AsyncRuntime::spawn(Self::write_loop(writer, rx, shared.clone()));
        AsyncRuntime::spawn(Self::read_loop(reader, tx.clone(), shared.clone(), video.clone(), stats.clone()));
        AsyncRuntime::spawn(Self::report_loop(reports, tx.clone(), shared.clone(), stats.clone()));
        AsyncRuntime::spawn(Self::tick_loop(tx.clone(), shared.clone(), stats, video, options.warm_radio));
        Ok(Self { tx, shared })
    }

    /// The remote command line for these options.
    fn command(options: &DesktopOptions) -> String {
        let program = options.server_command.trim();
        let program = if program.is_empty() { "gliff-server" } else { program };
        let mut command = format!("{program} --stdio");
        match &options.mode {
            DesktopMode::Fitted => command.push_str(" --headless"),
            DesktopMode::Mirror => command.push_str(" --output auto"),
            DesktopMode::Output { name } => {
                // Monitor names are short words like DP-1; anything else is
                // refused rather than quoted.
                let safe = !name.is_empty() && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
                command.push_str(if safe { " --output " } else { " --output auto" });
                if safe {
                    command.push_str(name);
                }
            }
        }
        if options.low_bandwidth {
            command.push_str(" --low-bandwidth");
        }
        command
    }

    /// Waits for the server's welcome, answering its pings meanwhile.
    async fn await_hello(reader: &mut Reader, writer: &mut Writer) -> anyhow::Result<DesktopEvent> {
        loop {
            match reader.read_msg::<ServerMsg>().await? {
                ServerMsg::HelloAck { version, session, outputs, .. } => {
                    if version != PROTOCOL_VERSION {
                        anyhow::bail!("{}", version_mismatch(PROTOCOL_VERSION, version));
                    }
                    return Ok(DesktopEvent::Started {
                        fitted: session.headless,
                        output: session.output,
                        outputs: outputs
                            .into_iter()
                            .map(|o| DesktopOutput {
                                name: o.name,
                                width: o.width,
                                height: o.height,
                                scale: f64::from(o.scale_milli) / 1000.0,
                            })
                            .collect(),
                    });
                }
                ServerMsg::Ping { t } => writer.write_msg(&ClientMsg::Pong { t }).await?,
                ServerMsg::Error { code, message, .. } if is_incompatible(code) => {
                    anyhow::bail!("This gliff version does not work with Multiplex: {message}")
                }
                ServerMsg::Error { message, .. } => anyhow::bail!("{message}"),
                _ => {}
            }
        }
    }

    /// Turns "the stream closed during the hello" into the likely cause.
    async fn explain(conn: &Connection, err: anyhow::Error) -> anyhow::Error {
        let closed = err
            .downcast_ref::<gliff_transport::Error>()
            .is_some_and(|e| matches!(e, gliff_transport::Error::Closed | gliff_transport::Error::Io(_)));
        if !closed {
            return err;
        }
        let check = "command -v gliff-server >/dev/null 2>&1 && echo found; \
                     [ -n \"$(ls ${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr 2>/dev/null)\" ] && echo hypr";
        match conn.exec(check, 256).await {
            Ok(out) if !out.stdout.contains("found") => {
                anyhow::anyhow!("gliff is not installed on this machine. On Omarchy: sudo pacman -S gliff")
            }
            Ok(out) if !out.stdout.contains("hypr") => {
                anyhow::anyhow!("No Hyprland session is running on this machine. Log in to the desktop first.")
            }
            _ => anyhow::anyhow!("The desktop closed the connection while starting."),
        }
    }

    // ----- input (all of these only queue a message) -----

    fn send(&self, msg: ClientMsg) {
        if !self.shared.closed.load(Ordering::Relaxed) {
            let _ = self.tx.send(Outgoing::Msg(msg));
        }
    }

    /// Moves the pointer to `x`, `y` in logical remote pixels.
    pub fn pointer_move(&self, x: f64, y: f64) {
        self.send(ClientMsg::PointerMotion { x, y });
    }

    pub fn pointer_button(&self, code: u32, pressed: bool) {
        self.send(ClientMsg::PointerButton { button: code, pressed });
    }

    /// Scrolls by `dx`, `dy` logical pixels. `wheel` sends whole wheel
    /// steps (one step = 15 px), as a mouse wheel would.
    pub fn scroll(&self, dx: f64, dy: f64, wheel: bool) {
        for (axis, value) in [(Axis::Vertical, dy), (Axis::Horizontal, dx)] {
            if value == 0.0 {
                continue;
            }
            let discrete = wheel.then_some(if value > 0.0 { 1 } else { -1 });
            self.send(ClientMsg::PointerAxis { axis, value, discrete, stop: false });
        }
    }

    /// Ends a finger scroll so kinetic scrolling on the remote stops.
    pub fn scroll_stop(&self) {
        for axis in [Axis::Vertical, Axis::Horizontal] {
            self.send(ClientMsg::PointerAxis { axis, value: 0.0, discrete: None, stop: true });
        }
    }

    /// Presses or releases a key (Linux input code, US layout).
    pub fn key(&self, code: u32, pressed: bool) {
        self.send(ClientMsg::Key { keycode: code, pressed });
    }

    /// New view size (rotation, split screen) or text size.
    pub fn resize(&self, width: u32, height: u32, scale: f64) {
        self.send(ClientMsg::Resize {
            width: width.max(320),
            height: height.max(240),
            scale: scale.clamp(0.5, 4.0) as f32,
        });
    }

    /// Asks for a full picture, for example after the view was rebuilt.
    pub fn request_keyframe(&self) {
        self.send(ClientMsg::RequestKeyframe);
    }

    /// Puts `text` on the remote clipboard (served when something there
    /// pastes).
    pub fn set_clipboard(&self, text: String) {
        let serial = self.shared.clip_serial.fetch_add(1, Ordering::SeqCst);
        *self.shared.offered_text.lock().unwrap_or_else(|p| p.into_inner()) = Some((serial, text));
        self.send(ClientMsg::ClipboardOffer {
            serial,
            mime_types: TEXT_MIMES.iter().map(|m| (*m).to_owned()).collect(),
            files: Vec::new(),
        });
    }

    pub fn is_closed(&self) -> bool {
        self.shared.closed.load(Ordering::Relaxed)
    }

    /// Ends the session; the remote's fitted screen goes away with it.
    pub fn close(&self) {
        let _ = self.tx.send(Outgoing::Msg(ClientMsg::Bye));
        let _ = self.tx.send(Outgoing::Close);
        self.shared.end("Disconnected.", false);
    }

    // ----- background tasks -----

    async fn write_loop(mut writer: Writer, mut rx: mpsc::UnboundedReceiver<Outgoing>, shared: Arc<Shared>) {
        while let Some(job) = rx.recv().await {
            let result = match job {
                Outgoing::Msg(msg) => writer.write_msg(&msg).await,
                Outgoing::ClipboardData { id, data } => Self::write_clipboard(&mut writer, id, &data).await,
                Outgoing::Close => break,
            };
            if result.is_err() {
                shared.end("The connection to the desktop was lost.", true);
                break;
            }
        }
        let _ = writer.into_inner().shutdown_quietly().await;
    }

    /// Sends clipboard text in protocol-sized chunks. Text is small, so the
    /// ack window never fills in practice; the server buffers it.
    async fn write_clipboard(writer: &mut Writer, id: u32, data: &[u8]) -> gliff_transport::Result<()> {
        let mut offset = 0usize;
        loop {
            let end = (offset + CHUNK).min(data.len());
            let chunk = &data[offset..end];
            let done = end == data.len();
            let msg = ClientMsg::ClipboardData { id, offset: offset as u64, data_len: chunk.len() as u32, done };
            writer.write_msg_with_payloads(&msg, &[chunk]).await?;
            if done {
                return Ok(());
            }
            offset = end;
        }
    }

    async fn read_loop(
        mut reader: Reader,
        tx: mpsc::UnboundedSender<Outgoing>,
        shared: Arc<Shared>,
        video: Arc<dyn VideoSink>,
        stats: Arc<StatsCounter>,
    ) {
        let mut incoming = IncomingClipboard::default();
        loop {
            let msg = match reader.read_msg::<ServerMsg>().await {
                Ok(msg) => msg,
                Err(_) => {
                    shared.end("The connection to the desktop was lost.", true);
                    break;
                }
            };
            let ok = match msg {
                ServerMsg::VideoFrame { frame_id, pts_us, keyframe, data_len, .. } => match reader.read_payload(data_len).await {
                    Ok(data) => {
                        stats.note_sent(frame_id, pts_us / 1000);
                        stats.bytes.fetch_add(u64::from(data_len), Ordering::Relaxed);
                        video.submit(EncodedFrame { id: frame_id, keyframe, data, arrived: Instant::now() });
                        true
                    }
                    Err(_) => false,
                },
                ServerMsg::StreamConfig { width, height, scale_milli, pipeline, .. } => {
                    video.configure(width, height);
                    shared.events.emit(DesktopEvent::Stream {
                        width,
                        height,
                        scale: f64::from(scale_milli.max(1)) / 1000.0,
                        hardware: pipeline == Some(VideoPipeline::Gpu),
                    });
                    true
                }
                ServerMsg::CursorShape { id, width, height, hot_x, hot_y, argb_len } => match reader.read_payload(argb_len).await {
                    Ok(bgra) => {
                        shared.events.emit(DesktopEvent::CursorShape { id, width, height, hot_x, hot_y, bgra: bgra.to_vec() });
                        true
                    }
                    Err(_) => false,
                },
                ServerMsg::CursorPos { x, y, shape_id, visible } => {
                    shared.events.emit(DesktopEvent::CursorMoved { x, y, shape_id, visible });
                    true
                }
                ServerMsg::Ping { t } => tx.send(Outgoing::Msg(ClientMsg::Pong { t })).is_ok(),
                ServerMsg::Pong { t, server_now_ms } => {
                    let rtt = now_ms().saturating_sub(t);
                    stats.rtt_ms.store(rtt as u32, Ordering::Relaxed);
                    stats.rtts.lock().unwrap_or_else(|p| p.into_inner()).push(rtt as u32);
                    stats.note_clock(t, server_now_ms, now_ms());
                    stats.last_pong_ms.store(now_ms(), Ordering::Relaxed);
                    true
                }
                ServerMsg::ClipboardOffer { serial, mime_types, .. } => {
                    // Text is taken right away so it lands on the phone's
                    // clipboard; anything else (images, files) is left.
                    if let Some(mime) = mime_types.iter().find(|m| is_text_mime(m)) {
                        let id = shared.next_request.fetch_add(2, Ordering::SeqCst);
                        incoming.start(id);
                        let _ = tx.send(Outgoing::Msg(ClientMsg::ClipboardRequest {
                            id,
                            serial,
                            item: ClipboardItem::Mime(mime.clone()),
                        }));
                    }
                    true
                }
                ServerMsg::ClipboardData { id, data_len, done, .. } => match reader.read_payload(data_len).await {
                    Ok(chunk) => {
                        if let Some(text) = incoming.accept(id, &chunk, done, &tx) {
                            shared.events.emit(DesktopEvent::Clipboard { text });
                        }
                        true
                    }
                    Err(_) => false,
                },
                ServerMsg::ClipboardRequest { id, serial, item } => {
                    let offered = shared.offered_text.lock().unwrap_or_else(|p| p.into_inner()).clone();
                    match (offered, item) {
                        (Some((s, text)), ClipboardItem::Mime(_)) if s == serial => {
                            let _ = tx.send(Outgoing::ClipboardData { id, data: text.into_bytes() });
                        }
                        _ => {
                            let _ = tx.send(Outgoing::Msg(ClientMsg::ClipboardAbort { id }));
                        }
                    }
                    true
                }
                ServerMsg::ClipboardAbort { id } => {
                    incoming.abort(id);
                    true
                }
                ServerMsg::Error { code, message, .. } => {
                    let retryable = !is_incompatible(code);
                    shared.end(if message.is_empty() { format!("The desktop stopped (error {code}).") } else { message }, retryable);
                    false
                }
                // HelloAck again, ClipboardAck, and messages from newer
                // servers: nothing to do.
                _ => true,
            };
            if !ok {
                shared.end("The connection to the desktop was lost.", true);
                break;
            }
            if shared.closed.load(Ordering::Relaxed) {
                break;
            }
        }
        video.close();
        let _ = tx.send(Outgoing::Close);
    }

    /// Turns decoder reports into frame acks and keyframe requests.
    async fn report_loop(
        mut reports: mpsc::UnboundedReceiver<VideoReport>,
        tx: mpsc::UnboundedSender<Outgoing>,
        shared: Arc<Shared>,
        stats: Arc<StatsCounter>,
    ) {
        while let Some(report) = reports.recv().await {
            if shared.closed.load(Ordering::Relaxed) {
                break;
            }
            let msg = match report {
                VideoReport::Shown { id, latency } => {
                    stats.note_shown(id, now_ms());
                    stats.frames.fetch_add(1, Ordering::Relaxed);
                    stats.latency_us.fetch_add(latency.as_micros() as u64, Ordering::Relaxed);
                    ClientMsg::FrameAck { frame_id: id, decoded_at_ms: now_ms() }
                }
                // A frame that was not shown is still acked, or the
                // server would wait for it and stall.
                VideoReport::Skipped { id } => ClientMsg::FrameAck { frame_id: id, decoded_at_ms: now_ms() },
                VideoReport::NeedKeyframe => ClientMsg::RequestKeyframe,
                VideoReport::Picture { width, height, visible_width, visible_height } => {
                    shared.events.emit(DesktopEvent::Picture { width, height, visible_width, visible_height });
                    continue;
                }
            };
            if tx.send(Outgoing::Msg(msg)).is_err() {
                break;
            }
        }
    }

    /// Pings for the round trip and publishes stats once a second.
    async fn tick_loop(tx: mpsc::UnboundedSender<Outgoing>, shared: Arc<Shared>, stats: Arc<StatsCounter>, video: Arc<dyn VideoSink>, warm: bool) {
        let mut tick = tokio::time::interval(if warm { WARM_PING_EVERY } else { PING_EVERY });
        tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        let mut last = Instant::now();
        stats.last_pong_ms.store(now_ms(), Ordering::Relaxed);
        loop {
            tick.tick().await;
            if shared.closed.load(Ordering::Relaxed) {
                video.close();
                break;
            }
            let silent = now_ms().saturating_sub(stats.last_pong_ms.load(Ordering::Relaxed));
            if silent > SILENCE_LIMIT.as_millis() as u64 {
                shared.end("The connection to the desktop stopped answering.", true);
                video.close();
                let _ = tx.send(Outgoing::Close);
                break;
            }
            if tx.send(Outgoing::Msg(ClientMsg::Ping { t: now_ms() })).is_err() {
                break;
            }
            // Stats once a second, however often we ping.
            if last.elapsed() >= Duration::from_millis(990) {
                let secs = last.elapsed().as_secs_f64().max(0.001);
                last = Instant::now();
                shared.events.emit(DesktopEvent::Stats(stats.take(secs)));
            }
        }
    }
}

impl Drop for DesktopSession {
    fn drop(&mut self) {
        self.close();
    }
}

/// Counters the tasks bump and the ticker turns into [`DesktopStats`].
#[derive(Default)]
struct StatsCounter {
    frames: std::sync::atomic::AtomicU64,
    bytes: std::sync::atomic::AtomicU64,
    latency_us: std::sync::atomic::AtomicU64,
    rtt_ms: AtomicU32,
    /// This second's ping round trips.
    rtts: std::sync::Mutex<Vec<u32>>,
    /// Server clock minus ours, from the ping with the shortest round
    /// trip: (offset ms, that round trip).
    clock: std::sync::Mutex<Option<(i64, u64)>>,
    /// When the server sent each frame still on its way (server clock).
    sent: std::sync::Mutex<std::collections::VecDeque<(u64, u64)>>,
    /// Sum and count of frame ages (server send to on screen) this second.
    ages: std::sync::Mutex<(f64, u32)>,
    /// When the server last answered a ping (wall clock, ms).
    last_pong_ms: std::sync::atomic::AtomicU64,
}

impl StatsCounter {
    fn note_sent(&self, id: u64, server_ms: u64) {
        let mut sent = self.sent.lock().unwrap_or_else(|p| p.into_inner());
        if sent.len() >= 256 {
            sent.pop_front();
        }
        sent.push_back((id, server_ms));
    }

    /// A pong: the server's clock read at `server_ms`, roughly half way
    /// between our `sent_ms` and `now_ms`. The shortest round trip seen
    /// gives the best offset (NTP's rule), refreshed now and then.
    fn note_clock(&self, sent_ms: u64, server_ms: u64, now_ms: u64) {
        let rtt = now_ms.saturating_sub(sent_ms);
        let offset = server_ms as i64 - (sent_ms + rtt / 2) as i64;
        let mut clock = self.clock.lock().unwrap_or_else(|p| p.into_inner());
        match *clock {
            Some((_, best)) if rtt > best + 2 => *clock = clock.map(|(o, b)| (o, b + 1)), // let a stale best age out
            _ => *clock = Some((offset, rtt)),
        }
    }

    /// The frame is on screen: its age is our clock now minus the server's
    /// send time, translated to our clock.
    fn note_shown(&self, id: u64, now_ms: u64) {
        let Some((offset, _)) = *self.clock.lock().unwrap_or_else(|p| p.into_inner()) else { return };
        let mut sent = self.sent.lock().unwrap_or_else(|p| p.into_inner());
        let Some(pos) = sent.iter().position(|&(fid, _)| fid == id) else { return };
        let (_, server_ms) = sent[pos];
        sent.drain(..=pos);
        let age = now_ms as i64 - (server_ms as i64 - offset);
        if (0..5000).contains(&age) {
            let mut ages = self.ages.lock().unwrap_or_else(|p| p.into_inner());
            ages.0 += age as f64;
            ages.1 += 1;
        }
    }

    fn take(&self, secs: f64) -> DesktopStats {
        let frames = self.frames.swap(0, Ordering::Relaxed);
        let bytes = self.bytes.swap(0, Ordering::Relaxed);
        let latency = self.latency_us.swap(0, Ordering::Relaxed);
        DesktopStats {
            fps: frames as f64 / secs,
            kbps: bytes as f64 * 8.0 / 1000.0 / secs,
            // The median of this second's pings (one sample when not warm).
            rtt_ms: {
                let mut v = std::mem::take(&mut *self.rtts.lock().unwrap_or_else(|p| p.into_inner()));
                if v.is_empty() {
                    f64::from(self.rtt_ms.load(Ordering::Relaxed))
                } else {
                    v.sort_unstable();
                    f64::from(v[v.len() / 2])
                }
            },
            decode_ms: if frames == 0 { 0.0 } else { latency as f64 / frames as f64 / 1000.0 },
            frame_age_ms: {
                let (sum, n) = std::mem::take(&mut *self.ages.lock().unwrap_or_else(|p| p.into_inner()));
                if n == 0 { 0.0 } else { sum / n as f64 }
            },
        }
    }
}

/// The remote clipboard text being received.
#[derive(Default)]
struct IncomingClipboard {
    id: Option<u32>,
    buf: Vec<u8>,
    /// Bytes received since the last ack.
    unacked: u32,
}

impl IncomingClipboard {
    fn start(&mut self, id: u32) {
        self.id = Some(id);
        self.buf.clear();
        self.unacked = 0;
    }

    fn abort(&mut self, id: u32) {
        if self.id == Some(id) {
            self.id = None;
            self.buf.clear();
        }
    }

    /// Adds a chunk; returns the text once the last one arrived.
    fn accept(&mut self, id: u32, chunk: &[u8], done: bool, tx: &mpsc::UnboundedSender<Outgoing>) -> Option<String> {
        if self.id != Some(id) {
            return None;
        }
        if self.buf.len() as u64 + chunk.len() as u64 > MAX_CLIPBOARD_TEXT {
            let _ = tx.send(Outgoing::Msg(ClientMsg::ClipboardAbort { id }));
            self.abort(id);
            return None;
        }
        self.buf.extend_from_slice(chunk);
        self.unacked += 1;
        if self.unacked >= gliff_proto::clipboard::WINDOW / 2 || done {
            self.unacked = 0;
            let _ = tx.send(Outgoing::Msg(ClientMsg::ClipboardAck { id, received: self.buf.len() as u64 }));
        }
        if !done {
            return None;
        }
        self.id = None;
        let text = String::from_utf8_lossy(&std::mem::take(&mut self.buf)).into_owned();
        (!text.is_empty()).then_some(text)
    }
}

fn now_ms() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis() as u64
}

/// `shutdown` that ignores errors (the channel may already be gone).
trait ShutdownQuietly {
    async fn shutdown_quietly(self) -> std::io::Result<()>;
}

impl<W: tokio::io::AsyncWrite + Unpin> ShutdownQuietly for W {
    async fn shutdown_quietly(mut self) -> std::io::Result<()> {
        use tokio::io::AsyncWriteExt;
        self.shutdown().await
    }
}
