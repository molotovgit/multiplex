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

/// A sink the listener can plug in later.
///
/// Jobs start before the app has subscribed to their events. The relay
/// keeps early events (up to a limit) and hands them over the moment a
/// listener attaches, so nothing important, such as "the shell exited",
/// is lost in between.
pub struct EventRelay<E> {
    state: std::sync::Mutex<RelayState<E>>,
}

struct RelayState<E> {
    target: Option<SharedSink<E>>,
    pending: Vec<E>,
}

impl<E> EventRelay<E> {
    /// Early events beyond this count are dropped; the oldest go first.
    const MAX_PENDING: usize = 256;

    pub fn new() -> Self {
        Self {
            state: std::sync::Mutex::new(RelayState { target: None, pending: Vec::new() }),
        }
    }

    /// Starts sending events to `sink`, beginning with the saved ones.
    pub fn attach(&self, sink: SharedSink<E>) {
        let mut state = self.state.lock().unwrap_or_else(|p| p.into_inner());
        for event in state.pending.drain(..) {
            sink.emit(event);
        }
        state.target = Some(sink);
    }
}

impl<E> Default for EventRelay<E> {
    fn default() -> Self {
        Self::new()
    }
}

impl<E: Send> EventSink<E> for EventRelay<E> {
    fn emit(&self, event: E) -> bool {
        let mut state = self.state.lock().unwrap_or_else(|p| p.into_inner());
        match &state.target {
            Some(target) => target.emit(event),
            None => {
                if state.pending.len() >= Self::MAX_PENDING {
                    state.pending.remove(0);
                }
                state.pending.push(event);
                true
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    #[test]
    fn relay_keeps_early_events_until_someone_listens() {
        let relay = EventRelay::new();
        relay.emit(1);
        relay.emit(2);
        let seen = Arc::new(Mutex::new(Vec::new()));
        let seen_in_sink = seen.clone();
        relay.attach(Arc::new(move |e| {
            seen_in_sink.lock().unwrap().push(e);
            true
        }));
        relay.emit(3);
        assert_eq!(*seen.lock().unwrap(), vec![1, 2, 3]);
    }

    #[test]
    fn relay_reports_a_listener_that_went_away() {
        let relay = EventRelay::new();
        relay.attach(Arc::new(|_: u8| false));
        assert!(!relay.emit(1));
    }
}
