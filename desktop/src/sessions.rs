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
        /// The variables it starts with (a window's own, so that programs
        /// in it find the desktop); the server's when empty.
        #[serde(default)]
        env: Vec<(String, String)>,
        /// It stands in for a plain terminal window: when its last viewer
        /// goes and nothing but its shell runs in it, it ends, as the
        /// window's own shell would have.
        #[serde(default)]
        window: bool,
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
    /// An agent says what it is doing (from its own hooks), and which
    /// conversation of its it is in, for continuing it later.
    Report {
        id: String,
        agent: String,
        state: String,
        #[serde(default)]
        conversation: String,
    },
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
    /// The agent's conversation, by the agent's own id for it.
    conversation: String,
    /// When the program last wrote, and when a viewer last typed.
    wrote: Instant,
    typed: Instant,
    /// It worked, then stopped with nobody in front of it: done, until
    /// someone looks.
    unseen: bool,
    was_working: bool,
    /// It stands in for a plain terminal window.
    window: bool,
    /// When it was started, and whether its program has written yet.
    started: Instant,
    wrote_once: bool,
    /// Since when it is being ended (its window closed with nothing
    /// running).
    ending: Option<Instant>,
}

impl Terminal {
    /// Nothing runs in it but the shell it started with.
    fn at_its_shell(&self) -> bool {
        self.front() == Some(self.child.id() as i32)
    }

    /// Its last viewer went: a window's stand-in with nothing running
    /// ends, as closing the window would have ended its shell.
    fn left_alone(&mut self) {
        if self.window && self.viewers.is_empty() && self.at_its_shell() {
            unsafe { libc::kill(-(self.child.id() as i32), libc::SIGHUP) };
            self.ending = Some(Instant::now());
        }
    }

    /// A shell can miss a hang-up that arrives just before it waits for
    /// input (seen with bash). One that is being ended is told again, and
    /// after a few seconds ended without being asked.
    fn still_ending(&mut self) {
        let Some(since) = self.ending else { return };
        if !self.viewers.is_empty() || !self.at_its_shell() {
            // Someone came back to it, or something runs in it after all.
            self.ending = None;
            return;
        }
        let signal = if since.elapsed() > Duration::from_secs(3) { libc::SIGKILL } else { libc::SIGHUP };
        unsafe { libc::kill(-(self.child.id() as i32), signal) };
    }

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
        if !agent {
            return AgentStatus::Unknown;
        }
        // A question by choice on its screen is waiting, whatever else is
        // known. Otherwise its own word counts; without one, it works
        // while it writes.
        let status = if !asked(&self.screen.screen().contents()).choices.is_empty() {
            AgentStatus::Blocked
        } else if let Some((_, said)) = &self.reported {
            *said
        } else if self.wrote.elapsed() < WORKING_FOR && self.wrote.duration_since(self.typed) > ECHO {
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

/// A terminal worth having back after the server (or the computer) was
/// restarted: one with an agent in a conversation that can be continued.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct Remembered {
    pub folder: String,
    pub label: String,
    pub agent: String,
    pub conversation: String,
}

/// What an agent is started with to carry on a conversation of its own.
/// None for an agent whose way of doing that is not known.
pub fn resume_command(agent: &str, conversation: &str) -> Option<String> {
    let fine = !conversation.is_empty() && conversation.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
    match agent {
        "claude" if fine => Some(format!("claude --resume {conversation}")),
        _ => None,
    }
}

pub fn remembered_file() -> PathBuf {
    std::env::var_os("MULTIPLEX_SESSIONS_FILE").map(PathBuf::from).unwrap_or_else(|| crate::share::state_dir().join("sessions.json"))
}

#[derive(Default)]
struct Kept {
    /// What was last written down as worth having back.
    written: Vec<Remembered>,
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

    /// Writes down what is worth having back, when that has changed.
    fn remember(&mut self, file: &Path) {
        let mut now: Vec<(u64, Remembered)> = self
            .terminals
            .values()
            .filter(|terminal| !terminal.conversation.is_empty())
            .filter_map(|terminal| {
                let (agent, _) = terminal.reported.as_ref()?;
                let label = self.spaces.iter().find(|space| space.number == terminal.space).map(|space| space.label.clone()).unwrap_or_default();
                Some((terminal.number, Remembered { folder: terminal.folder(), label, agent: agent.clone(), conversation: terminal.conversation.clone() }))
            })
            .collect();
        now.sort_by_key(|(number, _)| *number);
        let now: Vec<Remembered> = now.into_iter().map(|(_, remembered)| remembered).collect();
        if now != self.written {
            // Beside it and moved into place: never half a file.
            let beside = file.with_extension("json.new");
            if serde_json::to_vec_pretty(&now).ok().and_then(|bytes| std::fs::write(&beside, bytes).ok()).and_then(|()| std::fs::rename(&beside, file).ok()).is_some() {
                self.written = now;
            }
        }
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
    // Both ends are opened already marked to be closed in any program
    // started from here. Marked a moment later instead, a program started
    // at that very moment (by another request) inherited them, and the
    // terminal then never ended: its other end was still open somewhere.
    let failed = || anyhow!("no terminal could be made: {}", std::io::Error::last_os_error());
    unsafe {
        let master = libc::posix_openpt(libc::O_RDWR | libc::O_NOCTTY | libc::O_CLOEXEC);
        if master < 0 {
            return Err(failed());
        }
        let master = File::from_raw_fd(master);
        let mut name = [0 as libc::c_char; 128];
        if libc::grantpt(master.as_raw_fd()) != 0 || libc::unlockpt(master.as_raw_fd()) != 0 || libc::ptsname_r(master.as_raw_fd(), name.as_mut_ptr(), name.len()) != 0 {
            return Err(failed());
        }
        let slave = libc::open(name.as_ptr(), libc::O_RDWR | libc::O_NOCTTY | libc::O_CLOEXEC);
        if slave < 0 {
            return Err(failed());
        }
        let size = libc::winsize { ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0 };
        libc::ioctl(master.as_raw_fd(), libc::TIOCSWINSZ, &size);
        Ok((master, OwnedFd::from_raw_fd(slave)))
    }
}

/// What was made: the terminal, its tab and its workspace.
struct MadeIds {
    id: String,
    tab: String,
    workspace: String,
}

#[allow(clippy::too_many_arguments)]
fn start(shared: &Shared, cwd: &str, command: &[String], cols: u16, rows: u16, workspace: &str, label: &str, fresh: bool, env: &[(String, String)], window: bool) -> Result<MadeIds> {
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
    if !env.is_empty() {
        spawn.env_clear().envs(env.iter().map(|(name, value)| (name, value)));
    }
    spawn.args(&args).current_dir(cwd).env("MULTIPLEX_SESSION", &id);
    if env.is_empty() {
        spawn.env("TERM", "xterm-256color");
    }
    spawn.stdin(Stdio::from(slave.try_clone()?)).stdout(Stdio::from(slave.try_clone()?)).stderr(Stdio::from(slave));
    // Its own session, with the PTY as the terminal it is in charge of.
    unsafe {
        spawn.pre_exec(|| {
            // Signals as a fresh terminal gives them: a server started by
            // something that ignores hang-ups (nohup, say) would otherwise
            // hand that on, and a shell told its window closed would stay.
            for signal in [libc::SIGHUP, libc::SIGINT, libc::SIGQUIT, libc::SIGTERM, libc::SIGPIPE, libc::SIGTSTP, libc::SIGTTIN, libc::SIGTTOU] {
                libc::signal(signal, libc::SIG_DFL);
            }
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
        conversation: String::new(),
        wrote: now,
        typed: now,
        unseen: false,
        was_working: false,
        window,
        started: now,
        wrote_once: false,
        ending: None,
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
            terminal.wrote_once = true;
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
            // Stopped on purpose: nothing is to come back by itself.
            let _ = std::fs::remove_file(remembered_file());
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
        Request::New { cwd, command, cols, rows, workspace, label, fresh, env, window } => {
            return answer(
                &mut stream,
                match start(&shared, &cwd, &command, cols, rows, &workspace, &label, fresh, &env, window) {
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
            // A terminal that has only just started is given until its
            // shell has written its prompt and gone quiet: what is typed
            // before that is lost (seen: text sent right after making one).
            loop {
                let kept = shared.lock().unwrap();
                let Some(terminal) = kept.terminals.get(&id) else { break };
                let settled = terminal.wrote_once && terminal.wrote.elapsed() > Duration::from_millis(250);
                if settled || terminal.started.elapsed() > Duration::from_secs(4) {
                    break;
                }
                drop(kept);
                std::thread::sleep(Duration::from_millis(40));
            }
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
        Request::Report { id, agent, state, conversation } => {
            let mut kept = shared.lock().unwrap();
            let Some(terminal) = kept.terminals.get_mut(&id) else { return answer(&mut stream, missing(&id)) };
            let Ok(status) = serde_json::from_value::<AgentStatus>(serde_json::Value::String(state)) else { return answer(&mut stream, Answer::error("That is not a state.")) };
            terminal.reported = (status != AgentStatus::Unknown).then_some((agent, status));
            if status == AgentStatus::Unknown {
                // An agent that ended is no longer in a conversation.
                terminal.conversation.clear();
            } else if !conversation.is_empty() && conversation.len() <= 128 && conversation.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_') {
                terminal.conversation = conversation;
            }
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
        terminal.left_alone();
    }
    kept.tell();
    Ok(())
}

pub fn socket_path() -> PathBuf {
    std::env::var_os("MULTIPLEX_SESSIONS_SOCKET").map(PathBuf::from).unwrap_or_else(|| crate::share::runtime_dir().join("sessions.sock"))
}

/// `multiplex sessions serve`: until it is stopped.
pub fn serve(socket: &Path, file: &Path) -> Result<()> {
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
    // What was running when the server last went away without being told
    // to (a restart of the computer, say) comes back: a terminal in its
    // folder, and its agent asked to carry on its conversation.
    if let Some(dir) = file.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let before: Vec<Remembered> = std::fs::read(file).ok().and_then(|bytes| serde_json::from_slice(&bytes).ok()).unwrap_or_default();
    for remembered in before {
        let Some(command) = resume_command(&remembered.agent, &remembered.conversation) else { continue };
        let Ok(made) = start(&shared, &remembered.folder, &[], 120, 40, "", &remembered.label, false, &[], false) else { continue };
        // Remembered from the start, also if the server goes away again
        // before the agent has said a word.
        if let Some(terminal) = shared.lock().unwrap().terminals.get_mut(&made.id) {
            terminal.conversation = remembered.conversation.clone();
            terminal.reported = Some((remembered.agent.clone(), AgentStatus::Idle));
        }
        let (shared, id) = (shared.clone(), made.id);
        // Once its shell is at its prompt.
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(1500));
            if let Some(terminal) = shared.lock().unwrap().terminals.get_mut(&id) {
                let _ = terminal.master.write_all(format!("{command}\r").as_bytes());
            }
        });
    }
    // What changes without anyone asking (a title, a folder, an agent
    // starting to wait) is looked at twice a second while someone watches.
    let ticking = shared.clone();
    let file = file.to_owned();
    std::thread::spawn(move || loop {
        std::thread::sleep(Duration::from_millis(500));
        let mut kept = ticking.lock().unwrap();
        for terminal in kept.terminals.values_mut() {
            terminal.still_ending();
        }
        kept.remember(&file);
        kept.tell();
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
    // A server that does not answer must not hold up whoever asks (a
    // terminal window opening, say).
    stream.set_read_timeout(Some(Duration::from_secs(5)))?;
    let (kind, bytes) = read_frame(&mut stream).map_err(|_| anyhow!("The session server did not answer."))?;
    stream.set_read_timeout(None)?;
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
        ["serve"] => serve(&socket, &remembered_file())?,
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
            ask(&socket, &Request::Report { id: (*id).to_owned(), agent: (*agent).to_owned(), state: (*state).to_owned(), conversation: String::new() })?;
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

/// What an agent's hook says, as a state: the event's name, and for a
/// notice whether it is the agent sitting idle rather than asking.
pub fn hook_state(event: &str, told: &serde_json::Value) -> Option<&'static str> {
    Some(match event {
        "start" | "stop" => "idle",
        "prompt" | "tool" => "working",
        "notice" => {
            let kind = told["notification_type"].as_str().unwrap_or_default();
            let words = told["message"].as_str().unwrap_or_default().to_lowercase();
            if kind == "idle_prompt" || words.contains("waiting for your input") {
                "idle"
            } else {
                "blocked"
            }
        }
        "end" => "unknown",
        _ => return None,
    })
}

/// `multiplex agent hook <agent> <event>`: called by an agent's own hooks
/// (see `multiplex setup --agents`). Says nothing and never fails: an
/// agent outside a kept terminal, or with no server, is none of its
/// business, and a hook must not hold an agent up.
pub fn hook(agent: &str, event: &str) {
    let Ok(id) = std::env::var("MULTIPLEX_SESSION") else { return };
    let socket = socket_path();
    if UnixStream::connect(&socket).is_err() {
        return;
    }
    // What the agent tells its hook, when it does: a little JSON.
    let mut told = String::new();
    let _ = std::io::stdin().take(64 * 1024).read_to_string(&mut told);
    let told: serde_json::Value = serde_json::from_str(&told).unwrap_or_default();
    let Some(state) = hook_state(event, &told) else { return };
    let conversation = told["session_id"].as_str().unwrap_or_default().to_owned();
    let _ = ask(&socket, &Request::Report { id, agent: agent.to_owned(), state: state.to_owned(), conversation });
}

/// The hooks Claude Code is given, by its name for the event and ours.
const CLAUDE_HOOKS: &[(&str, &str)] = &[("SessionStart", "start"), ("UserPromptSubmit", "prompt"), ("PreToolUse", "tool"), ("Notification", "notice"), ("Stop", "stop"), ("SessionEnd", "end")];

fn is_our_hook(entry: &serde_json::Value) -> bool {
    entry["hooks"].as_array().is_some_and(|hooks| hooks.iter().any(|hook| hook["command"].as_str().is_some_and(|command| command.starts_with("multiplex agent hook "))))
}

/// Claude Code's settings with our hooks in them (`on`) or without. What
/// else is there, other hooks too, stays as it is.
pub fn with_claude_hooks(mut settings: serde_json::Value, on: bool) -> serde_json::Value {
    if !settings.is_object() {
        settings = serde_json::json!({});
    }
    let mut hooks = settings["hooks"].as_object().cloned().unwrap_or_default();
    for (event, ours) in CLAUDE_HOOKS {
        let mut entries: Vec<serde_json::Value> = hooks.get(*event).and_then(|list| list.as_array()).cloned().unwrap_or_default();
        entries.retain(|entry| !is_our_hook(entry));
        if on {
            entries.push(serde_json::json!({ "hooks": [{ "type": "command", "command": format!("multiplex agent hook claude {ours}"), "timeout": 5 }] }));
        }
        if entries.is_empty() {
            hooks.remove(*event);
        } else {
            hooks.insert((*event).to_owned(), serde_json::Value::Array(entries));
        }
    }
    let map = settings.as_object_mut().expect("made an object above");
    if hooks.is_empty() {
        map.remove("hooks");
    } else {
        map.insert("hooks".to_owned(), serde_json::Value::Object(hooks));
    }
    settings
}

/// `multiplex setup --agents` and `--agents-off`: Claude Code tells
/// Multiplex itself when it starts to work, asks, and stops.
pub fn setup_agents(on: bool, dry_run: bool) -> Result<()> {
    let home = PathBuf::from(std::env::var_os("HOME").ok_or_else(|| anyhow!("There is no home folder to set this up in."))?);
    let file = home.join(".claude/settings.json");
    let text = match std::fs::read_to_string(&file) {
        Ok(text) => text,
        Err(_) if on && home.join(".claude").is_dir() => "{}".to_owned(),
        Err(_) => {
            println!("Claude Code has no settings here ({}): nothing to do.", file.display());
            return Ok(());
        }
    };
    let before: serde_json::Value = serde_json::from_str(&text).map_err(|_| anyhow!("{} is not JSON that can be read; it was left alone.", file.display()))?;
    let after = with_claude_hooks(before.clone(), on);
    if after == before {
        println!("{}: already {}.", file.display(), if on { "set up" } else { "without Multiplex's hooks" });
        return Ok(());
    }
    if dry_run {
        println!("{}: would {} Multiplex's hooks ({}).", file.display(), if on { "get" } else { "lose" }, CLAUDE_HOOKS.iter().map(|(event, _)| *event).collect::<Vec<_>>().join(", "));
        return Ok(());
    }
    let kept = home.join(".claude/settings.json.before-multiplex");
    if !kept.exists() && file.exists() {
        std::fs::copy(&file, &kept)?;
    }
    let beside = home.join(".claude/settings.json.multiplex-new");
    std::fs::write(&beside, serde_json::to_string_pretty(&after)? + "\n")?;
    std::fs::rename(&beside, &file)?;
    println!("{}: {}.", file.display(), if on { "Claude Code now tells Multiplex when it works, asks and stops (in sessions started from now on)" } else { "Multiplex's hooks are out" });
    Ok(())
}

/// The unit that keeps the server running with the desktop session.
pub const UNIT: &str = "multiplex-sessions.service";

pub fn unit_text(program: &str) -> String {
    format!(
        "[Unit]\nDescription=Multiplex session server: terminals that keep running and can be picked up from the phone\nPartOf=graphical-session.target\nAfter=graphical-session.target\n\n[Service]\nExecStart={program} sessions serve\nRestart=on-failure\nRestartSec=2\n\n[Install]\nWantedBy=graphical-session.target\n"
    )
}

/// `multiplex setup --service` and `--service-off`: the session server
/// as a service of the user's own, started with the desktop (so that the
/// terminals it makes find the desktop, and what it remembers comes back
/// after a restart of the computer).
pub fn setup_service(on: bool, dry_run: bool) -> Result<()> {
    let home = PathBuf::from(std::env::var_os("HOME").ok_or_else(|| anyhow!("There is no home folder to set this up in."))?);
    let unit = home.join(".config/systemd/user").join(UNIT);
    let systemctl = |args: &[&str]| Command::new("systemctl").arg("--user").args(args).status().is_ok_and(|status| status.success());
    if dry_run {
        println!("Would {} {}.", if on { "write and start" } else { "stop and remove" }, unit.display());
        return Ok(());
    }
    if !on {
        systemctl(&["disable", "--now", UNIT]);
        let _ = std::fs::remove_file(&unit);
        systemctl(&["daemon-reload"]);
        println!("The session server is no longer a service. (It still starts when first asked.)");
        return Ok(());
    }
    let program = std::env::current_exe()?.to_string_lossy().into_owned();
    std::fs::create_dir_all(unit.parent().expect("has a folder"))?;
    std::fs::write(&unit, unit_text(&program))?;
    systemctl(&["daemon-reload"]);
    // A server started by hand or on first use holds the socket; with
    // terminals in it, it is left to finish, and the service takes over
    // the next time.
    let socket = socket_path();
    let running = UnixStream::connect(&socket).is_ok();
    let busy = running && ask(&socket, &Request::List).is_ok_and(|(answer, _)| !answer.terminals.is_empty());
    let active = systemctl(&["is-active", "--quiet", UNIT]);
    if active {
        systemctl(&["enable", UNIT]);
        println!("The session server already runs as a service.");
    } else if busy {
        systemctl(&["enable", UNIT]);
        println!("The session server is set up as a service. One started earlier is keeping terminals, so it is left to run; the service takes over at the next login.");
    } else {
        if running {
            // Asked to step aside, keeping what it remembers.
            let remembered = std::fs::read(remembered_file()).ok();
            let _ = ask(&socket, &Request::Stop);
            if let Some(bytes) = remembered {
                let _ = std::fs::write(remembered_file(), bytes);
            }
            std::thread::sleep(Duration::from_millis(300));
        }
        if !systemctl(&["enable", "--now", UNIT]) {
            bail!("systemd did not start the session server; see: systemctl --user status {UNIT}");
        }
        println!("The session server runs as a service and starts with the desktop.");
    }
    Ok(())
}

/// What `multiplex here --window` exits with when this terminal could
/// not be handed to the server: the shell that asked carries on as a
/// plain one.
pub const NOT_KEPT: i32 = 113;

/// `multiplex here`: this terminal becomes a viewer of a new one that the
/// server keeps, in the folder this one is in, with this one's variables.
/// With `window` it stands in for the window's own shell (see
/// `multiplex setup --terminals`): failing to start is said by the exit
/// code alone, and a program's own exit code never passes for that.
pub fn here(window: bool) -> Result<()> {
    let made = || -> Result<(PathBuf, String)> {
        if std::env::var_os("MULTIPLEX_SESSION").is_some() {
            bail!("This terminal is already kept by Multiplex.");
        }
        let socket = socket_path();
        let cwd = std::env::current_dir()?.to_string_lossy().into_owned();
        let (cols, rows) = crate::pane::terminal_size().unwrap_or((80, 24));
        let env: Vec<(String, String)> = std::env::vars().collect();
        let (answer, _) = ask(&socket, &Request::New { cwd, command: Vec::new(), cols, rows, workspace: String::new(), label: String::new(), fresh: false, env, window })?;
        Ok((socket, answer.id))
    };
    let (socket, id) = match made() {
        Ok(made) => made,
        Err(_) if window => std::process::exit(NOT_KEPT),
        Err(err) => return Err(err),
    };
    match attach(&socket, &id, false, false) {
        Ok(Some(code)) => std::process::exit(if code == NOT_KEPT { 1 } else { code }),
        Ok(None) => Ok(()),
        Err(_) if window => std::process::exit(NOT_KEPT),
        Err(err) => Err(err),
    }
}

/// The lines `multiplex setup --terminals` keeps in a shell's start-up
/// file, between two marks so they can be found and taken out again.
pub const MARK_BEGIN: &str = "# >>> multiplex terminals >>>";
pub const MARK_END: &str = "# <<< multiplex terminals <<<";

pub fn shell_lines() -> String {
    format!(
        "{MARK_BEGIN}\n# Every terminal window is kept by Multiplex, so it can be picked up from the\n# phone and runs on when its window closes. Not in a terminal that is already\n# kept, over SSH, or in tmux. If Multiplex cannot take it, this is a plain shell.\n# Undo with: multiplex setup --terminals-off   (once: MULTIPLEX_PLAIN=1)\nif [[ $- == *i* && -z $MULTIPLEX_SESSION && -z $MULTIPLEX_PLAIN && -z $SSH_CONNECTION && -z $TMUX && -t 0 && -t 1 ]] && command -v multiplex >/dev/null 2>&1; then\n  multiplex here --window\n  [[ $? -ne {NOT_KEPT} ]] && exit\nfi\n{MARK_END}\n"
    )
}

/// A start-up file's text with the lines in it (`on`) or without them.
pub fn with_shell_lines(text: &str, on: bool) -> String {
    let mut rest = match (text.find(MARK_BEGIN), text.find(MARK_END)) {
        (Some(from), Some(to)) if to > from => {
            let after = &text[to + MARK_END.len()..];
            format!("{}{}", &text[..from], after.strip_prefix('\n').unwrap_or(after))
        }
        _ => text.to_owned(),
    };
    if on {
        if !rest.is_empty() && !rest.ends_with('\n') {
            rest.push('\n');
        }
        rest.push_str(&shell_lines());
    }
    rest
}

/// `multiplex setup --terminals` and `--terminals-off`: every new
/// terminal window a session, or plain again. The file as it was is kept
/// beside it the first time.
pub fn setup_terminals(on: bool, dry_run: bool) -> Result<()> {
    let home = PathBuf::from(std::env::var_os("HOME").ok_or_else(|| anyhow!("There is no home folder to set this up in."))?);
    let mut touched = 0;
    for name in [".bashrc", ".zshrc"] {
        let file = home.join(name);
        let Ok(text) = std::fs::read_to_string(&file) else { continue };
        let next = with_shell_lines(&text, on);
        touched += 1;
        if next == text {
            println!("{}: already {}.", file.display(), if on { "set up" } else { "plain" });
            continue;
        }
        if dry_run {
            println!("{}: would {}.", file.display(), if on { "get these lines at its end:\n".to_owned() + &shell_lines() } else { "lose Multiplex's lines".to_owned() });
            continue;
        }
        let kept = home.join(format!("{name}.before-multiplex"));
        if !kept.exists() {
            std::fs::copy(&file, &kept)?;
        }
        // Written beside it and moved into place: never half a file.
        let beside = home.join(format!("{name}.multiplex-new"));
        std::fs::write(&beside, &next)?;
        std::fs::rename(&beside, &file)?;
        println!("{}: {}.", file.display(), if on { "every new terminal window is now kept by Multiplex" } else { "terminals are plain again" });
    }
    if touched == 0 {
        bail!("Neither ~/.bashrc nor ~/.zshrc is there to set this up in.");
    }
    if on && !dry_run {
        println!("Terminals that are already open stay as they are. Undo with: multiplex setup --terminals-off");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn new(cwd: &str, command: Vec<String>) -> Request {
        Request::New { cwd: cwd.to_owned(), command, cols: 80, rows: 24, workspace: String::new(), label: String::new(), fresh: false, env: Vec::new(), window: false }
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
        let file = dir.path().join("sessions.json");
        std::thread::spawn(move || serve(&serving, &file));
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
        // The folder is printed after the sum: both are in what is seen
        // by then.
        let seen = shown(&mut first, &format!("{cwd}\r\n"));
        assert!(seen.contains("one-42") && !seen.contains("[exit"), "{seen:?}");
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

    #[test]
    fn the_lines_for_a_shell_go_in_once_and_come_out_whole() {
        let before = "# my shell\nalias ll='ls -l'\n";
        let on = with_shell_lines(before, true);
        assert!(on.starts_with(before) && on.contains("multiplex here --window") && on.ends_with(&format!("{MARK_END}\n")));
        assert_eq!(with_shell_lines(&on, true), on, "a second time changes nothing");
        assert_eq!(with_shell_lines(&on, false), before);
        assert_eq!(with_shell_lines(before, false), before);
        assert_eq!(with_shell_lines("no newline at the end", true).lines().nth(1), Some(MARK_BEGIN));
        // What the user wrote after them stays.
        let more = format!("{on}export EDITOR=vi\n");
        assert_eq!(with_shell_lines(&more, false), format!("{before}export EDITOR=vi\n"));
    }

    #[test]
    fn a_windows_stand_in_ends_with_its_window_unless_something_runs_in_it() {
        let dir = tempfile::tempdir().unwrap();
        let socket = dir.path().join("sessions.sock");
        let serving = socket.clone();
        let file = dir.path().join("sessions.json");
        std::thread::spawn(move || serve(&serving, &file));
        while UnixStream::connect(&socket).is_err() {
            std::thread::sleep(Duration::from_millis(10));
        }
        let cwd = dir.path().to_string_lossy().into_owned();
        let window = |env: Vec<(String, String)>| Request::New { cwd: cwd.clone(), command: vec!["/bin/sh".to_owned()], cols: 80, rows: 24, workspace: String::new(), label: String::new(), fresh: false, env, window: true };
        let count = || ask(&socket, &Request::List).unwrap().0.terminals.len();
        let gone = |what: &str| {
            let started = Instant::now();
            while count() != 0 {
                assert!(started.elapsed() < Duration::from_secs(8), "{what}");
                std::thread::sleep(Duration::from_millis(20));
            }
        };

        // Idle at its shell: closing the window ends it. It started with
        // the window's own variables.
        let id = ask(&socket, &window(vec![("PATH".into(), "/usr/bin:/bin".into()), ("FROM_THE_WINDOW".into(), "yes".into())])).unwrap().0.id;
        let (_, mut view) = ask(&socket, &Request::Attach { id, cols: 80, rows: 24 }).unwrap();
        write_frame(&mut view, b'I', b"echo window=$FROM_THE_WINDOW kept=$MULTIPLEX_SESSION\n").unwrap();
        assert!(shown(&mut view, "window=yes kept=w1:p1").contains("window=yes"));
        drop(view);
        gone("an idle stand-in stayed after its window closed");

        // Something runs in it: it is kept, and can be come back to.
        let id = ask(&socket, &window(Vec::new())).unwrap().0.id;
        let (_, mut view) = ask(&socket, &Request::Attach { id: id.clone(), cols: 80, rows: 24 }).unwrap();
        write_frame(&mut view, b'I', b"echo started; sleep 30\n").unwrap();
        shown(&mut view, "started\r\n");
        std::thread::sleep(Duration::from_millis(200));
        drop(view);
        std::thread::sleep(Duration::from_millis(300));
        assert_eq!(count(), 1, "a stand-in with something running was ended");
        let (_, mut again) = ask(&socket, &Request::Attach { id, cols: 80, rows: 24 }).unwrap();
        write_frame(&mut again, b'I', &[3]).unwrap();
        // Seen to be back at its shell (the command gone) before leaving.
        write_frame(&mut again, b'I', b"echo back-$((1+1))\n").unwrap();
        shown(&mut again, "back-2");
        drop(again);
        gone("back at its shell and left again, it stayed");
    }

    #[test]
    fn claude_codes_settings_get_our_hooks_and_lose_only_ours() {
        use serde_json::json;
        let theirs = json!({"model": "x", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "notify-send done"}]}]}});
        let on = with_claude_hooks(theirs.clone(), true);
        assert_eq!(on["model"], "x");
        assert_eq!(on["hooks"]["Stop"].as_array().unwrap().len(), 2, "their own hook stays beside ours");
        assert_eq!(on["hooks"]["Notification"][0]["hooks"][0]["command"], "multiplex agent hook claude notice");
        assert_eq!(on["hooks"].as_object().unwrap().len(), CLAUDE_HOOKS.len());
        assert_eq!(with_claude_hooks(on.clone(), true), on, "a second time changes nothing");
        assert_eq!(with_claude_hooks(on, false), theirs);
        // Settings without hooks come back without a trace.
        assert_eq!(with_claude_hooks(with_claude_hooks(json!({"theme": "dark"}), true), false), json!({"theme": "dark"}));
        // What a hook is told becomes a state.
        assert_eq!(hook_state("prompt", &json!({})), Some("working"));
        assert_eq!(hook_state("notice", &json!({"message": "Claude needs your permission to use Bash"})), Some("blocked"));
        assert_eq!(hook_state("notice", &json!({"notification_type": "idle_prompt"})), Some("idle"));
        assert_eq!(hook_state("notice", &json!({"message": "Claude is waiting for your input"})), Some("idle"));
        assert_eq!(hook_state("stop", &json!({})), Some("idle"));
        assert_eq!(hook_state("dance", &json!({})), None);
    }

    #[test]
    fn an_agents_conversation_is_written_down_and_comes_back_with_a_new_server() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("sessions.json");
        let folder = dir.path().join("api");
        std::fs::create_dir_all(&folder).unwrap();
        let folder = folder.to_string_lossy().into_owned();
        let up = |name: &str| {
            let socket = dir.path().join(name);
            let (serving, file) = (socket.clone(), file.clone());
            std::thread::spawn(move || serve(&serving, &file));
            while UnixStream::connect(&socket).is_err() {
                std::thread::sleep(Duration::from_millis(10));
            }
            socket
        };
        let written = || -> Vec<Remembered> { std::fs::read(&file).ok().and_then(|bytes| serde_json::from_slice(&bytes).ok()).unwrap_or_default() };
        let waited = |what: &str, wanted: &dyn Fn(&[Remembered]) -> bool| {
            let started = Instant::now();
            while !wanted(&written()) {
                assert!(started.elapsed() < Duration::from_secs(5), "{what}: {:?}", written());
                std::thread::sleep(Duration::from_millis(50));
            }
        };

        // An agent says which conversation it is in: written down. A plain
        // terminal is not.
        let first = up("one.sock");
        let id = ask(&first, &Request::New { cwd: folder.clone(), command: vec!["/bin/sh".to_owned()], cols: 80, rows: 24, workspace: String::new(), label: "the api".into(), fresh: false, env: Vec::new(), window: false }).unwrap().0.id;
        ask(&first, &new(&folder, vec!["/bin/sh".to_owned()])).unwrap();
        let report = |state: &str, conversation: &str| ask(&first, &Request::Report { id: id.clone(), agent: "claude".into(), state: state.into(), conversation: conversation.into() }).unwrap();
        report("working", "0a1b2c3d-1111-2222-3333-444455556666");
        waited("the conversation was not written down", &|all| all == [Remembered { folder: folder.clone(), label: "the api".into(), agent: "claude".into(), conversation: "0a1b2c3d-1111-2222-3333-444455556666".into() }]);

        // A new server (the computer was restarted) with what was written:
        // a terminal in that folder, under that name, and the agent asked
        // to carry on that conversation.
        let second = up("two.sock");
        let state = ask(&second, &Request::State).unwrap().0.state.unwrap();
        assert_eq!(state.workspaces.iter().map(|w| w.label.as_str()).collect::<Vec<_>>(), ["the api"]);
        let pane = state.workspaces[0].tabs[0].panes[0].clone();
        assert_eq!(pane.folder, folder);
        let started = Instant::now();
        loop {
            let text = ask(&second, &Request::Read { id: pane.id.clone(), lines: 0 }).unwrap().0.text.unwrap();
            if text.contains("claude --resume 0a1b2c3d-1111-2222-3333-444455556666") {
                break;
            }
            assert!(started.elapsed() < Duration::from_secs(6), "the agent was not asked to carry on: {text:?}");
            std::thread::sleep(Duration::from_millis(100));
        }

        // The agent ends: nothing of it is to come back.
        report("unknown", "");
        ask(&second, &Request::Kill { id: pane.id }).unwrap();
        waited("an ended conversation stayed written", &|all| all.is_empty());
        // What cannot be carried on, or is not an id, never becomes a command.
        assert_eq!(resume_command("claude", "abc; rm -rf ~"), None);
        assert_eq!(resume_command("claude", ""), None);
        assert_eq!(resume_command("some-agent", "abc"), None);
    }
}
