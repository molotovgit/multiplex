//! Plain data for browsing and transferring files over SFTP.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EntryKind {
    File,
    Directory,
    /// A link; `link_to_dir` on the entry says where it leads.
    Symlink,
    Other,
}

/// One file or folder on the server.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RemoteEntry {
    pub name: String,
    /// Full path on the server.
    pub path: String,
    pub kind: EntryKind,
    /// True for directories and for links that point to a directory, so
    /// the app knows it can open them.
    pub is_dir: bool,
    pub size: u64,
    /// Unix permission bits, for example 0o644.
    pub permissions: u32,
    /// Last change as seconds since 1970, if the server told us.
    pub modified: Option<i64>,
}

/// Progress of a running upload or download.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TransferProgress {
    pub transferred: u64,
    /// Total size in bytes, 0 when unknown.
    pub total: u64,
}
