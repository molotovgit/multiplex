//! Tailscale inside the app: the embedded node from `native/tailscale`
//! (libmpxtailscale), loaded at run time.
//!
//! The library runs a whole Tailscale node in this process, so the phone
//! reaches tailnet devices without the Tailscale VPN app. A connection to
//! a device comes back as a socket file descriptor, which becomes an
//! ordinary async stream for russh.
//!
//! Builds without the library (desktop, tests) report Tailscale as not
//! available instead of failing.

use std::ffi::{c_char, c_int, CStr, CString};
use std::sync::OnceLock;

use libloading::Library;

/// The library's functions, resolved once.
struct Api {
    _lib: Library,
    start: unsafe extern "C" fn(*const c_char, *const c_char) -> c_int,
    status: unsafe extern "C" fn() -> *mut c_char,
    login: unsafe extern "C" fn() -> c_int,
    logout: unsafe extern "C" fn() -> c_int,
    dial: unsafe extern "C" fn(*const c_char, c_int, c_int) -> c_int,
    last_error: unsafe extern "C" fn() -> *mut c_char,
    free: unsafe extern "C" fn(*mut c_char),
}

static API: OnceLock<Result<Api, String>> = OnceLock::new();

fn api() -> anyhow::Result<&'static Api> {
    API.get_or_init(load).as_ref().map_err(|e| anyhow::anyhow!("{e}"))
}

fn load() -> Result<Api, String> {
    // SAFETY: loading our own library, built from native/tailscale, whose
    // exported functions have exactly these C signatures.
    unsafe {
        let lib = Library::new("libmpxtailscale.so").map_err(|_| "Tailscale is not included in this build of Multiplex.".to_owned())?;
        macro_rules! sym {
            ($name:literal) => {
                *lib.get($name).map_err(|e| format!("the Tailscale library is incomplete ({e})"))?
            };
        }
        Ok(Api {
            start: sym!(b"mpx_ts_start\0"),
            status: sym!(b"mpx_ts_status\0"),
            login: sym!(b"mpx_ts_login\0"),
            logout: sym!(b"mpx_ts_logout\0"),
            dial: sym!(b"mpx_ts_dial\0"),
            last_error: sym!(b"mpx_ts_last_error\0"),
            free: sym!(b"mpx_ts_free\0"),
            _lib: lib,
        })
    }
}

/// Takes a string the library allocated and frees it.
fn take(api: &Api, ptr: *mut c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    // SAFETY: the library returns NUL-terminated strings from C.CString,
    // which we free exactly once with its own free function.
    unsafe {
        let s = CStr::from_ptr(ptr).to_string_lossy().into_owned();
        (api.free)(ptr);
        s
    }
}

fn check(api: &Api, rc: c_int) -> anyhow::Result<c_int> {
    if rc < 0 {
        // SAFETY: plain call into the loaded library.
        let msg = take(api, unsafe { (api.last_error)() });
        anyhow::bail!("{}", if msg.is_empty() { "Tailscale failed".to_owned() } else { msg });
    }
    Ok(rc)
}

/// True when this build carries the Tailscale library.
pub fn available() -> bool {
    api().is_ok()
}

/// Starts the node (state kept in `dir`, so sign-in survives restarts).
pub fn start(dir: &str, hostname: &str) -> anyhow::Result<()> {
    let api = api()?;
    let (dir, host) = (CString::new(dir)?, CString::new(hostname)?);
    // SAFETY: valid C strings that outlive the call.
    check(api, unsafe { (api.start)(dir.as_ptr(), host.as_ptr()) })?;
    Ok(())
}

/// The node's state and devices, as the library's JSON.
pub fn status_json() -> anyhow::Result<String> {
    let api = api()?;
    // SAFETY: plain call; the string is freed by `take`.
    Ok(take(api, unsafe { (api.status)() }))
}

pub fn login() -> anyhow::Result<()> {
    let api = api()?;
    // SAFETY: plain call into the loaded library.
    check(api, unsafe { (api.login)() })?;
    Ok(())
}

pub fn logout() -> anyhow::Result<()> {
    let api = api()?;
    // SAFETY: plain call into the loaded library.
    check(api, unsafe { (api.logout)() })?;
    Ok(())
}

/// Connects to `host:port` on the tailnet. Blocks until connected, so
/// call it off the async threads.
pub fn dial(host: &str, port: u16, timeout_ms: u32) -> anyhow::Result<std::os::unix::net::UnixStream> {
    use std::os::fd::FromRawFd;
    let api = api()?;
    let host = CString::new(host)?;
    // SAFETY: valid C string; a non-negative result is a new descriptor
    // that we own from here on.
    let fd = check(api, unsafe { (api.dial)(host.as_ptr(), c_int::from(port), timeout_ms as c_int) })?;
    // SAFETY: `fd` is a fresh, open socket descriptor owned by nobody else.
    Ok(unsafe { std::os::unix::net::UnixStream::from_raw_fd(fd) })
}

/// [`dial`] as an async stream for russh.
pub async fn connect(host: &str, port: u16, timeout_ms: u32) -> anyhow::Result<tokio::net::UnixStream> {
    let host = host.to_owned();
    let stream = tokio::task::spawn_blocking(move || dial(&host, port, timeout_ms)).await??;
    stream.set_nonblocking(true)?;
    Ok(tokio::net::UnixStream::from_std(stream)?)
}
