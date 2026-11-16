//! Diagnostic: talk to gliff-server without SSH (its local `--listen`
//! mode) to see how much delay the server itself adds. Run with
//! MPX_GLIFF_DIRECT=127.0.0.1:47001 while `gliff-server --listen
//! 127.0.0.1:47001 --output auto` runs in a Hyprland session.

use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use gliff_proto::{ChromaMode, ClientCaps, ClientMsg, Codec, ServerMsg, PROTOCOL_VERSION};
use gliff_transport::Framed;

fn now_ms() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64
}

#[tokio::test(flavor = "multi_thread")]
async fn server_delay_without_ssh() {
    let Ok(addr) = std::env::var("MPX_GLIFF_DIRECT") else {
        eprintln!("skipped: set MPX_GLIFF_DIRECT");
        return;
    };
    // "ssh:user@host" goes through the OpenSSH client instead.
    let (r, w): (Box<dyn tokio::io::AsyncRead + Unpin + Send>, Box<dyn tokio::io::AsyncWrite + Unpin + Send>) = if let Some(target) = addr.strip_prefix("russh:") {
        // Multiplex's own SSH client (russh), as the app uses it.
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
        let sock = tokio::net::TcpStream::connect(&addr).await.expect("connect");
        sock.set_nodelay(true).unwrap();
        let (r, w) = sock.into_split();
        (Box::new(r), Box::new(w))
    };
    let (mut r, mut w) = (Framed::new(r), Framed::new(w));
    w.write_msg(&ClientMsg::Hello {
        version: PROTOCOL_VERSION,
        keymap: String::new(),
        caps: ClientCaps { codecs: vec![Codec::H264], max_width: 3840, max_height: 2160, chroma: vec![ChromaMode::Single420], features: vec![] },
    })
    .await
    .unwrap();
    w.write_msg(&ClientMsg::Resize { width: 1920, height: 1080, scale: 1.0 }).await.unwrap();
    let start = Instant::now();
    let (mut rtts, mut ages) = (Vec::new(), Vec::new());
    let mut last_ping = Instant::now() - Duration::from_secs(1);
    let mut x = 100.0;
    while start.elapsed() < Duration::from_secs(4) {
        if last_ping.elapsed() > Duration::from_millis(200) {
            w.write_msg(&ClientMsg::Ping { t: now_ms() }).await.unwrap();
            last_ping = Instant::now();
        }
        x += 7.0;
        w.write_msg(&ClientMsg::PointerMotion { x: x % 1800.0, y: 500.0 }).await.unwrap();
        let msg = tokio::time::timeout(Duration::from_millis(20), r.read_msg::<ServerMsg>()).await;
        let Ok(msg) = msg else { continue };
        match msg.unwrap() {
            ServerMsg::Ping { t } => w.write_msg(&ClientMsg::Pong { t }).await.unwrap(),
            ServerMsg::Pong { t, .. } => rtts.push(now_ms() - t),
            ServerMsg::VideoFrame { frame_id, pts_us, data_len, .. } => {
                let _ = r.read_payload(data_len).await.unwrap();
                ages.push(now_ms() as i64 - (pts_us / 1000) as i64);
                w.write_msg(&ClientMsg::FrameAck { frame_id, decoded_at_ms: now_ms() }).await.unwrap();
            }
            _ => {}
        }
    }
    rtts.sort();
    ages.sort();
    eprintln!("DIRECT pings {:?}", rtts);
    eprintln!("DIRECT frame ages (send->recv, same clock): median {} ms, n={}", ages.get(ages.len() / 2).copied().unwrap_or(-1), ages.len());
}
