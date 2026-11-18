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

/// Where it starts: low enough for a slow connection not to choke on the
/// first seconds; a fast one is at the top a few seconds later.
pub const START_BITRATE: u32 = 1_500_000;

/// The least: below this the picture is not readable any more.
pub const LOW_BITRATE: u32 = 500_000;

/// This much of the picture on its way (in seconds of it) is too late:
/// skip ahead.
const LATE: f64 = 1.0;

/// This much is a warning: ask less of the connection, keep sending.
const SLOW: f64 = 0.6;

/// As little as this, and the connection could carry more.
const CALM: f64 = 0.35;

/// As little on its way as this (in bytes) counts as caught up.
const CAUGHT_UP: u64 = 16 * 1024;

/// While nothing has gone wrong yet, a better picture is tried this often
/// (a third more each time: bigger steps overshoot a slow connection so
/// far that it comes to skipping before the warning can help).
const CLIMB_EVERY: Duration = Duration::from_secs(2);

/// After trouble, this often, and in small steps.
const RAISE_AFTER: Duration = Duration::from_secs(8);

/// The bitrate that caused trouble is stayed under for this long, so the
/// picture does not run into the same wall every few seconds.
const REMEMBER: Duration = Duration::from_secs(60);

/// The bitrate is lowered as a warning at most this often.
const EASE_EVERY: Duration = Duration::from_secs(2);

/// A fresh full picture is asked for at most this often.
const ASK_EVERY: Duration = Duration::from_secs(1);

/// The first pictures go out in a burst (they were kept while the other
/// end opened): for this long that is not taken for a warning.
const SETTLING: Duration = Duration::from_secs(2);

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
    began: Instant,
    bitrate: u32,
    skipping: bool,
    /// When the bitrate last changed, or skipping last ended.
    settled: Instant,
    asked: Option<Instant>,
    eased: Option<Instant>,
    /// The bitrate that last proved too much, and when.
    trouble: Option<(u32, Instant)>,
    /// There has been trouble at some point: from then on, small steps.
    troubled: bool,
    skipped: u64,
}

impl Pace {
    pub fn new(now: Instant) -> Self {
        Self { began: now, bitrate: START_BITRATE, skipping: false, settled: now, asked: None, eased: None, trouble: None, troubled: false, skipped: 0 }
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

    /// Lowers the bitrate to `part` of what it is (never under the least)
    /// and notes that the old one was too much. The new one, if it changed.
    fn lower(&mut self, numerator: u32, denominator: u32, now: Instant) -> Option<u32> {
        self.trouble = Some((self.bitrate, now));
        self.troubled = true;
        let lower = (self.bitrate / denominator * numerator).max(LOW_BITRATE);
        let changed = (lower != self.bitrate).then_some(lower);
        self.bitrate = lower;
        self.settled = now;
        changed
    }

    fn decide(&mut self, in_flight: u64, piece: Piece, now: Instant) -> Step {
        // The settings are tiny and a player cannot do without them.
        let send_anyway = piece == Piece::Settings;
        if self.skipping {
            // Wait until what was under way has arrived, then start again
            // from a full picture.
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
            return Step { send: send_anyway, bitrate: None, key_frame: ask };
        }

        let seconds_behind = in_flight as f64 * 8.0 / f64::from(self.bitrate);
        if seconds_behind > LATE {
            self.skipping = true;
            self.asked = None;
            let bitrate = self.lower(3, 5, now);
            return Step { send: send_anyway, bitrate, key_frame: false };
        }
        if seconds_behind > SLOW {
            // A warning: ask less before it comes to skipping.
            if now.duration_since(self.began) >= SETTLING && self.eased.is_none_or(|at| now.duration_since(at) >= EASE_EVERY) {
                self.eased = Some(now);
                let bitrate = self.lower(4, 5, now);
                return Step { send: true, bitrate, key_frame: false };
            }
            return Step { send: true, ..Step::default() };
        }
        if seconds_behind < CALM && self.bitrate < TOP_BITRATE {
            if self.trouble.is_some_and(|(_, at)| now.duration_since(at) >= REMEMBER) {
                self.trouble = None;
            }
            let (wait, wanted) = if self.troubled { (RAISE_AFTER, self.bitrate / 8 * 9) } else { (CLIMB_EVERY, self.bitrate / 3 * 4) };
            let most = self.trouble.map_or(TOP_BITRATE, |(too_much, _)| too_much / 10 * 9);
            let next = wanted.min(most).min(TOP_BITRATE);
            if next > self.bitrate && now.duration_since(self.settled) >= wait {
                self.bitrate = next;
                self.settled = now;
                return Step { send: true, bitrate: Some(next), key_frame: false };
            }
        }
        Step { send: true, ..Step::default() }
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
    fn a_connection_that_keeps_up_is_at_the_best_bitrate_within_seconds() {
        let start = Instant::now();
        let mut pace = Pace::new(start);
        let mut changes = Vec::new();
        for i in 0..600u64 {
            // A fifth of a second of picture on its way: ordinary.
            let on_its_way = u64::from(pace.bitrate()) / 8 / 5;
            let step = pace.next(on_its_way, if i % 60 == 0 { Piece::Key } else { Piece::Change }, start + Duration::from_millis(i * 33));
            assert!(step.send && !step.key_frame);
            changes.extend(step.bitrate.map(|b| (i * 33 / 1000, b)));
        }
        // From the start value to the top in four steps, two seconds apart.
        assert_eq!(changes, [(2, 2_000_000), (4, 2_666_664), (6, 3_555_552), (8, TOP_BITRATE)]);
        assert_eq!(pace.skipped(), 0);
    }

    #[test]
    fn falling_behind_skips_ahead_to_a_full_picture_at_a_lower_bitrate() {
        let start = Instant::now();
        let at = |ms: u64| start + Duration::from_millis(ms);
        let mut pace = Pace::new(start);
        // More than a second of picture on its way: too late.
        let step = pace.next(300_000, Piece::Change, at(0));
        assert_eq!(step, Step { send: false, bitrate: Some(900_000), key_frame: false });
        // While it is still arriving, nothing more is added, not even a full picture.
        assert!(!pace.next(200_000, Piece::Change, at(100)).send);
        assert!(!pace.next(100_000, Piece::Key, at(200)).send);
        // It has arrived: ask for a full picture, once, and wait for it.
        assert_eq!(pace.next(2_000, Piece::Change, at(300)), Step { send: false, bitrate: None, key_frame: true });
        assert_eq!(pace.next(2_000, Piece::Change, at(333)), Step { send: false, bitrate: None, key_frame: false });
        // Still none a second later: ask again.
        assert!(pace.next(2_000, Piece::Change, at(1_400)).key_frame);
        // There it is: carry on from it.
        assert_eq!(pace.next(2_000, Piece::Key, at(1_450)), Step { send: true, bitrate: None, key_frame: false });
        assert!(pace.next(20_000, Piece::Change, at(1_480)).send);
        assert_eq!(pace.skipped(), 6);
        assert!(!pace.skipping());
    }

    #[test]
    fn a_warning_lowers_the_bitrate_without_skipping() {
        let start = Instant::now();
        // (Past the first two seconds, whose burst is not a warning.)
        let at = |ms: u64| start + Duration::from_millis(10_000 + ms);
        let mut pace = Pace::new(start);
        // 0.7 s of picture on its way: not yet too late, but more than it should be.
        let warning = u64::from(START_BITRATE) / 8 * 7 / 10;
        assert_eq!(pace.next(warning, Piece::Change, at(0)), Step { send: true, bitrate: Some(1_200_000), key_frame: false });
        // Not again at once, even if it has not got better yet.
        assert_eq!(pace.next(140_000, Piece::Change, at(500)), Step { send: true, bitrate: None, key_frame: false });
        // Still so two seconds later: once more.
        assert_eq!(pace.next(120_000, Piece::Change, at(2_100)), Step { send: true, bitrate: Some(960_000), key_frame: false });
        assert_eq!(pace.skipped(), 0);
    }

    #[test]
    fn the_burst_of_the_first_pictures_is_not_a_warning() {
        let start = Instant::now();
        let mut pace = Pace::new(start);
        let burst = u64::from(START_BITRATE) / 8 * 7 / 10;
        assert_eq!(pace.next(burst, Piece::Key, start + Duration::from_millis(300)), Step { send: true, bitrate: None, key_frame: false });
        assert_eq!(pace.bitrate(), START_BITRATE);
        // Far too much on its way is still skipped, also then.
        assert!(!pace.next(u64::from(START_BITRATE), Piece::Change, start + Duration::from_millis(600)).send);
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
    fn the_bitrate_that_caused_trouble_is_stayed_under_for_a_while() {
        let start = Instant::now();
        let at = |ms: u64| start + Duration::from_millis(ms);
        let mut pace = Pace::new(start);
        // Up to 2.67 Mbit/s without trouble, then a skip there.
        pace.next(5_000, Piece::Change, at(2_000));
        pace.next(5_000, Piece::Change, at(4_000));
        assert_eq!(pace.bitrate(), 2_666_664);
        pace.next(600_000, Piece::Change, at(5_000));
        pace.next(0, Piece::Key, at(5_500));
        assert_eq!(pace.bitrate(), 1_599_996);
        // From now on small steps, eight seconds apart...
        assert_eq!(pace.next(5_000, Piece::Change, at(7_600)).bitrate, None);
        assert_eq!(pace.next(5_000, Piece::Change, at(13_500)).bitrate, Some(1_799_991));
        // ...and never back to what was too much, only to nine tenths of it.
        let mut now = 13_500;
        let mut most = 0;
        while now < 60_000 {
            now += 8_000;
            pace.next(5_000, Piece::Change, at(now));
            most = most.max(pace.bitrate());
        }
        assert_eq!(most, 2_399_994);
        // A minute after the trouble it may try higher again.
        pace.next(5_000, Piece::Change, at(70_000));
        assert!(pace.bitrate() > 2_399_994);
        let mut later = 70_000;
        while pace.bitrate() < TOP_BITRATE {
            later += 8_000;
            pace.next(5_000, Piece::Change, at(later));
        }
        assert_eq!(pace.next(5_000, Piece::Change, at(later + 60_000)).bitrate, None);
    }

    #[test]
    fn the_bitrate_never_goes_under_the_least() {
        let start = Instant::now();
        let mut pace = Pace::new(start);
        for i in 0..12u64 {
            pace.next(10_000_000, Piece::Change, start + Duration::from_millis(i * 100));
            pace.next(0, Piece::Key, start + Duration::from_millis(i * 100 + 10));
        }
        assert_eq!(pace.bitrate(), LOW_BITRATE);
    }
}
