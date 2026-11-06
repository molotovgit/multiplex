//! Plain data for copying files and folders between this device and
//! servers, and for keeping folders in sync.

/// What to do when the copy would land on something already there.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConflictPolicy {
    /// Replace files that are there; a folder is merged into the one there.
    Replace,
    /// Leave what is there and copy only what is missing.
    Skip,
    /// Copy under a new name: "notes (1).txt".
    KeepBoth,
}

/// What one copy did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CopyReport {
    /// Where the file or folder ended up.
    pub target: String,
    pub copied: u32,
    /// Files left alone because they were already there, and links to
    /// folders, which are not followed.
    pub skipped: u32,
    pub bytes: u64,
}
