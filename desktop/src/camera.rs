//! `multiplex camera`: the phone's camera as a camera of this computer.
//!
//! The phone films, encodes the picture as H.264 and writes it to this
//! command over SSH. Here ffmpeg decodes it, and the frames are offered
//! to other programs in one of two ways:
//!
//! - as a PipeWire camera (GStreamer's PipeWire sink provides it). No
//!   root needed. Programs that find cameras through PipeWire see it:
//!   browsers that use the camera portal, OBS.
//! - through a v4l2loopback device, when one exists. Every program that
//!   can use a webcam sees that one; the kernel module has to be
//!   installed and loaded by the owner.
//!
//! The camera is there for as long as the phone is sending.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};

use anyhow::{bail, Context, Result};

use crate::feed::pump;
use crate::h264::SizeWatch;
use crate::system::on_path;

/// How the frames reach other programs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Way {
    /// A v4l2loopback device.
    Loopback(PathBuf),
    /// A camera provided to PipeWire.
    PipeWire,
}

impl Way {
    /// The way that works here, if any.
    pub fn find() -> Option<Self> {
        if let Some(device) = loopback_device(Path::new("/sys/devices/virtual/video4linux"), Path::new("/dev")) {
            return Some(Self::Loopback(device));
        }
        let has = |element: &str| Command::new("gst-inspect-1.0").arg("--exists").arg(element).stdout(Stdio::null()).stderr(Stdio::null()).status().is_ok_and(|s| s.success());
        (on_path("gst-launch-1.0") && has("pipewiresink") && has("rawvideoparse")).then_some(Self::PipeWire)
    }

    pub fn words(&self) -> String {
        match self {
            Self::Loopback(device) => format!("through {}: every program that uses a webcam sees it", device.display()),
            Self::PipeWire => "as a PipeWire camera: browsers that use the camera portal and OBS see it (for every program, install and load v4l2loopback)".to_owned(),
        }
    }
}

/// What to install when there is no way.
pub const NEEDS: &str = "needs ffmpeg, and either GStreamer with its PipeWire plugin (sudo pacman -S gstreamer gst-plugins-base gst-plugin-pipewire) or a v4l2loopback device";

/// The first loopback device there is: a virtual video device that can
/// be written to.
fn loopback_device(virtual_devices: &Path, dev: &Path) -> Option<PathBuf> {
    let mut names: Vec<String> = std::fs::read_dir(virtual_devices).ok()?.flatten().filter_map(|e| e.file_name().into_string().ok()).filter(|n| n.starts_with("video")).collect();
    names.sort();
    names.into_iter().map(|name| dev.join(name)).find(|device| std::fs::OpenOptions::new().write(true).open(device).is_ok())
}

/// How far the picture is turned to stand upright, in quarter turns
/// clockwise, as ffmpeg's filter (the camera's sensor lies on its side
/// when the phone is held upright).
fn turn_filter(degrees: u32) -> Option<&'static str> {
    match degrees % 360 {
        90 => Some("transpose=1"),
        180 => Some("hflip,vflip"),
        270 => Some("transpose=2"),
        _ => None,
    }
}

/// The picture's size once turned.
fn turned(size: (u32, u32), degrees: u32) -> (u32, u32) {
    if degrees % 180 == 90 {
        (size.1, size.0)
    } else {
        size
    }
}

/// ffmpeg's part: H.264 in, frames out, holding nothing back.
fn decoder_args(degrees: u32, way: &Way) -> Vec<String> {
    let mut args: Vec<String> =
        ["-hide_banner", "-loglevel", "error", "-fflags", "nobuffer", "-flags", "low_delay", "-probesize", "32", "-analyzeduration", "0", "-f", "h264", "-i", "pipe:0"].map(str::to_owned).to_vec();
    if let Some(filter) = turn_filter(degrees) {
        args.extend(["-vf".to_owned(), filter.to_owned()]);
    }
    args.extend(["-fps_mode", "passthrough", "-pix_fmt", "yuv420p"].map(str::to_owned));
    match way {
        Way::Loopback(device) => args.extend(["-f".to_owned(), "v4l2".to_owned(), device.to_string_lossy().into_owned()]),
        Way::PipeWire => args.extend(["-f", "rawvideo", "pipe:1"].map(str::to_owned)),
    }
    args
}

/// GStreamer's part: the frames as a camera in PipeWire, named `label`.
fn provider_args(size: (u32, u32), label: &str) -> Vec<String> {
    let label = label.replace('\\', "").replace('"', "'");
    vec![
        "-q".to_owned(),
        "fdsrc".to_owned(),
        "fd=0".to_owned(),
        "!".to_owned(),
        "rawvideoparse".to_owned(),
        format!("width={}", size.0),
        format!("height={}", size.1),
        "format=i420".to_owned(),
        "framerate=30/1".to_owned(),
        "!".to_owned(),
        "pipewiresink".to_owned(),
        "mode=provide".to_owned(),
        "sync=false".to_owned(),
        // gst-launch reads its words as one line again: the whole value is
        // quoted, and the quotes inside it escaped (found by trying).
        format!(r#"stream-properties="props,media.class=Video/Source,media.role=Camera,node.name=multiplex-camera,node.description=\"{label}\"""#),
    ]
}

/// The programs that turn the stream into a camera, while they run.
struct Running {
    input: Option<ChildStdin>,
    children: Vec<Child>,
}

impl Running {
    fn start(way: &Way, size: (u32, u32), degrees: u32, label: &str) -> Result<Self> {
        let mut decoder = Command::new("ffmpeg");
        decoder.args(decoder_args(degrees, way)).stdin(Stdio::piped()).stderr(Stdio::null());
        match way {
            Way::Loopback(_) => {
                let mut ffmpeg = decoder.stdout(Stdio::null()).spawn().context("ffmpeg could not be started")?;
                Ok(Self { input: ffmpeg.stdin.take(), children: vec![ffmpeg] })
            }
            Way::PipeWire => {
                let mut ffmpeg = decoder.stdout(Stdio::piped()).spawn().context("ffmpeg could not be started")?;
                let frames = ffmpeg.stdout.take().context("ffmpeg gave no output")?;
                let provider = Command::new("gst-launch-1.0").args(provider_args(turned(size, degrees), label)).stdin(Stdio::from(frames)).stdout(Stdio::null()).stderr(Stdio::null()).spawn();
                match provider {
                    Ok(provider) => Ok(Self { input: ffmpeg.stdin.take(), children: vec![ffmpeg, provider] }),
                    Err(err) => {
                        let _ = ffmpeg.kill();
                        let _ = ffmpeg.wait();
                        Err(err).context("gst-launch-1.0 could not be started")
                    }
                }
            }
        }
    }

    /// False when the programs have stopped taking the stream.
    fn write(&mut self, piece: &[u8]) -> bool {
        self.input.as_mut().is_some_and(|input| input.write_all(piece).is_ok())
    }
}

impl Drop for Running {
    fn drop(&mut self) {
        // The end of the stream ends them; make sure of it.
        self.input = None;
        std::thread::sleep(std::time::Duration::from_millis(150));
        for child in &mut self.children {
            if !matches!(child.try_wait(), Ok(Some(_))) {
                let _ = child.kill();
            }
            let _ = child.wait();
        }
    }
}

/// `multiplex camera [--turn <degrees>] [<phone>]`.
pub fn run(args: &[&str]) -> Result<()> {
    let (degrees, name) = match args {
        ["--turn", degrees, rest @ ..] => (degrees.parse::<u32>().ok().filter(|d| d % 90 == 0).context("use --turn 0, 90, 180 or 270")?, rest),
        rest => (0, rest),
    };
    let phone = match name {
        [] => crate::share::the_phone("").ok(),
        [name] => multiplex_proto::clean_device_name(name),
        _ => bail!("use: multiplex camera [--turn <degrees>] [<phone>]"),
    };
    let label = phone.map_or_else(|| "Phone camera".to_owned(), |name| format!("{name} camera"));
    if !on_path("ffmpeg") {
        bail!("the phone's camera {NEEDS}");
    }
    let Some(way) = Way::find() else {
        bail!("the phone's camera {NEEDS}");
    };

    // The programs are started when the stream has said its picture's
    // size, which it does with its first full picture.
    let mut watch = SizeWatch::default();
    let mut held: Vec<u8> = Vec::new();
    let mut running: Option<Running> = None;
    pump(
        |piece| {
            if let Some(running) = &mut running {
                return Ok(running.write(piece));
            }
            held.extend_from_slice(piece);
            let Some(size) = watch.feed(piece).first().copied() else {
                if held.len() > 4 * 1024 * 1024 {
                    bail!("the camera's picture did not begin");
                }
                return Ok(true);
            };
            let mut started = Running::start(&way, size, degrees, &label)?;
            let taking = started.write(&held);
            held = Vec::new();
            running = Some(started);
            Ok(taking)
        },
        "the phone stopped sending its camera",
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_picture_is_turned_upright() {
        assert_eq!(turn_filter(0), None);
        assert_eq!(turn_filter(90), Some("transpose=1"));
        assert_eq!(turn_filter(180), Some("hflip,vflip"));
        assert_eq!(turn_filter(270), Some("transpose=2"));
        assert_eq!(turn_filter(360), None);
        assert_eq!(turned((1280, 720), 0), (1280, 720));
        assert_eq!(turned((1280, 720), 90), (720, 1280));
        assert_eq!(turned((1280, 720), 180), (1280, 720));
        assert_eq!(turned((1280, 720), 270), (720, 1280));
    }

    #[test]
    fn the_decoder_holds_nothing_back_and_writes_where_the_way_says() {
        let to_pipewire = decoder_args(90, &Way::PipeWire);
        let line = to_pipewire.join(" ");
        assert!(line.contains("-fflags nobuffer -flags low_delay -probesize 32 -analyzeduration 0 -f h264 -i pipe:0"), "{line}");
        assert!(line.contains("-vf transpose=1 "), "{line}");
        assert!(line.ends_with("-fps_mode passthrough -pix_fmt yuv420p -f rawvideo pipe:1"), "{line}");
        let to_device = decoder_args(0, &Way::Loopback(PathBuf::from("/dev/video9"))).join(" ");
        assert!(!to_device.contains("-vf"), "{to_device}");
        assert!(to_device.ends_with("-f v4l2 /dev/video9"), "{to_device}");
    }

    #[test]
    fn the_camera_is_offered_under_the_phones_name() {
        let args = provider_args((720, 1280), "Sam's \"best\" phone camera");
        assert!(args.contains(&"width=720".to_owned()) && args.contains(&"height=1280".to_owned()));
        let properties = args.last().unwrap();
        assert!(properties.contains("media.class=Video/Source,media.role=Camera"), "{properties}");
        // Nothing in a name can end the description early.
        assert!(properties.starts_with(r#"stream-properties="props,"#), "{properties}");
        assert!(properties.ends_with(r#"node.description=\"Sam's 'best' phone camera\"""#), "{properties}");
    }

    #[test]
    fn a_loopback_device_is_found_among_the_virtual_ones() {
        let dir = tempfile::tempdir().unwrap();
        let (sys, dev) = (dir.path().join("sys"), dir.path().join("dev"));
        std::fs::create_dir_all(&sys).unwrap();
        std::fs::create_dir_all(&dev).unwrap();
        assert_eq!(loopback_device(&sys, &dev), None, "none there");
        assert_eq!(loopback_device(&dir.path().join("missing"), &dev), None);
        for name in ["video12", "video10", "vbi0"] {
            std::fs::create_dir(sys.join(name)).unwrap();
        }
        std::fs::write(dev.join("video10"), b"").unwrap();
        std::fs::write(dev.join("video12"), b"").unwrap();
        assert_eq!(loopback_device(&sys, &dev), Some(dev.join("video10")));
    }
}
