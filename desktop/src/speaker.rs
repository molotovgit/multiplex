//! `multiplex speaker`: the phone as a loudspeaker of this computer.
//!
//! The sound server gets one more output, named after the phone. What is
//! played into it is encoded (AAC, by ffmpeg) and written to this
//! command's standard output, which over SSH is the phone; the phone
//! plays it. With `--default` the new output also becomes the computer's
//! default output for as long as this runs, so everything is heard on the
//! phone; without it, only what is pointed at it.
//!
//! The phone says "still here" on standard input once a second. When it
//! stops (out of range, app closed) everything is put back at once: a
//! computer whose sound goes to a phone that has left would be silent.

use std::io::{Read, Write};
use std::process::{Child, Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use multiplex_proto::share::FEED_READY;

use crate::system::on_path;

/// The output's name next to its description.
const SINK: &str = "multiplex-speaker";

/// What is missing when it cannot work.
pub const NEEDS: &str = "needs ffmpeg and pactl (PipeWire with pipewire-pulse, or PulseAudio)";

/// With no word from the phone for this long, it is gone.
const SILENCE: Duration = Duration::from_secs(5);

pub fn available() -> bool {
    on_path("ffmpeg") && on_path("pactl")
}

/// The sound server's words for the new output.
fn module_args(label: &str) -> Vec<String> {
    // Inside the properties a space ends a value unless it is escaped.
    let label = label.replace(['\\', '"'], "").replace(' ', "\\ ");
    vec!["load-module".to_owned(), "module-null-sink".to_owned(), format!("sink_name={SINK}"), format!("sink_properties=device.description=\"{label}\"")]
}

/// ffmpeg's part: what is played into the output, as AAC frames with ADTS
/// headers on standard output, holding nothing back.
fn encoder_args() -> Vec<String> {
    let monitor = format!("{SINK}.monitor");
    ["-hide_banner", "-loglevel", "error", "-f", "pulse", "-fragment_size", "3840", "-i", &monitor, "-ac", "2", "-ar", "48000", "-c:a", "aac", "-b:a", "128k", "-flush_packets", "1", "-f", "adts", "pipe:1"]
        .map(str::to_owned)
        .to_vec()
}

/// The modules of earlier runs that were left loaded, from
/// `pactl list short modules`.
fn left_loaded(modules: &str) -> Vec<String> {
    modules
        .lines()
        .filter(|line| line.contains("module-null-sink") && line.contains(&format!("sink_name={SINK}")))
        .filter_map(|line| line.split_whitespace().next().map(str::to_owned))
        .collect()
}

fn pactl(args: &[&str]) -> Option<String> {
    let out = Command::new("pactl").args(args).output().ok()?;
    out.status.success().then(|| String::from_utf8_lossy(&out.stdout).trim().to_owned())
}

/// The output while it exists. Dropping it puts everything back.
struct Speaker {
    module: String,
    /// The default output before this one took its place.
    default_before: Option<String>,
    encoder: Option<Child>,
}

impl Speaker {
    fn open(label: &str, make_default: bool) -> Result<Self> {
        // One at a time: clear away what an earlier run left behind.
        for module in left_loaded(&pactl(&["list", "short", "modules"]).unwrap_or_default()) {
            let _ = pactl(&["unload-module", &module]);
        }
        // Read before the new output exists: a sound server may make a new
        // output the default by itself.
        let before = pactl(&["get-default-sink"]).filter(|name| !name.is_empty() && name != SINK);
        let args = module_args(label);
        let module = pactl(&args.iter().map(String::as_str).collect::<Vec<_>>()).filter(|m| !m.is_empty() && m.bytes().all(|b| b.is_ascii_digit())).context("the sound server did not take the new output")?;
        let mut speaker = Self { module, default_before: None, encoder: None };
        if make_default {
            speaker.default_before = before;
            let _ = pactl(&["set-default-sink", SINK]);
        } else if let Some(before) = &before {
            // Not asked to be the default: make sure it did not become it.
            if pactl(&["get-default-sink"]).as_deref() == Some(SINK) {
                let _ = pactl(&["set-default-sink", before]);
            }
        }
        Ok(speaker)
    }

    /// Starts the encoder, writing to this command's standard output.
    fn start(&mut self) -> Result<()> {
        self.encoder = Some(Command::new("ffmpeg").args(encoder_args()).stdin(Stdio::null()).stdout(Stdio::inherit()).stderr(Stdio::null()).spawn().context("ffmpeg could not be started")?);
        Ok(())
    }

    /// Whether the encoder has stopped by itself.
    fn ended(&mut self) -> bool {
        self.encoder.as_mut().is_none_or(|encoder| matches!(encoder.try_wait(), Ok(Some(_)) | Err(_)))
    }
}

impl Drop for Speaker {
    fn drop(&mut self) {
        // The computer's sound first: back to where it was.
        if let Some(before) = &self.default_before {
            if pactl(&["get-default-sink"]).as_deref() == Some(SINK) {
                let _ = pactl(&["set-default-sink", before]);
            }
        }
        if let Some(mut encoder) = self.encoder.take() {
            let _ = encoder.kill();
            let _ = encoder.wait();
        }
        let _ = pactl(&["unload-module", &self.module]);
    }
}

/// `multiplex speaker [--default] [<phone>]`.
pub fn run(args: &[&str]) -> Result<()> {
    let (make_default, name) = match args {
        ["--default", rest @ ..] => (true, rest),
        rest => (false, rest),
    };
    let phone = match name {
        [] => crate::share::the_phone("").ok(),
        [name] => multiplex_proto::clean_device_name(name),
        _ => bail!("use: multiplex speaker [--default] [<phone>]"),
    };
    let label = phone.map_or_else(|| "Phone speaker".to_owned(), |name| format!("{name} speaker"));
    if !available() {
        bail!("the phone as a speaker {NEEDS}");
    }
    let mut speaker = Speaker::open(&label, make_default)?;
    {
        let mut out = std::io::stdout().lock();
        writeln!(out, "{FEED_READY}")?;
        out.flush()?;
    }
    speaker.start()?;

    // The phone's "still here", read on its own thread so that its
    // stopping can be noticed.
    let (words, heard) = mpsc::channel::<()>();
    std::thread::spawn(move || {
        let mut input = std::io::stdin().lock();
        let mut buffer = [0u8; 64];
        while matches!(input.read(&mut buffer), Ok(n) if n > 0) {
            if words.send(()).is_err() {
                break;
            }
        }
    });
    let mut last_word = Instant::now();
    loop {
        match heard.recv_timeout(Duration::from_millis(200)) {
            Ok(()) => last_word = Instant::now(),
            // The phone stopped (the input ended).
            Err(mpsc::RecvTimeoutError::Disconnected) => return Ok(()),
            Err(mpsc::RecvTimeoutError::Timeout) => {
                if last_word.elapsed() > SILENCE {
                    bail!("the phone stopped listening");
                }
            }
        }
        if speaker.ended() {
            bail!("the sound could not be taken from the sound server");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_output_is_offered_under_the_phones_name() {
        let args = module_args("Sam's \"best\" phone speaker");
        assert_eq!(args[..3], ["load-module", "module-null-sink", "sink_name=multiplex-speaker"]);
        assert_eq!(args[3], r#"sink_properties=device.description="Sam's\ best\ phone\ speaker""#);
    }

    #[test]
    fn the_encoder_takes_what_is_played_into_the_output() {
        let line = encoder_args().join(" ");
        assert!(line.contains("-f pulse -fragment_size 3840 -i multiplex-speaker.monitor"), "{line}");
        assert!(line.ends_with("-ac 2 -ar 48000 -c:a aac -b:a 128k -flush_packets 1 -f adts pipe:1"), "{line}");
    }

    #[test]
    fn only_this_commands_own_leftovers_are_unloaded() {
        let modules = "536870915\tmodule-null-sink\tsink_name=someone-elses\n\
            536870916\tmodule-null-sink\tsink_name=multiplex-speaker sink_properties=device.description=\"x\"\n\
            536870917\tmodule-pipe-source\tsource_name=multiplex-mic file=/tmp/x\n";
        assert_eq!(left_loaded(modules), ["536870916"]);
    }
}
