//! `multiplex mic`: the phone's microphone as a microphone of this
//! computer.
//!
//! The phone records, encodes the sound as AAC and writes it to this
//! command over SSH. Here ffmpeg decodes it, the samples go into a pipe,
//! and the sound server (PipeWire, through its PulseAudio side) offers
//! that pipe to other programs as a microphone named after the phone. No
//! root needed.
//!
//! While no program is listening, the sound server does not read the
//! pipe. The samples are then dropped, not kept: a program that starts
//! listening later must hear now, not what was said a while ago, and
//! nothing here may wait on a pipe nobody reads.
//!
//! The microphone is there for as long as the phone is sending. It does
//! not become the default input: programs that should use it are pointed
//! at it.

use std::fs::File;
use std::io::{Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};

use anyhow::{bail, Context, Result};

use crate::feed::pump;
use crate::share::runtime_dir;
use crate::system::on_path;

/// The name other programs' settings see next to the description.
const SOURCE: &str = "multiplex-mic";

/// What is missing when it cannot work.
pub const NEEDS: &str = "needs ffmpeg and pactl (PipeWire with pipewire-pulse, or PulseAudio)";

pub fn available() -> bool {
    on_path("ffmpeg") && on_path("pactl")
}

/// The sound server's words for a microphone fed from `pipe`.
fn module_args(pipe: &Path, label: &str) -> Vec<String> {
    // Inside the properties a space ends a value unless it is escaped.
    let label = label.replace(['\\', '"'], "").replace(' ', "\\ ");
    vec![
        "load-module".to_owned(),
        "module-pipe-source".to_owned(),
        format!("source_name={SOURCE}"),
        format!("file={}", pipe.display()),
        "format=s16le".to_owned(),
        "rate=48000".to_owned(),
        "channels=1".to_owned(),
        format!("source_properties=device.description=\"{label}\""),
    ]
}

/// ffmpeg's part: AAC in, plain samples out, holding nothing back.
fn decoder_args() -> Vec<&'static str> {
    vec![
        "-hide_banner", "-loglevel", "error", "-fflags", "nobuffer", "-flags", "low_delay", "-probesize", "32", "-analyzeduration", "0", "-f", "aac", "-i", "pipe:0", "-f", "s16le", "-ar", "48000", "-ac", "1",
        "-flush_packets", "1", "pipe:1",
    ]
}

/// The most the pipe holds: 170 ms of sound. That is all the old sound a
/// program can get when it starts listening, and the room there is for
/// sound that arrives in a clump.
const PIPE_BYTES: i32 = 16 * 1024;

/// The samples are handed over 20 ms at a time. A piece this small goes
/// into a pipe whole or not at all, so the samples never get out of step.
const HANDOVER_BYTES: usize = 1920;

/// Opens the pipe so that writing to it never waits: for reading too
/// (then opening does not wait for the sound server either), and small.
fn open_pipe(pipe: &Path) -> std::io::Result<File> {
    let file = std::fs::OpenOptions::new().read(true).write(true).custom_flags(libc::O_NONBLOCK).open(pipe)?;
    // SAFETY: a plain fcntl on a descriptor this function owns.
    unsafe { libc::fcntl(file.as_raw_fd(), libc::F_SETPIPE_SZ, PIPE_BYTES) };
    Ok(file)
}

/// Moves the decoder's samples into the pipe until the decoder ends.
/// What does not fit is dropped: nobody is listening, or it came late.
fn hand_over(mut samples: impl Read, mut pipe: impl Write) -> u64 {
    let mut piece = [0u8; HANDOVER_BYTES];
    let mut dropped = 0;
    while samples.read_exact(&mut piece).is_ok() {
        if pipe.write(&piece).is_err() {
            dropped += 1;
        }
    }
    dropped
}

/// The modules of earlier runs that were left loaded (a command that was
/// killed could not unload its own), from `pactl list short modules`.
fn left_loaded(modules: &str) -> Vec<String> {
    modules
        .lines()
        .filter(|line| line.contains("module-pipe-source") && line.contains(&format!("source_name={SOURCE}")))
        .filter_map(|line| line.split_whitespace().next().map(str::to_owned))
        .collect()
}

/// The microphone while it exists: the pipe, the sound server's module
/// and the decoder. Dropping it takes all three away.
struct Microphone {
    pipe: PathBuf,
    module: String,
    decoder: Child,
    input: Option<ChildStdin>,
}

impl Microphone {
    fn open(label: &str) -> Result<Self> {
        // One at a time: clear away what an earlier run left behind.
        if let Ok(out) = Command::new("pactl").args(["list", "short", "modules"]).output() {
            for module in left_loaded(&String::from_utf8_lossy(&out.stdout)) {
                let _ = Command::new("pactl").args(["unload-module", &module]).status();
            }
        }
        crate::screen::sweep(&runtime_dir());
        let pipe = runtime_dir().join(format!("mic-{}.pcm", std::process::id()));
        let _ = std::fs::remove_file(&pipe);
        if !Command::new("mkfifo").arg("-m").arg("600").arg(&pipe).status().is_ok_and(|s| s.success()) {
            bail!("could not make a pipe for the sound");
        }
        let loaded = Command::new("pactl").args(module_args(&pipe, label)).output().context("pactl could not be run")?;
        let module = String::from_utf8_lossy(&loaded.stdout).trim().to_owned();
        if !loaded.status.success() || module.is_empty() || !module.bytes().all(|b| b.is_ascii_digit()) {
            let _ = std::fs::remove_file(&pipe);
            bail!("the sound server did not take the microphone: {}", String::from_utf8_lossy(&loaded.stderr).trim());
        }
        let started = open_pipe(&pipe).context("the pipe for the sound could not be opened").and_then(|writing| {
            let mut decoder = Command::new("ffmpeg").args(decoder_args()).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().context("ffmpeg could not be started")?;
            let samples = decoder.stdout.take().context("ffmpeg gave no output")?;
            std::thread::spawn(move || hand_over(samples, writing));
            Ok(decoder)
        });
        match started {
            Ok(mut decoder) => Ok(Self { pipe, module, input: decoder.stdin.take(), decoder }),
            Err(err) => {
                let _ = Command::new("pactl").args(["unload-module", &module]).status();
                let _ = std::fs::remove_file(&pipe);
                Err(err)
            }
        }
    }

    /// False when the decoder has stopped taking the sound.
    fn write(&mut self, piece: &[u8]) -> bool {
        self.input.as_mut().is_some_and(|input| input.write_all(piece).is_ok())
    }
}

impl Drop for Microphone {
    fn drop(&mut self) {
        self.input = None;
        std::thread::sleep(std::time::Duration::from_millis(100));
        if !matches!(self.decoder.try_wait(), Ok(Some(_))) {
            let _ = self.decoder.kill();
        }
        let _ = self.decoder.wait();
        let _ = Command::new("pactl").args(["unload-module", &self.module]).stdout(Stdio::null()).stderr(Stdio::null()).status();
        let _ = std::fs::remove_file(&self.pipe);
    }
}

/// `multiplex mic [<phone>]`.
pub fn run(args: &[&str]) -> Result<()> {
    let phone = match args {
        [] => crate::share::the_phone("").ok(),
        [name] => multiplex_proto::clean_device_name(name),
        _ => bail!("use: multiplex mic [<phone>]"),
    };
    let label = phone.map_or_else(|| "Phone microphone".to_owned(), |name| format!("{name} microphone"));
    if !available() {
        bail!("the phone's microphone {NEEDS}");
    }
    let mut microphone = Microphone::open(&label)?;
    pump(|piece| Ok(microphone.write(piece)), "the phone stopped sending its sound")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_microphone_is_offered_under_the_phones_name() {
        let args = module_args(Path::new("/run/user/1000/multiplex/mic-7.pcm"), "Sam's \"best\" phone microphone");
        assert_eq!(args[..3], ["load-module", "module-pipe-source", "source_name=multiplex-mic"]);
        assert!(args.contains(&"file=/run/user/1000/multiplex/mic-7.pcm".to_owned()));
        assert!(args.contains(&"format=s16le".to_owned()) && args.contains(&"rate=48000".to_owned()) && args.contains(&"channels=1".to_owned()));
        // Spaces are escaped; nothing in a name can end the description early.
        assert_eq!(args.last().unwrap(), r#"source_properties=device.description="Sam's\ best\ phone\ microphone""#);
    }

    #[test]
    fn the_decoder_gives_plain_samples_at_once() {
        let line = decoder_args().join(" ");
        assert!(line.contains("-fflags nobuffer -flags low_delay -probesize 32 -analyzeduration 0 -f aac -i pipe:0"), "{line}");
        assert!(line.ends_with("-f s16le -ar 48000 -ac 1 -flush_packets 1 pipe:1"), "{line}");
    }

    /// A pipe nobody reads: it takes a few pieces, then no more.
    struct Full {
        room: usize,
        taken: Vec<u8>,
    }

    impl Write for Full {
        fn write(&mut self, piece: &[u8]) -> std::io::Result<usize> {
            if piece.len() > self.room {
                return Err(std::io::ErrorKind::WouldBlock.into());
            }
            self.room -= piece.len();
            self.taken.extend_from_slice(piece);
            Ok(piece.len())
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    #[test]
    fn sound_nobody_takes_is_dropped_whole_and_nothing_waits() {
        // Ten pieces of sound; the pipe has room for three.
        let sound: Vec<u8> = (0..HANDOVER_BYTES * 10).map(|i| (i / HANDOVER_BYTES) as u8).collect();
        let mut pipe = Full { room: HANDOVER_BYTES * 3 + 100, taken: Vec::new() };
        let dropped = hand_over(sound.as_slice(), &mut pipe);
        assert_eq!(dropped, 7);
        // What went in went in whole: the samples stay in step.
        assert_eq!(pipe.taken.len(), HANDOVER_BYTES * 3);
        assert!(pipe.taken.chunks(HANDOVER_BYTES).enumerate().all(|(i, piece)| piece.iter().all(|b| *b == i as u8)));
    }

    #[test]
    fn a_real_pipe_nobody_reads_does_not_hold_the_writer() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("mic.pcm");
        assert!(Command::new("mkfifo").arg(&path).status().unwrap().success());
        let pipe = open_pipe(&path).expect("opens without anyone at the other end");
        // A second of sound, with nobody reading: this returns at once.
        let started = std::time::Instant::now();
        let dropped = hand_over(vec![1u8; 96_000].as_slice(), &pipe);
        assert!(started.elapsed() < std::time::Duration::from_millis(500));
        // 170 ms fit; the rest was dropped.
        assert!((35..=48).contains(&dropped), "{dropped} of 50 pieces dropped");
    }

    #[test]
    fn only_this_commands_own_leftovers_are_unloaded() {
        let modules = "536870915\tmodule-null-sink\tsink_name=other\n\
            536870916\tmodule-pipe-source\tsource_name=multiplex-mic file=/run/user/1000/multiplex/mic-1.pcm format=s16le\n\
            536870917\tmodule-pipe-source\tsource_name=someone-elses file=/tmp/x\n\
            536870918\tmodule-pipe-source\tsource_name=multiplex-mic file=/run/user/1000/multiplex/mic-2.pcm\n";
        assert_eq!(left_loaded(modules), ["536870916", "536870918"]);
        assert!(left_loaded("").is_empty());
    }
}
