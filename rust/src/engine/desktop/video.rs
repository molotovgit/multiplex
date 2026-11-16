//! Where encoded pictures go: the platform's hardware decoder.
//!
//! The session hands every H.264 picture to a [`VideoSink`] and never waits
//! for it. The sink reports back through a channel what it did with each
//! picture ([`VideoReport`]); those reports become the frame acks the
//! server paces its stream by, so a slow decoder slows the stream down
//! instead of building a queue.

use std::time::{Duration, Instant};

use bytes::Bytes;
use tokio::sync::mpsc;

/// One encoded picture (Annex-B H.264; SPS and PPS ride along with every
/// keyframe).
pub struct EncodedFrame {
    pub id: u64,
    pub keyframe: bool,
    pub data: Bytes,
    /// When it came off the network.
    pub arrived: Instant,
}

/// What the decoder did with a picture.
#[derive(Debug, PartialEq)]
pub enum VideoReport {
    /// On screen, `latency` after it arrived.
    Shown { id: u64, latency: Duration },
    /// Not shown (no surface yet, or waiting for a keyframe).
    Skipped { id: u64 },
    /// The decoder lost its place; the next picture must be a keyframe.
    NeedKeyframe,
}

/// A video decoder that draws onto the app's view.
pub trait VideoSink: Send + Sync {
    /// The stream's size changed (or was set for the first time).
    fn configure(&self, width: u32, height: u32);
    /// Decode and show this picture. Must not block.
    fn submit(&self, frame: EncodedFrame);
    /// The session ended; release the decoder.
    fn close(&self);
}

/// Makes the decoder for a session drawing into `texture_id`.
pub fn create(texture_id: i64, reports: mpsc::UnboundedSender<VideoReport>) -> Box<dyn VideoSink> {
    #[cfg(target_os = "android")]
    {
        Box::new(super::android::AndroidDecoder::start(texture_id, reports))
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = texture_id;
        Box::new(CountingSink { reports })
    }
}

/// Stands in for a decoder where there is none (desktop builds, tests):
/// reports every picture as shown at once.
pub struct CountingSink {
    pub reports: mpsc::UnboundedSender<VideoReport>,
}

impl VideoSink for CountingSink {
    fn configure(&self, _width: u32, _height: u32) {}

    fn submit(&self, frame: EncodedFrame) {
        let _ = self.reports.send(VideoReport::Shown { id: frame.id, latency: frame.arrived.elapsed() });
    }

    fn close(&self) {}
}
