//! Optional test of the desk commands against a real computer with the
//! Multiplex package and Hyprland running.
//!
//! Skipped unless `MPX_DESKTOP_HOST`, `MPX_DESKTOP_USER` and
//! `MPX_DESKTOP_KEY` (a key file) are set; `MPX_DESKTOP_PORT` is optional.
//!
//! It only reads, plus one request that changes nothing: giving the focus
//! to the monitor that already has it.

use multiplex_core::api::ssh_types::{ConnectError, ConnectOptions, Credentials};
use multiplex_core::engine::desk;
use multiplex_core::engine::ssh::{Connection, Connector};
use multiplex_proto::desk::DeskAction;

async fn connect() -> Option<Connection> {
    let host = std::env::var("MPX_DESKTOP_HOST").ok()?;
    let username = std::env::var("MPX_DESKTOP_USER").ok()?;
    let key = std::fs::read_to_string(std::env::var("MPX_DESKTOP_KEY").ok()?).expect("key file");
    let port = std::env::var("MPX_DESKTOP_PORT").ok().and_then(|p| p.parse().ok()).unwrap_or(22);
    let mut opts = ConnectOptions {
        host,
        port,
        username,
        credentials: Credentials { private_key: Some(key), ..Default::default() },
        trusted_host_keys: vec![],
        keepalive_secs: 10,
        connect_timeout_secs: 20,
        jump: None,
        forward_agent: false,
        via_tailscale: false,
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

#[tokio::test(flavor = "multi_thread")]
async fn the_desk_answers_over_ssh() {
    let Some(conn) = connect().await else {
        eprintln!("desk test skipped: set MPX_DESKTOP_HOST, MPX_DESKTOP_USER and MPX_DESKTOP_KEY");
        return;
    };

    let started = std::time::Instant::now();
    let state = desk::state(&conn).await.expect("state");
    eprintln!("state in {:?}: {} monitors", started.elapsed(), state.monitors.len());
    assert!(!state.monitors.is_empty());
    assert!(state.monitors.iter().all(|m| m.slots.len() == 10 && m.slots.iter().map(|s| s.slot).eq(1..=10)));
    let focused = state.monitors.iter().find(|m| m.focused).expect("a monitor has the focus");

    let bindings = desk::bindings(&conn).await.expect("bindings");
    eprintln!("{} bindings, {} runnable", bindings.len(), bindings.iter().filter(|b| b.run).count());
    assert!(bindings.iter().any(|b| b.run));

    // Changes nothing: that monitor has the focus already.
    let started = std::time::Instant::now();
    let after = desk::act(&conn, &DeskAction::FocusMonitor { name: focused.name.clone() }).await.expect("a request that changes nothing");
    eprintln!("action and new state in {:?}", started.elapsed());
    assert!(after.monitors.iter().any(|m| m.focused));

    // Refused on the phone, before anything is sent.
    assert!(desk::act(&conn, &DeskAction::Workspace { slot: 11, monitor: None }).await.is_err());
    // Refused by the computer, with its reason.
    let err = desk::act(&conn, &DeskAction::Bind { keys: "NO + SUCH KEYS".into() }).await.unwrap_err();
    assert_eq!(err.to_string(), "The computer has no binding for NO + SUCH KEYS");
}

/// The touchpad starts on the computer and ends cleanly. Only a "still
/// there" line is sent: nothing moves and no key is pressed.
#[tokio::test(flavor = "multi_thread")]
async fn the_touchpad_starts_and_ends_without_touching_anything() {
    use std::sync::{Arc, Mutex};

    use multiplex_core::engine::events::EventRelay;
    use multiplex_core::engine::touchpad::Touchpad;
    use multiplex_proto::input::InputEvent;

    let Some(conn) = connect().await else {
        eprintln!("touchpad test skipped: set MPX_DESKTOP_HOST, MPX_DESKTOP_USER and MPX_DESKTOP_KEY");
        return;
    };
    let ended = Arc::new(EventRelay::<String>::new());
    let reasons = Arc::new(Mutex::new(Vec::<String>::new()));
    let seen = reasons.clone();
    ended.attach(Arc::new(move |reason| {
        seen.lock().unwrap().push(reason);
        true
    }));
    let started = std::time::Instant::now();
    let pad = Touchpad::open(Arc::new(conn), ended).await.expect("the touchpad starts");
    eprintln!("touchpad ready in {:?}", started.elapsed());
    assert!(pad.send(InputEvent::Ping));
    tokio::time::sleep(std::time::Duration::from_millis(300)).await;
    assert!(reasons.lock().unwrap().is_empty(), "it is still running");
    pad.close();
    for _ in 0..40 {
        if !reasons.lock().unwrap().is_empty() {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    }
    assert_eq!(*reasons.lock().unwrap(), vec![String::new()], "closed from here: no reason to give");
}
