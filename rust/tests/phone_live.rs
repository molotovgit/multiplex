//! Optional test that plays a paired phone against a real computer: it
//! logs in with a phone's key, listens on the link as the app does, and
//! answers what the computer asks with the same code the app uses.
//!
//! Skipped unless these are set:
//! - `MPX_PHONE_HOST`, `MPX_PHONE_USER`, `MPX_PHONE_KEY` (the key file of
//!   a phone paired with that computer; `MPX_PHONE_PORT` is optional);
//! - `MPX_PHONE_NAME`: the name that phone is paired under;
//! - `MPX_PHONE_BIN`: the computer's `multiplex` command. The test runs it
//!   itself, so the computer has to be this machine.
//!
//! Use a throwaway key registered for the test, not a real phone's.

use std::process::{Command, Stdio};
use std::sync::Arc;
use std::time::Duration;

use multiplex_core::api::ssh_types::{ConnectError, ConnectOptions, Credentials};
use multiplex_core::engine::share;
use multiplex_core::engine::ssh::{Connection, Connector};
use multiplex_proto::share::{link_command, parse_link_event, LinkEvent};
use russh::ChannelMsg;
use tokio::sync::mpsc;

struct Setup {
    conn: Arc<Connection>,
    key: String,
    name: String,
    bin: String,
}

async fn setup() -> Option<Setup> {
    let host = std::env::var("MPX_PHONE_HOST").ok()?;
    let username = std::env::var("MPX_PHONE_USER").ok()?;
    let key = std::fs::read_to_string(std::env::var("MPX_PHONE_KEY").ok()?).expect("key file");
    let name = std::env::var("MPX_PHONE_NAME").ok()?;
    let bin = std::env::var("MPX_PHONE_BIN").ok()?;
    let port = std::env::var("MPX_PHONE_PORT").ok().and_then(|p| p.parse().ok()).unwrap_or(22);
    let mut opts = ConnectOptions {
        host,
        port,
        username,
        credentials: Credentials { private_key: Some(key.clone()), ..Default::default() },
        trusted_host_keys: vec![],
        keepalive_secs: 10,
        connect_timeout_secs: 20,
        jump: None,
        forward_agent: false,
        via_tailscale: false,
    };
    for _ in 0..3 {
        match Connector::connect(opts.clone()).await {
            Ok(conn) => return Some(Setup { conn: Arc::new(conn), key, name, bin }),
            Err(ConnectError::HostKeyUnknown { key, .. }) => opts.trusted_host_keys = vec![key.public_key],
            Err(e) => panic!("connect failed: {e:?}"),
        }
    }
    panic!("could not settle the host keys");
}

/// Listens on the link, as the app does while connected.
async fn link(conn: &Connection, name: &str) -> mpsc::UnboundedReceiver<LinkEvent> {
    let channel = conn.handle().channel_open_session().await.expect("a channel");
    channel.exec(true, link_command(name).as_bytes()).await.expect("the link starts");
    let (events, heard) = mpsc::unbounded_channel();
    tokio::spawn(async move {
        let (mut reader, _writer) = channel.split();
        let mut pending = Vec::new();
        while let Some(msg) = reader.wait().await {
            if let ChannelMsg::Data { data } = msg {
                pending.extend_from_slice(&data);
                while let Some(end) = pending.iter().position(|b| *b == b'\n') {
                    let line: Vec<u8> = pending.drain(..=end).collect();
                    if let Ok(event) = parse_link_event(&String::from_utf8_lossy(&line)) {
                        if events.send(event).is_err() {
                            return;
                        }
                    }
                }
            }
        }
    });
    // The computer counts the phone as connected once the link's loop runs.
    tokio::time::sleep(Duration::from_millis(600)).await;
    heard
}

/// The next approval the computer asks for.
async fn next_approval(heard: &mut mpsc::UnboundedReceiver<LinkEvent>) -> (String, String, String) {
    loop {
        match tokio::time::timeout(Duration::from_secs(10), heard.recv()).await.expect("the computer asks in time").expect("the link is open") {
            LinkEvent::Approve { id, reason, challenge } => return (id, reason, challenge),
            _ => continue,
        }
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_fingerprint_yes_reaches_the_computer_and_nothing_else_passes() {
    let Some(Setup { conn, key, name, bin }) = setup().await else {
        eprintln!("phone test skipped: set MPX_PHONE_HOST, MPX_PHONE_USER, MPX_PHONE_KEY, MPX_PHONE_NAME and MPX_PHONE_BIN");
        return;
    };
    let mut heard = link(&conn, &name).await;
    let ask = |what: &str| Command::new(&bin).args(["approve", "--to", &name, what]).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().expect("the computer's command runs");

    // Yes: signed with the phone's key, for exactly what was asked.
    let waiting = ask("the live test");
    let (id, reason, challenge) = next_approval(&mut heard).await;
    assert_eq!(reason, "the live test");
    let signature = share::approval_signature(&key, &id, &reason, &challenge).expect("the phone signs");
    share::approved(&conn, &id, &signature).await.expect("the answer is taken");
    let out = waiting.wait_with_output().unwrap();
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), format!("Approved on {name}."));

    // No.
    let waiting = ask("something else");
    let (id, _, _) = next_approval(&mut heard).await;
    share::approved(&conn, &id, "no").await.unwrap();
    let out = waiting.wait_with_output().unwrap();
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stderr).contains("refused on the phone"));

    // The right key, but a yes to other words than those asked: refused.
    let waiting = ask("delete nothing");
    let (id, _, challenge) = next_approval(&mut heard).await;
    let other = share::approval_signature(&key, &id, "delete everything", &challenge).unwrap();
    share::approved(&conn, &id, &other).await.unwrap();
    let out = waiting.wait_with_output().unwrap();
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stderr).contains("did not come from the paired phone"));

    // An answer to a request that is over is not taken.
    assert!(share::approved(&conn, &id, &other).await.is_err());
}
