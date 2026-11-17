//! The desktop as the phone sees and steers it: Hyprland's monitors and
//! workspaces, the window in focus, what is playing, and the actions the
//! phone may ask for.
//!
//! Everything goes through the tools the session already has: `hyprctl`
//! for Hyprland, `busctl` for media players (MPRIS) and `wpctl` for the
//! volume. Nothing listens on the network; the phone runs these commands
//! over its SSH connection, as the user.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, ErrorKind, Write};
use std::os::unix::fs::MetadataExt;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::Command;
use std::time::{Duration, Instant};

use anyhow::{anyhow, bail, Context, Result};
use multiplex_proto::desk::{DeskAction, DeskBinding, DeskMedia, DeskMonitor, DeskSlot, DeskState, DeskVolume, DeskWindow, SLOTS};
use serde_json::Value;

const SINK: &str = "@DEFAULT_AUDIO_SINK@";
const MPRIS: &str = "org.mpris.MediaPlayer2.";
const MPRIS_PATH: &str = "/org/mpris/MediaPlayer2";
const MPRIS_PLAYER: &str = "org.mpris.MediaPlayer2.Player";

/// The running Hyprland session of this user.
pub struct Session {
    runtime: PathBuf,
    signature: String,
}

/// Whether this process runs with a UTF-8 locale.
pub(crate) fn utf8_locale() -> bool {
    ["LC_ALL", "LC_CTYPE", "LANG"]
        .iter()
        .find_map(|name| std::env::var(name).ok().filter(|v| !v.is_empty()))
        .is_some_and(|value| value.to_ascii_lowercase().replace('-', "").contains("utf8"))
}

fn home() -> PathBuf {
    PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
}

fn dir_from_env(var: &str, fallback: &str) -> PathBuf {
    std::env::var_os(var).filter(|v| !v.is_empty()).map(PathBuf::from).unwrap_or_else(|| home().join(fallback))
}

impl Session {
    /// Finds the session. Over SSH nothing in the environment points at
    /// it, so the newest Hyprland socket of this user is taken.
    pub fn find() -> Result<Self> {
        let runtime = match std::env::var_os("XDG_RUNTIME_DIR").filter(|v| !v.is_empty()) {
            Some(dir) => PathBuf::from(dir),
            None => PathBuf::from(format!("/run/user/{}", std::fs::metadata("/proc/self").context("could not tell which user this is")?.uid())),
        };
        let hypr = runtime.join("hypr");
        if let Some(signature) = std::env::var("HYPRLAND_INSTANCE_SIGNATURE").ok().filter(|s| hypr.join(s).join(".socket.sock").exists()) {
            return Ok(Self { runtime, signature });
        }
        let mut newest: Option<(std::time::SystemTime, String)> = None;
        for entry in std::fs::read_dir(&hypr).map_err(|_| anyhow!("Hyprland is not running for this user"))?.flatten() {
            let socket = entry.path().join(".socket.sock");
            let Ok(changed) = std::fs::metadata(&socket).and_then(|m| m.modified()) else { continue };
            let name = entry.file_name().to_string_lossy().into_owned();
            if newest.as_ref().is_none_or(|(at, _)| changed > *at) {
                newest = Some((changed, name));
            }
        }
        let (_, signature) = newest.ok_or_else(|| anyhow!("Hyprland is not running for this user"))?;
        Ok(Self { runtime, signature })
    }

    /// The socket Wayland programs of this session talk to.
    pub fn wayland_socket(&self) -> PathBuf {
        // Hyprland writes its process id and its socket's name into a lock file.
        let lock = std::fs::read_to_string(self.runtime.join("hypr").join(&self.signature).join("hyprland.lock")).unwrap_or_default();
        let name = lock.lines().nth(1).map(str::trim).filter(|n| !n.is_empty() && !n.contains('/')).unwrap_or("wayland-1");
        self.runtime.join(name)
    }

    pub fn runtime_dir(&self) -> &std::path::Path {
        &self.runtime
    }

    /// A command that can reach the session: Hyprland, the session bus
    /// and the sound server, with Omarchy's own commands on the path.
    pub(crate) fn command(&self, program: &str) -> Command {
        let mut command = Command::new(program);
        command.env("XDG_RUNTIME_DIR", &self.runtime).env("HYPRLAND_INSTANCE_SIGNATURE", &self.signature);
        if std::env::var_os("WAYLAND_DISPLAY").is_none() {
            // By name, not by path: Omarchy's shell finds itself by the name.
            if let Some(name) = self.wayland_socket().file_name() {
                command.env("WAYLAND_DISPLAY", name);
            }
        }
        // Over SSH there may be no locale at all, and tools then refuse
        // anything that is not ASCII (a name, a "·", an emoji).
        if !utf8_locale() {
            command.env("LC_ALL", "C.UTF-8");
        }
        if std::env::var_os("DBUS_SESSION_BUS_ADDRESS").is_none() {
            command.env("DBUS_SESSION_BUS_ADDRESS", format!("unix:path={}", self.runtime.join("bus").display()));
        }
        let omarchy = [PathBuf::from("/usr/share/omarchy"), home().join(".local/share/omarchy")].into_iter().find(|p| p.join("bin").is_dir());
        if let Some(omarchy) = omarchy {
            let path = std::env::var("PATH").unwrap_or_else(|_| "/usr/local/bin:/usr/bin".to_owned());
            command.env("PATH", format!("{path}:{}", omarchy.join("bin").display()));
            if std::env::var_os("OMARCHY_PATH").is_none() {
                command.env("OMARCHY_PATH", &omarchy);
            }
        }
        command
    }

    /// Runs a tool and returns what it printed; `None` when it is missing
    /// or failed.
    fn output(&self, program: &str, args: &[&str]) -> Option<String> {
        let out = self.command(program).args(args).output().ok()?;
        out.status.success().then(|| String::from_utf8_lossy(&out.stdout).into_owned())
    }

    fn json(&self, what: &str) -> Result<Value> {
        let text = self.output("hyprctl", &["-j", what]).ok_or_else(|| anyhow!("hyprctl could not be asked for {what}"))?;
        serde_json::from_str(&text).with_context(|| format!("hyprctl's answer for {what} was not understood"))
    }

    /// Hands Hyprland something to do. `words` is one Lua expression (the
    /// form Hyprland takes with a Lua configuration), or a dispatcher and
    /// its argument (the older form).
    fn dispatch(&self, words: &[&str]) -> Result<()> {
        let out = self.command("hyprctl").arg("dispatch").args(words).output().context("hyprctl could not be run")?;
        let said = String::from_utf8_lossy(&out.stdout).trim().to_owned();
        if out.status.success() && said == "ok" {
            Ok(())
        } else {
            bail!("{}", if said.is_empty() { String::from_utf8_lossy(&out.stderr).trim().to_owned() } else { said })
        }
    }

    /// Tries the Lua form, then the older one.
    pub(crate) fn dispatch_either(&self, lua: &str, older: (&str, &str)) -> Result<()> {
        let first = match self.dispatch(&[lua]) {
            Ok(()) => return Ok(()),
            Err(err) => err,
        };
        let (dispatcher, arg) = older;
        let words: Vec<&str> = if arg.is_empty() { vec![dispatcher] } else { vec![dispatcher, arg] };
        self.dispatch(&words).map_err(|_| first)
    }

    /// The whole state, as the phone shows it.
    pub fn state(&self) -> Result<DeskState> {
        Ok(DeskState { monitors: self.monitors()?, window: self.window(), media: self.media(), volume: self.volume(), dnd: self.dnd() })
    }

    fn monitors(&self) -> Result<Vec<DeskMonitor>> {
        let blocks = std::fs::read_to_string(dir_from_env("XDG_STATE_HOME", ".local/state").join("omarchy/monitor-workspaces")).unwrap_or_default();
        Ok(build_monitors(&self.json("monitors")?, &self.json("workspaces")?, &read_blocks(&blocks)))
    }

    fn window(&self) -> Option<DeskWindow> {
        build_window(&self.json("activewindow").ok()?)
    }

    /// Media players on the session bus.
    fn players(&self) -> Vec<String> {
        let list = self.output("busctl", &["--user", "list", "--no-legend", "--no-pager"]).unwrap_or_default();
        list.lines().filter_map(|line| line.split_whitespace().next()).filter(|name| name.starts_with(MPRIS)).map(str::to_owned).collect()
    }

    fn player_property(&self, player: &str, property: &str) -> Option<Value> {
        let text = self.output("busctl", &["--user", "--json=short", "get-property", player, MPRIS_PATH, MPRIS_PLAYER, property])?;
        serde_json::from_str::<Value>(&text).ok().map(|v| v["data"].clone())
    }

    /// What is playing; failing that, what is paused.
    fn media(&self) -> Option<DeskMedia> {
        let mut paused = None;
        for player in self.players() {
            let Some(status) = self.player_property(&player, "PlaybackStatus").and_then(|v| v.as_str().map(str::to_owned)) else { continue };
            let media = build_media(&player, &status, &self.player_property(&player, "Metadata").unwrap_or(Value::Null));
            match status.as_str() {
                "Playing" => return Some(media),
                "Paused" if paused.is_none() => paused = Some(media),
                _ => {}
            }
        }
        paused
    }

    /// Whether notifications are silenced. Omarchy's shell is asked; with
    /// another notification daemon it is simply not known.
    fn dnd(&self) -> Option<bool> {
        match self.output("omarchy-shell", &["notifications", "isDnd"])?.trim() {
            "on" => Some(true),
            "off" => Some(false),
            _ => None,
        }
    }

    fn set_dnd(&self, on: bool) -> Result<()> {
        let word = if on { "on" } else { "off" };
        if self.output("omarchy-shell", &["notifications", "setDnd", word]).is_some() {
            // The bar's bell follows.
            let _ = self.output("omarchy-shell", &["-q", "omarchy.indicators", "refresh"]);
            return Ok(());
        }
        // Other notification daemons, where they are what runs.
        if self.output("makoctl", &["mode", if on { "-a" } else { "-r" }, "do-not-disturb"]).is_some() || self.output("dunstctl", &["set-paused", if on { "true" } else { "false" }]).is_some() {
            return Ok(());
        }
        bail!("notifications could not be silenced here")
    }

    /// Pauses every player that is playing; the answer is which ones.
    pub fn pause_playing(&self) -> Vec<String> {
        self.players()
            .into_iter()
            .filter(|p| self.player_property(p, "PlaybackStatus").is_some_and(|v| v == "Playing"))
            .filter(|p| self.output("busctl", &["--user", "call", p, MPRIS_PATH, MPRIS_PLAYER, "Pause"]).is_some())
            .collect()
    }

    /// Carries on with players that were paused for a call, unless the
    /// user did something with them meanwhile (then they are left alone).
    pub fn resume(&self, players: &[String]) {
        let here = self.players();
        for player in players.iter().filter(|p| here.contains(p)) {
            if self.player_property(player, "PlaybackStatus").is_some_and(|v| v == "Paused") {
                let _ = self.output("busctl", &["--user", "call", player, MPRIS_PATH, MPRIS_PLAYER, "Play"]);
            }
        }
    }

    fn volume(&self) -> Option<DeskVolume> {
        parse_volume(&self.output("wpctl", &["get-volume", SINK])?)
    }

    /// The player a media key would mean: the one playing, else the first.
    fn current_player(&self) -> Option<String> {
        let players = self.players();
        let playing = players.iter().find(|p| self.player_property(p, "PlaybackStatus").is_some_and(|v| v == "Playing")).cloned();
        playing.or_else(|| players.into_iter().next())
    }

    fn player_call(&self, method: &str) -> Result<()> {
        let player = self.current_player().ok_or_else(|| anyhow!("no media player is open"))?;
        self.output("busctl", &["--user", "call", &player, MPRIS_PATH, MPRIS_PLAYER, method]).map(|_| ()).ok_or_else(|| anyhow!("the player did not take that"))
    }

    fn wpctl(&self, args: &[&str]) -> Result<()> {
        self.output("wpctl", args).map(|_| ()).ok_or_else(|| anyhow!("the volume could not be changed"))
    }

    /// Omarchy's list of bindings, which also knows how to run each one.
    /// `refresh` has Omarchy rebuild it first (after a configuration
    /// change); without it the last list is read, which is fast.
    fn records(&self, refresh: bool) -> Vec<Record> {
        let newest = || {
            let dir = dir_from_env("XDG_CACHE_HOME", ".cache").join("omarchy");
            let mut files: Vec<(std::time::SystemTime, PathBuf)> = std::fs::read_dir(dir)
                .ok()?
                .flatten()
                .filter(|e| {
                    let name = e.file_name();
                    let name = name.to_string_lossy();
                    name.starts_with("keybindings-") && name.ends_with(".records")
                })
                .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
                .collect();
            files.sort();
            std::fs::read_to_string(files.pop()?.1).ok()
        };
        let mut text = if refresh { None } else { newest() };
        if text.is_none() {
            // Printing the list makes Omarchy write it.
            let _ = self.output("omarchy-menu-keybindings", &["--print"]);
            text = newest();
        }
        parse_records(&text.unwrap_or_default())
    }

    /// Every binding with a description, for the phone's list.
    pub fn bindings(&self) -> Vec<DeskBinding> {
        self.records(true).iter().map(Record::listed).collect()
    }

    fn run_record(&self, record: &Record) -> Result<()> {
        match record.how {
            How::Lua => self.dispatch(&[&record.arg]),
            How::Command => self.dispatch_either(&format!("hl.dsp.exec_cmd({})", lua_string(&record.arg)), ("exec", &record.arg)),
            How::Unknown => bail!("\"{}\" is not something the phone can run", record.title),
        }
    }

    /// Runs the binding with these keys, if the computer has one.
    fn run_keys(&self, keys: &str) -> Result<bool> {
        match self.records(false).iter().find(|r| r.has_keys(keys)) {
            Some(record) => self.run_record(record).map(|()| true),
            None => Ok(false),
        }
    }

    /// The id of a workspace by its number on a monitor (the one in focus
    /// when not named).
    fn workspace_id(&self, slot: u8, monitor: Option<&str>) -> Result<i64> {
        let monitors = self.monitors()?;
        let monitor = match monitor {
            Some(name) => monitors.iter().find(|m| m.name == name),
            None => monitors.iter().find(|m| m.focused),
        };
        let monitor = monitor.ok_or_else(|| anyhow!("that monitor is not connected"))?;
        monitor.slots.iter().find(|s| s.slot == slot).map(|s| s.id).ok_or_else(|| anyhow!("that workspace does not exist"))
    }

    /// Does what the phone asked.
    pub fn act(&self, action: &DeskAction) -> Result<()> {
        match action {
            DeskAction::Workspace { slot, monitor } => {
                // Omarchy's own way first: it knows each monitor's workspaces.
                let named = monitor.as_deref().map(|m| format!(", {}", lua_string(m))).unwrap_or_default();
                if self.dispatch(&[&format!("o.workspaces.focus({slot}{named})")]).is_ok() {
                    return Ok(());
                }
                let id = self.workspace_id(*slot, monitor.as_deref())?.to_string();
                if let Some(name) = monitor {
                    self.act(&DeskAction::FocusMonitor { name: name.clone() })?;
                }
                self.dispatch_either(&format!("hl.dsp.focus({{ workspace = \"{id}\" }})"), ("workspace", &id))
            }
            DeskAction::MoveWindow { slot } => {
                if self.dispatch(&[&format!("o.workspaces.move_window({slot})")]).is_ok() {
                    return Ok(());
                }
                let id = self.workspace_id(*slot, None)?.to_string();
                self.dispatch_either(&format!("hl.dsp.window.move({{ workspace = \"{id}\" }})"), ("movetoworkspace", &id))
            }
            DeskAction::FocusMonitor { name } => self.dispatch_either(&format!("hl.dsp.focus({{ monitor = {} }})", lua_string(name)), ("focusmonitor", name)),
            DeskAction::Focus(dir) => self.dispatch_either(&format!("hl.dsp.focus({{ direction = \"{}\" }})", dir.letter()), ("movefocus", dir.letter())),
            DeskAction::Swap(dir) => self.dispatch_either(&format!("hl.dsp.window.swap({{ direction = \"{}\" }})", dir.letter()), ("swapwindow", dir.letter())),
            DeskAction::Close => self.dispatch_either("hl.dsp.window.close()", ("killactive", "")),
            DeskAction::Fullscreen => self.dispatch_either("hl.dsp.window.fullscreen({ mode = \"fullscreen\" })", ("fullscreen", "0")),
            DeskAction::Float => self.dispatch_either("hl.dsp.window.float({ action = \"toggle\" })", ("togglefloating", "")),
            DeskAction::Split => self.dispatch_either("hl.dsp.layout(\"togglesplit\")", ("layoutmsg", "togglesplit")),
            // Media keys do what the keyboard's do; without such a binding,
            // the player and the sound server are asked directly.
            DeskAction::PlayPause => self.media_key("XF86AudioPlay", || self.player_call("PlayPause")),
            DeskAction::Next => self.media_key("XF86AudioNext", || self.player_call("Next")),
            DeskAction::Previous => self.media_key("XF86AudioPrev", || self.player_call("Previous")),
            DeskAction::VolumeUp => self.media_key("XF86AudioRaiseVolume", || self.wpctl(&["set-volume", "-l", "1.0", SINK, "5%+"])),
            DeskAction::VolumeDown => self.media_key("XF86AudioLowerVolume", || self.wpctl(&["set-volume", SINK, "5%-"])),
            DeskAction::Mute => self.media_key("XF86AudioMute", || self.wpctl(&["set-mute", SINK, "toggle"])),
            DeskAction::Dnd { on } => self.set_dnd(*on),
            DeskAction::Bind { keys } => match self.run_keys(keys)? {
                true => Ok(()),
                false => bail!("the computer has no binding for {keys}"),
            },
        }
    }

    fn media_key(&self, key: &str, otherwise: impl FnOnce() -> Result<()>) -> Result<()> {
        match self.run_keys(key) {
            Ok(true) => Ok(()),
            _ => otherwise(),
        }
    }

    /// Prints the state now, and again whenever it changes, one line of
    /// JSON each, until the phone hangs up or Hyprland goes away.
    pub fn watch(&self) -> Result<()> {
        let socket = self.runtime.join("hypr").join(&self.signature).join(".socket2.sock");
        let stream = UnixStream::connect(&socket).context("could not listen to Hyprland's events")?;
        let mut reader = BufReader::new(stream);
        let mut out = std::io::stdout().lock();

        // Media and volume have no events here; they are looked at now and then.
        const SLOW: Duration = Duration::from_secs(2);
        // A window's title can change many times a second (a terminal's does).
        const TITLES: Duration = Duration::from_secs(1);
        // An empty line now and then, so a phone that hung up is noticed.
        const ALIVE: Duration = Duration::from_secs(10);
        // Events come in bursts; the state is read once they settle.
        const SETTLE: Duration = Duration::from_millis(40);

        let mut last: Option<DeskState> = None;
        let mut slow = (self.media(), self.volume(), self.dnd());
        let mut slow_at = Instant::now();
        let mut said_at = Instant::now();
        let mut titles_at = Instant::now();
        let mut changed = true;
        let mut title_changed = false;
        let mut line = String::new();
        loop {
            if slow_at.elapsed() >= SLOW {
                let now = (self.media(), self.volume(), self.dnd());
                changed |= now != slow;
                slow = now;
                slow_at = Instant::now();
            }
            if title_changed && titles_at.elapsed() >= TITLES {
                changed = true;
            }
            reader.get_ref().set_read_timeout(Some(if changed { SETTLE } else { Duration::from_millis(500) }))?;
            match reader.read_line(&mut line) {
                Ok(0) => return Ok(()),
                Ok(_) => {
                    match line.split(">>").next().unwrap_or_default() {
                        "windowtitle" | "windowtitlev2" => title_changed = true,
                        _ => changed = true,
                    }
                    line.clear();
                    continue;
                }
                // Quiet for a moment (a partly read line stays in `line`).
                Err(err) if matches!(err.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {}
                Err(err) => return Err(err).context("Hyprland's events stopped"),
            }
            if changed {
                changed = false;
                title_changed = false;
                titles_at = Instant::now();
                let state = DeskState { monitors: self.monitors()?, window: self.window(), media: slow.0.clone(), volume: slow.1.clone(), dnd: slow.2 };
                if last.as_ref() != Some(&state) {
                    writeln!(out, "{}", serde_json::to_string(&state)?)?;
                    out.flush()?;
                    said_at = Instant::now();
                    last = Some(state);
                }
            } else if said_at.elapsed() >= ALIVE {
                writeln!(out)?;
                out.flush()?;
                said_at = Instant::now();
            }
        }
    }
}

/// `multiplex desk …`.
pub fn run(args: &[&str]) -> Result<()> {
    match args {
        ["state"] => println!("{}", serde_json::to_string(&Session::find()?.state()?)?),
        ["binds"] => println!("{}", serde_json::to_string(&Session::find()?.bindings())?),
        ["watch"] => match Session::find()?.watch() {
            // The phone hung up: that is how a watch ends.
            Err(err) if err.downcast_ref::<std::io::Error>().is_some_and(|e| e.kind() == ErrorKind::BrokenPipe) => {}
            other => other?,
        },
        ["do", words @ ..] => {
            let action = DeskAction::parse(words).map_err(|err| anyhow!("{err}"))?;
            let session = Session::find()?;
            session.act(&action)?;
            // The answer is the state after it, once Hyprland has settled.
            std::thread::sleep(Duration::from_millis(60));
            println!("{}", serde_json::to_string(&session.state()?)?);
        }
        _ => bail!("use: multiplex desk state | watch | binds | do <action>"),
    }
    Ok(())
}

/// A Lua string literal.
pub(crate) fn lua_string(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 2);
    out.push('"');
    for c in text.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\0' => out.push_str("\\0"),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// Omarchy's file of which block of ten workspaces each monitor has:
/// `block<TAB>connector<TAB>description` per line.
fn read_blocks(text: &str) -> HashMap<String, i64> {
    text.lines()
        .filter_map(|line| {
            let mut fields = line.split('\t');
            let block = fields.next()?.trim().parse().ok()?;
            let connector = fields.next()?.trim();
            (!connector.is_empty()).then(|| (connector.to_owned(), block))
        })
        .collect()
}

/// Monitors left to right, each with its ten workspaces.
fn build_monitors(monitors: &Value, workspaces: &Value, blocks: &HashMap<String, i64>) -> Vec<DeskMonitor> {
    let windows: HashMap<i64, u32> = workspaces
        .as_array()
        .map(|list| list.iter().filter_map(|w| Some((w["id"].as_i64()?, w["windows"].as_u64().unwrap_or(0) as u32))).collect())
        .unwrap_or_default();
    let mut list: Vec<&Value> = monitors.as_array().map(|l| l.iter().filter(|m| m["disabled"].as_bool() != Some(true)).collect()).unwrap_or_default();
    list.sort_by_key(|m| (m["x"].as_i64().unwrap_or(0), m["y"].as_i64().unwrap_or(0)));
    list.into_iter()
        .filter_map(|m| {
            let name = m["name"].as_str()?.to_owned();
            let active = m["activeWorkspace"]["id"].as_i64().unwrap_or(0);
            // Until Omarchy has written its file, a monitor's block is the
            // one its current workspace is in.
            let block = blocks.get(&name).copied().unwrap_or(if active > 0 { (active - 1) / i64::from(SLOTS) } else { 0 });
            let slots = (1..=SLOTS)
                .map(|slot| {
                    let id = block * i64::from(SLOTS) + i64::from(slot);
                    DeskSlot { slot, id, windows: windows.get(&id).copied().unwrap_or(0), active: id == active }
                })
                .collect();
            Some(DeskMonitor { name, focused: m["focused"].as_bool().unwrap_or(false), slots })
        })
        .collect()
}

fn build_window(window: &Value) -> Option<DeskWindow> {
    // With nothing in focus Hyprland answers with an empty object.
    window["address"].as_str()?;
    Some(DeskWindow {
        title: window["title"].as_str().unwrap_or_default().to_owned(),
        class: window["class"].as_str().unwrap_or_default().to_owned(),
        floating: window["floating"].as_bool().unwrap_or(false),
        fullscreen: window["fullscreen"].as_i64().unwrap_or(0) != 0 || window["fullscreen"].as_bool() == Some(true),
    })
}

/// A player from its bus name, state and metadata (`busctl --json`).
fn build_media(bus_name: &str, status: &str, metadata: &Value) -> DeskMedia {
    let text = |key: &str| -> String {
        match &metadata[key]["data"] {
            Value::String(s) => s.clone(),
            Value::Array(items) => items.iter().filter_map(Value::as_str).filter(|s| !s.is_empty()).collect::<Vec<_>>().join(", "),
            _ => String::new(),
        }
    };
    // "org.mpris.MediaPlayer2.firefox.instance_1_23" is Firefox.
    let short = bus_name.trim_start_matches(MPRIS).split('.').next().unwrap_or_default();
    let mut player = short.to_owned();
    if let Some(first) = player.get_mut(..1) {
        first.make_ascii_uppercase();
    }
    DeskMedia { player, playing: status == "Playing", title: text("xesam:title"), artist: text("xesam:artist") }
}

/// `wpctl get-volume`: "Volume: 0.35" or "Volume: 0.35 [MUTED]".
fn parse_volume(text: &str) -> Option<DeskVolume> {
    let level: f64 = text.split_whitespace().nth(1)?.parse().ok()?;
    Some(DeskVolume { percent: (level * 100.0).round().clamp(0.0, 255.0) as u8, muted: text.contains("MUTED") })
}

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
enum How {
    /// A Lua expression for `hyprctl dispatch`.
    Lua,
    /// A command line to start.
    Command,
    /// Listed only.
    Unknown,
}

/// One line of Omarchy's list: what the keys are called, what they do,
/// and how to do it without the keyboard.
#[derive(Debug, PartialEq, Eq)]
struct Record {
    chords: Vec<String>,
    title: String,
    how: How,
    arg: String,
}

fn tidy(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

impl Record {
    fn keys(&self) -> String {
        self.chords.join(" / ")
    }

    fn listed(&self) -> DeskBinding {
        DeskBinding { keys: self.keys(), title: self.title.clone(), run: self.how != How::Unknown }
    }

    /// `keys` is one of this binding's chords, or all of them as listed.
    fn has_keys(&self, keys: &str) -> bool {
        let keys = tidy(keys);
        self.keys().eq_ignore_ascii_case(&keys) || self.chords.iter().any(|c| c.eq_ignore_ascii_case(&keys))
    }
}

/// Reads Omarchy's list: `KEYS → Title<TAB>how<TAB>argument` per line.
fn parse_records(text: &str) -> Vec<Record> {
    text.lines()
        .filter_map(|line| {
            let mut fields = line.splitn(3, '\t');
            let (keys, title) = fields.next()?.split_once('→')?;
            let how = fields.next().unwrap_or_default().trim();
            let arg = fields.next().unwrap_or_default().trim().to_owned();
            let chords: Vec<String> = keys.split(" / ").map(tidy).filter(|c| !c.is_empty()).collect();
            let title = tidy(title);
            if chords.is_empty() || title.is_empty() {
                return None;
            }
            let how = match how {
                "lua" if !arg.is_empty() => How::Lua,
                "exec" if !arg.is_empty() => How::Command,
                _ => How::Unknown,
            };
            Some(Record { chords, title, how, arg })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn monitors_get_their_block_of_ten_left_to_right() {
        let monitors = json!([
            {"name": "DP-3", "x": 1920, "y": 0, "focused": true, "activeWorkspace": {"id": 31}},
            {"name": "HDMI-A-1", "x": 0, "y": 0, "focused": false, "activeWorkspace": {"id": 2}},
            {"name": "OFF-1", "x": 9000, "y": 0, "disabled": true, "activeWorkspace": {"id": 99}},
        ]);
        let workspaces = json!([{"id": 31, "windows": 2}, {"id": 2, "windows": 1}, {"id": 35, "windows": 4}, {"id": -98, "windows": 1}]);
        let blocks = read_blocks("0\tHDMI-A-1\tSome Monitor\n3\tDP-3\tOther #2\n4\t\tgliff-1\nnonsense\n");
        let list = build_monitors(&monitors, &workspaces, &blocks);
        assert_eq!(list.iter().map(|m| m.name.as_str()).collect::<Vec<_>>(), ["HDMI-A-1", "DP-3"]);
        let right = &list[1];
        assert!(right.focused);
        assert_eq!(right.slots.len(), 10);
        assert_eq!(right.slots[0], DeskSlot { slot: 1, id: 31, windows: 2, active: true });
        assert_eq!(right.slots[4], DeskSlot { slot: 5, id: 35, windows: 4, active: false });
        assert_eq!(list[0].slots[1], DeskSlot { slot: 2, id: 2, windows: 1, active: true });
    }

    #[test]
    fn without_omarchys_file_the_block_comes_from_the_current_workspace() {
        let monitors = json!([{"name": "eDP-1", "x": 0, "y": 0, "focused": true, "activeWorkspace": {"id": 14}}]);
        let list = build_monitors(&monitors, &json!([]), &HashMap::new());
        assert_eq!(list[0].slots.iter().map(|s| s.id).collect::<Vec<_>>(), (11..=20).collect::<Vec<i64>>());
        assert_eq!(list[0].slots.iter().find(|s| s.active).map(|s| s.slot), Some(4));
    }

    #[test]
    fn the_window_in_focus_or_none() {
        assert_eq!(build_window(&json!({})), None);
        let window = build_window(&json!({"address": "0x1", "title": "notes", "class": "foot", "floating": true, "fullscreen": 2})).unwrap();
        assert_eq!(window, DeskWindow { title: "notes".into(), class: "foot".into(), floating: true, fullscreen: true });
    }

    #[test]
    fn media_and_volume_read_what_the_tools_print() {
        let metadata = json!({"xesam:title": {"type": "s", "data": "Song"}, "xesam:artist": {"type": "as", "data": ["A", "", "B"]}});
        let media = build_media("org.mpris.MediaPlayer2.chromium.instance123", "Paused", &metadata);
        assert_eq!(media, DeskMedia { player: "Chromium".into(), playing: false, title: "Song".into(), artist: "A, B".into() });
        assert_eq!(build_media("org.mpris.MediaPlayer2.spotify", "Playing", &Value::Null).playing, true);
        assert_eq!(parse_volume("Volume: 0.35\n"), Some(DeskVolume { percent: 35, muted: false }));
        assert_eq!(parse_volume("Volume: 1.00 [MUTED]\n"), Some(DeskVolume { percent: 100, muted: true }));
        assert_eq!(parse_volume("nothing"), None);
    }

    #[test]
    fn omarchys_binding_list_is_read() {
        let text = "SUPER + K                           → Keybindings\texec\tomarchy-menu-keybindings\n\
                    SUPER + W / SUPER + Q               → Close window\tlua\thl.dsp.window.close()\n\
                    SUPER + C                           → Universal copy\t\t\n\
                    SUPER + COMMA                       → Dismiss\t invoke\t or focus,lua,x\n\
                    a line that is something else\n";
        let records = parse_records(text);
        assert_eq!(records.len(), 4);
        assert_eq!(records[0], Record { chords: vec!["SUPER + K".into()], title: "Keybindings".into(), how: How::Command, arg: "omarchy-menu-keybindings".into() });
        assert_eq!(records[1].listed(), DeskBinding { keys: "SUPER + W / SUPER + Q".into(), title: "Close window".into(), run: true });
        assert!(records[1].has_keys("super + q") && records[1].has_keys("SUPER + W / SUPER + Q") && !records[1].has_keys("SUPER + E"));
        assert!(!records[2].listed().run && !records[3].listed().run);
    }

    #[test]
    fn lua_strings_cannot_be_broken_out_of() {
        assert_eq!(lua_string("DP-1"), "\"DP-1\"");
        assert_eq!(lua_string("a\"b\\c\nd"), "\"a\\\"b\\\\c\\nd\"");
    }
}
