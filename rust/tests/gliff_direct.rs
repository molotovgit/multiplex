//! Latency lab: talk to gliff-server without the app, to measure what each
//! part of the path adds. Skipped unless MPX_GLIFF_DIRECT is set:
//! - `127.0.0.1:47001`: gliff-server's local `--listen` mode;
//! - `ssh:user@host`: through the OpenSSH client (MPX_GLIFF_KEY = key);
//! - `russh:user@host`: through Multiplex's own SSH client.
//!
//! What it measures (client and server on one clock, so ages are exact):
//! - small frames: the pointer moves every 16 ms; frame age = server send
//!   to fully received;
//! - big frames after a pause (MPX_LAB_BURSTS, default 8): idle for
//!   MPX_LAB_IDLE_MS (default 1500), then ask for a keyframe and time it
//!   from the request until its last byte arrived.
//!
//! With `unshare -rn` and `tc netem` on lo this runs on an emulated mobile
//! link without root (see docs/remote-desktop/latency-lab.md).

use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use gliff_proto::{ChromaMode, ClientCaps, ClientMsg, Codec, ServerMsg, PROTOCOL_VERSION};
use gliff_transport::Framed;
use tokio::io::{AsyncRead, AsyncWrite};

fn now_ms() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64
}

fn env_u64(name: &str, default: u64) -> u64 {
    std::env::var(name).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
}

type Reader = Framed<Box<dyn AsyncRead + Unpin + Send>>;
type Writer = Framed<Box<dyn AsyncWrite + Unpin + Send>>;

async fn open(addr: &str) -> (Reader, Writer) {
    let (r, w): (Box<dyn AsyncRead + Unpin + Send>, Box<dyn AsyncWrite + Unpin + Send>) = if let Some(target) = addr.strip_prefix("russh:") {
        let (user, host) = target.split_once('@').unwrap();
        let key = std::fs::read_to_string(std::env::var("MPX_GLIFF_KEY").unwrap()).unwrap();
        let mut opts = multiplex_core::api::ssh_types::ConnectOptions {
            host: host.into(),
            port: 22,
            username: user.into(),
            credentials: multiplex_core::api::ssh_types::Credentials { private_key: Some(key), ..Default::default() },
            trusted_host_keys: vec![],
            keepalive_secs: 10,
            connect_timeout_secs: 10,
            jump: None,
            forward_agent: false,
            via_tailscale: false,
        };
        let conn = match multiplex_core::engine::ssh::Connector::connect(opts.clone()).await {
            Ok(c) => c,
            Err(multiplex_core::api::ssh_types::ConnectError::HostKeyUnknown { key, .. }) => {
                opts.trusted_host_keys = vec![key.public_key];
                multiplex_core::engine::ssh::Connector::connect(opts).await.unwrap()
            }
            Err(e) => panic!("{e:?}"),
        };
        let channel = conn.handle().channel_open_session().await.unwrap();
        channel.exec(true, "gliff-server --stdio --output auto").await.unwrap();
        let (r, w) = tokio::io::split(channel.into_stream());
        std::mem::forget(conn);
        (Box::new(r), Box::new(w))
    } else if let Some(target) = addr.strip_prefix("ssh:") {
        let key = std::env::var("MPX_GLIFF_KEY").unwrap();
        let mut child = tokio::process::Command::new("ssh")
            .args(["-T", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-i", &key, target, "gliff-server", "--stdio", "--output", "auto"])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .unwrap();
        let (o, i) = (child.stdout.take().unwrap(), child.stdin.take().unwrap());
        std::mem::forget(child);
        (Box::new(o), Box::new(i))
    } else {
        let sock = tokio::net::TcpStream::connect(addr).await.expect("connect");
        sock.set_nodelay(true).unwrap();
        let (r, w) = sock.into_split();
        (Box::new(r), Box::new(w))
    };
    (Framed::new(r), Framed::new(w))
}

fn pct(v: &mut [f64], p: f64) -> f64 {
    if v.is_empty() {
        return -1.0;
    }
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    v[((v.len() - 1) as f64 * p).round() as usize]
}

#[tokio::test(flavor = "multi_thread")]
async fn server_delay_without_ssh() {
    let Ok(addr) = std::env::var("MPX_GLIFF_DIRECT") else {
        eprintln!("skipped: set MPX_GLIFF_DIRECT");
        return;
    };
    let (mut r, mut w) = open(&addr).await;
    w.write_msg(&ClientMsg::Hello {
        version: PROTOCOL_VERSION,
        keymap: String::new(),
        caps: ClientCaps { codecs: vec![Codec::H264], max_width: 3840, max_height: 2160, chroma: vec![ChromaMode::Single420], features: vec![] },
    })
    .await
    .unwrap();
    w.write_msg(&ClientMsg::Resize { width: 1920, height: 1080, scale: 1.0 }).await.unwrap();

    let (mut rtts, mut small, mut bursts, mut burst_bytes) = (Vec::new(), Vec::new(), Vec::new(), Vec::new());
    // Input to picture: from a pointer move to the first frame after it.
    let (mut input_to_frame, mut pending_input): (Vec<f64>, Option<Instant>) = (Vec::new(), None);
    // Phase 1: warm up and measure small frames with steady pointer motion.
    let start = Instant::now();
    let mut last_ping = Instant::now() - Duration::from_secs(1);
    let mut x = 100.0;
    let mut next_move = Instant::now();
    let warm = Duration::from_millis(env_u64("MPX_LAB_WARM_MS", 4000));
    // Phase 2 state.
    let bursts_wanted = env_u64("MPX_LAB_BURSTS", 8) as usize;
    let idle = Duration::from_millis(env_u64("MPX_LAB_IDLE_MS", 1500));
    let mut burst_asked: Option<Instant> = None;
    let mut idle_since = Instant::now();
    let (mut moves, mut moved_at): (Vec<f64>, Option<Instant>) = (Vec::new(), None);
    loop {
        let in_warm = start.elapsed() < warm;
        if !in_warm && bursts.len() >= bursts_wanted && moves.len() >= bursts_wanted {
            break;
        }
        if in_warm && Instant::now() >= next_move {
            x += 7.0;
            w.write_msg(&ClientMsg::PointerMotion { x: x % 1800.0, y: 500.0 }).await.unwrap();
            pending_input.get_or_insert_with(Instant::now);
            next_move = Instant::now() + Duration::from_millis(16);
            if last_ping.elapsed() > Duration::from_millis(200) {
                w.write_msg(&ClientMsg::Ping { t: now_ms() }).await.unwrap();
                last_ping = Instant::now();
            }
        }
        if !in_warm && burst_asked.is_none() && moved_at.is_none() && idle_since.elapsed() >= idle {
            if bursts.len() < moves.len() {
                w.write_msg(&ClientMsg::RequestKeyframe).await.unwrap();
                burst_asked = Some(Instant::now());
            } else {
                // One move on a still screen: the next frame is its result.
                x += 40.0;
                w.write_msg(&ClientMsg::PointerMotion { x: x % 1800.0, y: 520.0 }).await.unwrap();
                moved_at = Some(Instant::now());
            }
        }
        let Ok(msg) = tokio::time::timeout(Duration::from_millis(5), r.read_msg::<ServerMsg>()).await else { continue };
        match msg.unwrap() {
            ServerMsg::Ping { t } => w.write_msg(&ClientMsg::Pong { t }).await.unwrap(),
            ServerMsg::Pong { t, .. } => rtts.push((now_ms() - t) as f64),
            ServerMsg::VideoFrame { frame_id, pts_us, keyframe, data_len, .. } => {
                let _ = r.read_payload(data_len).await.unwrap();
                let age = now_ms() as f64 - (pts_us / 1000) as f64;
                w.write_msg(&ClientMsg::FrameAck { frame_id, decoded_at_ms: now_ms() }).await.unwrap();
                if in_warm && start.elapsed() > Duration::from_millis(1500) {
                    small.push(age);
                    if let Some(at) = pending_input.take() {
                        input_to_frame.push(at.elapsed().as_secs_f64() * 1000.0);
                    }
                }
                if let Some(at) = moved_at.take() {
                    moves.push(at.elapsed().as_secs_f64() * 1000.0);
                    idle_since = Instant::now();
                }
                if let (Some(asked), true) = (burst_asked, keyframe) {
                    bursts.push(asked.elapsed().as_secs_f64() * 1000.0);
                    burst_bytes.push(f64::from(data_len));
                    burst_asked = None;
                    idle_since = Instant::now();
                }
            }
            _ => {}
        }
    }
    let n_small = small.len();
    eprintln!(
        "LAB ping p50 {:.0} ms | move->frame (causal) p50 {:.0} p95 {:.0} | small frames: age p50 {:.1} p95 {:.1} ms (n={n_small}) | keyframe after {} ms idle: p50 {:.0} p95 {:.0} ms, size p50 {:.0} KB",
        pct(&mut rtts, 0.5),
        pct(&mut moves, 0.5),
        pct(&mut moves, 0.95),
        pct(&mut small, 0.5),
        pct(&mut small, 0.95),
        idle.as_millis(),
        pct(&mut bursts, 0.5),
        pct(&mut bursts, 0.95),
        pct(&mut burst_bytes, 0.5) / 1024.0,
    );
}
