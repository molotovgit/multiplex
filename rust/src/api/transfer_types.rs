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

/// Which way a folder sync copies.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncDirection {
    /// Left (the phone) to right (the server).
    ToRight,
    /// Right to left.
    ToLeft,
    /// Each way: the newer copy of a file wins.
    Both,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncActionKind {
    CopyToRight,
    CopyToLeft,
    DeleteOnRight,
    DeleteOnLeft,
    /// Shown, never applied: the user has to sort it out.
    Conflict,
}

/// Why an action is in the plan.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncReason {
    /// Only on one side.
    New,
    /// Different size or time; the one-way source wins.
    Changed,
    /// Both sides changed it; this copy is newer.
    Newer,
    /// Not on the source side ("mirror" deletes it).
    Extra,
    /// A file on one side, a folder on the other.
    TypeClash,
    /// Different, but neither is clearly newer.
    Undecided,
}

/// One step of a folder sync.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncAction {
    /// Path inside the synced folders, with "/" between parts.
    pub path: String,
    pub kind: SyncActionKind,
    pub reason: SyncReason,
    pub is_dir: bool,
    /// Bytes to copy (0 for folders and deletes).
    pub size: u64,
}

/// What a sync did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncReport {
    pub copied: u32,
    pub deleted: u32,
    /// "path: why" for each step that failed; the others still ran.
    pub failed: Vec<String>,
}
