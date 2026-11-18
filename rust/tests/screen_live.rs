//! Optional test of the phone-screen stream against a real computer with
//! the Multiplex package, Hyprland and mpv.
//!
//! Skipped unless `MPX_DESKTOP_HOST`, `MPX_DESKTOP_USER` and
//! `MPX_DESKTOP_KEY` (a key file) are set, and `ffmpeg` is here to make a
//! test picture; `MPX_DESKTOP_PORT` is optional.
//!
//! It opens a window on that computer for a few seconds. To keep it out
//! of sight, create the file `multiplex/screen-hidden` in that computer's
//! runtime folder first: the window then opens on a workspace that is not
//! shown.

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use multiplex_core::api::ssh_types::{ConnectError, ConnectOptions, Credentials};
use multiplex_core::engine::events::EventRelay;
use multiplex_core::engine::pipe::Pipe;
use multiplex_core::engine::ssh::{Connection, Connector};
use multiplex_proto::share::screen_command;

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

/// Three seconds of a moving test picture, the shape of a phone screen.
fn sample() -> Option<Vec<u8>> {
    let made = std::process::Command::new("ffmpeg")
        .args(["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=size=736x1600:rate=30", "-t", "3"])
        .args(["-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency", "-b:v", "2M", "-g", "30", "-f", "h264", "-"])
        .output()
        .ok()?;
    (made.status.success() && made.stdout.len() > 10_000).then_some(made.stdout)
}

#[tokio::test(flavor = "multi_thread")]
async fn a_picture_reaches_the_window_and_closing_is_immediate() {
    let Some(conn) = connect().await else {
        eprintln!("screen test skipped: set MPX_DESKTOP_HOST, MPX_DESKTOP_USER and MPX_DESKTOP_KEY");
        return;
    };
    let Some(picture) = sample() else {
        eprintln!("screen test skipped: ffmpeg could not make a test picture");
        return;
    };
    let conn = Arc::new(conn);

    let heard = Arc::new(Mutex::new(Vec::<String>::new()));
    let relay = Arc::new(EventRelay::<String>::new());
    let sink = heard.clone();
    relay.attach(Arc::new(move |reason: String| {
        sink.lock().unwrap().push(reason);
        true
    }));

    let started = Instant::now();
    let pipe = Pipe::open(conn.clone(), &screen_command("Test phone"), relay).await.expect("the window opens");
    eprintln!("window open in {:?}", started.elapsed());

    // The picture at its own speed: three seconds of it.
    let pieces: Vec<&[u8]> = picture.chunks(16 * 1024).collect();
    let pause = Duration::from_secs(3) / pieces.len() as u32;
    let mut most = 0;
    for piece in &pieces {
        pipe.write(piece.to_vec()).expect("the stream is open");
        most = most.max(pipe.in_flight());
        tokio::time::sleep(pause).await;
    }
    // The computer says what it has taken: nothing stays on its way.
    let waited = Instant::now();
    while pipe.in_flight() > 0 && waited.elapsed() < Duration::from_secs(3) {
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    eprintln!("{} bytes sent, at most {most} on their way, all taken {:?} after the last piece", picture.len(), waited.elapsed());
    assert_eq!(pipe.in_flight(), 0, "the computer reports what it has taken");
    assert!(most < picture.len() as u64, "it reported while the picture was still coming");
    assert!(heard.lock().unwrap().is_empty(), "still open: {:?}", heard.lock().unwrap());

    // Closing from the phone's side: heard at once, and no more writes.
    let closing = Instant::now();
    pipe.close();
    assert_eq!(*heard.lock().unwrap(), [""]);
    assert_eq!(pipe.write(vec![0; 16]), Err(String::new()));
    eprintln!("closed in {:?}", closing.elapsed());
}

#[tokio::test(flavor = "multi_thread")]
async fn a_phone_that_goes_silent_is_noticed_by_the_computer() {
    let Some(conn) = connect().await else {
        return;
    };
    let Some(picture) = sample() else {
        return;
    };
    let heard = Arc::new(Mutex::new(Vec::<String>::new()));
    let relay = Arc::new(EventRelay::<String>::new());
    let sink = heard.clone();
    relay.attach(Arc::new(move |reason: String| {
        sink.lock().unwrap().push(reason);
        true
    }));
    let pipe = Pipe::open(Arc::new(conn), &screen_command(""), relay).await.expect("the window opens");
    pipe.write(picture[..picture.len().min(200_000)].to_vec()).expect("open");

    // Not a word more: after a while the computer closes the window and
    // says why.
    let waiting = Instant::now();
    while heard.lock().unwrap().is_empty() && waiting.elapsed() < Duration::from_secs(15) {
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    eprintln!("the computer gave up after {:?}: {:?}", waiting.elapsed(), heard.lock().unwrap());
    assert_eq!(*heard.lock().unwrap(), ["The phone stopped sending its screen"]);
    assert!(waiting.elapsed() > Duration::from_secs(6), "not too eager: a short stall is forgiven");
    assert!(pipe.write(vec![0; 16]).is_err());
}
