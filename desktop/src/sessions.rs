//! Multiplex's own session server: terminals that keep running whether or
//! not anything shows them, and that several viewers (a window on the
//! computer, the phone) can sit in front of at once.
//!
//! `multiplex sessions serve` owns the terminals. Each has a PTY with a
//! program in it, and a model of its screen, so a viewer that comes late
//! gets a correct picture at once. `multiplex here` turns the terminal it
//! is run in into a viewer of a new one: it looks like a plain terminal,
//! and closing the window leaves the program running.
//!
//! The socket speaks frames: one byte for the kind, four for the length,
//! then that many bytes. A viewer first sends one request (`Q`, JSON) and
//! gets one answer (`A`, JSON); attached, it sends input (`I`) and its
//! size (`R`), and gets output (`O`) and, at the end, the exit (`X`).

use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Write};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::net::{UnixListener, UnixStream};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{anyhow, bail, Context, Result};
use multiplex_proto::agents::AgentStatus;
use multiplex_proto::asked::asked;
use multiplex_proto::herd::{Pane, PaneAgent, Session, Tab, Workspace};
use serde::{Deserialize, Serialize};

/// Lines of earlier output kept per terminal.
const SCROLLBACK: usize = 5000;

/// The one session's name, as the phone's lists show it.
pub const SESSION: &str = "main";

/// Programs that are coding agents, by the name they are started with.
pub const AGENTS: &[&str] = &["claude", "codex", "gemini", "opencode", "amp", "aider", "cursor-agent", "copilot", "goose", "qwen", "crush", "droid", "kiro", "pi"];

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
#[serde(tag = "do", rename_all = "lowercase")]
pub enum Request {
    /// A new terminal in a folder, running a program (the user's shell
    /// when none is named). In the workspace named; else in the one for
    /// that folder, made if there is none (or always, when `fresh`).
    New {
        cwd: String,
        #[serde(default)]
        command: Vec<String>,
        cols: u16,
        rows: u16,
        #[serde(default)]
        workspace: String,
        #[serde(default)]
        label: String,
        #[serde(default)]
        fresh: bool,
    },
    List,
    /// Everything kept, as the phone lists it.
    State,
    /// The same, and again whenever it changes (`S` frames).
    Watch,
    /// Sit in front of one; its output and the viewer's input follow.
    Attach { id: String, cols: u16, rows: u16 },
    Kill { id: String },
    /// A terminal's text: its last `lines` lines, those that scrolled off
    /// the screen too; with 0, the screen exactly as it stands.
    Read { id: String, lines: u32 },
    /// Keys by name ("esc", "enter", "up", "ctrl+c", "2").
    Keys { id: String, keys: Vec<String> },
    /// Text as one piece, then Enter.
    Text { id: String, text: String },
    /// An agent says what it is doing (from its own hooks).
    Report { id: String, agent: String, state: String },
    /// End the server and every terminal it keeps.
    Stop,
}

/// One terminal as a list tells it.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct Told {
    pub id: String,
    pub cwd: String,
    pub command: String,
    pub viewers: usize,
    pub cols: u16,
    pub rows: u16,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct Answer {
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub error: String,
    /// The terminal made or meant.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub id: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub workspace: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub tab: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub terminals: Vec<Told>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub state: Option<Session>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    /// What the agent in it is doing, with a read.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub status: Option<AgentStatus>,
}

impl Answer {
    fn error(words: impl Into<String>) -> Self {
        Answer { error: words.into(), ..Answer::default() }
    }
}

pub fn write_frame(to: &mut impl Write, kind: u8, bytes: &[u8]) -> std::io::Result<()> {
    let mut head = [0u8; 5];
    head[0] = kind;
    head[1..].copy_from_slice(&(bytes.len() as u32).to_be_bytes());
    to.write_all(&head)?;
    to.write_all(bytes)?;
    to.flush()
}

pub fn read_frame(from: &mut impl Read) -> std::io::Result<(u8, Vec<u8>)> {
    let mut head = [0u8; 5];
    from.read_exact(&mut head)?;
    let len = u32::from_be_bytes([head[1], head[2], head[3], head[4]]) as usize;
    if len > 4 << 20 {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "a frame too large to be one"));
    }
    let mut bytes = vec![0u8; len];
    from.read_exact(&mut bytes)?;
    Ok((head[0], bytes))
}

fn size_bytes(cols: u16, rows: u16) -> [u8; 4] {
    let (c, r) = (cols.to_be_bytes(), rows.to_be_bytes());
    [c[0], c[1], r[0], r[1]]
}

/// Someone in front of a terminal.
struct Viewer {
    id: u64,
    stream: UnixStream,
    cols: u16,
    rows: u16,
}

/// The title a program gave its terminal.
#[derive(Default)]
struct Title(String);

impl vt100::Callbacks for Title {
    fn set_window_title(&mut self, _: &mut vt100::Screen, title: &[u8]) {
        self.0 = String::from_utf8_lossy(title).chars().filter(|c| !c.is_control()).take(120).collect();
    }
}

/// A terminal the server keeps.
struct Terminal {
    /// Its workspace, and its own number among all terminals.
    space: u64,
    number: u64,
    cwd: String,
    command: String,
    /// The PTY's own end: written to for input, sized by ioctl.
    master: File,
    child: Child,
    screen: vt100::Parser<Title>,
    viewers: Vec<Viewer>,
    /// What an agent's own hooks last said: its name and state.
    reported: Option<(String, AgentStatus)>,
    /// When the program last wrote, and when a viewer last typed.
    wrote: Instant,
    typed: Instant,
    /// It worked, then stopped with nobody in front of it: done, until
    /// someone looks.
    unseen: bool,
    was_working: bool,
}

impl Terminal {
    fn resize(&mut self, cols: u16, rows: u16) {
        let (cols, rows) = (cols.clamp(2, 1000), rows.clamp(2, 1000));
        let (now_rows, now_cols) = self.screen.screen().size();
        if (now_cols.get(), now_rows.get()) == (cols, rows) {
            return;
        }
        let size = libc::winsize { ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0 };
        unsafe { libc::ioctl(self.master.as_raw_fd(), libc::TIOCSWINSZ, &size) };
        self.screen.screen_mut().set_size(nz(rows), nz(cols));
    }

    /// The program in front in the terminal (a shell, or what it runs).
    fn front(&self) -> Option<i32> {
        let group = unsafe { libc::tcgetpgrp(self.master.as_raw_fd()) };
        (group > 0).then_some(group)
    }

    /// The folder that program is in now.
    fn folder(&self) -> String {
        self.front().and_then(|pid| std::fs::read_link(format!("/proc/{pid}/cwd")).ok()).map(|path| path.to_string_lossy().into_owned()).unwrap_or_else(|| self.cwd.clone())
    }

    /// The agent running in it, by the program in front.
    fn agent(&self) -> Option<String> {
        let pid = self.front()?;
        let line = std::fs::read(format!("/proc/{pid}/cmdline")).ok()?;
        // The program's own name, or the script an interpreter runs.
        line.split(|b| *b == 0).take(2).filter_map(|word| Path::new(std::str::from_utf8(word).ok()?).file_name()?.to_str()).find_map(|name| AGENTS.iter().find(|agent| **agent == name)).map(|agent| (*agent).to_owned())
    }

    /// What its agent is doing: as its hooks said, or as its screen shows.
    fn status(&mut self, agent: bool) -> AgentStatus {
        let working = match &self.reported {
            Some((_, status)) if agent => return self.seen_or_done(*status),
            _ => self.wrote.elapsed() < WORKING_FOR && self.wrote.duration_since(self.typed) > ECHO,
        };
        if !agent {
            return AgentStatus::Unknown;
        }
        let status = if !asked(&self.screen.screen().contents()).choices.is_empty() {
            AgentStatus::Blocked
        } else if working {
            AgentStatus::Working
        } else {
            AgentStatus::Idle
        };
        self.seen_or_done(status)
    }

    /// Idle after work that nobody watched end is "done", until looked at.
    fn seen_or_done(&mut self, status: AgentStatus) -> AgentStatus {
        match status {
            AgentStatus::Working => {
                self.was_working = true;
                self.unseen = false;
            }
            AgentStatus::Idle if self.was_working => {
                self.was_working = false;
                self.unseen = self.viewers.is_empty();
            }
            AgentStatus::Idle => {}
            _ => {
                self.was_working = false;
                self.unseen = false;
            }
        }
        if !self.viewers.is_empty() {
            self.unseen = false;
        }
        if status == AgentStatus::Idle && self.unseen {
            AgentStatus::Done
        } else {
            status
        }
    }

    /// Its text: the screen, and what scrolled off it, `lines` at most.
    fn text(&mut self, lines: usize) -> String {
        let rows = usize::from(self.screen.screen().size().0.get());
        let screen = self.screen.screen_mut();
        screen.set_scrollback(usize::MAX);
        let most = screen.scrollback();
        let mut all: Vec<String> = Vec::new();
        // From the oldest wanted page down to the screen itself.
        let mut at = most.min(lines.saturating_sub(rows));
        loop {
            screen.set_scrollback(at);
            let page: Vec<String> = screen.contents().lines().map(str::to_owned).collect();
            let step = if at >= rows { rows } else { at };
            all.extend(page.into_iter().take(if at == 0 { rows } else { step.max(1) }));
            if at == 0 {
                break;
            }
            at -= step.max(1).min(at);
        }
        screen.set_scrollback(0);
        while all.last().is_some_and(|line| line.trim().is_empty()) {
            all.pop();
        }
        let from = all.len().saturating_sub(lines);
        all[from..].join("\n")
    }
}

/// Output this soon after typing is the terminal showing what was typed.
const ECHO: Duration = Duration::from_millis(400);
/// An agent that wrote this recently is at work.
const WORKING_FOR: Duration = Duration::from_millis(1500);

/// A workspace: the terminals of one folder.
struct Space {
    number: u64,
    folder: String,
    label: String,
}

#[derive(Default)]
struct Kept {
    terminals: HashMap<String, Terminal>,
    spaces: Vec<Space>,
    next_space: u64,
    next_terminal: u64,
    watchers: Vec<UnixStream>,
    last: Option<Session>,
}

impl Kept {
    /// Everything kept, as the phone lists it. An empty workspace goes.
    fn session(&mut self) -> Session {
        let used: Vec<u64> = self.terminals.values().map(|t| t.space).collect();
        self.spaces.retain(|space| used.contains(&space.number));
        let mut workspaces = Vec::new();
        for space in &self.spaces {
            let mut ids: Vec<(u64, String)> = self.terminals.iter().filter(|(_, t)| t.space == space.number).map(|(id, t)| (t.number, id.clone())).collect();
            ids.sort();
            let tabs = ids
                .into_iter()
                .enumerate()
                .map(|(n, (number, id))| {
                    let terminal = self.terminals.get_mut(&id).expect("listed above");
                    let running = terminal.agent();
                    let name = running.clone().or_else(|| terminal.reported.as_ref().filter(|_| false).map(|(name, _)| name.clone()));
                    let status = terminal.status(name.is_some());
                    let title = Some(terminal.screen.callbacks().0.clone()).filter(|title| !title.trim().is_empty()).unwrap_or_else(|| terminal.command.rsplit('/').next().unwrap_or_default().to_owned());
                    Tab {
                        id: format!("w{}:t{number}", space.number),
                        label: (n + 1).to_string(),
                        panes: vec![Pane { id, title, folder: terminal.folder(), focused: false, agent: name.map(|name| PaneAgent { name, status }) }],
                    }
                })
                .collect();
            workspaces.push(Workspace { id: format!("w{}", space.number), label: space.label.clone(), tabs });
        }
        Session { name: SESSION.to_owned(), running: true, workspaces }
    }

    /// Tells the watchers, if what they were last told has changed.
    fn tell(&mut self) {
        if self.watchers.is_empty() {
            self.last = None;
            return;
        }
        let now = self.session();
        if self.last.as_ref() != Some(&now) {
            let line = serde_json::to_vec(&now).unwrap_or_default();
            self.watchers.retain_mut(|watcher| write_frame(watcher, b'S', &line).is_ok());
            self.last = Some(now);
        }
    }
}

type Shared = Arc<Mutex<Kept>>;

/// A size's side as the screen model wants it; never nothing.
fn nz(n: u16) -> std::num::NonZero<u16> {
    std::num::NonZero::new(n.max(1)).expect("at least one")
}

fn open_pty(cols: u16, rows: u16) -> Result<(File, OwnedFd)> {
    let (mut master, mut slave) = (0, 0);
    let size = libc::winsize { ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0 };
    if unsafe { libc::openpty(&mut master, &mut slave, std::ptr::null_mut(), std::ptr::null(), &size) } != 0 {
        bail!("no terminal could be made: {}", std::io::Error::last_os_error());
    }
    unsafe {
        libc::fcntl(master, libc::F_SETFD, libc::FD_CLOEXEC);
        Ok((File::from_raw_fd(master), OwnedFd::from_raw_fd(slave)))
    }
}

/// What was made: the terminal, its tab and its workspace.
struct MadeIds {
    id: String,
    tab: String,
    workspace: String,
}

#[allow(clippy::too_many_arguments)]
fn start(shared: &Shared, cwd: &str, command: &[String], cols: u16, rows: u16, workspace: &str, label: &str, fresh: bool) -> Result<MadeIds> {
    if !Path::new(cwd).is_dir() {
        bail!("{cwd} is not a folder on this computer");
    }
    let (cols, rows) = (cols.clamp(2, 1000), rows.clamp(2, 1000));
    let (master, slave) = open_pty(cols, rows)?;
    let shell = std::env::var("SHELL").ok().filter(|s| !s.is_empty()).unwrap_or_else(|| "/bin/sh".to_owned());
    let (program, args) = match command.split_first() {
        Some((program, args)) => (program.clone(), args.to_vec()),
        None => (shell, Vec::new()),
    };
    let mut kept = shared.lock().unwrap();
    // Its workspace: the one named, the one of this folder, or a new one.
    let space = if !workspace.is_empty() {
        kept.spaces.iter().find(|space| format!("w{}", space.number) == workspace).map(|space| space.number).ok_or_else(|| anyhow!("There is no workspace {workspace}."))?
    } else if let Some(space) = kept.spaces.iter().find(|space| !fresh && space.folder == cwd) {
        space.number
    } else {
        kept.next_space += 1;
        let number = kept.next_space;
        let name = if label.is_empty() { Path::new(cwd).file_name().map_or_else(|| cwd.to_owned(), |name| name.to_string_lossy().into_owned()) } else { label.to_owned() };
        kept.spaces.push(Space { number, folder: cwd.to_owned(), label: name });
        number
    };
    kept.next_terminal += 1;
    let number = kept.next_terminal;
    let id = format!("w{space}:p{number}");
    let mut spawn = Command::new(&program);
    spawn.args(&args).current_dir(cwd).env("TERM", "xterm-256color").env("MULTIPLEX_SESSION", &id);
    spawn.stdin(Stdio::from(slave.try_clone()?)).stdout(Stdio::from(slave.try_clone()?)).stderr(Stdio::from(slave));
    // Its own session, with the PTY as the terminal it is in charge of.
    unsafe {
        spawn.pre_exec(|| {
            if libc::setsid() < 0 || libc::ioctl(0, libc::TIOCSCTTY as _, 0) < 0 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        });
    }
    let child = spawn.spawn().with_context(|| format!("{program} could not be started"))?;
    let mut reader = master.try_clone()?;
    let now = Instant::now();
    let terminal = Terminal {
        space,
        number,
        cwd: cwd.to_owned(),
        command: program,
        master,
        child,
        screen: vt100::Parser::new_with_callbacks(nz(rows), nz(cols), SCROLLBACK, Title::default()),
        viewers: Vec::new(),
        reported: None,
        wrote: now,
        typed: now,
        unseen: false,
        was_working: false,
    };
    kept.terminals.insert(id.clone(), terminal);
    kept.tell();
    drop(kept);

    // What the program writes: into the screen's model, and on to whoever
    // is looking. When it ends, they are told, and the terminal goes.
    let (shared, name) = (shared.clone(), id.clone());
    std::thread::spawn(move || {
        let mut buffer = [0u8; 16 * 1024];
        loop {
            let read = reader.read(&mut buffer).unwrap_or(0);
            let mut kept = shared.lock().unwrap();
            let Some(terminal) = kept.terminals.get_mut(&name) else { return };
            if read == 0 {
                let code = terminal.child.wait().ok().and_then(|status| status.code()).unwrap_or(-1);
                for viewer in &mut terminal.viewers {
                    let _ = write_frame(&mut viewer.stream, b'X', code.to_string().as_bytes());
                    let _ = viewer.stream.shutdown(std::net::Shutdown::Both);
                }
                kept.terminals.remove(&name);
                kept.tell();
                return;
            }
            terminal.wrote = Instant::now();
            terminal.screen.process(&buffer[..read]);
            terminal.viewers.retain_mut(|viewer| write_frame(&mut viewer.stream, b'O', &buffer[..read]).is_ok());
        }
    });
    Ok(MadeIds { id, tab: format!("w{space}:t{number}"), workspace: format!("w{space}") })
}

/// A key's name as the bytes a terminal sends for it.
pub fn key_bytes(key: &str, application_cursor: bool) -> Option<Vec<u8>> {
    let arrow = |letter: char| format!("\x1b{}{letter}", if application_cursor { 'O' } else { '[' }).into_bytes();
    Some(match key {
        "enter" | "return" => b"\r".to_vec(),
        "esc" | "escape" => b"\x1b".to_vec(),
        "tab" => b"\t".to_vec(),
        "shift+tab" => b"\x1b[Z".to_vec(),
        "space" => b" ".to_vec(),
        "backspace" => b"\x7f".to_vec(),
        "minus" => b"-".to_vec(),
        "plus" => b"+".to_vec(),
        "up" => arrow('A'),
        "down" => arrow('B'),
        "right" => arrow('C'),
        "left" => arrow('D'),
        "home" => b"\x1b[H".to_vec(),
        "end" => b"\x1b[F".to_vec(),
        "pageup" => b"\x1b[5~".to_vec(),
        "pagedown" => b"\x1b[6~".to_vec(),
        "delete" => b"\x1b[3~".to_vec(),
        _ => match key.strip_prefix("ctrl+") {
            Some(letter) if letter.len() == 1 && letter.as_bytes()[0].is_ascii_lowercase() => vec![letter.as_bytes()[0] & 0x1f],
            Some(_) => return None,
            None if key.len() == 1 && (key.as_bytes()[0].is_ascii_lowercase() || key.as_bytes()[0].is_ascii_digit()) => key.as_bytes().to_vec(),
            None => return None,
        },
    })
}

fn told(all: &HashMap<String, Terminal>) -> Vec<Told> {
    let mut list: Vec<(u64, Told)> = all
        .iter()
        .map(|(id, t)| {
            let (rows, cols) = t.screen.screen().size();
            (t.number, Told { id: id.clone(), cwd: t.cwd.clone(), command: t.command.clone(), viewers: t.viewers.len(), cols: cols.get(), rows: rows.get() })
        })
        .collect();
    list.sort_by_key(|(number, _)| *number);
    list.into_iter().map(|(_, told)| told).collect()
}

fn serve_one(mut stream: UnixStream, shared: Shared, viewer_id: u64) -> Result<()> {
    let (kind, bytes) = read_frame(&mut stream)?;
    if kind != b'Q' {
        bail!("a request was expected first");
    }
    let answer = |stream: &mut UnixStream, answer: Answer| write_frame(stream, b'A', &serde_json::to_vec(&answer)?).map_err(anyhow::Error::from);
    let Ok(request) = serde_json::from_slice::<Request>(&bytes) else { return answer(&mut stream, Answer::error("That request was not understood.")) };
    let missing = |id: &str| Answer::error(format!("There is no terminal {id}."));
    let id = match request {
        Request::List => return answer(&mut stream, Answer { terminals: told(&shared.lock().unwrap().terminals), ..Answer::default() }),
        Request::State => {
            let state = shared.lock().unwrap().session();
            return answer(&mut stream, Answer { state: Some(state), ..Answer::default() });
        }
        Request::Watch => {
            let mut kept = shared.lock().unwrap();
            let now = kept.session();
            answer(&mut stream, Answer { state: Some(now.clone()), ..Answer::default() })?;
            kept.watchers.push(stream.try_clone()?);
            kept.last = Some(now);
            drop(kept);
            // Until the watcher hangs up.
            while read_frame(&mut stream).is_ok() {}
            return Ok(());
        }
        Request::Stop => {
            let kept = shared.lock().unwrap();
            for terminal in kept.terminals.values() {
                unsafe { libc::kill(-(terminal.child.id() as i32), libc::SIGHUP) };
            }
            let _ = answer(&mut stream, Answer::default());
            let _ = std::fs::remove_file(socket_path());
            std::process::exit(0);
        }
        Request::Kill { id } => {
            let mut kept = shared.lock().unwrap();
            let Some(terminal) = kept.terminals.get_mut(&id) else { return answer(&mut stream, missing(&id)) };
            // Its whole session, as closing a window would.
            unsafe { libc::kill(-(terminal.child.id() as i32), libc::SIGHUP) };
            return answer(&mut stream, Answer { id, ..Answer::default() });
        }
        Request::New { cwd, command, cols, rows, workspace, label, fresh } => {
            return answer(
                &mut stream,
                match start(&shared, &cwd, &command, cols, rows, &workspace, &label, fresh) {
                    Ok(made) => Answer { id: made.id, tab: made.tab, workspace: made.workspace, ..Answer::default() },
                    Err(err) => Answer::error(format!("{err:#}")),
                },
            );
        }
        Request::Read { id, lines } => {
            let mut kept = shared.lock().unwrap();
            let Some(terminal) = kept.terminals.get_mut(&id) else { return answer(&mut stream, missing(&id)) };
            let agent = terminal.agent().is_some();
            // No lines asked for: the screen as it stands, no more and no less.
            let text = if lines == 0 { terminal.screen.screen().contents() } else { terminal.text(lines.min(5000) as usize) };
            let status = terminal.status(agent);
            return answer(&mut stream, Answer { id, text: Some(text), status: agent.then_some(status), ..Answer::default() });
        }
        Request::Keys { id, keys } => {
            let mut kept = shared.lock().unwrap();
            let Some(terminal) = kept.terminals.get_mut(&id) else { return answer(&mut stream, missing(&id)) };
            let application = terminal.screen.screen().application_cursor();
            let Some(bytes) = keys.iter().map(|key| key_bytes(key, application)).collect::<Option<Vec<_>>>() else { return answer(&mut stream, Answer::error("One of those is not a key Multiplex knows.")) };
            terminal.typed = Instant::now();
            // One at a time: a program reads a list key by key.
            for key in bytes {
                let _ = terminal.master.write_all(&key);
            }
            return answer(&mut stream, Answer { id, ..Answer::default() });
        }
        Request::Text { id, text } => {
            let mut master = {
                let mut kept = shared.lock().unwrap();
                let Some(terminal) = kept.terminals.get_mut(&id) else { return answer(&mut stream, missing(&id)) };
                terminal.typed = Instant::now();
                // As a paste where the program takes pastes, so that lines
                // in it are not taken for Enter one by one.
                let pasted = terminal.screen.screen().bracketed_paste();
                let mut master = terminal.master.try_clone()?;
                if pasted {
                    master.write_all(format!("\x1b[200~{text}\x1b[201~").as_bytes())?;
                } else {
                    master.write_all(text.as_bytes())?;
                }
                master
            };
            // The paste is taken in before Enter is pressed.
            std::thread::sleep(Duration::from_millis(60));
            master.write_all(b"\r")?;
            return answer(&mut stream, Answer { id, ..Answer::default() });
        }
        Request::Report { id, agent, state } => {
            let mut kept = shared.lock().unwrap();
            let Some(terminal) = kept.terminals.get_mut(&id) else { return answer(&mut stream, missing(&id)) };
            let Ok(status) = serde_json::from_value::<AgentStatus>(serde_json::Value::String(state)) else { return answer(&mut stream, Answer::error("That is not a state.")) };
            terminal.reported = (status != AgentStatus::Unknown).then_some((agent, status));
            kept.tell();
            return answer(&mut stream, Answer { id, ..Answer::default() });
        }
        Request::Attach { id, cols, rows } => {
            let mut kept = shared.lock().unwrap();
            let Some(terminal) = kept.terminals.get_mut(&id) else { return answer(&mut stream, missing(&id)) };
            // The newest viewer's size is the terminal's: it is the one in use.
            terminal.resize(cols, rows);
            answer(&mut stream, Answer { id: id.clone(), ..Answer::default() })?;
            // The picture as it stands, then everything that follows.
            write_frame(&mut stream, b'O', terminal.screen.screen().state_formatted().as_bytes())?;
            terminal.viewers.push(Viewer { id: viewer_id, stream: stream.try_clone()?, cols, rows });
            kept.tell();
            id
        }
    };
    // Attached: what the viewer types, and its size when that changes.
    while let Ok((kind, bytes)) = read_frame(&mut stream) {
        let mut kept = shared.lock().unwrap();
        let Some(terminal) = kept.terminals.get_mut(&id) else { break };
        match kind {
            b'I' => {
                // Whoever types has the terminal at their own size.
                if let Some((cols, rows)) = terminal.viewers.iter().find(|viewer| viewer.id == viewer_id).map(|viewer| (viewer.cols, viewer.rows)) {
                    terminal.resize(cols, rows);
                }
                terminal.typed = Instant::now();
                let _ = terminal.master.write_all(&bytes);
            }
            b'R' if bytes.len() == 4 => {
                let (cols, rows) = (u16::from_be_bytes([bytes[0], bytes[1]]), u16::from_be_bytes([bytes[2], bytes[3]]));
                if let Some(viewer) = terminal.viewers.iter_mut().find(|viewer| viewer.id == viewer_id) {
                    (viewer.cols, viewer.rows) = (cols, rows);
                }
                terminal.resize(cols, rows);
            }
            _ => {}
        }
    }
    let mut kept = shared.lock().unwrap();
    if let Some(terminal) = kept.terminals.get_mut(&id) {
        terminal.viewers.retain(|viewer| viewer.id != viewer_id);
    }
    kept.tell();
    Ok(())
}

pub fn socket_path() -> PathBuf {
    std::env::var_os("MULTIPLEX_SESSIONS_SOCKET").map(PathBuf::from).unwrap_or_else(|| crate::share::runtime_dir().join("sessions.sock"))
}

/// `multiplex sessions serve`: until it is stopped.
pub fn serve(socket: &Path) -> Result<()> {
    if UnixStream::connect(socket).is_ok() {
        bail!("The session server is already running.");
    }
    let _ = std::fs::remove_file(socket);
    if let Some(dir) = socket.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let listener = UnixListener::bind(socket).with_context(|| format!("{} could not be opened", socket.display()))?;
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(socket, std::fs::Permissions::from_mode(0o600))?;
    let shared: Shared = Arc::new(Mutex::new(Kept::default()));
    // What changes without anyone asking (a title, a folder, an agent
    // starting to wait) is looked at twice a second while someone watches.
    let ticking = shared.clone();
    std::thread::spawn(move || loop {
        std::thread::sleep(Duration::from_millis(500));
        ticking.lock().unwrap().tell();
    });
    for (viewer, stream) in listener.incoming().flatten().enumerate() {
        let shared = shared.clone();
        std::thread::spawn(move || {
            let _ = serve_one(stream, shared, viewer as u64);
        });
    }
    Ok(())
}

/// A connection to the server, which is started if it is not running.
fn connect(socket: &Path) -> Result<UnixStream> {
    if let Ok(stream) = UnixStream::connect(socket) {
        return Ok(stream);
    }
    let mut serve = Command::new(std::env::current_exe()?);
    serve.args(["sessions", "serve"]).env("MULTIPLEX_SESSIONS_SOCKET", socket).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    // Of nobody's terminal: it outlives whoever asked first.
    unsafe {
        serve.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    serve.spawn().context("The session server could not be started")?;
    let started = Instant::now();
    loop {
        if let Ok(stream) = UnixStream::connect(socket) {
            return Ok(stream);
        }
        if started.elapsed() > Duration::from_secs(3) {
            bail!("The session server did not start.");
        }
        std::thread::sleep(Duration::from_millis(20));
    }
}

/// Asks the server one thing.
pub fn ask(socket: &Path, request: &Request) -> Result<(Answer, UnixStream)> {
    let mut stream = connect(socket)?;
    write_frame(&mut stream, b'Q', &serde_json::to_vec(request)?)?;
    let (kind, bytes) = read_frame(&mut stream)?;
    if kind != b'A' {
        bail!("The session server's answer was not understood.");
    }
    let answer: Answer = serde_json::from_slice(&bytes)?;
    if !answer.error.is_empty() {
        bail!("{}", answer.error);
    }
    Ok((answer, stream))
}

/// Ctrl+\: leave a terminal that was opened only to look in on it.
const LEAVE: u8 = 0x1c;

/// Sits in front of a terminal with this terminal: what is typed goes in,
/// what it shows comes out, until its program ends (its exit code comes
/// back) or this terminal goes away (None; the program runs on). With
/// `leave`, Ctrl+\ goes away too; with `watch`, nothing typed is sent.
pub fn attach(socket: &Path, id: &str, leave: bool, watch: bool) -> Result<Option<i32>> {
    let (cols, rows) = crate::pane::terminal_size().unwrap_or((80, 24));
    let (_, mut stream) = ask(socket, &Request::Attach { id: id.to_owned(), cols, rows })?;
    let _raw = crate::pane::Raw::on();
    let mut up = stream.try_clone()?;
    // This terminal's size, whenever it changes (a window resized, a
    // phone turned, a phone's terminal saying its real size a moment
    // after it opened): looked at a few times a second.
    let mut sized = stream.try_clone()?;
    std::thread::spawn(move || {
        let mut last = (cols, rows);
        loop {
            std::thread::sleep(Duration::from_millis(150));
            if let Some(now) = crate::pane::terminal_size().filter(|now| *now != last) {
                last = now;
                if write_frame(&mut sized, b'R', &size_bytes(now.0, now.1)).is_err() {
                    break;
                }
            }
        }
    });
    // What is typed, on its own thread.
    std::thread::spawn(move || {
        let mut stdin = std::io::stdin().lock();
        let mut buffer = [0u8; 4096];
        loop {
            let read = match stdin.read(&mut buffer) {
                Ok(0) | Err(_) => break,
                Ok(read) => read,
            };
            if leave && buffer[..read].contains(&LEAVE) {
                break;
            }
            if read > 0 && !watch && write_frame(&mut up, b'I', &buffer[..read]).is_err() {
                break;
            }
        }
        let _ = up.shutdown(std::net::Shutdown::Both);
    });
    let mut out = std::io::stdout().lock();
    let ended = loop {
        match read_frame(&mut stream) {
            Ok((b'O', bytes)) => {
                out.write_all(&bytes)?;
                out.flush()?;
            }
            Ok((b'X', bytes)) => break String::from_utf8_lossy(&bytes).parse().ok(),
            Ok(_) => {}
            Err(_) => break None,
        }
    };
    // This terminal back as it was: the cursor shown, colours off, its
    // own screen if the program had taken the other one.
    let _ = out.write_all(b"\x1b[?1049l\x1b[?25h\x1b[0m\x1b[?2004l");
    let _ = out.flush();
    Ok(ended)
}

pub fn run(args: &[&str]) -> Result<()> {
    let socket = socket_path();
    match args {
        ["serve"] => serve(&socket)?,
        ["list"] => println!("{}", serde_json::to_string(&ask(&socket, &Request::List)?.0.terminals)?),
        ["attach", id] => {
            if let Some(code) = attach(&socket, id, false, false)? {
                std::process::exit(code);
            }
        }
        ["kill", id] => {
            ask(&socket, &Request::Kill { id: (*id).to_owned() })?;
        }
        ["report", id, agent, state] => {
            ask(&socket, &Request::Report { id: (*id).to_owned(), agent: (*agent).to_owned(), state: (*state).to_owned() })?;
        }
        ["stop"] => {
            // Not started just to be stopped.
            if UnixStream::connect(&socket).is_ok() {
                let _ = ask(&socket, &Request::Stop);
            }
        }
        _ => bail!("usage: multiplex sessions serve | list | attach <id> | kill <id> | report <id> <agent> <state> | stop"),
    }
    Ok(())
}

/// `multiplex here`: this terminal becomes a viewer of a new one that the
/// server keeps, in the folder this one is in.
pub fn here() -> Result<()> {
    if std::env::var_os("MULTIPLEX_SESSION").is_some() {
        bail!("This terminal is already kept by Multiplex.");
    }
    let socket = socket_path();
    let cwd = std::env::current_dir()?.to_string_lossy().into_owned();
    let (cols, rows) = crate::pane::terminal_size().unwrap_or((80, 24));
    let (answer, _) = ask(&socket, &Request::New { cwd, command: Vec::new(), cols, rows, workspace: String::new(), label: String::new(), fresh: false })?;
    if let Some(code) = attach(&socket, &answer.id, false, false)? {
        std::process::exit(code);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn new(cwd: &str, command: Vec<String>) -> Request {
        Request::New { cwd: cwd.to_owned(), command, cols: 80, rows: 24, workspace: String::new(), label: String::new(), fresh: false }
    }

    /// Reads what a viewer is shown until `wanted` is in it.
    fn shown(stream: &mut UnixStream, wanted: &str) -> String {
        stream.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
        let mut seen = String::new();
        let started = Instant::now();
        while !seen.contains(wanted) {
            assert!(started.elapsed() < Duration::from_secs(5), "never shown {wanted:?}: {seen:?}");
            match read_frame(stream) {
                Ok((b'O', bytes)) => seen.push_str(&String::from_utf8_lossy(&bytes)),
                Ok((b'X', bytes)) => seen.push_str(&format!("[exit {}]", String::from_utf8_lossy(&bytes))),
                Ok(_) => {}
                Err(err) => panic!("the viewer was cut off ({err}) before {wanted:?}: {seen:?}"),
            }
        }
        seen
    }

    #[test]
    fn a_terminal_runs_on_without_a_viewer_and_a_late_viewer_sees_what_it_shows() {
        let dir = tempfile::tempdir().unwrap();
        let socket = dir.path().join("sessions.sock");
        let serving = socket.clone();
        std::thread::spawn(move || serve(&serving));
        let started = Instant::now();
        while UnixStream::connect(&socket).is_err() {
            assert!(started.elapsed() < Duration::from_secs(5));
            std::thread::sleep(Duration::from_millis(10));
        }
        let sh = vec!["/bin/sh".to_owned()];
        let cwd = dir.path().to_string_lossy().into_owned();
        let id = ask(&socket, &new(&cwd, sh)).unwrap().0.id;
        assert!(ask(&socket, &new("/no/such/folder", vec![])).unwrap_err().to_string().contains("not a folder"));

        // A viewer types; the program answers; the viewer leaves.
        let (_, mut first) = ask(&socket, &Request::Attach { id: id.clone(), cols: 80, rows: 24 }).unwrap();
        write_frame(&mut first, b'I', b"echo one-$((6*7)); pwd\n").unwrap();
        let seen = shown(&mut first, "one-42");
        shown(&mut first, &cwd);
        assert!(!seen.contains("[exit"));
        drop(first);
        std::thread::sleep(Duration::from_millis(100));

        // It ran on: listed, with nobody in front of it.
        let list = ask(&socket, &Request::List).unwrap().0.terminals;
        assert_eq!(list.iter().map(|t| (t.id.as_str(), t.cwd.as_str(), t.command.as_str(), t.viewers)).collect::<Vec<_>>(), [(id.as_str(), cwd.as_str(), "/bin/sh", 0)]);

        // A later viewer, of another size, is shown what is on the screen
        // at once, and the program is told the new size.
        let (_, mut second) = ask(&socket, &Request::Attach { id: id.clone(), cols: 44, rows: 12 }).unwrap();
        shown(&mut second, "one-42");
        write_frame(&mut second, b'I', b"stty size\n").unwrap();
        shown(&mut second, "12 44");
        // Two at once see the same.
        let (_, mut third) = ask(&socket, &Request::Attach { id: id.clone(), cols: 44, rows: 12 }).unwrap();
        write_frame(&mut second, b'I', b"echo two-$((40+2))\n").unwrap();
        shown(&mut second, "two-42");
        shown(&mut third, "two-42");
        assert_eq!(ask(&socket, &Request::List).unwrap().0.terminals[0].viewers, 2);

        // Its program ends: the viewers are told how, and it is gone.
        write_frame(&mut third, b'I', b"exit 7\n").unwrap();
        assert!(shown(&mut second, "[exit 7]").contains("[exit 7]"));
        std::thread::sleep(Duration::from_millis(100));
        assert!(ask(&socket, &Request::List).unwrap().0.terminals.is_empty());
        assert!(ask(&socket, &Request::Attach { id, cols: 80, rows: 24 }).unwrap_err().to_string().contains("no terminal"));

        // One that is killed goes as if its window had closed.
        let id = ask(&socket, &new(&cwd, vec!["/bin/sh".to_owned()])).unwrap().0.id;
        ask(&socket, &Request::Kill { id }).unwrap();
        let started = Instant::now();
        while !ask(&socket, &Request::List).unwrap().0.terminals.is_empty() {
            assert!(started.elapsed() < Duration::from_secs(5), "the killed terminal stayed");
            std::thread::sleep(Duration::from_millis(20));
        }
    }
}
