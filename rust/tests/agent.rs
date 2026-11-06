//! Agent forwarding against the in-process test server: the server uses
//! the phone's key through the forwarded agent, as `git` would.

mod support;

use std::sync::Arc;
use std::time::Duration;

use multiplex_core::api::ssh_types::Credentials;
use multiplex_core::api::terminal_types::{ShellEvent, ShellOptions, TerminalPalette};
use multiplex_core::engine::shell::ShellSession;
use multiplex_core::engine::ssh::Connector;
use russh::keys::{Algorithm, HashAlg, PrivateKey};
use support::{Logins, TestServer};
use tokio::sync::mpsc;

fn options() -> ShellOptions {
    ShellOptions {
        cols: 120,
        rows: 10,
        term: "xterm-256color".into(),
        scrollback_lines: 100,
        env: vec![],
        startup_command: None,
        command: None,
        palette: TerminalPalette::default(),
    }
}

/// Logs in with a key, opens a shell, and returns the server's agent
/// report line.
async fn agent_report(forward_agent: bool, probe_agent: bool) -> (String, PrivateKey) {
    let key = PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap();
    let server = TestServer::start(Logins { authorized_key: Some(key.public_key().clone()), probe_agent, ..Default::default() }).await;
    let mut opts = server.options();
    opts.credentials = Credentials { private_key: Some(key.to_openssh(Default::default()).unwrap().to_string()), ..Default::default() };
    opts.forward_agent = forward_agent;
    let conn = Connector::connect(opts).await.unwrap();
    assert_eq!(conn.forwards_agent(), forward_agent);
    let (tx, mut events) = mpsc::unbounded_channel();
    let shell = ShellSession::open(&conn, options(), Arc::new(move |e| tx.send(e).is_ok())).await.unwrap();

    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    loop {
        // The report follows the shell's "$ " prompt.
        if let Some(at) = shell.visible_text().find("agent:") {
            let line = shell.visible_text()[at..].lines().next().unwrap_or_default().to_owned();
            std::mem::forget(conn);
            return (line, key);
        }
        let left = deadline.saturating_duration_since(tokio::time::Instant::now());
        match tokio::time::timeout(left, events.recv()).await {
            Ok(Some(ShellEvent::Changed)) => {
                shell.frame();
            }
            Ok(Some(_)) => {}
            _ => panic!("no agent report; screen was:\n{}", shell.visible_text()),
        }
    }
}

#[tokio::test]
async fn the_server_can_use_the_forwarded_key_but_not_change_the_agent() {
    let (report, key) = agent_report(true, false).await;
    let fingerprint = key.public_key().fingerprint(HashAlg::Sha256).to_string();
    assert_eq!(report, format!("agent: 1 key {fingerprint} signed=true add=false"));
}

#[tokio::test]
async fn without_the_option_the_key_is_never_offered() {
    // The server tries anyway; the client refuses the agent channel.
    let (report, _) = agent_report(false, true).await;
    assert_eq!(report, "agent: refused");
}
