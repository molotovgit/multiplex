//! Just enough of H.264 to know the size of the picture in a stream: the
//! window showing a phone's screen takes the picture's shape when the
//! phone is turned.

/// Reads bits, most significant first, and the codes H.264 writes its
/// settings in.
struct Bits<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl Bits<'_> {
    fn bit(&mut self) -> Option<u32> {
        let byte = *self.bytes.get(self.at / 8)?;
        let bit = (byte >> (7 - self.at % 8)) & 1;
        self.at += 1;
        Some(u32::from(bit))
    }

    fn bits(&mut self, count: u32) -> Option<u32> {
        let mut value = 0;
        for _ in 0..count {
            value = (value << 1) | self.bit()?;
        }
        Some(value)
    }

    /// An unsigned Exp-Golomb code.
    fn ue(&mut self) -> Option<u32> {
        let mut zeros = 0;
        while self.bit()? == 0 {
            zeros += 1;
            if zeros > 31 {
                return None;
            }
        }
        Some((1u32 << zeros) - 1 + self.bits(zeros)?)
    }

    /// A signed Exp-Golomb code.
    fn se(&mut self) -> Option<i32> {
        let code = self.ue()?;
        let half = i32::try_from(code.div_ceil(2)).ok()?;
        Some(if code % 2 == 1 { half } else { -half })
    }
}

/// The bytes as they were before the "this is not a start code" byte was
/// put in (00 00 03 stands for 00 00).
fn unescaped(payload: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(payload.len());
    let mut zeros = 0;
    for &byte in payload {
        if zeros >= 2 && byte == 3 {
            zeros = 0;
            continue;
        }
        zeros = if byte == 0 { zeros + 1 } else { 0 };
        out.push(byte);
    }
    out
}

/// The picture's width and height from a stream's settings (a sequence
/// parameter set, without its start code and first byte).
pub fn picture_size(settings: &[u8]) -> Option<(u32, u32)> {
    let bytes = unescaped(settings);
    let mut read = Bits { bytes: &bytes, at: 0 };
    let profile = read.bits(8)?;
    read.bits(16)?; // what it promises, and the level
    read.ue()?; // which settings these are
    let mut chroma = 1;
    if [100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135].contains(&profile) {
        chroma = read.ue()?;
        if chroma == 3 {
            read.bit()?;
        }
        read.ue()?;
        read.ue()?;
        read.bit()?;
        if read.bit()? == 1 {
            // Scaling lists: read past them.
            for list in 0..(if chroma == 3 { 12 } else { 8 }) {
                if read.bit()? == 1 {
                    let (mut last, mut next) = (8i32, 8i32);
                    for _ in 0..(if list < 6 { 16 } else { 64 }) {
                        if next != 0 {
                            next = (last + read.se()?).rem_euclid(256);
                        }
                        if next != 0 {
                            last = next;
                        }
                    }
                }
            }
        }
    }
    read.ue()?;
    match read.ue()? {
        0 => {
            read.ue()?;
        }
        1 => {
            read.bit()?;
            read.se()?;
            read.se()?;
            for _ in 0..read.ue()?.min(255) {
                read.se()?;
            }
        }
        _ => {}
    }
    read.ue()?; // pictures to keep
    read.bit()?;
    let wide = read.ue()?.checked_add(1)?;
    let high = read.ue()?.checked_add(1)?;
    let whole_frames = read.bit()?;
    if whole_frames == 0 {
        read.bit()?;
    }
    read.bit()?;
    let (mut left, mut right, mut top, mut bottom) = (0, 0, 0, 0);
    if read.bit()? == 1 {
        (left, right, top, bottom) = (read.ue()?, read.ue()?, read.ue()?, read.ue()?);
    }
    // The picture is coded in blocks of 16; what is cut off its edges is
    // counted in units that depend on the colour layout.
    let (unit_x, unit_y) = match chroma {
        1 => (2, 2 * (2 - whole_frames)),
        2 => (2, 2 - whole_frames),
        _ => (1, 2 - whole_frames),
    };
    let width = wide.checked_mul(16)?.checked_sub(left.checked_add(right)?.checked_mul(unit_x)?)?;
    let height = high.checked_mul(16 * (2 - whole_frames))?.checked_sub(top.checked_add(bottom)?.checked_mul(unit_y)?)?;
    ((16..=16_384).contains(&width) && (16..=16_384).contains(&height)).then_some((width, height))
}

/// Watches a stream go by, in whatever pieces it comes, and says the
/// picture's size each time the stream states it.
#[derive(Default)]
pub struct SizeWatch {
    zeros: usize,
    /// The byte after a start code says what follows.
    kind_next: bool,
    /// The settings being read, when inside them.
    settings: Option<Vec<u8>>,
}

impl SizeWatch {
    /// The sizes stated in this piece, in order (none, nearly always).
    pub fn feed(&mut self, piece: &[u8]) -> Vec<(u32, u32)> {
        let mut found = Vec::new();
        for &byte in piece {
            if byte == 1 && self.zeros >= 2 {
                // A start code: whatever was being read ends before it.
                if let Some(mut settings) = self.settings.take() {
                    while settings.last() == Some(&0) {
                        settings.pop();
                    }
                    found.extend(picture_size(&settings));
                }
                self.kind_next = true;
                self.zeros = 0;
                continue;
            }
            if self.kind_next {
                self.kind_next = false;
                if byte & 0x1F == 7 {
                    self.settings = Some(Vec::new());
                }
            } else if let Some(settings) = &mut self.settings {
                settings.push(byte);
                // Settings are a few dozen bytes: this is something else.
                if settings.len() > 1024 {
                    self.settings = None;
                }
            }
            self.zeros = if byte == 0 { self.zeros + 1 } else { 0 };
        }
        found
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Settings as x264 wrote them for pictures of these sizes.
    const TALL: [u8; 24] = [0xF4, 0x00, 0x20, 0x91, 0x96, 0x80, 0xB8, 0x0C, 0x9B, 0x01, 0x10, 0x00, 0x00, 0x03, 0x00, 0x10, 0x00, 0x00, 0x03, 0x03, 0xC8, 0xF1, 0x83, 0x2A];
    const WIDE: [u8; 24] = [0xF4, 0x00, 0x20, 0x91, 0x96, 0x80, 0x64, 0x05, 0xDB, 0x01, 0x10, 0x00, 0x00, 0x03, 0x00, 0x10, 0x00, 0x00, 0x03, 0x03, 0xC8, 0xF1, 0x83, 0x2A];
    // Sizes that are not whole blocks of 16: part of the coded picture is cut off.
    const PHONE: [u8; 27] = [
        0x64, 0x00, 0x32, 0xAC, 0xD9, 0x40, 0x44, 0x01, 0x27, 0xE5, 0x9F, 0x01, 0x10, 0x00, 0x00, 0x03, 0x00, 0x10, 0x00, 0x00, 0x03, 0x03, 0xC0, 0xF1, 0x83, 0x19, 0x60,
    ];
    const FULL_HD: [u8; 25] = [0x4D, 0x40, 0x28, 0xEC, 0xA0, 0x3C, 0x01, 0x13, 0xF2, 0xE0, 0x22, 0x00, 0x00, 0x03, 0x00, 0x02, 0x00, 0x00, 0x03, 0x00, 0x78, 0x1E, 0x30, 0x63, 0x2C];

    #[test]
    fn the_size_is_read_from_the_settings() {
        assert_eq!(picture_size(&TALL), Some((736, 1600)));
        assert_eq!(picture_size(&WIDE), Some((1600, 736)));
        assert_eq!(picture_size(&PHONE), Some((1080, 2340)));
        assert_eq!(picture_size(&FULL_HD), Some((1920, 1080)));
    }

    #[test]
    fn nonsense_has_no_size() {
        assert_eq!(picture_size(&[]), None);
        assert_eq!(picture_size(&[0x42]), None);
        assert_eq!(picture_size(&TALL[..6]), None, "cut short");
        assert_eq!(picture_size(&[0x00; 40]), None);
        // Anything at all is read without a panic.
        for seed in 0..=255u8 {
            let noise: Vec<u8> = (0..48u8).map(|i| seed.wrapping_mul(31).wrapping_add(i.wrapping_mul(seed | 1))).collect();
            let _ = picture_size(&noise);
        }
    }

    fn stream(settings: &[u8]) -> Vec<u8> {
        // Settings, more settings, a picture: as a key picture arrives.
        [&[0, 0, 0, 1, 0x67][..], settings, &[0, 0, 0, 1, 0x68, 0xCE, 0x3C, 0x80], &[0, 0, 1, 0x65, 0x88, 0x84, 0x00, 0x10]].concat()
    }

    #[test]
    fn a_stream_is_watched_in_whatever_pieces_it_comes() {
        let bytes = [stream(&TALL), vec![0, 0, 0, 1, 0x41, 0x9A, 0x00, 0x00, 0x7F], stream(&WIDE)].concat();
        // All at once.
        assert_eq!(SizeWatch::default().feed(&bytes), [(736, 1600), (1600, 736)]);
        // Cut anywhere, also inside a start code or the settings.
        for cut in [1, 2, 3, 5, 7, 64] {
            let mut watch = SizeWatch::default();
            let found: Vec<_> = bytes.chunks(cut).flat_map(|piece| watch.feed(piece)).collect();
            assert_eq!(found, [(736, 1600), (1600, 736)], "pieces of {cut}");
        }
    }

    #[test]
    fn pictures_without_settings_say_nothing() {
        let mut watch = SizeWatch::default();
        assert!(watch.feed(&[0, 0, 0, 1, 0x41, 0x9A, 0x12, 0x34, 0, 0, 0, 1, 9, 0xF0]).is_empty());
        assert!(watch.feed(&[0xAB; 5000]).is_empty());
    }
}
