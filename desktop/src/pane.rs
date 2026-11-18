//! This command's own terminal: its size, and taking keys as they are
//! typed, for sitting in front of a terminal the session server keeps.

/// The size of the terminal this runs in, in columns and rows.
pub(crate) fn terminal_size() -> Option<(u16, u16)> {
    let mut size: libc::winsize = unsafe { std::mem::zeroed() };
    let ok = unsafe { libc::ioctl(libc::STDOUT_FILENO, libc::TIOCGWINSZ, &mut size) } == 0;
    (ok && size.ws_col > 0 && size.ws_row > 0).then_some((size.ws_col.clamp(2, 1000), size.ws_row.clamp(2, 1000)))
}

/// Keys come as typed, unechoed, while this lives; the terminal is put
/// back as it was when it goes.
pub(crate) struct Raw {
    before: libc::termios,
}

impl Raw {
    pub(crate) fn on() -> Option<Self> {
        if unsafe { libc::isatty(libc::STDIN_FILENO) } != 1 {
            return None;
        }
        let mut before: libc::termios = unsafe { std::mem::zeroed() };
        if unsafe { libc::tcgetattr(libc::STDIN_FILENO, &mut before) } != 0 {
            return None;
        }
        let mut raw = before;
        unsafe { libc::cfmakeraw(&mut raw) };
        (unsafe { libc::tcsetattr(libc::STDIN_FILENO, libc::TCSANOW, &raw) } == 0).then_some(Raw { before })
    }
}

impl Drop for Raw {
    fn drop(&mut self) {
        unsafe { libc::tcsetattr(libc::STDIN_FILENO, libc::TCSANOW, &self.before) };
    }
}
