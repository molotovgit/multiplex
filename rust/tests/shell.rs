//! Interactive shells against the in-process test server's echo shell.

mod support;

use std::sync::Arc;
use std::time::Duration;

use support::{Logins, TestServer, PASSWORD};
use tokio::sync::mpsc;
use multiplex_core::api::terminal_types::{KeyModifiers, ShellEvent, ShellOptions, TerminalPalette};
use multiplex_core::engine::shell::ShellSession;
use multiplex_core::engine::ssh::Connector;

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

/// Opens a shell and returns it with the stream of its events.
async fn open_shell(options: ShellOptions) -> (ShellSession, mpsc::UnboundedReceiver<ShellEvent>) {
    let server = TestServer::start(Logins { password: Some(PASSWORD.into()), ..Default::default() }).await;
    let conn = Connector::connect(server.options()).await.unwrap();
    let (tx, rx) = mpsc::unbounded_channel();
    let sink = Arc::new(move |event| tx.send(event).is_ok());
    let shell = ShellSession::open(&conn, options, sink).await.unwrap();
    // Keep the connection alive for the whole test.
    std::mem::forget(conn);
    (shell, rx)
}

/// Waits until the screen shows `needle`, taking frames as the app would.
async fn wait_for_text(shell: &ShellSession, events: &mut mpsc::UnboundedReceiver<ShellEvent>, needle: &str) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    loop {
        if shell.visible_text().contains(needle) {
            return;
        }
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
async fn shows_server_output_and_echoes_typing() {
    let (shell, mut events) = open_shell(options()).await;
    wait_for_text(&shell, &mut events, "welcome").await;

    shell.send_text("hello", KeyModifiers::default());
    wait_for_text(&shell, &mut events, "$ hello").await;

    let frame = shell.frame();
    assert_eq!((frame.rows, frame.cols), (10, 40));
    assert_eq!(frame.lines[1].runs[0].text, "$ hello");
    assert_eq!((frame.cursor.row, frame.cursor.col), (1, 7));
}

#[tokio::test]
async fn tells_the_server_about_a_new_size() {
    let (shell, mut events) = open_shell(options()).await;
    wait_for_text(&shell, &mut events, "welcome").await;
    shell.resize(60, 20);
    wait_for_text(&shell, &mut events, "[resized 60x20]").await;
    let frame = shell.frame();
    assert_eq!((frame.rows, frame.cols), (20, 60));
}

#[tokio::test]
async fn runs_the_startup_command() {
    let mut opts = options();
    opts.startup_command = Some("uptime".into());
    let (shell, mut events) = open_shell(opts).await;
    // The echo shell sends the command back, carriage return included.
    wait_for_text(&shell, &mut events, "$ uptime").await;
}

#[tokio::test]
async fn reports_the_exit_code_when_the_shell_ends() {
    let (shell, mut events) = open_shell(options()).await;
    wait_for_text(&shell, &mut events, "welcome").await;
    // Ctrl+D ends the test server's shell with exit code 0.
    shell.send_text("d", KeyModifiers { ctrl: true, ..Default::default() });
    let exited = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            match events.recv().await {
                Some(ShellEvent::Exited { code }) => return code,
                Some(_) => continue,
                None => panic!("events ended without an exit"),
            }
        }
    })
    .await
    .expect("shell did not exit");
    assert_eq!(exited, Some(0));
    assert!(shell.is_closed());
}

#[tokio::test]
async fn coalesces_change_events_until_a_frame_is_taken() {
    let (shell, mut events) = open_shell(options()).await;
    wait_for_text(&shell, &mut events, "welcome").await;
    shell.frame();
    // Drain whatever is pending, then send a lot of small updates.
    while events.try_recv().is_ok() {}
    for i in 0..50 {
        shell.send_text(&format!("{i} "), KeyModifiers::default());
    }
    tokio::time::sleep(Duration::from_millis(300)).await;
    let mut changed = 0;
    while let Ok(event) = events.try_recv() {
        if event == ShellEvent::Changed {
            changed += 1;
        }
    }
    // Without a frame being taken, only one Changed may be sent.
    assert_eq!(changed, 1);
}
