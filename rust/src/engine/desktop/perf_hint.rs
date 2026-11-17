//! Android's performance hints (ADPF) for the video path.
//!
//! Left alone, the phone's scheduler sees a few threads that each work
//! for a couple of milliseconds per frame and parks them on slow cores at
//! a low clock. A hint session names those threads, says how long a
//! frame's work should take, and reports how long it took; when it took
//! longer than wanted, the system gives them faster cores.
//!
//! The functions are in libandroid from Android 13; they are looked up
//! when the desktop starts, and on older phones nothing happens.

use std::ffi::c_void;
use std::time::Duration;

use libloading::Library;

type GetManager = unsafe extern "C" fn() -> *mut c_void;
type CreateSession = unsafe extern "C" fn(*mut c_void, *const i32, usize, i64) -> *mut c_void;
type Report = unsafe extern "C" fn(*mut c_void, i64) -> i32;
type Close = unsafe extern "C" fn(*mut c_void);

pub struct PerfHint {
    session: *mut c_void,
    report: Report,
    close: Close,
    // Keeps the functions above loaded.
    _lib: Library,
}

// SAFETY: a hint session may be used from any one thread at a time; it
// lives on the decoder thread only.
unsafe impl Send for PerfHint {}

impl PerfHint {
    /// A session for these threads, whose work per frame should take
    /// `target`. `None` where Android has no hints, or refuses.
    pub fn start(threads: &[i32], target: Duration) -> Option<Self> {
        if threads.is_empty() {
            return None;
        }
        // SAFETY: libandroid is the platform's own library, already loaded
        // in every app process; the signatures are those of
        // <android/performance_hint.h>.
        unsafe {
            let lib = Library::new("libandroid.so").ok()?;
            let get_manager = *lib.get::<GetManager>(b"APerformanceHint_getManager\0").ok()?;
            let create = *lib.get::<CreateSession>(b"APerformanceHint_createSession\0").ok()?;
            let report = *lib.get::<Report>(b"APerformanceHint_reportActualWorkDuration\0").ok()?;
            let close = *lib.get::<Close>(b"APerformanceHint_closeSession\0").ok()?;
            let manager = get_manager();
            if manager.is_null() {
                return None;
            }
            let session = create(manager, threads.as_ptr(), threads.len(), target.as_nanos() as i64);
            // Many phones refuse (their power service has no hint sessions).
            // Nothing is built around a refused session: dropping one would
            // close it, and Android aborts the app for closing nothing.
            if session.is_null() {
                return None;
            }
            Some(Self { session, report, close, _lib: lib })
        }
    }

    /// How long a frame's work took.
    pub fn report(&self, actual: Duration) {
        let nanos = (actual.as_nanos() as i64).max(1);
        // SAFETY: the session is open until drop.
        unsafe {
            (self.report)(self.session, nanos);
        }
    }
}

impl Drop for PerfHint {
    fn drop(&mut self) {
        // SAFETY: closed once, here.
        unsafe { (self.close)(self.session) }
    }
}

/// Hints are off unless asked for: `adb shell setprop
/// debug.multiplex.perfhint 1`. They are in the picture's path, and a
/// change there is only switched on for everyone once it has numbers
/// behind it. The one phone they were tried on (a Galaxy S21 FE) refuses
/// hint sessions outright, so there are none yet.
pub fn allowed() -> bool {
    let mut value = [0u8; 92];
    // SAFETY: the buffer is PROP_VALUE_MAX long, as the call requires.
    let len = unsafe { libc::__system_property_get(c"debug.multiplex.perfhint".as_ptr(), value.as_mut_ptr().cast()) };
    len == 1 && value[0] == b'1'
}
