//! The phone as a loudspeaker of a paired computer: `multiplex speaker`
//! there encodes what is played, this brings the stream to the phone,
//! and Android decodes and plays it.

use std::sync::{Arc, Mutex};

use flutter_rust_bridge::frb;
use multiplex_proto::share::speaker_command;

use super::ssh::SshSession;
use crate::engine::adts::Frames;
use crate::engine::events::EventRelay;
use crate::engine::runtime::AsyncRuntime;
use crate::engine::tap::Tap;
use crate::frb_generated::StreamSink;

impl SshSession {
    /// Gives the computer one more sound output, named after the phone
    /// (`phone`, or empty), whose sound comes here. With `everything` it
    /// becomes the computer's default output while this is open, so all
    /// of its sound is heard on the phone.
    pub async fn open_speaker(&self, phone: String, everything: bool) -> anyhow::Result<SpeakerStream> {
        let conn = self.conn.clone();
        let (sound, ended) = (Arc::new(EventRelay::<Vec<u8>>::new()), Arc::new(EventRelay::<String>::new()));
        let (bytes, over) = (sound.clone(), ended.clone());
        let inner = AsyncRuntime::run(async move { Tap::open(conn, &speaker_command(&phone, everything), bytes, over).await }).await??;
        Ok(SpeakerStream { inner, sound, ended })
    }
}

/// The computer's sound on its way to the phone: AAC frames (AAC-LC,
/// 48 kHz, two channels), one at a time and without their headers, ready
/// for a decoder.
#[frb(opaque)]
pub struct SpeakerStream {
    inner: Tap,
    sound: Arc<EventRelay<Vec<u8>>>,
    ended: Arc<EventRelay<String>>,
}

impl SpeakerStream {
    /// The frames. Listen once.
    pub fn sound(&self, sink: StreamSink<Vec<u8>>) {
        let frames = Mutex::new(Frames::default());
        self.sound.attach(Arc::new(move |piece: Vec<u8>| {
            let whole = frames.lock().unwrap_or_else(|e| e.into_inner()).feed(&piece);
            whole.into_iter().all(|frame| sink.add(frame).is_ok())
        }));
    }

    /// Hears once why the stream ended (empty when it was closed from
    /// here). Listen once.
    pub fn ended(&self, sink: StreamSink<String>) {
        self.ended.attach(Arc::new(move |reason| sink.add(reason).is_ok()));
    }

    #[frb(sync)]
    pub fn close(&self) {
        self.inner.close();
    }
}
