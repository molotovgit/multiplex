//! Small H.264 fix-ups applied before pictures reach the phone's decoder.
//!
//! gliff's GPU encoder writes its sequence header (SPS) without "VUI"
//! information. Without it a decoder must assume pictures may arrive out of
//! order and holds up to 16 of them back before showing any: on Qualcomm
//! phones that is half a second of delay, and a still screen may not show
//! its last change at all. It also has to guess the colours.
//!
//! [`low_latency_sps`] adds the VUI the stream really has: no reordering
//! (gliff sends only I and P pictures, never B), one picture of buffering,
//! and BT.709 limited-range colour. Game-streaming clients do the same.
//! Anything it does not fully understand is passed through unchanged.

/// Rewrites every SPS in an Annex-B access unit; other NAL units are
/// copied as they are. Returns the input when there is nothing to change.
pub fn low_latency_sps(data: &[u8]) -> Option<Vec<u8>> {
    let nals = split_annex_b(data);
    if !nals.iter().any(|n| n.first().is_some_and(|h| h & 0x1f == 7)) {
        return None;
    }
    let mut out = Vec::with_capacity(data.len() + 32);
    let mut changed = false;
    for nal in nals {
        out.extend_from_slice(&[0, 0, 0, 1]);
        match (nal.first().map(|h| h & 0x1f), rewrite_sps(nal)) {
            (Some(7), Some(new)) => {
                out.extend_from_slice(&new);
                changed = true;
            }
            _ => out.extend_from_slice(nal),
        }
    }
    changed.then_some(out)
}

/// The NAL units of an Annex-B stream (start codes removed).
fn split_annex_b(data: &[u8]) -> Vec<&[u8]> {
    let mut starts = Vec::new();
    let mut i = 0;
    while i + 3 <= data.len() {
        if data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1 {
            starts.push(i + 3);
            i += 3;
        } else {
            i += 1;
        }
    }
    let mut nals = Vec::with_capacity(starts.len());
    for (k, &s) in starts.iter().enumerate() {
        let mut end = if k + 1 < starts.len() { starts[k + 1] - 3 } else { data.len() };
        // A 4-byte start code leaves one zero byte behind.
        while end > s && data[end - 1] == 0 && k + 1 < starts.len() {
            end -= 1;
        }
        nals.push(&data[s..end]);
    }
    nals
}

/// The SPS (header byte included) with a low-latency VUI, or None to
/// leave it alone (it already has a VUI, or uses features we do not parse).
fn rewrite_sps(nal: &[u8]) -> Option<Vec<u8>> {
    let header = *nal.first()?;
    let rbsp = unescape(&nal[1..]);
    let mut r = BitReader::new(&rbsp);
    let mut w = BitWriter::default();

    let profile_idc = r.copy(&mut w, 8)?;
    r.copy(&mut w, 8)?; // constraint flags
    r.copy(&mut w, 8)?; // level_idc
    r.copy_ue(&mut w)?; // seq_parameter_set_id
    if matches!(profile_idc, 100 | 110 | 122 | 244 | 44 | 83 | 86 | 118 | 128 | 138 | 139 | 134 | 135) {
        let chroma = r.copy_ue(&mut w)?;
        if chroma == 3 {
            r.copy(&mut w, 1)?; // separate_colour_plane_flag
        }
        r.copy_ue(&mut w)?; // bit_depth_luma_minus8
        r.copy_ue(&mut w)?; // bit_depth_chroma_minus8
        r.copy(&mut w, 1)?; // qpprime_y_zero_transform_bypass_flag
        if r.copy(&mut w, 1)? == 1 {
            return None; // scaling matrices: not worth parsing
        }
    }
    r.copy_ue(&mut w)?; // log2_max_frame_num_minus4
    match r.copy_ue(&mut w)? {
        0 => {
            r.copy_ue(&mut w)?; // log2_max_pic_order_cnt_lsb_minus4
        }
        1 => return None,
        _ => {}
    }
    let max_refs = r.copy_ue(&mut w)?;
    r.copy(&mut w, 1)?; // gaps_in_frame_num_value_allowed_flag
    r.copy_ue(&mut w)?; // pic_width_in_mbs_minus1
    r.copy_ue(&mut w)?; // pic_height_in_map_units_minus1
    if r.copy(&mut w, 1)? == 0 {
        r.copy(&mut w, 1)?; // mb_adaptive_frame_field_flag
    }
    r.copy(&mut w, 1)?; // direct_8x8_inference_flag
    if r.copy(&mut w, 1)? == 1 {
        for _ in 0..4 {
            r.copy_ue(&mut w)?; // frame_crop_*_offset
        }
    }
    if r.bits(1)? == 1 {
        return None; // a VUI is already there; trust it
    }

    w.bit(1); // vui_parameters_present_flag
    w.bit(0); // aspect_ratio_info_present_flag
    w.bit(0); // overscan_info_present_flag
    w.bit(1); // video_signal_type_present_flag
    w.bits(5, 3); // video_format: unspecified
    w.bit(0); // video_full_range_flag: limited, as gliff encodes
    w.bit(1); // colour_description_present_flag
    w.bits(1, 8); // colour_primaries: BT.709
    w.bits(1, 8); // transfer_characteristics: BT.709
    w.bits(1, 8); // matrix_coefficients: BT.709
    w.bit(0); // chroma_loc_info_present_flag
    w.bit(0); // timing_info_present_flag
    w.bit(0); // nal_hrd_parameters_present_flag
    w.bit(0); // vcl_hrd_parameters_present_flag
    w.bit(0); // pic_struct_present_flag
    w.bit(1); // bitstream_restriction_flag
    w.bit(1); // motion_vectors_over_pic_boundaries_flag
    w.ue(0); // max_bytes_per_pic_denom
    w.ue(0); // max_bits_per_mb_denom
    w.ue(16); // log2_max_mv_length_horizontal
    w.ue(16); // log2_max_mv_length_vertical
    w.ue(0); // max_num_reorder_frames: show each picture at once
    w.ue(max_refs.max(1)); // max_dec_frame_buffering
    w.bit(1); // rbsp_stop_one_bit
    let mut out = vec![header];
    out.extend_from_slice(&escape(&w.finish()));
    Some(out)
}

/// Removes emulation-prevention bytes (00 00 03 -> 00 00).
fn unescape(data: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(data.len());
    let mut zeros = 0;
    for &b in data {
        if zeros >= 2 && b == 3 {
            zeros = 0;
            continue;
        }
        zeros = if b == 0 { zeros + 1 } else { 0 };
        out.push(b);
    }
    out
}

/// Adds emulation-prevention bytes where the payload would look like a
/// start code.
fn escape(data: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(data.len() + 4);
    let mut zeros = 0;
    for &b in data {
        if zeros >= 2 && b <= 3 {
            out.push(3);
            zeros = 0;
        }
        zeros = if b == 0 { zeros + 1 } else { 0 };
        out.push(b);
    }
    out
}

struct BitReader<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> BitReader<'a> {
    fn new(data: &'a [u8]) -> Self {
        Self { data, pos: 0 }
    }

    fn bits(&mut self, n: u32) -> Option<u32> {
        let mut v = 0u32;
        for _ in 0..n {
            let byte = *self.data.get(self.pos / 8)?;
            v = (v << 1) | u32::from((byte >> (7 - self.pos % 8)) & 1);
            self.pos += 1;
        }
        Some(v)
    }

    fn ue(&mut self) -> Option<u32> {
        let mut zeros = 0;
        while self.bits(1)? == 0 {
            zeros += 1;
            if zeros > 31 {
                return None;
            }
        }
        Some(((1u64 << zeros) - 1 + u64::from(self.bits(zeros)?)) as u32)
    }

    /// Reads `n` bits and writes them unchanged.
    fn copy(&mut self, w: &mut BitWriter, n: u32) -> Option<u32> {
        let v = self.bits(n)?;
        w.bits(v, n);
        Some(v)
    }

    fn copy_ue(&mut self, w: &mut BitWriter) -> Option<u32> {
        let v = self.ue()?;
        w.ue(v);
        Some(v)
    }
}

#[derive(Default)]
struct BitWriter {
    out: Vec<u8>,
    cur: u8,
    n: u8,
}

impl BitWriter {
    fn bit(&mut self, b: u32) {
        self.cur = (self.cur << 1) | (b & 1) as u8;
        self.n += 1;
        if self.n == 8 {
            self.out.push(self.cur);
            self.cur = 0;
            self.n = 0;
        }
    }

    fn bits(&mut self, v: u32, n: u32) {
        for i in (0..n).rev() {
            self.bit((v >> i) & 1);
        }
    }

    fn ue(&mut self, v: u32) {
        let x = u64::from(v) + 1;
        let len = 64 - x.leading_zeros();
        for _ in 0..len - 1 {
            self.bit(0);
        }
        for i in (0..len).rev() {
            self.bit(((x >> i) & 1) as u32);
        }
    }

    /// Pads with zero bits to a whole byte (after the stop bit).
    fn finish(mut self) -> Vec<u8> {
        while self.n != 0 {
            self.bit(0);
        }
        self.out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A High-profile 1920x1080 SPS like gliff's GPU encoder writes:
    /// POC type 0, one reference, cropping 1088 -> 1080, no VUI.
    fn gliff_like_sps() -> Vec<u8> {
        let mut w = BitWriter::default();
        w.bits(100, 8); // profile_idc High
        w.bits(0, 8);
        w.bits(51, 8); // level 5.1
        w.ue(0); // sps id
        w.ue(1); // chroma 4:2:0
        w.ue(0);
        w.ue(0);
        w.bit(0);
        w.bit(0); // no scaling matrix
        w.ue(4); // log2_max_frame_num_minus4
        w.ue(0); // poc type 0
        w.ue(4); // log2_max_poc_lsb_minus4
        w.ue(1); // max_num_ref_frames
        w.bit(0);
        w.ue(119); // 1920 / 16 - 1
        w.ue(67); // 1088 / 16 - 1
        w.bit(1); // frame_mbs_only
        w.bit(1); // direct_8x8
        w.bit(1); // cropping
        w.ue(0);
        w.ue(0);
        w.ue(0);
        w.ue(4); // bottom: 8 rows
        w.bit(0); // no VUI
        w.bit(1); // stop bit
        let mut nal = vec![0x67];
        nal.extend(escape(&w.finish()));
        nal
    }

    fn annex_b(nals: &[&[u8]]) -> Vec<u8> {
        nals.iter().flat_map(|n| [&[0u8, 0, 0, 1][..], n].concat()).collect()
    }

    /// Reads back the VUI's max_num_reorder_frames from a rewritten SPS.
    fn reorder_frames(sps: &[u8]) -> u32 {
        let rbsp = unescape(&sps[1..]);
        let mut r = BitReader::new(&rbsp);
        let mut sink = BitWriter::default();
        // Walk the same fields as rewrite_sps.
        for n in [8, 8, 8] {
            r.copy(&mut sink, n);
        }
        r.ue();
        for _ in 0..3 {
            r.ue();
        }
        r.bits(2);
        r.ue();
        r.ue();
        r.ue();
        r.ue();
        r.bits(1);
        r.ue();
        r.ue();
        r.bits(2);
        assert_eq!(r.bits(1), Some(1), "cropping kept");
        for _ in 0..4 {
            r.ue();
        }
        assert_eq!(r.bits(1), Some(1), "VUI present");
        r.bits(3); // aspect, overscan, signal type
        assert_eq!(r.bits(3), Some(5));
        r.bits(2); // full range, colour description
        assert_eq!(r.bits(8), Some(1), "BT.709 primaries");
        r.bits(16);
        r.bits(5); // chroma loc, timing, hrd x2, pic struct
        assert_eq!(r.bits(1), Some(1), "bitstream restriction");
        r.bits(1);
        for _ in 0..4 {
            r.ue();
        }
        r.ue().unwrap()
    }

    #[test]
    fn adds_a_low_latency_vui_to_gliffs_sps() {
        let sps = gliff_like_sps();
        let pps = [0x68u8, 0xce, 0x3c, 0x80];
        let slice = [0x65u8, 0x88, 0x84, 0x00, 0x33];
        let au = annex_b(&[&sps, &pps, &slice]);
        let out = low_latency_sps(&au).expect("rewritten");
        let nals = split_annex_b(&out);
        assert_eq!(nals.len(), 3);
        assert_eq!(nals[1], &pps[..], "PPS untouched");
        assert_eq!(nals[2], &slice[..], "slice untouched");
        assert_eq!(reorder_frames(nals[0]), 0);
    }

    #[test]
    fn leaves_pictures_without_an_sps_alone() {
        let au = annex_b(&[&[0x41u8, 0x9a, 0x00, 0x10]]);
        assert!(low_latency_sps(&au).is_none());
    }

    #[test]
    fn keeps_an_existing_vui() {
        let mut sps = gliff_like_sps();
        // Flip the VUI flag on: rebuild with vui=1 by re-encoding.
        let rbsp = unescape(&sps[1..]);
        let mut r = BitReader::new(&rbsp);
        let mut w = BitWriter::default();
        // Copy everything up to the VUI flag (same walk as the rewrite).
        let walk = |r: &mut BitReader, w: &mut BitWriter| -> Option<()> {
            for n in [8, 8, 8] {
                r.copy(w, n)?;
            }
            r.copy_ue(w)?;
            for _ in 0..3 {
                r.copy_ue(w)?;
            }
            r.copy(w, 2)?;
            for _ in 0..4 {
                r.copy_ue(w)?;
            }
            r.copy(w, 1)?;
            r.copy_ue(w)?;
            r.copy_ue(w)?;
            r.copy(w, 3)?;
            for _ in 0..4 {
                r.copy_ue(w)?;
            }
            Some(())
        };
        walk(&mut r, &mut w).unwrap();
        w.bit(1); // VUI present
        w.bits(0, 9); // some VUI
        w.bit(1);
        sps = [vec![0x67], escape(&w.finish())].concat();
        assert!(low_latency_sps(&annex_b(&[&sps])).is_none());
    }

    #[test]
    fn escaping_round_trips() {
        let raw = [0u8, 0, 1, 0, 0, 0, 0, 0, 3, 7, 0, 0];
        assert_eq!(unescape(&escape(&raw)), raw);
    }
}
