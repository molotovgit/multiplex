//! A small "send events back to the app" interface.
//!
//! The engine never talks to Flutter directly. It sends events through an
//! [`EventSink`]. The API layer plugs in a Flutter stream, the tests plug in
//! a plain channel, so the engine code is the same in both cases.

use std::sync::Arc;

/// Something that receives events from a running job.
pub trait EventSink<E>: Send + Sync {
    /// Delivers one event. Returns `false` when nobody listens any more,
    /// so the sender can stop.
    fn emit(&self, event: E) -> bool;
}

/// Any closure `Fn(E) -> bool` can be used as a sink.
impl<E, F> EventSink<E> for F
where
    F: Fn(E) -> bool + Send + Sync,
{
    fn emit(&self, event: E) -> bool {
        self(event)
    }
}

/// Shared, type-erased sink that can be cloned into background tasks.
pub type SharedSink<E> = Arc<dyn EventSink<E>>;

/// A sink that throws events away. Handy when the app does not care.
pub struct NullSink;

impl<E> EventSink<E> for NullSink {
    fn emit(&self, _event: E) -> bool {
        true
    }
}
