//! Keeping a shell across a dropped connection, and shells that run a
//! command instead of the login shell (tmux).

mod support;

use std::sync::Arc;
use std::time::Duration;

use multiplex_core::api::terminal_types::{KeyModifiers, ShellEvent, ShellOptions, TerminalPalette};
use multiplex_core::engine::shell::ShellSession;
use multiplex_core::engine::ssh::Connector;
use support::{Logins, TestServer, PASSWORD};
use tokio::sync::mpsc;

fn options() -> ShellOptions {
    ShellOptions {
        cols: 40,
        rows: 10,
        term: "xterm-256color".into(),
        scrollback_lines: 100,
        env: vec![],
        startup_command: None,
        command: None,
        palette: TerminalPalette::default(),
    }
}

async fn server() -> TestServer {
    TestServer::start(Logins { password: Some(PASSWORD.into()), ..Default::default() }).await
}

/// Waits for an event that matches, taking frames on the way.
async fn wait_for(shell: &ShellSession, events: &mut mpsc::UnboundedReceiver<ShellEvent>, wanted: impl Fn(&ShellEvent) -> bool) -> ShellEvent {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            match events.recv().await {
                Some(event) if wanted(&event) => return event,
                Some(ShellEvent::Changed) => {
                    shell.frame();
                }
                Some(_) => {}
                None => panic!("events ended"),
            }
        }
    })
    .await
    .expect("timed out waiting for an event")
}

async fn wait_for_text(shell: &ShellSession, events: &mut mpsc::UnboundedReceiver<ShellEvent>, needle: &str) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    while !shell.visible_text().contains(needle) {
        let left = deadline.saturating_duration_since(tokio::time::Instant::now());
        match tokio::time::timeout(left, events.recv()).await {
            Ok(Some(ShellEvent::Changed)) => {
                shell.frame();
            }
            Ok(Some(_)) => {}
            _ => panic!("timed out waiting for {needle:?}; screen was:\n{}", shell.visible_text()),
        }
    }
}

#[tokio::test]
async fn a_shell_keeps_its_screen_on_a_new_connection() {
    let server = server().await;
    let first = Connector::connect(server.options()).await.unwrap();
    let (tx, mut events) = mpsc::unbounded_channel();
    let shell = ShellSession::open(&first, options(), Arc::new(move |e| tx.send(e).is_ok())).await.unwrap();
    wait_for_text(&shell, &mut events, "welcome").await;
    shell.send_text("before", KeyModifiers::default());
    wait_for_text(&shell, &mut events, "$ before").await;

    // The connection drops: the shell says so once.
    first.disconnect().await;
    wait_for(&shell, &mut events, |e| *e == ShellEvent::Disconnected).await;
    assert!(shell.is_closed());

    let second = Connector::connect(server.options()).await.unwrap();
    shell.reattach(&second, options()).await.unwrap();
    assert!(!shell.is_closed());
    shell.send_text("after", KeyModifiers::default());
    wait_for_text(&shell, &mut events, "$ after").await;
    // What was on screen before the drop is still there.
    assert!(shell.visible_text().contains("$ before"), "{}", shell.visible_text());
    std::mem::forget(second);
}

#[tokio::test]
async fn the_old_channel_ending_late_says_nothing() {
    let server = server().await;
    let first = Connector::connect(server.options()).await.unwrap();
    let (tx, mut events) = mpsc::unbounded_channel();
    let shell = ShellSession::open(&first, options(), Arc::new(move |e| tx.send(e).is_ok())).await.unwrap();
    wait_for_text(&shell, &mut events, "welcome").await;

    // Taken over before the old connection is noticed as gone.
    let second = Connector::connect(server.options()).await.unwrap();
    shell.reattach(&second, options()).await.unwrap();
    first.disconnect().await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    while let Ok(event) = events.try_recv() {
        assert!(!matches!(event, ShellEvent::Disconnected | ShellEvent::Exited { .. }), "unexpected {event:?}");
    }
    assert!(!shell.is_closed());
    std::mem::forget(second);
}

#[tokio::test]
async fn runs_a_command_instead_of_the_login_shell() {
    let server = server().await;
    let conn = Connector::connect(server.options()).await.unwrap();
    let (tx, mut events) = mpsc::unbounded_channel();
    let mut opts = options();
    opts.command = Some("echo from-command".into());
    let shell = ShellSession::open(&conn, opts, Arc::new(move |e| tx.send(e).is_ok())).await.unwrap();
    wait_for_text(&shell, &mut events, "from-command").await;
    // The test server's commands end with exit 0; no "welcome" shell ran.
    let exited = wait_for(&shell, &mut events, |e| matches!(e, ShellEvent::Exited { .. })).await;
    assert_eq!(exited, ShellEvent::Exited { code: Some(0) });
    assert!(!shell.visible_text().contains("welcome"));
    std::mem::forget(conn);
}

#[tokio::test]
async fn a_live_connection_answers_and_a_closed_one_does_not() {
    let server = server().await;
    let conn = Connector::connect(server.options()).await.unwrap();
    assert!(conn.check_alive(Duration::from_secs(5)).await);
    conn.disconnect().await;
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert!(!conn.check_alive(Duration::from_secs(1)).await);
}
