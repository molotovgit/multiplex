//! Optional tests of the remote desktop against a real gliff-server.
//!
//! Skipped unless these environment variables are set:
//! - `MPX_DESKTOP_HOST`, `MPX_DESKTOP_USER`, `MPX_DESKTOP_KEY` (key file),
//!   `MPX_DESKTOP_PORT` (optional, 22): a machine running Hyprland with
//!   gliff installed;
//! - `MPX_DESKTOP_CLIPBOARD=1` (optional): also test the clipboard with
//!   `wl-copy`/`wl-paste`, which must then run on the same machine as the
//!   test (as when testing against localhost).
//!
//! The tests mirror the focused monitor, so they never add a screen.

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use multiplex_core::api::desktop_types::{DesktopEvent, DesktopMode, DesktopOptions};
use multiplex_core::api::ssh_types::{ConnectError, ConnectOptions, Credentials};
use multiplex_core::engine::desktop::video::CountingSink;
use multiplex_core::engine::desktop::DesktopSession;
use multiplex_core::engine::ssh::{Connection, Connector};
use tokio::sync::mpsc;

fn options() -> Option<ConnectOptions> {
    let host = std::env::var("MPX_DESKTOP_HOST").ok()?;
    let username = std::env::var("MPX_DESKTOP_USER").ok()?;
    let key = std::fs::read_to_string(std::env::var("MPX_DESKTOP_KEY").ok()?).expect("key file");
    let port = std::env::var("MPX_DESKTOP_PORT").ok().and_then(|p| p.parse().ok()).unwrap_or(22);
    let credentials = Credentials { private_key: Some(key), ..Default::default() };
    Some(ConnectOptions {
        host,
        port,
        username,
        credentials,
        trusted_host_keys: vec![],
        keepalive_secs: 10,
        connect_timeout_secs: 20,
        jump: None,
        forward_agent: false,
        via_tailscale: false,
    })
}

/// Connects, trusting each host key on first sight.
async fn connect() -> Option<Connection> {
    let Some(mut opts) = options() else {
        eprintln!("desktop tests skipped: set MPX_DESKTOP_HOST, MPX_DESKTOP_USER and MPX_DESKTOP_KEY");
        return None;
    };
    for _ in 0..3 {
        match Connector::connect(opts.clone()).await {
            Ok(c) => return Some(c),
            Err(ConnectError::HostKeyUnknown { key, .. }) => opts.trusted_host_keys = vec![key.public_key],
            Err(e) => panic!("connect failed: {e:?}"),
        }
    }
    panic!("could not settle the host keys");
}

type Events = Arc<Mutex<Vec<DesktopEvent>>>;

async fn open(conn: &Connection) -> (DesktopSession, Events) {
    let events: Events = Arc::default();
    let seen = events.clone();
    let (reports_tx, reports_rx) = mpsc::unbounded_channel();
    let session = DesktopSession::open(
        conn,
        DesktopOptions {
            // MPX_DESKTOP_OUTPUT picks a monitor; MPX_DESKTOP_SERVER another
            // gliff-server build (A/B tests).
            mode: std::env::var("MPX_DESKTOP_OUTPUT").map(|name| DesktopMode::Output { name }).unwrap_or(DesktopMode::Mirror),
            width: 1920,
            height: 1080,
            scale: 1.0,
            low_bandwidth: false,
            texture_id: 0,
            server_command: std::env::var("MPX_DESKTOP_SERVER").unwrap_or_default(),
        },
        Arc::new(move |e| {
            seen.lock().unwrap().push(e);
            true
        }),
        Box::new(CountingSink { reports: reports_tx }),
        reports_rx,
    )
    .await
    .expect("desktop should start");
    (session, events)
}

async fn wait_for(events: &Events, limit: Duration, pred: impl Fn(&DesktopEvent) -> bool) -> bool {
    let start = Instant::now();
    while start.elapsed() < limit {
        if events.lock().unwrap().iter().any(&pred) {
            return true;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    false
}

#[tokio::test(flavor = "multi_thread")]
async fn streams_video_and_keeps_pace() {
    let Some(conn) = connect().await else { return };
    let started = Instant::now();
    let (session, events) = open(&conn).await;
    eprintln!("desktop started in {:?}", started.elapsed());

    assert!(wait_for(&events, Duration::from_secs(5), |e| matches!(e, DesktopEvent::Started { .. })).await);
    assert!(
        wait_for(&events, Duration::from_secs(5), |e| matches!(e, DesktopEvent::Stream { .. })).await,
        "no stream config"
    );
    // Move the pointer around so the screen changes and frames flow.
    // Move the pointer (MPX_DESKTOP_SECONDS long, default 1 s) so frames flow.
    let secs: u32 = std::env::var("MPX_DESKTOP_SECONDS").ok().and_then(|v| v.parse().ok()).unwrap_or(1);
    for i in 0..(60 * secs) {
        session.pointer_move(200.0 + f64::from(i % 300) * 5.0, 200.0);
        tokio::time::sleep(Duration::from_millis(16)).await;
    }
    assert!(
        wait_for(&events, Duration::from_secs(5), |e| matches!(e, DesktopEvent::Stats(s) if s.fps > 0.0)).await,
        "no frames were shown"
    );
    for e in events.lock().unwrap().iter() {
        match e {
            DesktopEvent::Stream { width, height, scale, hardware } => {
                eprintln!("stream {width}x{height} scale {scale} hardware {hardware}")
            }
            DesktopEvent::Stats(s) => eprintln!(
                "stats: {:.0} fps, {:.0} kbps, rtt {:.0} ms, frame age {:.1} ms",
                s.fps, s.kbps, s.rtt_ms, s.frame_age_ms
            ),
            _ => {}
        }
    }
    session.close();
    assert!(session.is_closed());
}

#[tokio::test(flavor = "multi_thread")]
async fn clipboard_goes_both_ways() {
    if std::env::var("MPX_DESKTOP_CLIPBOARD").is_err() {
        eprintln!("clipboard test skipped: set MPX_DESKTOP_CLIPBOARD=1");
        return;
    }
    let Some(conn) = connect().await else { return };
    let (session, events) = open(&conn).await;
    assert!(wait_for(&events, Duration::from_secs(5), |e| matches!(e, DesktopEvent::Stream { .. })).await);

    // Desktop -> phone.
    let marker = format!("multiplex-test-{}", std::process::id());
    std::process::Command::new("wl-copy").arg(&marker).status().expect("wl-copy");
    assert!(
        wait_for(&events, Duration::from_secs(5), |e| matches!(e, DesktopEvent::Clipboard { text } if *text == marker)).await,
        "desktop copy did not reach us"
    );

    // Phone -> desktop.
    let back = format!("from-phone-{}", std::process::id());
    session.set_clipboard(back.clone());
    let mut pasted = String::new();
    for _ in 0..50 {
        tokio::time::sleep(Duration::from_millis(100)).await;
        let out = std::process::Command::new("timeout").args(["3", "wl-paste", "-n"]).output().expect("wl-paste");
        pasted = String::from_utf8_lossy(&out.stdout).into_owned();
        if pasted == back {
            break;
        }
    }
    assert_eq!(pasted, back, "our text did not reach the desktop clipboard");
    session.close();
}

/// Keeps the first keyframe it sees.
struct KeyframeGrabber {
    reports: mpsc::UnboundedSender<multiplex_core::engine::desktop::video::VideoReport>,
    first: Arc<Mutex<Option<Vec<u8>>>>,
}

impl multiplex_core::engine::desktop::video::VideoSink for KeyframeGrabber {
    fn configure(&self, _: u32, _: u32) {}
    fn submit(&self, frame: multiplex_core::engine::desktop::video::EncodedFrame) {
        if frame.keyframe {
            self.first.lock().unwrap().get_or_insert_with(|| frame.data.to_vec());
        }
        let _ = self.reports.send(multiplex_core::engine::desktop::video::VideoReport::Shown { id: frame.id, latency: Duration::ZERO });
    }
    fn close(&self) {}
}

#[tokio::test(flavor = "multi_thread")]
async fn real_keyframes_get_a_low_latency_header() {
    let Some(conn) = connect().await else { return };
    let first = Arc::new(Mutex::new(None));
    let (tx, rx) = mpsc::unbounded_channel();
    let session = DesktopSession::open(
        &conn,
        DesktopOptions {
            mode: DesktopMode::Mirror,
            width: 1920,
            height: 1080,
            scale: 1.0,
            low_bandwidth: false,
            texture_id: 0,
            server_command: String::new(),
        },
        Arc::new(|_| true),
        Box::new(KeyframeGrabber { reports: tx, first: first.clone() }),
        rx,
    )
    .await
    .expect("desktop should start");
    let start = Instant::now();
    while first.lock().unwrap().is_none() && start.elapsed() < Duration::from_secs(10) {
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    let key = first.lock().unwrap().clone().expect("a keyframe");
    let fixed = multiplex_core::engine::desktop::h264::low_latency_sps(&key).expect("the SPS was rewritten");
    eprintln!("keyframe {} bytes -> {} bytes", key.len(), fixed.len());
    assert!(fixed.len() > key.len() && fixed.len() < key.len() + 32);
    session.close();
}
