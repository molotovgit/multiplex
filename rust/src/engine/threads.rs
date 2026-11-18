//! The threads that carry the remote desktop's picture (the network
//! workers and the decoder), by their system ids, so Android can be told
//! they do time-critical work. Elsewhere this keeps nothing.

use std::sync::Mutex;

static IDS: Mutex<Vec<i32>> = Mutex::new(Vec::new());

/// Called on a thread when it starts: remembers it.
pub fn note_this_thread() {
    #[cfg(target_os = "android")]
    {
        // SAFETY: gettid has no preconditions.
        let id = unsafe { libc::gettid() };
        let mut ids = IDS.lock().unwrap_or_else(|p| p.into_inner());
        if !ids.contains(&id) {
            ids.push(id);
        }
    }
}

/// The threads noted so far.
pub fn noted() -> Vec<i32> {
    IDS.lock().unwrap_or_else(|p| p.into_inner()).clone()
}
