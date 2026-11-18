//! `multiplex herd` against a real herdr: a session of this test's own,
//! started without a screen and removed afterwards. Nothing else that
//! herdr runs is looked at or touched.
//!
//! Runs only when asked for (`MPX_HERD_LIVE=1 cargo test --test herd_live`)
//! and where herdr is installed.

use std::io::{BufRead, BufReader};
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::{channel, Receiver};
use std::time::{Duration, Instant};

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use multiplex_proto::agents::AgentStatus;
use multiplex_proto::herd::{parse_state, parse_text, Herd};

/// The test's own herdr session; stopped and deleted when dropped, also
/// when the test fails.
struct OwnSession {
    name: String,
    server: Child,
    watch: Option<Child>,
}

impl OwnSession {
    fn herdr(&self, args: &[&str]) -> String {
        let done = Command::new("herdr").args(["--session", &self.name]).args(args).output().expect("herdr runs");
        String::from_utf8_lossy(&done.stdout).into_owned()
    }

    fn multiplex(&self, args: &[&str]) -> (bool, String) {
        let done = Command::new(env!("CARGO_BIN_EXE_multiplex")).env("MULTIPLEX_HERD_SESSION", &self.name).args(args).output().expect("multiplex runs");
        (done.status.success(), String::from_utf8_lossy(&done.stdout).into_owned())
    }
}

impl Drop for OwnSession {
    fn drop(&mut self) {
        if let Some(mut watch) = self.watch.take() {
            let _ = watch.kill();
            let _ = watch.wait();
        }
        let _ = Command::new("herdr").args(["--session", &self.name, "server", "stop"]).output();
        let _ = self.server.wait();
        let _ = Command::new("herdr").args(["session", "delete", &self.name]).output();
    }
}

/// The next state `watch` prints for which `wanted` holds, within `limit`.
fn next(lines: &Receiver<String>, limit: Duration, what: &str, wanted: impl Fn(&Herd) -> bool) -> Herd {
    let until = Instant::now() + limit;
    loop {
        let left = until.checked_duration_since(Instant::now()).unwrap_or_else(|| panic!("watch never said: {what}"));
        let line = lines.recv_timeout(left).unwrap_or_else(|_| panic!("watch never said: {what}"));
        if line.trim().is_empty() {
            continue;
        }
        let herd = parse_state(&line).expect("a line of watch is a herd");
        if wanted(&herd) {
            return herd;
        }
    }
}

fn status_of(herd: &Herd, pane: &str) -> Option<AgentStatus> {
    herd.sessions.iter().flat_map(|s| &s.workspaces).flat_map(|w| &w.tabs).flat_map(|t| &t.panes).find(|p| p.id == pane)?.agent.as_ref().map(|a| a.status)
}

#[test]
fn the_herd_is_told_as_it_changes_and_does_as_asked() {
    if std::env::var("MPX_HERD_LIVE").as_deref() != Ok("1") {
        eprintln!("skipped: set MPX_HERD_LIVE=1 to run against a herdr session of the test's own");
        return;
    }
    let name = format!("mpx-live-{}", std::process::id());
    let server = Command::new("herdr").args(["--session", &name, "server"]).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn().expect("herdr is installed");
    let mut own = OwnSession { name: name.clone(), server, watch: None };
    let started = Instant::now();
    while !own.herdr(&["workspace", "list"]).contains("workspace_list") {
        assert!(started.elapsed() < Duration::from_secs(10), "the test's herdr session did not start");
        std::thread::sleep(Duration::from_millis(100));
    }
    let created: serde_json::Value = serde_json::from_str(&own.herdr(&["workspace", "create", "--cwd", "/tmp", "--label", "live", "--no-focus"])).expect("herdr answers in JSON");
    let pane = created["result"]["root_pane"]["pane_id"].as_str().expect("a pane id").to_owned();

    let mut watch = Command::new(env!("CARGO_BIN_EXE_multiplex")).env("MULTIPLEX_HERD_SESSION", &name).args(["herd", "watch"]).stdout(Stdio::piped()).spawn().expect("multiplex runs");
    let out = watch.stdout.take().unwrap();
    own.watch = Some(watch);
    let (tell, lines) = channel::<String>();
    std::thread::spawn(move || {
        for line in BufReader::new(out).lines().map_while(Result::ok) {
            if tell.send(line).is_err() {
                break;
            }
        }
    });

    // At once: the session with its one workspace, tab and plain terminal.
    let first = next(&lines, Duration::from_secs(5), "the session", |herd| herd.sessions.len() == 1);
    assert!(first.available);
    assert_eq!(first.sessions[0].name, name);
    assert_eq!(first.sessions[0].workspaces.iter().map(|w| w.label.as_str()).collect::<Vec<_>>(), ["live"]);
    let the_pane = &first.sessions[0].workspaces[0].tabs[0].panes[0];
    assert_eq!((the_pane.id.as_str(), the_pane.folder.as_str(), the_pane.agent.is_none()), (pane.as_str(), "/tmp", true));
    assert!(first.agents().is_empty());

    // An agent appears in the pane, and each change of its state is told
    // without anyone asking again.
    for (state, status) in [("working", AgentStatus::Working), ("blocked", AgentStatus::Blocked), ("idle", AgentStatus::Idle)] {
        let asked = Instant::now();
        own.herdr(&["pane", "report-agent", &pane, "--source", "multiplex-test", "--agent", "claude", "--state", state]);
        let herd = next(&lines, Duration::from_secs(3), state, |herd| status_of(herd, &pane) == Some(status));
        assert!(asked.elapsed() < Duration::from_secs(1), "{state} took {:?}", asked.elapsed());
        assert_eq!(herd.waiting(), usize::from(status == AgentStatus::Blocked));
        assert_eq!(herd.agents()[0].folder, "tmp");
    }
    own.herdr(&["pane", "release-agent", &pane, "--source", "multiplex-test", "--agent", "claude"]);
    next(&lines, Duration::from_secs(3), "the agent gone", |herd| status_of(herd, &pane).is_none());

    // A new tab is told too, with its pane.
    own.herdr(&["tab", "create", "--workspace", "w1", "--label", "second", "--no-focus"]);
    let herd = next(&lines, Duration::from_secs(3), "the second tab", |herd| herd.sessions[0].workspaces[0].tabs.len() == 2);
    assert_eq!(herd.sessions[0].workspaces[0].tabs[1].label, "second");
    assert_eq!(herd.sessions[0].workspaces[0].tabs[1].panes.len(), 1);

    // Text for the pane arrives as written, whatever a shell would have
    // made of it on the way, and is run; keys are pressed; output is read.
    let text = r#"echo "live $((20+22)) it's `echo fine`""#;
    let (ok, _) = own.multiplex(&["herd", "do", "prompt", &name, &pane, &URL_SAFE_NO_PAD.encode(text)]);
    assert!(ok);
    let (ok, _) = own.multiplex(&["herd", "do", "keys", &name, &pane, "e", "c", "h", "o", "space", "k", "minus", "o", "k", "enter"]);
    assert!(ok);
    let asked = Instant::now();
    loop {
        let (ok, printed) = own.multiplex(&["herd", "do", "read", &name, &pane, "40"]);
        assert!(ok);
        let seen = parse_text(&printed).expect("read prints one line of JSON").text;
        if seen.contains("live 42 it's fine") && seen.lines().any(|line| line.trim() == "k-ok") {
            break;
        }
        assert!(asked.elapsed() < Duration::from_secs(5), "the pane never showed it: {seen}");
        std::thread::sleep(Duration::from_millis(100));
    }

    // One pane in a terminal of another size: what is typed there runs in
    // the pane, its picture is drawn, and the pane itself is not resized.
    let size_of = |own: &OwnSession| {
        let layout: serde_json::Value = serde_json::from_str(&own.herdr(&["pane", "layout", "--pane", &pane])).unwrap();
        let rect = &layout["result"]["layout"]["panes"][0]["rect"];
        (rect["width"].as_u64().unwrap(), rect["height"].as_u64().unwrap())
    };
    let before = size_of(&own);
    let mut view = Command::new(env!("CARGO_BIN_EXE_multiplex"))
        .env("MULTIPLEX_HERD_SESSION", &name)
        .args(["herd", "pane", &name, &pane, "--cols", "44", "--rows", "12"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("multiplex runs");
    let mut keys = view.stdin.take().unwrap();
    std::thread::sleep(Duration::from_millis(400));
    use std::io::Write;
    keys.write_all(b"echo view-$((30+3))\r").unwrap();
    keys.flush().unwrap();
    std::thread::sleep(Duration::from_millis(700));
    assert_eq!(size_of(&own), before, "the pane kept its size while it was viewed at 44 by 12");
    // Ctrl+\ leaves; what follows it in the same breath is not typed.
    keys.write_all(b"\x1cecho never\r").unwrap();
    keys.flush().unwrap();
    let drawn = view.wait_with_output().expect("the view ends");
    assert!(drawn.status.success());
    let picture = String::from_utf8_lossy(&drawn.stdout).into_owned();
    assert!(picture.contains("view-33"), "the pane's answer was drawn");
    assert!(picture.ends_with("\x1b[?25h\x1b[0m\x1b[2J\x1b[H"), "the terminal is left as a terminal");
    let (_, printed) = own.multiplex(&["herd", "do", "read", &name, &pane, "40"]);
    let seen = parse_text(&printed).unwrap().text;
    assert!(seen.contains("view-33") && !seen.contains("never"), "{seen}");
    // A pane that is not there: herdr's own reason, and a failure.
    let none = Command::new(env!("CARGO_BIN_EXE_multiplex")).args(["herd", "pane", &name, "w9:p9", "--cols", "40", "--rows", "10"]).stdin(Stdio::null()).output().unwrap();
    assert!(!none.status.success());
    assert!(String::from_utf8_lossy(&none.stderr).contains("not found"));

    // Made from outside: a tab with a name, told by `watch` like any
    // other change, and closed again; and which agents could be started.
    let (ok, printed) = own.multiplex(&["herd", "do", "new-tab", &name, "w1", &URL_SAFE_NO_PAD.encode("from the phone")]);
    assert!(ok);
    let made = multiplex_proto::herd::parse_made(&printed).expect("what was made is said");
    let herd = next(&lines, Duration::from_secs(3), "the tab made from outside", |herd| herd.sessions[0].workspaces[0].tabs.iter().any(|tab| tab.id == made.tab));
    let tab = herd.sessions[0].workspaces[0].tabs.iter().find(|tab| tab.id == made.tab).unwrap();
    assert_eq!((tab.label.as_str(), tab.panes.len(), tab.panes[0].id.as_str()), ("from the phone", 1, made.pane.as_str()));
    assert!(own.multiplex(&["herd", "do", "close-pane", &name, &made.pane]).0);
    next(&lines, Duration::from_secs(3), "the tab gone with its last pane", |herd| herd.sessions[0].workspaces[0].tabs.iter().all(|tab| tab.id != made.tab));
    let (ok, printed) = own.multiplex(&["herd", "do", "new-tab", &name, "w1"]);
    assert!(ok);
    let again = multiplex_proto::herd::parse_made(&printed).unwrap();
    // Waited for before it is closed: `watch` tells where things have
    // settled, and a tab made and closed in one breath is never told.
    next(&lines, Duration::from_secs(3), "the second tab", |herd| herd.sessions[0].workspaces[0].tabs.iter().any(|tab| tab.id == again.tab));
    assert!(own.multiplex(&["herd", "do", "close-tab", &name, &again.tab]).0);
    next(&lines, Duration::from_secs(3), "that tab closed too", |herd| herd.sessions[0].workspaces[0].tabs.iter().all(|tab| tab.id != again.tab));
    assert!(!own.multiplex(&["herd", "do", "new-tab", &name, "w99"]).0, "a workspace that is not there");
    let (ok, printed) = own.multiplex(&["herd", "kinds"]);
    assert!(ok);
    multiplex_proto::herd::parse_kinds(&printed).expect("a list of kinds");

    // What is not there, or not an id, is refused.
    assert!(!own.multiplex(&["herd", "do", "keys", &name, "w9:p9", "enter"]).0);
    assert!(!own.multiplex(&["herd", "do", "read", &name, "w1:p1;ls", "5"]).0);

    // `state` says the same as the last line of `watch`.
    let (ok, printed) = own.multiplex(&["herd", "state"]);
    assert!(ok);
    let state = parse_state(&printed).unwrap();
    assert!(state.sessions[0].running);
    assert_eq!(state.sessions[0].workspaces[0].tabs.len(), 2);

    // The session stops: herdr still knows it by name, and so does the
    // phone, as one that is not running and has nothing in it. `watch`
    // notices by itself (it looks for sessions every few seconds).
    own.herdr(&["server", "stop"]);
    let herd = next(&lines, Duration::from_secs(12), "the session stopped", |herd| herd.sessions.first().is_some_and(|session| !session.running));
    assert_eq!((herd.sessions[0].name.as_str(), herd.sessions[0].workspaces.len()), (name.as_str(), 0));
    let (ok, printed) = own.multiplex(&["herd", "state"]);
    assert!(ok);
    let state = parse_state(&printed).unwrap();
    assert_eq!((state.sessions.len(), state.sessions[0].running, state.agents().len()), (1, false, 0));
}
