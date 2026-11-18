//! Cutting a stream of AAC with ADTS headers into its frames.
//!
//! The computer's sound arrives in whatever pieces the network makes of
//! it; the phone's decoder wants one frame at a time, without the header.

/// A frame is never bigger than this (the header's length field is 13 bits).
const MAX_FRAME: usize = 8191;

/// Takes the stream as it arrives and gives out whole frames.
#[derive(Default)]
pub struct Frames {
    held: Vec<u8>,
}

impl Frames {
    /// The frames completed by this piece, each without its header.
    pub fn feed(&mut self, piece: &[u8]) -> Vec<Vec<u8>> {
        self.held.extend_from_slice(piece);
        let mut frames = Vec::new();
        let mut at = 0;
        loop {
            let rest = &self.held[at..];
            // A header begins with twelve set bits.
            let Some(start) = rest.windows(2).position(|pair| pair[0] == 0xFF && pair[1] & 0xF6 == 0xF0) else {
                // None here; a lone 0xFF at the very end may be the start of one.
                at = self.held.len() - usize::from(rest.last() == Some(&0xFF));
                break;
            };
            at += start;
            let header = &self.held[at..];
            if header.len() < 7 {
                break;
            }
            // A header without a checksum is 7 bytes long, one with is 9.
            let header_bytes = if header[1] & 1 == 1 { 7 } else { 9 };
            let length = (usize::from(header[3] & 0x03) << 11) | (usize::from(header[4]) << 3) | usize::from(header[5] >> 5);
            if length <= header_bytes || length > MAX_FRAME {
                // Not a header after all: look further on.
                at += 1;
                continue;
            }
            if header.len() < length {
                break;
            }
            frames.push(header[header_bytes..length].to_vec());
            at += length;
        }
        self.held.drain(..at);
        frames
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A frame as an encoder writes it: AAC-LC, 48 kHz, two channels.
    fn framed(payload: &[u8]) -> Vec<u8> {
        let length = payload.len() + 7;
        let mut out = vec![0xFF, 0xF1, 0x4C, 0x80 | (length >> 11) as u8, (length >> 3) as u8, ((length & 7) << 5) as u8 | 0x1F, 0xFC];
        out.extend_from_slice(payload);
        out
    }

    #[test]
    fn frames_come_out_whole_however_the_stream_is_cut() {
        let payloads: Vec<Vec<u8>> = (0..6u8).map(|i| (0..(40 + usize::from(i) * 13)).map(|b| (b as u8).wrapping_mul(i + 3)).collect()).collect();
        let stream: Vec<u8> = payloads.iter().flat_map(|p| framed(p)).collect();
        for cut in [1, 2, 6, 7, 8, 50, 1000] {
            let mut frames = Frames::default();
            let got: Vec<Vec<u8>> = stream.chunks(cut).flat_map(|piece| frames.feed(piece)).collect();
            assert_eq!(got, payloads, "pieces of {cut}");
        }
    }

    #[test]
    fn a_stream_joined_in_the_middle_finds_its_feet() {
        let (first, second) = (vec![7u8; 60], vec![9u8; 80]);
        // The tail of a frame whose beginning was missed, then two whole ones.
        let mut stream = vec![0x12, 0x34, 0xFF, 0x00, 0x56];
        stream.extend(framed(&first));
        stream.extend(framed(&second));
        assert_eq!(Frames::default().feed(&stream), [first, second]);
    }

    #[test]
    fn nonsense_gives_nothing_and_does_not_pile_up() {
        let mut frames = Frames::default();
        for _ in 0..100 {
            assert!(frames.feed(&[0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77]).is_empty());
        }
        assert!(frames.held.len() < 16, "kept {}", frames.held.len());
        // Bytes that look like a header but give an impossible length are passed over.
        assert!(frames.feed(&[0xFF, 0xF1, 0x4C, 0x80, 0x00, 0x1F, 0xFC, 0x00]).is_empty());
    }

    #[test]
    fn a_frame_with_a_checksum_loses_its_longer_header() {
        // Protection present: nine header bytes.
        let payload = [5u8; 30];
        let length = payload.len() + 9;
        let mut stream = vec![0xFF, 0xF0, 0x4C, 0x80 | (length >> 11) as u8, (length >> 3) as u8, ((length & 7) << 5) as u8 | 0x1F, 0xFC, 0xAB, 0xCD];
        stream.extend_from_slice(&payload);
        assert_eq!(Frames::default().feed(&stream), [payload.to_vec()]);
    }
}
