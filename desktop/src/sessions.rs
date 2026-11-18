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

use anyhow::{anyhow, bail, Context, Result};
use serde::{Deserialize, Serialize};

/// Lines of earlier output kept per terminal.
const SCROLLBACK: usize = 5000;

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
#[serde(tag = "do", rename_all = "lowercase")]
pub enum Request {
    /// A new terminal in a folder, running a program (the user's shell
    /// when none is named).
    New { cwd: String, #[serde(default)] command: Vec<String>, cols: u16, rows: u16 },
    List,
    /// Sit in front of one; its output and the viewer's input follow.
    Attach { id: String, cols: u16, rows: u16 },
    Kill { id: String },
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
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub id: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub terminals: Vec<Told>,
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
    if len > 1 << 20 {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "a frame of more than a megabyte"));
    }
    let mut bytes = vec![0u8; len];
    from.read_exact(&mut bytes)?;
    Ok((kind_of(head[0]), bytes))
}

fn kind_of(byte: u8) -> u8 {
    byte
}

fn size_bytes(cols: u16, rows: u16) -> [u8; 4] {
    let (c, r) = (cols.to_be_bytes(), rows.to_be_bytes());
    [c[0], c[1], r[0], r[1]]
}

/// A terminal the server keeps.
struct Terminal {
    cwd: String,
    command: String,
    /// The PTY's own end: written to for input, sized by ioctl.
    master: File,
    child: Child,
    screen: vt100::Parser,
    viewers: Vec<(u64, UnixStream)>,
    exited: Option<i32>,
}

impl Terminal {
    fn resize(&mut self, cols: u16, rows: u16) {
        let (cols, rows) = (cols.clamp(2, 1000), rows.clamp(2, 1000));
        let size = libc::winsize { ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0 };
        unsafe { libc::ioctl(self.master.as_raw_fd(), libc::TIOCSWINSZ, &size) };
        self.screen.screen_mut().set_size(nz(rows), nz(cols));
    }
}

/// A size's side as the screen model wants it; never nothing.
fn nz(n: u16) -> std::num::NonZero<u16> {
    std::num::NonZero::new(n.max(1)).expect("at least one")
}

type Shared = Arc<Mutex<HashMap<String, Terminal>>>;

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

fn start(terminals: &Shared, next: &Mutex<u64>, cwd: &str, command: &[String], cols: u16, rows: u16) -> Result<String> {
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
    let mut spawn = Command::new(&program);
    spawn.args(&args).current_dir(cwd).env("TERM", "xterm-256color").env("MULTIPLEX_SESSION", "1");
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
    let id = {
        let mut next = next.lock().unwrap();
        *next += 1;
        format!("t{next}")
    };
    let mut reader = master.try_clone()?;
    let terminal = Terminal { cwd: cwd.to_owned(), command: program, master, child, screen: vt100::Parser::new(nz(rows), nz(cols), SCROLLBACK), viewers: Vec::new(), exited: None };
    terminals.lock().unwrap().insert(id.clone(), terminal);

    // What the program writes: into the screen's model, and on to whoever
    // is looking. When it ends, they are told, and the terminal goes.
    let (shared, name) = (terminals.clone(), id.clone());
    std::thread::spawn(move || {
        let mut buffer = [0u8; 16 * 1024];
        loop {
            let read = reader.read(&mut buffer).unwrap_or(0);
            let mut all = shared.lock().unwrap();
            let Some(terminal) = all.get_mut(&name) else { return };
            if read == 0 {
                let code = terminal.child.wait().ok().and_then(|status| status.code()).unwrap_or(-1);
                terminal.exited = Some(code);
                for (_, viewer) in &mut terminal.viewers {
                    let _ = write_frame(viewer, b'X', code.to_string().as_bytes());
                    let _ = viewer.shutdown(std::net::Shutdown::Both);
                }
                all.remove(&name);
                return;
            }
            terminal.screen.process(&buffer[..read]);
            terminal.viewers.retain_mut(|(_, viewer)| write_frame(viewer, b'O', &buffer[..read]).is_ok());
        }
    });
    Ok(id)
}

fn told(all: &HashMap<String, Terminal>) -> Vec<Told> {
    let mut list: Vec<Told> = all
        .iter()
        .map(|(id, t)| {
            let (rows, cols) = t.screen.screen().size();
            Told { id: id.clone(), cwd: t.cwd.clone(), command: t.command.clone(), viewers: t.viewers.len(), cols: cols.get(), rows: rows.get() }
        })
        .collect();
    list.sort_by_key(|t| t.id[1..].parse::<u64>().unwrap_or(0));
    list
}

fn serve_one(mut stream: UnixStream, terminals: Shared, next: Arc<Mutex<u64>>, viewer_id: u64) -> Result<()> {
    let (kind, bytes) = read_frame(&mut stream)?;
    if kind != b'Q' {
        bail!("a request was expected first");
    }
    let answer = |stream: &mut UnixStream, answer: Answer| write_frame(stream, b'A', &serde_json::to_vec(&answer)?).map_err(anyhow::Error::from);
    let request: Request = match serde_json::from_slice(&bytes) {
        Ok(request) => request,
        Err(_) => return answer(&mut stream, Answer { error: "That request was not understood.".into(), ..Answer::default() }),
    };
    let id = match request {
        Request::List => return answer(&mut stream, Answer { terminals: told(&terminals.lock().unwrap()), ..Answer::default() }),
        Request::Kill { id } => {
            let mut all = terminals.lock().unwrap();
            let Some(terminal) = all.get_mut(&id) else { return answer(&mut stream, Answer { error: format!("There is no terminal {id}."), ..Answer::default() }) };
            // Its whole session, as closing a window would.
            unsafe { libc::kill(-(terminal.child.id() as i32), libc::SIGHUP) };
            return answer(&mut stream, Answer { id, ..Answer::default() });
        }
        Request::New { cwd, command, cols, rows } => match start(&terminals, &next, &cwd, &command, cols, rows) {
            Ok(id) => return answer(&mut stream, Answer { id, ..Answer::default() }),
            Err(err) => return answer(&mut stream, Answer { error: format!("{err:#}"), ..Answer::default() }),
        },
        Request::Attach { id, cols, rows } => {
            let mut all = terminals.lock().unwrap();
            let Some(terminal) = all.get_mut(&id) else { return answer(&mut stream, Answer { error: format!("There is no terminal {id}."), ..Answer::default() }) };
            // The newest viewer's size is the terminal's: it is the one in use.
            terminal.resize(cols, rows);
            answer(&mut stream, Answer { id: id.clone(), ..Answer::default() })?;
            // The picture as it stands, then everything that follows.
            write_frame(&mut stream, b'O', terminal.screen.screen().state_formatted().as_bytes())?;
            terminal.viewers.push((viewer_id, stream.try_clone()?));
            id
        }
    };
    // Attached: what the viewer types, and its size when that changes.
    while let Ok((kind, bytes)) = read_frame(&mut stream) {
        let mut all = terminals.lock().unwrap();
        let Some(terminal) = all.get_mut(&id) else { break };
        match kind {
            b'I' => {
                let _ = terminal.master.write_all(&bytes);
            }
            b'R' if bytes.len() == 4 => terminal.resize(u16::from_be_bytes([bytes[0], bytes[1]]), u16::from_be_bytes([bytes[2], bytes[3]])),
            _ => {}
        }
    }
    if let Some(terminal) = terminals.lock().unwrap().get_mut(&id) {
        terminal.viewers.retain(|(viewer, _)| *viewer != viewer_id);
    }
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
    let terminals: Shared = Arc::new(Mutex::new(HashMap::new()));
    let next = Arc::new(Mutex::new(0u64));
    for (viewer, stream) in listener.incoming().flatten().enumerate() {
        let (terminals, next) = (terminals.clone(), next.clone());
        std::thread::spawn(move || {
            let _ = serve_one(stream, terminals, next, viewer as u64);
        });
    }
    Ok(())
}

/// Asks the server one thing.
pub fn ask(socket: &Path, request: &Request) -> Result<(Answer, UnixStream)> {
    let mut stream = UnixStream::connect(socket).map_err(|_| anyhow!("The session server is not running. Start it with: multiplex sessions serve"))?;
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

/// Sits in front of a terminal with this terminal: what is typed goes in,
/// what it shows comes out, until its program ends (its exit code comes
/// back) or this terminal goes away (None; the program runs on).
pub fn attach(socket: &Path, id: &str) -> Result<Option<i32>> {
    let (cols, rows) = crate::pane::terminal_size().unwrap_or((80, 24));
    let (_, mut stream) = ask(socket, &Request::Attach { id: id.to_owned(), cols, rows })?;
    let _raw = crate::pane::Raw::on();
    let mut up = stream.try_clone()?;
    // Input, and the size whenever it may have changed, on its own thread.
    std::thread::spawn(move || {
        let mut stdin = std::io::stdin().lock();
        let mut buffer = [0u8; 4096];
        let mut last = (cols, rows);
        loop {
            let read = match stdin.read(&mut buffer) {
                Ok(0) => break,
                Ok(read) => read,
                // A signal (the window was resized) interrupts the read.
                Err(err) if err.kind() == std::io::ErrorKind::Interrupted => 0,
                Err(_) => break,
            };
            if let Some(now) = crate::pane::terminal_size().filter(|now| *now != last) {
                last = now;
                if write_frame(&mut up, b'R', &size_bytes(now.0, now.1)).is_err() {
                    break;
                }
            }
            if read > 0 && write_frame(&mut up, b'I', &buffer[..read]).is_err() {
                break;
            }
        }
        let _ = up.shutdown(std::net::Shutdown::Both);
    });
    let mut out = std::io::stdout().lock();
    loop {
        match read_frame(&mut stream) {
            Ok((b'O', bytes)) => {
                out.write_all(&bytes)?;
                out.flush()?;
            }
            Ok((b'X', bytes)) => return Ok(String::from_utf8_lossy(&bytes).parse().ok()),
            Ok(_) => {}
            Err(_) => return Ok(None),
        }
    }
}

pub fn run(args: &[&str]) -> Result<()> {
    let socket = socket_path();
    match args {
        ["serve"] => serve(&socket)?,
        ["list"] => println!("{}", serde_json::to_string(&ask(&socket, &Request::List)?.0.terminals)?),
        ["attach", id] => {
            if let Some(code) = attach(&socket, id)? {
                std::process::exit(code);
            }
        }
        ["kill", id] => {
            ask(&socket, &Request::Kill { id: (*id).to_owned() })?;
        }
        _ => bail!("usage: multiplex sessions serve | list | attach <id> | kill <id>"),
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
    let (answer, _) = ask(&socket, &Request::New { cwd, command: Vec::new(), cols, rows })?;
    if let Some(code) = attach(&socket, &answer.id)? {
        std::process::exit(code);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{Duration, Instant};

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
        let id = ask(&socket, &Request::New { cwd: cwd.clone(), command: sh, cols: 80, rows: 24 }).unwrap().0.id;
        assert!(ask(&socket, &Request::New { cwd: "/no/such/folder".into(), command: vec![], cols: 80, rows: 24 }).unwrap_err().to_string().contains("not a folder"));

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
        let id = ask(&socket, &Request::New { cwd, command: vec!["/bin/sh".to_owned()], cols: 80, rows: 24 }).unwrap().0.id;
        ask(&socket, &Request::Kill { id }).unwrap();
        let started = Instant::now();
        while !ask(&socket, &Request::List).unwrap().0.terminals.is_empty() {
            assert!(started.elapsed() < Duration::from_secs(5), "the killed terminal stayed");
            std::thread::sleep(Duration::from_millis(20));
        }
    }
}
