//! Keeping the phone's screen on the computer live when the connection
//! is slower than the picture.
//!
//! A video stream that is simply queued falls further and further behind:
//! the window then shows what the phone looked like seconds ago. So when
//! too much is on its way, the phone stops sending, lets what is under
//! way arrive, and carries on from a fresh full picture at a lower
//! bitrate. When things go well for a while it tries a better one again.

use std::time::{Duration, Instant};

/// The best picture asked of the encoder, in bits per second.
pub const TOP_BITRATE: u32 = 4_000_000;

/// The least: below this the screen is not readable any more.
pub const LOW_BITRATE: u32 = 500_000;

/// This much of the picture on its way (in seconds of it) is too late.
const LATE: f64 = 1.0;

/// As little on its way as this (in bytes) counts as caught up.
const CAUGHT_UP: u64 = 16 * 1024;

/// A better picture is tried after this long without trouble.
const RAISE_AFTER: Duration = Duration::from_secs(8);

/// A fresh full picture is asked for at most this often.
const ASK_EVERY: Duration = Duration::from_secs(1);

/// An H.264 access unit delimiter: valid anywhere in the stream, and
/// nothing to show. It has two uses here.
///
/// After every picture it tells the player "that picture is complete".
/// Without it a player only knows that when the next picture begins, so
/// it always shows one picture late: on a still screen, where the next
/// one comes half a second later, the last change would show that late
/// (measured with mpv: picture 4 of 5 shown, however long one waits).
///
/// Alone, it says the phone is still there while pieces are skipped.
pub const DELIMITER: [u8; 6] = [0, 0, 0, 1, 9, 0xF0];

/// The piece as it goes out: with the "picture complete" mark after it.
pub fn completed(mut piece: Vec<u8>, kind: Piece) -> Vec<u8> {
    // The settings are not a picture: the picture follows them.
    if kind != Piece::Settings {
        piece.extend_from_slice(&DELIMITER);
    }
    piece
}

/// What a piece of the stream is, as far as skipping goes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Piece {
    /// A full picture: the stream can start (again) here.
    Key,
    /// The stream's settings alone. Always sent, never a place to start.
    Settings,
    /// A picture that builds on the ones before it.
    Change,
}

/// Looks at the piece's NAL units (Annex B, as Android's encoder gives
/// them) up to its first picture.
pub fn kind(bytes: &[u8]) -> Piece {
    let mut settings = false;
    let mut at = 0;
    while at + 3 < bytes.len() {
        if bytes[at] == 0 && bytes[at + 1] == 0 && bytes[at + 2] == 1 {
            match bytes[at + 3] & 0x1F {
                5 => return Piece::Key,
                7 | 8 => settings = true,
                1 => return Piece::Change,
                _ => {}
            }
            at += 4;
        } else {
            at += 1;
        }
    }
    if settings {
        Piece::Settings
    } else {
        Piece::Change
    }
}

/// What to do with one piece.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Step {
    /// Send it (otherwise it is skipped).
    pub send: bool,
    /// Set the encoder to this bitrate.
    pub bitrate: Option<u32>,
    /// Ask the encoder for a full picture now.
    pub key_frame: bool,
}

pub struct Pace {
    bitrate: u32,
    skipping: bool,
    /// When the bitrate last changed, or skipping last ended.
    settled: Instant,
    asked: Option<Instant>,
    skipped: u64,
}

impl Pace {
    pub fn new(now: Instant) -> Self {
        Self { bitrate: TOP_BITRATE, skipping: false, settled: now, asked: None, skipped: 0 }
    }

    pub fn bitrate(&self) -> u32 {
        self.bitrate
    }

    /// Pieces skipped so far.
    pub fn skipped(&self) -> u64 {
        self.skipped
    }

    pub fn skipping(&self) -> bool {
        self.skipping
    }

    /// Decides about the next piece. `in_flight` is how many bytes are
    /// written but not yet taken by the computer.
    pub fn next(&mut self, in_flight: u64, piece: Piece, now: Instant) -> Step {
        let step = self.decide(in_flight, piece, now);
        if !step.send {
            self.skipped += 1;
        }
        step
    }

    fn decide(&mut self, in_flight: u64, piece: Piece, now: Instant) -> Step {
        // The settings are tiny and a player cannot do without them.
        let send_anyway = piece == Piece::Settings;
        if !self.skipping {
            let seconds_behind = in_flight as f64 * 8.0 / f64::from(self.bitrate);
            if seconds_behind > LATE {
                self.skipping = true;
                self.asked = None;
                let lower = (self.bitrate / 5 * 3).max(LOW_BITRATE);
                let bitrate = (lower != self.bitrate).then_some(lower);
                self.bitrate = lower;
                self.settled = now;
                return Step { send: send_anyway, bitrate, key_frame: false };
            }
            let mut bitrate = None;
            if self.bitrate < TOP_BITRATE && seconds_behind < LATE / 2.0 && now.duration_since(self.settled) >= RAISE_AFTER {
                self.bitrate = (self.bitrate / 4 * 5).min(TOP_BITRATE);
                self.settled = now;
                bitrate = Some(self.bitrate);
            }
            return Step { send: true, bitrate, key_frame: false };
        }
        // Skipping: wait until what was under way has arrived, then start
        // again from a full picture.
        if in_flight > CAUGHT_UP {
            return Step { send: send_anyway, ..Step::default() };
        }
        if piece == Piece::Key {
            self.skipping = false;
            self.settled = now;
            return Step { send: true, ..Step::default() };
        }
        let ask = self.asked.is_none_or(|at| now.duration_since(at) >= ASK_EVERY);
        if ask {
            self.asked = Some(now);
        }
        Step { send: send_anyway, bitrate: None, key_frame: ask }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn unit(kind: u8) -> Vec<u8> {
        vec![0, 0, 0, 1, kind, 0xAA, 0xBB]
    }

    #[test]
    fn pieces_are_told_apart() {
        // Settings, then a full picture, as the encoder sends a key picture.
        assert_eq!(kind(&[unit(0x67), unit(0x68), unit(0x65)].concat()), Piece::Key);
        assert_eq!(kind(&unit(0x65)), Piece::Key);
        // Three-byte start codes too.
        assert_eq!(kind(&[0, 0, 1, 0x65, 0x88]), Piece::Key);
        assert_eq!(kind(&[unit(0x67), unit(0x68)].concat()), Piece::Settings);
        assert_eq!(kind(&unit(0x41)), Piece::Change);
        assert_eq!(kind(&[unit(0x09), unit(0x41)].concat()), Piece::Change);
        assert_eq!(kind(&DELIMITER), Piece::Change);
        assert_eq!(kind(&[]), Piece::Change);
    }

    #[test]
    fn every_picture_goes_out_marked_complete() {
        let picture = unit(0x41);
        let sent = completed(picture.clone(), kind(&picture));
        assert_eq!(sent, [picture.clone(), DELIMITER.to_vec()].concat());
        // What it is does not change by that.
        assert_eq!(kind(&sent), Piece::Change);
        let key = [unit(0x67), unit(0x68), unit(0x65)].concat();
        assert!(completed(key.clone(), Piece::Key).ends_with(&DELIMITER));
        // The settings alone are not a picture.
        let settings = [unit(0x67), unit(0x68)].concat();
        assert_eq!(completed(settings.clone(), Piece::Settings), settings);
    }

    #[test]
    fn a_connection_that_keeps_up_sends_everything_at_the_best_bitrate() {
        let start = Instant::now();
        let mut pace = Pace::new(start);
        for i in 0..600u64 {
            // A third of a second of picture on its way: ordinary.
            let step = pace.next(160_000, if i % 60 == 0 { Piece::Key } else { Piece::Change }, start + Duration::from_millis(i * 33));
            assert_eq!(step, Step { send: true, bitrate: None, key_frame: false });
        }
        assert_eq!(pace.bitrate(), TOP_BITRATE);
        assert_eq!(pace.skipped(), 0);
    }

    #[test]
    fn falling_behind_skips_ahead_to_a_full_picture_at_a_lower_bitrate() {
        let start = Instant::now();
        let at = |ms: u64| start + Duration::from_millis(ms);
        let mut pace = Pace::new(start);
        // More than a second of picture on its way: too late.
        let step = pace.next(600_000, Piece::Change, at(0));
        assert_eq!(step, Step { send: false, bitrate: Some(2_400_000), key_frame: false });
        // While it is still arriving, nothing more is added, not even a full picture.
        assert!(!pace.next(300_000, Piece::Change, at(100)).send);
        assert!(!pace.next(200_000, Piece::Key, at(200)).send);
        // It has arrived: ask for a full picture, once, and wait for it.
        assert_eq!(pace.next(2_000, Piece::Change, at(300)), Step { send: false, bitrate: None, key_frame: true });
        assert_eq!(pace.next(2_000, Piece::Change, at(333)), Step { send: false, bitrate: None, key_frame: false });
        // Still none a second later: ask again.
        assert!(pace.next(2_000, Piece::Change, at(1_400)).key_frame);
        // There it is: carry on from it.
        assert_eq!(pace.next(2_000, Piece::Key, at(1_450)), Step { send: true, bitrate: None, key_frame: false });
        assert!(pace.next(40_000, Piece::Change, at(1_480)).send);
        assert_eq!(pace.skipped(), 6);
        assert!(!pace.skipping());
    }

    #[test]
    fn the_settings_always_go_through() {
        let start = Instant::now();
        let mut pace = Pace::new(start);
        assert!(!pace.next(900_000, Piece::Change, start).send);
        assert!(pace.next(900_000, Piece::Settings, start).send);
        // But they are no place to start again from.
        assert!(pace.next(0, Piece::Settings, start).send);
        assert!(pace.skipping());
    }

    #[test]
    fn the_bitrate_stops_at_the_least_and_comes_back_when_things_go_well() {
        let start = Instant::now();
        let at = |ms: u64| start + Duration::from_millis(ms);
        let mut pace = Pace::new(start);
        let mut now = 0;
        // Trouble again and again: down to the least, never below.
        for _ in 0..8 {
            pace.next(10_000_000, Piece::Change, at(now));
            pace.next(0, Piece::Key, at(now + 10));
            now += 100;
        }
        assert_eq!(pace.bitrate(), LOW_BITRATE);
        // Going well: nothing changes at once...
        assert_eq!(pace.next(5_000, Piece::Change, at(now + 1_000)).bitrate, None);
        // ...but after a while a better picture is tried, step by step.
        assert_eq!(pace.next(5_000, Piece::Change, at(now + 9_000)).bitrate, Some(625_000));
        assert_eq!(pace.next(5_000, Piece::Change, at(now + 10_000)).bitrate, None);
        assert_eq!(pace.next(5_000, Piece::Change, at(now + 17_500)).bitrate, Some(781_250));
        let mut later = now + 17_500;
        while pace.bitrate() < TOP_BITRATE {
            later += 8_000;
            pace.next(5_000, Piece::Change, at(later));
        }
        assert_eq!(pace.bitrate(), TOP_BITRATE);
        assert_eq!(pace.next(5_000, Piece::Change, at(later + 60_000)).bitrate, None);
    }
}
