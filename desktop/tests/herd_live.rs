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

    /// Whether it did as asked, and everything it said (its refusal too).
    fn asked(&self, args: &[&str]) -> (bool, String) {
        let done = Command::new(env!("CARGO_BIN_EXE_multiplex")).env("MULTIPLEX_HERD_SESSION", &self.name).args(args).output().expect("multiplex runs");
        (done.status.success(), format!("{}{}", String::from_utf8_lossy(&done.stdout), String::from_utf8_lossy(&done.stderr)))
    }

    /// What the pane shows now.
    fn screen(&self, pane: &str) -> String {
        Command::new("herdr").args(["--session", &self.name, "pane", "read", pane, "--source", "visible"]).output().map(|o| String::from_utf8_lossy(&o.stdout).into_owned()).unwrap_or_default()
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

fn live() -> bool {
    let live = std::env::var("MPX_HERD_LIVE").as_deref() == Ok("1");
    if !live {
        eprintln!("skipped: set MPX_HERD_LIVE=1 to run against a herdr session of the test's own");
    }
    live
}

/// A herdr session of the test's own, with one workspace in /tmp, and
/// the lines of `multiplex herd <following>` about it as they come.
fn own_session(tag: &str, following: &str) -> (OwnSession, String, Receiver<String>) {
    let name = format!("mpx-{tag}-{}", std::process::id());
    let server = Command::new("herdr").args(["--session", &name, "server"]).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn().expect("herdr is installed");
    let mut own = OwnSession { name: name.clone(), server, watch: None };
    let started = Instant::now();
    while !own.herdr(&["workspace", "list"]).contains("workspace_list") {
        assert!(started.elapsed() < Duration::from_secs(10), "the test's herdr session did not start");
        std::thread::sleep(Duration::from_millis(100));
    }
    let created: serde_json::Value = serde_json::from_str(&own.herdr(&["workspace", "create", "--cwd", "/tmp", "--label", "live", "--no-focus"])).expect("herdr answers in JSON");
    let pane = created["result"]["root_pane"]["pane_id"].as_str().expect("a pane id").to_owned();

    let mut watch = Command::new(env!("CARGO_BIN_EXE_multiplex")).env("MULTIPLEX_HERD_SESSION", &name).args(["herd", following]).stdout(Stdio::piped()).spawn().expect("multiplex runs");
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
    (own, pane, lines)
}

/// A stand-in for an agent that asks by choice, as Claude and Codex do:
/// the pointer moves with the arrows and Enter takes what it is on. A
/// number key does nothing here, as in some of them.
const ASKS: &str = r#"#!/bin/bash
choices=("Yes" "Yes, and don't ask again for make" "No, and tell me what to do differently (esc)")
at=0
draw() {
  printf '\033[2J\033[H'
  printf ' Bash command\n\n   make test\n   Run the test suite\n\n Do you want to proceed?\n'
  for i in "${!choices[@]}"; do
    if [ "$i" = "$at" ]; then printf ' ❯ %d. %s\n' $((i+1)) "${choices[$i]}"; else printf '   %d. %s\n' $((i+1)) "${choices[$i]}"; fi
  done
}
draw
while IFS= read -rsn1 key; do
  case "$key" in
    $'\033')
      read -rsn2 -t 0.05 rest
      case "$rest" in
        '[A'|'OA') [ $at -gt 0 ] && at=$((at-1));;
        '[B'|'OB') [ $at -lt 2 ] && at=$((at+1));;
        '') printf '\033[2J\033[Hchosen: esc\n'; exit;;
      esac
      draw;;
    '') printf '\033[2J\033[Hchosen: %d\n' $((at+1)); exit;;
  esac
done
"#;

/// The next thing `news` says, within `limit`.
fn next_news(lines: &Receiver<String>, limit: Duration, what: &str) -> multiplex_proto::share::LinkEvent {
    let line = lines.recv_timeout(limit).unwrap_or_else(|_| panic!("news never said: {what}"));
    multiplex_proto::share::parse_link_event(&line).unwrap_or_else(|_| panic!("not a line of the link: {line}"))
}

#[test]
fn an_agent_that_asks_is_told_with_its_choices_and_answered_only_while_it_asks() {
    use multiplex_proto::share::LinkEvent;
    if !live() {
        return;
    }
    let (own, pane, news) = own_session("asks", "news");
    let name = own.name.clone();
    let report = |state: &str| own.herdr(&["pane", "report-agent", &pane, "--source", "multiplex-test", "--agent", "claude", "--state", state]);
    let shows = |what: &str| {
        let asked = Instant::now();
        while !own.screen(&pane).contains(what) {
            assert!(asked.elapsed() < Duration::from_secs(5), "the pane never showed {what:?}: {}", own.screen(&pane));
            std::thread::sleep(Duration::from_millis(50));
        }
    };
    let script = std::env::temp_dir().join(format!("mpx-asks-{}.sh", std::process::id()));
    std::fs::write(&script, ASKS).unwrap();

    // The agent works, then asks. (What is there when the listening
    // begins is not news, so it is given a moment to be seen working.)
    report("working");
    own.herdr(&["pane", "run", &pane, &format!("bash {}", script.display())]);
    shows("❯ 1. Yes");
    std::thread::sleep(Duration::from_millis(700));
    let asked_at = Instant::now();
    report("blocked");
    let LinkEvent::Agent(agent) = next_news(&news, Duration::from_secs(3), "it waits") else { panic!("an agent was expected") };
    assert!(asked_at.elapsed() < Duration::from_millis(1500), "told after {:?}", asked_at.elapsed());
    assert_eq!((agent.session.as_str(), agent.id.as_str(), agent.status), (name.as_str(), pane.as_str(), AgentStatus::Blocked));
    assert_eq!(agent.question, "Bash command\n\nmake test\nRun the test suite\n\nDo you want to proceed?");
    assert_eq!(agent.choices.iter().map(|c| (c.key.as_str(), c.label.as_str())).collect::<Vec<_>>(), [("1", "Yes"), ("2", "Yes, and don't ask again for make"), ("3", "No, and tell me what to do differently (esc)")]);
    assert_eq!(agent.mark.len(), 16);

    // An answer to another question, or words where a choice is wanted,
    // is not sent: the pointer has not moved and nothing was taken.
    let answer = |mark: &str, how: &str, what: &str| own.asked(&["herd", "do", "answer", &name, &pane, mark, how, what]);
    let (ok, said) = answer("0123456789abcdef", "choice", "1");
    assert!(!ok && said.contains("no longer what it asks"), "{said}");
    let (ok, said) = answer(&agent.mark, "text", &URL_SAFE_NO_PAD.encode("yes please"));
    assert!(!ok && said.contains("one of its choices"), "{said}");
    let (ok, said) = answer(&agent.mark, "choice", "4");
    assert!(!ok && said.contains("not one of its choices"), "{said}");
    assert!(own.screen(&pane).contains("❯ 1. Yes"));

    // The third choice, for the question it was shown for: taken.
    let (ok, said) = answer(&agent.mark, "choice", "3");
    assert!(ok, "{said}");
    shows("chosen: 3");
    // Pressed once more (a second tap, a notification left over): the
    // question is gone, so nothing is sent.
    let (ok, said) = answer(&agent.mark, "choice", "3");
    assert!(!ok && said.contains("no longer what it asks"), "{said}");

    // It goes on: the phone is told that it no longer waits.
    report("working");
    assert_eq!(next_news(&news, Duration::from_secs(3), "it no longer waits"), LinkEvent::Settled { session: name.clone(), pane: pane.clone() });
    let (ok, said) = answer("-", "text", &URL_SAFE_NO_PAD.encode("echo too-soon"));
    assert!(!ok && said.contains("working again"), "{said}");

    // It stops and sits at its prompt: words for it arrive. (herdr
    // itself decides when a stop counts as "done", so that news is
    // covered by the test of `news` on its own.)
    report("idle");
    let (ok, said) = answer("-", "text", &URL_SAFE_NO_PAD.encode("echo answered-$((40+2))"));
    assert!(ok, "{said}");
    shows("answered-42");
    assert!(!own.screen(&pane).contains("too-soon"));
    // Its pane closes while it waits: that is told as well.
    report("blocked");
    let LinkEvent::Agent(again) = next_news(&news, Duration::from_secs(3), "it waits again") else { panic!("an agent was expected") };
    assert_eq!((again.status, again.choices.len(), again.mark.as_str()), (AgentStatus::Blocked, 0, ""), "it asks in words now: no choices are on its screen");
    own.herdr(&["pane", "close", &pane]);
    assert_eq!(next_news(&news, Duration::from_secs(3), "its pane closed"), LinkEvent::Settled { session: name.clone(), pane: pane.clone() });
    let _ = std::fs::remove_file(&script);
}

#[test]
fn the_herd_is_told_as_it_changes_and_does_as_asked() {
    if !live() {
        return;
    }
    let (own, pane, lines) = own_session("live", "watch");
    let name = own.name.clone();

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

    // A folder opened as a workspace: offered (the test's pane is in
    // /tmp, and what is open in herdr is offered), looked into, opened.
    let (ok, printed) = own.multiplex(&["herd", "places"]);
    assert!(ok);
    let places = multiplex_proto::herd::parse_places(&printed).expect("a list of folders");
    assert!(places.iter().any(|place| place.path == "/tmp"), "the folder a pane is in is offered");
    assert_eq!(places.last().map(|place| place.shown.as_str()), Some("/"), "the root comes last, to walk from");
    let inside = std::env::temp_dir().join(format!("mpx-live-{}", std::process::id()));
    std::fs::create_dir_all(inside.join("project/.git")).unwrap();
    std::fs::create_dir_all(inside.join("plain")).unwrap();
    let (ok, printed) = own.multiplex(&["herd", "folders", &URL_SAFE_NO_PAD.encode(inside.to_str().unwrap())]);
    assert!(ok);
    let folders = multiplex_proto::herd::parse_places(&printed).unwrap();
    assert_eq!(folders.iter().map(|p| (multiplex_proto::herd::folder_name(&p.path), p.project)).collect::<Vec<_>>(), [("plain", false), ("project", true)]);
    let (ok, printed) = own.multiplex(&["herd", "do", "new-workspace", &name, &URL_SAFE_NO_PAD.encode(folders[1].path.as_str()), &URL_SAFE_NO_PAD.encode("project")]);
    assert!(ok);
    let space = multiplex_proto::herd::parse_made(&printed).unwrap();
    let herd = next(&lines, Duration::from_secs(3), "the new workspace", |herd| herd.sessions[0].workspaces.iter().any(|w| w.id == space.workspace));
    let made = herd.sessions[0].workspaces.iter().find(|w| w.id == space.workspace).unwrap();
    assert_eq!((made.label.as_str(), made.tabs[0].panes[0].id.as_str()), ("project", space.pane.as_str()));
    assert!(made.tabs[0].panes[0].folder.ends_with("/project"), "its terminal is in that folder");
    assert!(own.multiplex(&["herd", "do", "close-pane", &name, &space.pane]).0);
    next(&lines, Duration::from_secs(3), "the workspace gone with its only pane", |herd| herd.sessions[0].workspaces.iter().all(|w| w.id != space.workspace));
    assert!(!own.multiplex(&["herd", "folders", &URL_SAFE_NO_PAD.encode("/no/such/folder")]).0);
    let _ = std::fs::remove_dir_all(&inside);

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
