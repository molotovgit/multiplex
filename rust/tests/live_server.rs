//! Optional tests against a real SSH server (for example OpenSSH on a VPS).
//!
//! They are skipped unless these environment variables are set:
//! - `VT_LIVE_HOST`  server address
//! - `VT_LIVE_USER`  user name
//! - `VT_LIVE_KEY`   path to a private key file that may log in
//! - `VT_LIVE_PORT`  optional, defaults to 22
//!
//! Everything they create lives in a fresh folder under /tmp and is
//! deleted again. Nothing about the server is stored in the repository.

mod support;

use std::sync::Arc;
use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;
use vaultterm_core::api::ssh_types::{ConnectError, ConnectOptions, Credentials};
use vaultterm_core::api::terminal_types::{KeyModifiers, ShellEvent, ShellOptions, TerminalPalette};
use vaultterm_core::api::tunnel_types::{TunnelKind, TunnelSpec};
use vaultterm_core::engine::sftp::{RemotePath, SftpBrowser};
use vaultterm_core::engine::shell::ShellSession;
use vaultterm_core::engine::ssh::{Connection, Connector};
use vaultterm_core::engine::tunnel::Tunnel;

/// Connection settings from the environment, or `None` to skip.
fn live_options() -> Option<ConnectOptions> {
    let host = std::env::var("VT_LIVE_HOST").ok()?;
    let username = std::env::var("VT_LIVE_USER").ok()?;
    let key_path = std::env::var("VT_LIVE_KEY").ok()?;
    let port = std::env::var("VT_LIVE_PORT").ok().and_then(|p| p.parse().ok()).unwrap_or(22);
    let private_key = std::fs::read_to_string(key_path).expect("VT_LIVE_KEY is not readable");
    Some(ConnectOptions {
        host,
        port,
        username,
        credentials: Credentials { private_key: Some(private_key), ..Default::default() },
        trusted_host_keys: vec![],
        keepalive_secs: 15,
        connect_timeout_secs: 15,
        jump: None,
    })
}

/// Connects, accepting the server key on first sight like a user would.
async fn live_connect() -> Option<Arc<Connection>> {
    let Some(mut options) = live_options() else {
        eprintln!("live tests skipped: set VT_LIVE_HOST, VT_LIVE_USER and VT_LIVE_KEY to run them");
        return None;
    };
    match Connector::connect(options.clone()).await {
        Err(ConnectError::HostKeyUnknown { key, .. }) => options.trusted_host_keys = vec![key.public_key],
        other => panic!("expected the first connect to ask about the host key, got {:?}", other.err()),
    }
    Some(Arc::new(Connector::connect(options).await.expect("live connect")))
}

fn unique_dir() -> String {
    let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    format!("/tmp/vaultterm-test-{nanos}")
}

#[tokio::test]
async fn live_exec_and_shell() {
    let Some(conn) = live_connect().await else { return };
    let out = conn.exec("uname -s", 4096).await.unwrap();
    assert_eq!((out.stdout.trim(), out.exit_code), ("Linux", Some(0)));

    let (tx, mut rx) = mpsc::unbounded_channel();
    let options = ShellOptions {
        cols: 80,
        rows: 24,
        term: "xterm-256color".into(),
        scrollback_lines: 500,
        env: vec![],
        startup_command: None,
        palette: TerminalPalette::default(),
    };
    let shell = ShellSession::open(&conn, options, Arc::new(move |e| tx.send(e).is_ok())).await.unwrap();
    // The shell computes 6*7, so seeing 42 proves it ran (not just echoed).
    shell.send_text("echo vt-$((6*7))", KeyModifiers::default());
    shell.send_key(vaultterm_core::api::terminal_types::TerminalKey::Enter, KeyModifiers::default());
    let found = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            if shell.visible_text().contains("vt-42") {
                return;
            }
            if let Some(ShellEvent::Changed) = rx.recv().await {
                shell.frame();
            }
        }
    })
    .await;
    assert!(found.is_ok(), "shell output never showed vt-42:\n{}", shell.visible_text());
    shell.close();
    conn.disconnect().await;
}

#[tokio::test]
async fn live_sftp_round_trip() {
    let Some(conn) = live_connect().await else { return };
    let sftp = SftpBrowser::open(&conn).await.unwrap();
    assert!(sftp.home().await.unwrap().starts_with('/'));

    let dir = unique_dir();
    sftp.make_dir(&dir).await.unwrap();
    let file = RemotePath::join(&dir, "hello.txt");
    sftp.write_text(&file, "hello from vaultterm\n").await.unwrap();
    assert_eq!(sftp.read_text(&file, 1024).await.unwrap(), "hello from vaultterm\n");

    sftp.make_dir(&RemotePath::join(&dir, "sub")).await.unwrap();
    let listing = sftp.list(&dir).await.unwrap();
    let names: Vec<_> = listing.iter().map(|e| (e.name.as_str(), e.is_dir)).collect();
    assert_eq!(names, vec![("sub", true), ("hello.txt", false)]);

    let renamed = RemotePath::join(&dir, "renamed.txt");
    sftp.rename(&file, &renamed).await.unwrap();
    sftp.set_permissions(&renamed, 0o600).await.unwrap();
    assert_eq!(sftp.stat(&renamed).await.unwrap().permissions, 0o600);

    // Upload 3 MiB, download it again, compare.
    let local = tempfile::tempdir().unwrap();
    let source = local.path().join("blob.bin");
    let data: Vec<u8> = (0..3 * 1024 * 1024).map(|i| (i % 251) as u8).collect();
    std::fs::write(&source, &data).unwrap();
    let remote_blob = RemotePath::join(&dir, "sub/blob.bin");
    let (tx, mut progress) = mpsc::unbounded_channel();
    let sent = sftp
        .upload(&source, &remote_blob, Arc::new(move |p| tx.send(p).is_ok()), CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(sent, data.len() as u64);
    let mut last = None;
    while let Ok(p) = progress.try_recv() {
        last = Some(p);
    }
    assert_eq!(last.map(|p| p.transferred), Some(data.len() as u64));

    let back = local.path().join("back.bin");
    sftp.download(&remote_blob, &back, Arc::new(|_| true), CancellationToken::new()).await.unwrap();
    assert_eq!(std::fs::read(&back).unwrap(), data);

    // A cancelled download leaves nothing behind.
    let cancelled = local.path().join("cancelled.bin");
    let token = CancellationToken::new();
    token.cancel();
    assert!(sftp.download(&remote_blob, &cancelled, Arc::new(|_| true), token).await.is_err());
    assert!(!cancelled.exists() && !cancelled.with_extension("part").exists());

    sftp.remove(&dir).await.unwrap();
    assert!(sftp.stat(&dir).await.is_err(), "test folder was not removed");
}

#[tokio::test]
async fn live_tunnels() {
    let Some(conn) = live_connect().await else { return };
    let spec = |kind| TunnelSpec { kind, bind_host: "127.0.0.1".into(), bind_port: 0, target_host: "127.0.0.1".into(), target_port: 22 };

    // Local forward to the server's own SSH port: we should hear its banner.
    let local = Tunnel::start(conn.clone(), spec(TunnelKind::Local)).await.unwrap();
    let mut stream = TcpStream::connect(("127.0.0.1", local.bound_port())).await.unwrap();
    let mut banner = [0u8; 8];
    stream.read_exact(&mut banner).await.unwrap();
    assert_eq!(&banner, b"SSH-2.0-");
    local.stop().await;

    // The same through the SOCKS5 proxy.
    let socks = Tunnel::start(conn.clone(), spec(TunnelKind::Dynamic)).await.unwrap();
    let mut stream = TcpStream::connect(("127.0.0.1", socks.bound_port())).await.unwrap();
    stream.write_all(&[5, 1, 0, 5, 1, 0, 1, 127, 0, 0, 1, 0, 22]).await.unwrap();
    let mut reply = [0u8; 12];
    stream.read_exact(&mut reply).await.unwrap();
    assert_eq!(reply[..2], [5, 0]);
    let mut banner = [0u8; 8];
    stream.read_exact(&mut banner).await.unwrap();
    assert_eq!(&banner, b"SSH-2.0-");
    socks.stop().await;

    // Remote forward: the server sends "ping" into its forwarded port with
    // bash's /dev/tcp, it reaches our echo service and comes back.
    let echo = support::echo_service().await;
    let mut remote_spec = spec(TunnelKind::Remote);
    remote_spec.target_port = echo;
    let remote = Tunnel::start(conn.clone(), remote_spec).await.unwrap();
    let command = format!(
        "bash -c 'exec 3<>/dev/tcp/127.0.0.1/{}; printf ping >&3; timeout 5 head -c 4 <&3'",
        remote.bound_port()
    );
    let out = conn.exec(&command, 1024).await.unwrap();
    assert_eq!(out.stdout, "ping", "stderr: {}", out.stderr);
    remote.stop().await;
    conn.disconnect().await;
}
