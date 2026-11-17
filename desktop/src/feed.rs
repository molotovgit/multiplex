//! Taking a stream the phone writes to this command's standard input
//! (its screen, its camera) and handing it on, piece by piece.
//!
//! The phone is told `ready`, and then now and then how many bytes have
//! been taken, so it knows how far behind this end is and can skip ahead
//! when the connection cannot keep up.

use std::io::{Read, Write};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use anyhow::{anyhow, Result};
use multiplex_proto::share::{fed_line, FEED_READY};

/// With no piece for this long, the phone is gone.
const SILENCE: Duration = Duration::from_secs(8);

/// How often the phone is told how much has been taken.
const TELL_EVERY: Duration = Duration::from_millis(100);

/// Says `ready`, then gives every piece that arrives to `take` until the
/// phone stops (the input ends), `take` says it has had enough (`false`),
/// or the phone goes silent, which is an error with the words `gone`.
///
/// The input is read on its own thread, so that its stopping can be
/// noticed: a phone that is still there sends something at least once a
/// second. One that has gone without a word (out of range, app killed)
/// would otherwise hold this command until SSH itself gives up, a minute
/// or more later.
pub fn pump(mut take: impl FnMut(&[u8]) -> Result<bool>, gone: &str) -> Result<()> {
    let mut out = std::io::stdout().lock();
    writeln!(out, "{FEED_READY}")?;
    out.flush()?;

    let (pieces, arriving) = mpsc::sync_channel::<Vec<u8>>(8);
    std::thread::spawn(move || {
        let mut input = std::io::stdin().lock();
        let mut buffer = vec![0u8; 64 * 1024];
        while let Ok(n) = input.read(&mut buffer) {
            if n == 0 || pieces.send(buffer[..n].to_vec()).is_err() {
                break;
            }
        }
    });
    let (mut taken, mut told) = (0u64, 0u64);
    let (mut last_piece, mut last_told) = (Instant::now(), Instant::now());
    loop {
        match arriving.recv_timeout(TELL_EVERY) {
            Ok(piece) => {
                if !take(&piece)? {
                    return Ok(());
                }
                taken += piece.len() as u64;
                last_piece = Instant::now();
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => return Ok(()),
            Err(mpsc::RecvTimeoutError::Timeout) => {
                if last_piece.elapsed() > SILENCE {
                    return Err(anyhow!("{gone}"));
                }
            }
        }
        if taken != told && last_told.elapsed() >= TELL_EVERY {
            if writeln!(out, "{}", fed_line(taken)).and_then(|()| out.flush()).is_err() {
                return Ok(());
            }
            told = taken;
            last_told = Instant::now();
        }
    }
}
