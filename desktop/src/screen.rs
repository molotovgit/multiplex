//! `multiplex screen`: the phone's screen in a window on this computer.
//!
//! The phone captures its screen, encodes it as H.264 and writes the
//! stream to this command over SSH. This command hands it to mpv, which
//! Hyprland starts as a small floating window. Closing the window ends
//! the capture on the phone; stopping on the phone closes the window.

use std::io::Write;
use std::path::Path;
use std::sync::mpsc;
use std::time::Duration;

use anyhow::{anyhow, bail, Context, Result};

use crate::desk::{lua_string, Session};
use crate::feed::pump;
use crate::h264::SizeWatch;
use crate::share::runtime_dir;

/// The window's longer side when it opens, in pixels.
const LONG_SIDE: u32 = 900;


/// One argument for a POSIX shell.
fn quoted(arg: &str) -> String {
    format!("'{}'", arg.replace('\'', r"'\''"))
}

/// The player's command line: no buffering anywhere, since this is a
/// live screen and not a film.
///
/// The player must also never wait for the compositor before taking the
/// next picture. With mpv's usual waiting, a window on a workspace that
/// is not shown takes the stream erratically (a 6 s feed took up to 21 s
/// here), so it would show the past when looked at again. With the
/// three "do not wait" options the same feed takes 6.1 s every time.
fn player_command(stream: &Path, title: &str, control: Option<&Path>) -> String {
    let mut words = vec![
        "mpv".to_owned(),
        "--no-config".to_owned(),
        "--no-terminal".to_owned(),
        "--really-quiet".to_owned(),
        "--no-audio".to_owned(),
        "--no-osc".to_owned(),
        "--no-input-default-bindings".to_owned(),
        "--profile=low-latency".to_owned(),
        "--untimed".to_owned(),
        "--no-cache".to_owned(),
        "--gpu-api=opengl,vulkan".to_owned(),
        "--opengl-swapinterval=0".to_owned(),
        "--vulkan-swap-mode=mailbox".to_owned(),
        "--wayland-internal-vsync=no".to_owned(),
        "--demuxer-lavf-format=h264".to_owned(),
        "--demuxer-lavf-o=fflags=+nobuffer".to_owned(),
        "--keepaspect-window".to_owned(),
        // The window opens with the first picture, in its shape, about
        // the size of a phone.
        format!("--autofit-larger={LONG_SIDE}x{LONG_SIDE}"),
        "--wayland-app-id=multiplex-screen".to_owned(),
        format!("--title={}", quoted(title)),
    ];
    // For tests: a way to ask the player what it is showing.
    if let Some(socket) = control {
        words.push(format!("--input-ipc-server={}", quoted(&socket.to_string_lossy())));
    }
    words.push(quoted(&stream.to_string_lossy()));
    words.join(" ")
}

/// The Lua that has Hyprland start the player: floating, in the middle;
/// or, for trying it without disturbing anyone, on a workspace that is
/// not shown.
fn launch_expression(command: &str, hidden: bool) -> String {
    let rules = if hidden { r#"{ float = true, center = true, workspace = "special:multiplex silent" }"# } else { "{ float = true, center = true }" };
    format!("hl.dsp.exec_cmd({}, {rules})", lua_string(command))
}

fn window_title(phone: Option<&str>) -> String {
    phone.map_or_else(|| "Phone screen".to_owned(), |name| format!("{name} screen"))
}

/// The window's size for a picture of this size: the same shape, with
/// its longer side as long as `long_side`.
fn window_size(picture: (u32, u32), long_side: u32) -> (u32, u32) {
    let (width, height) = picture;
    let longest = width.max(height).max(1);
    let scaled = |side: u32| ((u64::from(side) * u64::from(long_side) + u64::from(longest) / 2) / u64::from(longest)).max(1) as u32;
    (scaled(width), scaled(height))
}

/// Whether this file is the pipe of a `multiplex screen` that is gone
/// (one that was killed could not remove its own).
fn left_behind(name: &str, running: impl Fn(u32) -> bool) -> bool {
    name.strip_prefix("screen-").and_then(|rest| rest.strip_suffix(".h264")).and_then(|pid| pid.parse::<u32>().ok()).is_some_and(|pid| !running(pid))
}

/// Removes such pipes.
fn sweep(folder: &Path) {
    for entry in std::fs::read_dir(folder).into_iter().flatten().flatten() {
        if entry.file_name().to_str().is_some_and(|name| left_behind(name, |pid| Path::new("/proc").join(pid.to_string()).exists())) {
            let _ = std::fs::remove_file(entry.path());
        }
    }
}

/// The player showing this stream: the one process with the pipe in its
/// command line.
fn player_of(pipe: &Path) -> Option<u32> {
    let wanted = pipe.to_string_lossy().into_owned();
    std::fs::read_dir("/proc").ok()?.flatten().find_map(|entry| {
        let pid: u32 = entry.file_name().to_str()?.parse().ok()?;
        (pid != std::process::id() && String::from_utf8_lossy(&std::fs::read(entry.path().join("cmdline")).ok()?).split('\0').any(|word| word == wanted)).then_some(pid)
    })
}

/// The phone was turned: the window takes the picture's new shape and
/// keeps its size (as long on its longer side as it was, so a window the
/// user made bigger stays bigger). A window that is tiled or fills the
/// screen is left to Hyprland.
fn reshape(session: &Session, pipe: &Path, picture: (u32, u32)) -> Result<()> {
    let pid = player_of(pipe).ok_or_else(|| anyhow!("the player was not found"))?;
    let windows = session.json("clients")?;
    let window = windows.as_array().and_then(|all| all.iter().find(|w| w["pid"].as_u64() == Some(u64::from(pid)))).ok_or_else(|| anyhow!("the window was not found"))?;
    if window["floating"].as_bool() != Some(true) || window["fullscreen"].as_u64().unwrap_or(0) != 0 {
        return Ok(());
    }
    let side = |i: usize| window["size"][i].as_u64().and_then(|v| u32::try_from(v).ok()).unwrap_or(0);
    let long_side = side(0).max(side(1));
    let (width, height) = window_size(picture, if long_side == 0 { LONG_SIDE } else { long_side });
    if (width, height) == (side(0), side(1)) {
        return Ok(());
    }
    session.dispatch_either(&format!(r#"hl.dsp.window.resize({{ x = {width}, y = {height}, relative = false, window = "pid:{pid}" }})"#), ("resizewindowpixel", &format!("exact {width} {height},pid:{pid}")))
}

/// `multiplex screen [--hidden] [<title>]`.
pub fn run(args: &[&str]) -> Result<()> {
    let (hidden, title) = match args {
        ["--hidden", rest @ ..] => (true, rest),
        rest => (false, rest),
    };
    // The phone's name goes in the title. A phone paired before names
    // were kept says none; it is then the only one paired.
    let phone = match title {
        [] => crate::share::the_phone("").ok(),
        [name] => multiplex_proto::clean_device_name(name),
        _ => bail!("use: multiplex screen [--hidden] [<phone>]"),
    };
    let title = window_title(phone.as_deref());
    // A marker file does the same as --hidden, for tests from the phone.
    let hidden = hidden || runtime_dir().join("screen-hidden").exists();
    let session = Session::find()?;
    if !crate::system::on_path("mpv") {
        bail!("mpv is needed to show the phone's screen: sudo pacman -S mpv");
    }

    // The stream goes through a named pipe: the player is started by
    // Hyprland (so it is a window of the session), not by this command.
    sweep(&runtime_dir());
    let pipe = runtime_dir().join(format!("screen-{}.h264", std::process::id()));
    let _ = std::fs::remove_file(&pipe);
    let made = std::process::Command::new("mkfifo").arg("-m").arg("600").arg(&pipe).status().is_ok_and(|s| s.success());
    if !made {
        bail!("could not make a pipe for the picture");
    }
    let cleanup = || {
        let _ = std::fs::remove_file(&pipe);
        let _ = std::fs::remove_file(runtime_dir().join("screen-test.sock"));
    };
    // A hidden window is a test: the test may ask the player what it shows.
    let control = hidden.then(|| runtime_dir().join("screen-test.sock"));
    let command = player_command(&pipe, &title, control.as_deref());
    if let Err(err) = session.dispatch_either(&launch_expression(&command, hidden), ("exec", &command)) {
        cleanup();
        return Err(err).context("the window could not be opened");
    }

    // Opening the pipe waits for the player to open its end. If it never
    // does (it failed to start), give up instead of hanging.
    let (opened, wait) = mpsc::channel();
    let path = pipe.clone();
    std::thread::spawn(move || {
        let _ = opened.send(std::fs::OpenOptions::new().write(true).open(path));
    });
    let mut stream = match wait.recv_timeout(Duration::from_secs(8)) {
        Ok(Ok(stream)) => stream,
        _ => {
            cleanup();
            bail!("the player did not start");
        }
    };
    let mut watch = SizeWatch::default();
    let mut shape: Option<(u32, u32)> = None;
    let result = pump(
        |piece| {
            // The window was closed: that is how the user stops it here.
            if stream.write_all(piece).is_err() {
                return Ok(false);
            }
            // The stream says its picture's size at every full picture.
            // The first one the player sizes its window for; a new one
            // means the phone was turned.
            for size in watch.feed(piece) {
                if shape.is_some_and(|before| before != size) {
                    // If it cannot be done the picture still shows, with bars.
                    let _ = reshape(&session, &pipe, size);
                }
                shape = Some(size);
            }
            Ok(true)
        },
        "the phone stopped sending its screen",
    );
    drop(stream);
    cleanup();
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_player_is_started_for_a_live_picture_with_safe_words() {
        let command = player_command(Path::new("/run/user/1000/multiplex/screen-1.h264"), "Sam's phone screen", None);
        assert!(!command.contains("ipc"), "no control socket outside tests");
        assert!(command.starts_with("mpv --no-config "));
        for needed in ["--profile=low-latency", "--untimed", "--no-cache", "--demuxer-lavf-format=h264", "--wayland-app-id=multiplex-screen", "--opengl-swapinterval=0", "--wayland-internal-vsync=no"] {
            assert!(command.contains(needed), "{needed}");
        }
        assert!(command.contains(r"--title='Sam'\''s phone screen'"), "{command}");
        assert!(command.ends_with("'/run/user/1000/multiplex/screen-1.h264'"));
        let tested = player_command(Path::new("/x/s.h264"), "T", Some(Path::new("/x/test.sock")));
        assert!(tested.contains("--input-ipc-server='/x/test.sock' '/x/s.h264'"), "{tested}");
    }

    #[test]
    fn the_window_takes_the_pictures_shape_and_keeps_its_size() {
        // A phone upright, then turned.
        assert_eq!(window_size((736, 1600), 900), (414, 900));
        assert_eq!(window_size((1600, 736), 900), (900, 414));
        // A window the user made bigger stays that big.
        assert_eq!(window_size((1600, 736), 1400), (1400, 644));
        // Square, and nonsense, do no harm.
        assert_eq!(window_size((1000, 1000), 900), (900, 900));
        assert_eq!(window_size((0, 0), 900), (1, 1));
    }

    #[test]
    fn the_title_names_the_phone_when_it_is_known() {
        assert_eq!(window_title(Some("Sam's phone")), "Sam's phone screen");
        assert_eq!(window_title(None), "Phone screen");
    }

    #[test]
    fn only_pipes_of_commands_that_are_gone_are_swept() {
        let running = |pid: u32| pid == 500;
        assert!(left_behind("screen-499.h264", running));
        assert!(!left_behind("screen-500.h264", running), "still in use");
        for other in ["screen-hidden", "screen-test.sock", "screen-.h264", "screen-x.h264", "agent.sock", "screen-499.h264.bak"] {
            assert!(!left_behind(other, running), "{other}");
        }
    }

    #[test]
    fn the_player_is_found_by_its_pipe() {
        // No process has this in its command line.
        assert_eq!(player_of(Path::new("/nonexistent/multiplex/screen-0.h264")), None);
    }

    #[test]
    fn hyprland_is_told_where_the_window_goes() {
        assert_eq!(launch_expression("mpv x", false), r#"hl.dsp.exec_cmd("mpv x", { float = true, center = true })"#);
        assert_eq!(launch_expression("mpv x", true), r#"hl.dsp.exec_cmd("mpv x", { float = true, center = true, workspace = "special:multiplex silent" })"#);
        // A quote in the command cannot end the Lua string early.
        assert!(launch_expression("mpv --title='a\"b'", false).contains(r#"\"b"#));
    }
}
