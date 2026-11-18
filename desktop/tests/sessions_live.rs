//! The phone's side of Multiplex's own session server, end to end: the
//! real command, a server of the test's own on a socket of its own, real
//! terminals, and a stand-in for an agent that asks by choice.

use std::io::{BufRead, BufReader, Read, Write};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::{channel, Receiver};
use std::time::{Duration, Instant};

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use multiplex_proto::agents::AgentStatus;
use multiplex_proto::herd::{parse_made, parse_places, parse_state, parse_text, Herd};
use multiplex_proto::share::{parse_link_event, LinkEvent};

/// A server of the test's own; stopped, with all its terminals, when dropped.
struct Own {
    socket: PathBuf,
    following: Vec<Child>,
    _dir: tempfile::TempDir,
}

impl Own {
    fn command(&self, args: &[&str]) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_multiplex"));
        command.env("MULTIPLEX_SESSIONS_SOCKET", &self.socket).env("SHELL", "/bin/bash").args(args);
        command
    }

    /// Whether it did as asked, and everything it said (its refusal too).
    fn asked(&self, args: &[&str]) -> (bool, String) {
        let done = self.command(args).output().expect("multiplex runs");
        (done.status.success(), format!("{}{}", String::from_utf8_lossy(&done.stdout), String::from_utf8_lossy(&done.stderr)))
    }

    /// The lines a command that keeps talking prints, as they come.
    fn follow(&mut self, args: &[&str]) -> Receiver<String> {
        let mut child = self.command(args).stdout(Stdio::piped()).spawn().expect("multiplex runs");
        let out = child.stdout.take().unwrap();
        self.following.push(child);
        let (tell, lines) = channel::<String>();
        std::thread::spawn(move || {
            for line in BufReader::new(out).lines().map_while(Result::ok) {
                if tell.send(line).is_err() {
                    break;
                }
            }
        });
        lines
    }

    fn text(&self, pane: &str) -> String {
        let (ok, printed) = self.asked(&["herd", "do", "read", "main", pane, "60"]);
        assert!(ok, "{printed}");
        parse_text(&printed).expect("read prints one line of JSON").text
    }

    fn shows(&self, pane: &str, what: &str) {
        let asked = Instant::now();
        while !self.text(pane).contains(what) {
            assert!(asked.elapsed() < Duration::from_secs(6), "the terminal never showed {what:?}: {}", self.text(pane));
            std::thread::sleep(Duration::from_millis(50));
        }
    }
}

impl Drop for Own {
    fn drop(&mut self) {
        for child in &mut self.following {
            let _ = child.kill();
            let _ = child.wait();
        }
        let _ = self.command(&["sessions", "stop"]).output();
    }
}

/// The next state `watch` prints for which `wanted` holds.
fn next(lines: &Receiver<String>, what: &str, wanted: impl Fn(&Herd) -> bool) -> Herd {
    let until = Instant::now() + Duration::from_secs(6);
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

fn next_news(lines: &Receiver<String>, what: &str) -> LinkEvent {
    let line = lines.recv_timeout(Duration::from_secs(6)).unwrap_or_else(|_| panic!("news never said: {what}"));
    parse_link_event(&line).unwrap_or_else(|_| panic!("not a line of the link: {line}"))
}

fn status_of(herd: &Herd, pane: &str) -> Option<AgentStatus> {
    herd.sessions.iter().flat_map(|s| &s.workspaces).flat_map(|w| &w.tabs).flat_map(|t| &t.panes).find(|p| p.id == pane)?.agent.as_ref().map(|a| a.status)
}

fn packed(text: &str) -> String {
    URL_SAFE_NO_PAD.encode(text)
}

/// A stand-in for an agent that asks by choice, as Claude and Codex do:
/// it is quiet for a moment, then asks; the pointer moves with the arrows
/// and Enter takes what it is on. A number key does nothing here, as in
/// some of them. It is a file named `claude`, which is how an agent is
/// known.
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
sleep 2
draw
while IFS= read -rsn1 key; do
  case "$key" in
    $'\033')
      read -rsn2 -t 0.05 rest
      case "$rest" in
        '[A'|'OA') [ $at -gt 0 ] && at=$((at-1));;
        '[B'|'OB') [ $at -lt 2 ] && at=$((at+1));;
      esac
      draw;;
    '') printf '\033[2J\033[Hchosen: %d\n' $((at+1)); exit;;
  esac
done
"#;

#[test]
fn the_phone_sees_makes_uses_and_answers_what_the_server_keeps() {
    let dir = tempfile::tempdir().unwrap();
    let folder = dir.path().join("project");
    std::fs::create_dir_all(folder.join(".git")).unwrap();
    let folder = folder.to_string_lossy().into_owned();
    let mut own = Own { socket: dir.path().join("sessions.sock"), following: Vec::new(), _dir: dir };

    // Asked for the first time, the server starts by itself: one session,
    // nothing in it.
    let (ok, printed) = own.asked(&["herd", "state"]);
    assert!(ok, "{printed}");
    let first = parse_state(&printed).unwrap();
    assert!(first.available);
    assert_eq!(first.sessions.iter().map(|s| (s.name.as_str(), s.running, s.workspaces.len())).collect::<Vec<_>>(), [("main", true, 0)]);
    let watch = own.follow(&["herd", "watch"]);
    let news = own.follow(&["herd", "news"]);

    // A folder opened as a workspace: told to whoever watches, with its
    // terminal in that folder.
    let (ok, printed) = own.asked(&["herd", "do", "new-workspace", "main", &packed(&folder), &packed("live")]);
    assert!(ok, "{printed}");
    let made = parse_made(&printed).unwrap();
    let pane = made.pane.clone();
    let herd = next(&watch, "the workspace", |herd| herd.sessions[0].workspaces.len() == 1);
    let space = &herd.sessions[0].workspaces[0];
    assert_eq!((space.id.as_str(), space.label.as_str(), space.tabs[0].id.as_str()), (made.workspace.as_str(), "live", made.tab.as_str()));
    assert_eq!((space.tabs[0].panes[0].id.as_str(), space.tabs[0].panes[0].folder.as_str(), space.tabs[0].panes[0].agent.is_none()), (pane.as_str(), folder.as_str(), true));
    let (ok, said) = own.asked(&["herd", "do", "new-workspace", "main", &packed("/no/such/folder")]);
    assert!(!ok && said.contains("not a folder"), "{said}");
    let (ok, said) = own.asked(&["herd", "do", "read", "other", &pane, "10"]);
    assert!(!ok && said.contains("no session other"), "{said}");

    // Text arrives as written, whatever a shell would have made of it on
    // the way, and is run; keys are pressed; what it shows is read.
    let (ok, said) = own.asked(&["herd", "do", "prompt", "main", &pane, &packed(r#"echo "live $((20+22)) it's `echo fine`""#)]);
    assert!(ok, "{said}");
    own.shows(&pane, "live 42 it's fine");
    assert!(own.asked(&["herd", "do", "keys", "main", &pane, "e", "c", "h", "o", "space", "k", "minus", "o", "k", "enter"]).0);
    own.shows(&pane, "k-ok");
    assert!(!own.asked(&["herd", "do", "keys", "main", &pane, "nonsense"]).0);

    // Another terminal in the workspace, in its folder; then closed.
    let (ok, printed) = own.asked(&["herd", "do", "new-tab", "main", &made.workspace]);
    assert!(ok, "{printed}");
    let second = parse_made(&printed).unwrap();
    let herd = next(&watch, "the second tab", |herd| herd.sessions[0].workspaces[0].tabs.len() == 2);
    assert_eq!((herd.sessions[0].workspaces[0].tabs[1].panes[0].id.as_str(), herd.sessions[0].workspaces[0].tabs[1].panes[0].folder.as_str()), (second.pane.as_str(), folder.as_str()));
    assert!(own.asked(&["herd", "do", "close-tab", "main", &second.tab]).0);
    next(&watch, "the second tab gone", |herd| herd.sessions[0].workspaces[0].tabs.len() == 1);

    // The folders offered for a workspace include one that is open; the
    // agents that could be started are a list.
    let (ok, printed) = own.asked(&["herd", "places"]);
    assert!(ok);
    assert!(parse_places(&printed).unwrap().iter().any(|place| place.path == folder && place.project));
    let (ok, printed) = own.asked(&["herd", "kinds"]);
    assert!(ok);
    multiplex_proto::herd::parse_kinds(&printed).expect("a list of kinds");

    // One terminal in another terminal: what is typed there runs in it,
    // and Ctrl+\ leaves it running.
    let mut view = own.command(&["herd", "pane", "main", &pane]).stdin(Stdio::piped()).stdout(Stdio::piped()).spawn().unwrap();
    let mut typed = view.stdin.take().unwrap();
    typed.write_all(b"echo viewed-$((40+2))\n").unwrap();
    own.shows(&pane, "viewed-42");
    typed.write_all(&[0x1c]).unwrap();
    let left = Instant::now();
    while view.try_wait().unwrap().is_none() {
        assert!(left.elapsed() < Duration::from_secs(5), "the view did not leave");
        std::thread::sleep(Duration::from_millis(20));
    }
    let mut seen = String::new();
    view.stdout.take().unwrap().read_to_string(&mut seen).unwrap();
    assert!(seen.contains("viewed-42"), "the view was shown what the terminal showed: {seen:?}");

    // An agent starts in the terminal: it is known by its program, and
    // when it asks, whoever watches sees it wait, and a phone that is not
    // looking is told with its question and choices.
    let agent = PathBuf::from(&folder).join("claude");
    std::fs::write(&agent, ASKS).unwrap();
    assert!(own.asked(&["herd", "do", "prompt", "main", &pane, &packed(&format!("bash {}", agent.display()))]).0);
    let herd = next(&watch, "an agent in the terminal", |herd| status_of(herd, &pane).is_some());
    assert_eq!(herd.agents()[0].name, "claude");
    next(&watch, "it waits", |herd| status_of(herd, &pane) == Some(AgentStatus::Blocked));
    let LinkEvent::Agent(asks) = next_news(&news, "it waits") else { panic!("an agent was expected") };
    assert_eq!((asks.session.as_str(), asks.id.as_str(), asks.status), ("main", pane.as_str(), AgentStatus::Blocked));
    assert_eq!(asks.question, "Bash command\n\nmake test\nRun the test suite\n\nDo you want to proceed?");
    assert_eq!(asks.choices.iter().map(|c| c.label.as_str()).collect::<Vec<_>>(), ["Yes", "Yes, and don't ask again for make", "No, and tell me what to do differently (esc)"]);
    let (ok, printed) = own.asked(&["herd", "do", "read", "main", &pane, "40"]);
    assert!(ok);
    assert_eq!(parse_text(&printed).unwrap().asked.map(|asked| asked.mark), Some(asks.mark.clone()), "reading it says the same question");

    // An answer to another question, or words where a choice is wanted,
    // is not sent; the third choice, for the question it was shown for, is
    // taken; pressed once more, nothing is sent.
    let answer = |mark: &str, how: &str, what: &str| own.asked(&["herd", "do", "answer", "main", &pane, mark, how, what]);
    let (ok, said) = answer("0123456789abcdef", "choice", "1");
    assert!(!ok && said.contains("no longer what it asks"), "{said}");
    let (ok, said) = answer(&asks.mark, "text", &packed("yes please"));
    assert!(!ok && said.contains("one of its choices"), "{said}");
    assert!(own.text(&pane).contains("❯ 1. Yes"));
    let (ok, said) = answer(&asks.mark, "choice", "3");
    assert!(ok, "{said}");
    own.shows(&pane, "chosen: 3");
    // The agent ended with its answer: the phone is told it no longer
    // waits, and there is nobody left to answer.
    assert_eq!(next_news(&news, "it no longer waits"), LinkEvent::Settled { session: "main".into(), pane: pane.clone() });
    let (ok, said) = answer(&asks.mark, "choice", "3");
    assert!(!ok && said.contains("No agent"), "{said}");

    // Its terminal closed: the workspace goes with its last terminal.
    assert!(own.asked(&["herd", "do", "close-pane", "main", &pane]).0);
    next(&watch, "the workspace gone", |herd| herd.sessions[0].workspaces.is_empty());
}
