//! Android: H.264 decoded by the phone's hardware (MediaCodec) straight
//! onto the surface behind the Flutter texture. No picture ever passes
//! through Dart or Java.
//!
//! The Kotlin side creates the texture and hands its `Surface` to us with
//! [`Java_io_github_molotovgit_multiplex_DesktopVideo_nativeSetSurface`].
//! The surface can be replaced (the app went to the background and came
//! back); the decoder notices, rebuilds itself on the new one and asks the
//! server for a keyframe.
//!
//! MediaCodec objects must stay on one thread, so each session gets its own
//! decoder thread that feeds pictures in and renders them out as soon as
//! they are ready (no frame is ever held back for "smooth" playback).

use std::collections::{HashMap, VecDeque};
use std::sync::mpsc::{self as std_mpsc, RecvTimeoutError, TryRecvError};
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant};

use jni_sys::{jlong, jobject, JNIEnv};
use ndk::media::media_codec::{
    DequeuedInputBufferResult, DequeuedOutputBufferInfoResult, MediaCodec, MediaCodecDirection,
};
use ndk::media::media_format::MediaFormat;
use ndk::native_window::NativeWindow;
use tokio::sync::mpsc;

use super::video::{EncodedFrame, VideoReport, VideoSink};

/// Surfaces by texture id, with a counter that changes whenever one is
/// replaced.
struct Surfaces {
    by_texture: HashMap<i64, NativeWindow>,
    generation: HashMap<i64, u64>,
}

static SURFACES: LazyLock<Mutex<Surfaces>> =
    LazyLock::new(|| Mutex::new(Surfaces { by_texture: HashMap::new(), generation: HashMap::new() }));

fn surface_for(texture: i64) -> (Option<NativeWindow>, u64) {
    let s = SURFACES.lock().unwrap_or_else(|p| p.into_inner());
    (s.by_texture.get(&texture).cloned(), s.generation.get(&texture).copied().unwrap_or(0))
}

/// Called from Kotlin (`DesktopVideo.nativeSetSurface`) when a texture's
/// surface appears, changes or goes away (`surface` is null then).
///
/// # Safety
/// The JVM calls this with a valid `env`, and `surface` is null or an
/// `android.view.Surface`.
#[no_mangle]
pub unsafe extern "system" fn Java_io_github_molotovgit_multiplex_DesktopVideo_nativeSetSurface(
    env: *mut JNIEnv,
    _class: jobject,
    texture: jlong,
    surface: jobject,
) {
    // SAFETY: see the function's contract; a null surface is checked first.
    let window = if surface.is_null() { None } else { unsafe { NativeWindow::from_surface(env, surface) } };
    let mut s = SURFACES.lock().unwrap_or_else(|p| p.into_inner());
    *s.generation.entry(texture).or_insert(0) += 1;
    match window {
        Some(w) => {
            s.by_texture.insert(texture, w);
        }
        None => {
            s.by_texture.remove(&texture);
        }
    }
}

enum Command {
    Configure { width: u32, height: u32 },
    Frame(EncodedFrame),
    Close,
}

/// The app-facing end: queues work for the decoder thread.
pub struct AndroidDecoder {
    tx: Mutex<std_mpsc::Sender<Command>>,
}

impl AndroidDecoder {
    pub fn start(texture: i64, reports: mpsc::UnboundedSender<VideoReport>) -> Self {
        let (tx, rx) = std_mpsc::channel();
        std::thread::Builder::new()
            .name("multiplex-video".into())
            .spawn(move || DecoderThread::new(texture, reports).run(rx))
            .expect("could not start the video thread");
        Self { tx: Mutex::new(tx) }
    }

    fn send(&self, cmd: Command) {
        let _ = self.tx.lock().unwrap_or_else(|p| p.into_inner()).send(cmd);
    }
}

impl VideoSink for AndroidDecoder {
    fn configure(&self, width: u32, height: u32) {
        self.send(Command::Configure { width, height });
    }

    fn submit(&self, frame: EncodedFrame) {
        self.send(Command::Frame(frame));
    }

    fn close(&self) {
        self.send(Command::Close);
    }
}

impl Drop for AndroidDecoder {
    fn drop(&mut self) {
        self.send(Command::Close);
    }
}

/// A started codec and the surface version it draws on.
struct Codec {
    codec: MediaCodec,
    generation: u64,
    /// Kept alive as long as the codec draws on it.
    _window: NativeWindow,
}

struct DecoderThread {
    texture: i64,
    reports: mpsc::UnboundedSender<VideoReport>,
    size: (u32, u32),
    codec: Option<Codec>,
    /// Pictures fed in and not out yet: (id, arrived).
    in_flight: VecDeque<(u64, Instant)>,
    /// Feed nothing until a keyframe comes (after a reset or a loss).
    need_keyframe: bool,
    /// We already asked for a keyframe and are waiting for it.
    asked: bool,
}

impl DecoderThread {
    /// How long to wait for a free input buffer before giving up a frame.
    const INPUT_WAIT: Duration = Duration::from_millis(20);
    /// How long one output poll may block while pictures are in flight.
    const OUTPUT_POLL: Duration = Duration::from_millis(2);
    /// Pictures stuck longer than this were dropped by the codec.
    const STUCK: Duration = Duration::from_millis(1500);

    fn new(texture: i64, reports: mpsc::UnboundedSender<VideoReport>) -> Self {
        Self {
            texture,
            reports,
            size: (1280, 720),
            codec: None,
            in_flight: VecDeque::new(),
            need_keyframe: true,
            asked: false,
        }
    }

    fn run(mut self, rx: std_mpsc::Receiver<Command>) {
        loop {
            // Block while idle; poll quickly while a picture is decoding.
            let cmd = if self.in_flight.is_empty() {
                match rx.recv_timeout(Duration::from_millis(250)) {
                    Ok(c) => Some(c),
                    Err(RecvTimeoutError::Timeout) => None,
                    Err(RecvTimeoutError::Disconnected) => break,
                }
            } else {
                match rx.try_recv() {
                    Ok(c) => Some(c),
                    Err(TryRecvError::Empty) => None,
                    Err(TryRecvError::Disconnected) => break,
                }
            };
            let got = cmd.is_some();
            match cmd {
                Some(Command::Close) => break,
                Some(Command::Configure { width, height }) => {
                    if (width, height) != self.size {
                        self.size = (width, height);
                        self.reset();
                    }
                }
                Some(Command::Frame(frame)) => self.feed(frame),
                None => {}
            }
            self.drain(if got { Duration::ZERO } else { Self::OUTPUT_POLL });
        }
        self.reset();
    }

    /// Drops the codec; the next keyframe builds a new one.
    fn reset(&mut self) {
        if let Some(c) = self.codec.take() {
            let _ = c.codec.stop();
        }
        for (id, _) in self.in_flight.drain(..) {
            let _ = self.reports.send(VideoReport::Skipped { id });
        }
        self.need_keyframe = true;
    }

    fn ask_keyframe(&mut self) {
        if !self.asked {
            self.asked = true;
            let _ = self.reports.send(VideoReport::NeedKeyframe);
        }
    }

    fn skip(&mut self, id: u64) {
        let _ = self.reports.send(VideoReport::Skipped { id });
    }

    fn feed(&mut self, frame: EncodedFrame) {
        // A new or replaced surface means a new codec.
        let (window, generation) = surface_for(self.texture);
        if self.codec.as_ref().is_some_and(|c| c.generation != generation) {
            self.reset();
        }
        let Some(window) = window else {
            self.skip(frame.id);
            self.need_keyframe = true;
            self.asked = false; // ask again once a surface exists
            return;
        };
        if self.need_keyframe && !frame.keyframe {
            self.skip(frame.id);
            self.ask_keyframe();
            return;
        }
        if self.codec.is_none() {
            match self.build(window, generation) {
                Some(c) => self.codec = Some(c),
                None => {
                    self.skip(frame.id);
                    self.asked = false;
                    self.ask_keyframe();
                    return;
                }
            }
        }
        if frame.keyframe {
            self.need_keyframe = false;
            self.asked = false;
        }
        // Keyframes carry the sequence header: give it a low-latency VUI so
        // the decoder shows each picture at once (see h264.rs).
        let data = if frame.keyframe { super::h264::low_latency_sps(&frame.data).map(bytes::Bytes::from) } else { None };
        let data = data.as_ref().unwrap_or(&frame.data);
        let codec = &self.codec.as_ref().expect("codec built above").codec;
        let fed = match codec.dequeue_input_buffer(Self::INPUT_WAIT) {
            Ok(DequeuedInputBufferResult::Buffer(mut buf)) => {
                let dst = buf.buffer_mut();
                if dst.len() < data.len() {
                    None
                } else {
                    for (d, s) in dst.iter_mut().zip(data.iter()) {
                        d.write(*s);
                    }
                    // The frame id rides along as the timestamp, so the
                    // output tells us which picture it is.
                    codec.queue_input_buffer(buf, 0, data.len(), frame.id, 0).ok()
                }
            }
            _ => None,
        };
        match fed {
            Some(()) => self.in_flight.push_back((frame.id, frame.arrived)),
            None => {
                // A lost picture breaks the chain of P-frames after it.
                self.skip(frame.id);
                self.reset();
                self.ask_keyframe();
            }
        }
    }

    /// Renders every finished picture right away.
    fn drain(&mut self, first_wait: Duration) {
        let mut wait = first_wait;
        loop {
            let Some(c) = &self.codec else { return };
            match c.codec.dequeue_output_buffer(wait) {
                Ok(DequeuedOutputBufferInfoResult::Buffer(buf)) => {
                    let id = buf.info().presentation_time_us() as u64;
                    let _ = c.codec.release_output_buffer(buf, true);
                    // Everything older than this picture was dropped by
                    // the codec; report those too.
                    while let Some(&(fid, arrived)) = self.in_flight.front() {
                        self.in_flight.pop_front();
                        if fid == id {
                            let _ = self.reports.send(VideoReport::Shown { id, latency: arrived.elapsed() });
                            break;
                        }
                        let _ = self.reports.send(VideoReport::Skipped { id: fid });
                    }
                    wait = Duration::ZERO;
                }
                Ok(DequeuedOutputBufferInfoResult::TryAgainLater) => break,
                Ok(DequeuedOutputBufferInfoResult::OutputFormatChanged) => {
                    let f = c.codec.output_format();
                    log_format(&f);
                    let (w, h) = (f.i32("width").unwrap_or(0), f.i32("height").unwrap_or(0));
                    // crop-right/bottom are inclusive pixel indices.
                    let vw = f.i32("crop-right").map(|r| r - f.i32("crop-left").unwrap_or(0) + 1).unwrap_or(w);
                    let vh = f.i32("crop-bottom").map(|b| b - f.i32("crop-top").unwrap_or(0) + 1).unwrap_or(h);
                    if w > 0 && h > 0 {
                        let _ = self.reports.send(VideoReport::Picture {
                            width: w as u32,
                            height: h as u32,
                            visible_width: vw.clamp(1, w) as u32,
                            visible_height: vh.clamp(1, h) as u32,
                        });
                    }
                    wait = Duration::ZERO;
                }
                Ok(_) => wait = Duration::ZERO, // buffers changed
                Err(_) => {
                    self.reset();
                    self.ask_keyframe();
                    return;
                }
            }
        }
        // A codec that swallowed a picture must not stall the acks.
        while let Some(&(id, arrived)) = self.in_flight.front() {
            if arrived.elapsed() < Self::STUCK {
                break;
            }
            self.in_flight.pop_front();
            self.skip(id);
        }
    }

    fn build(&self, window: NativeWindow, generation: u64) -> Option<Codec> {
        let codec = MediaCodec::from_decoder_type("video/avc")?;
        let mut format = MediaFormat::new();
        format.set_str("mime", "video/avc");
        format.set_i32("width", self.size.0 as i32);
        format.set_i32("height", self.size.1 as i32);
        format.set_i32("max-width", 4096);
        format.set_i32("max-height", 4096);
        // Show each picture as soon as it is decoded (Android 11+), plus
        // the vendor switches for chips that predate that key.
        format.set_i32("low-latency", 1);
        format.set_i32("vendor.qti-ext-dec-low-latency.enable", 1);
        format.set_i32("vendor.rtc-ext-dec-low-latency.enable", 1);
        format.set_i32("vendor.low-latency.enable", 1);
        // Real-time priority.
        format.set_i32("priority", 0);
        codec.configure(&format, Some(&window), MediaCodecDirection::Decoder).ok()?;
        codec.start().ok()?;
        Some(Codec { codec, generation, _window: window })
    }
}

/// Writes the decoder's output format to the Android log (tag
/// multiplex-video), for diagnosing picture-size problems.
fn log_format(f: &MediaFormat) {
    let keys = ["width", "height", "stride", "slice-height", "crop-left", "crop-top", "crop-right", "crop-bottom", "color-format"];
    let line = keys.iter().map(|k| format!("{k}={}", f.i32(k).map_or("-".into(), |v| v.to_string()))).collect::<Vec<_>>().join(" ");
    let msg = std::ffi::CString::new(format!("output format: {line}")).unwrap_or_default();
    let tag = c"multiplex-video";
    // SAFETY: valid NUL-terminated strings for the duration of the call.
    unsafe { __android_log_write(4, tag.as_ptr(), msg.as_ptr()) };
}

extern "C" {
    fn __android_log_write(prio: std::ffi::c_int, tag: *const std::ffi::c_char, text: *const std::ffi::c_char) -> std::ffi::c_int;
}
