//! One place files can live: this device's own storage or a server over
//! SFTP. Copying and syncing work the same way between any two of them.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, UNIX_EPOCH};

use russh_sftp::client::error::Error as SftpError;
use russh_sftp::protocol::{FileAttributes, OpenFlags, StatusCode};
use tokio::io::{AsyncRead, AsyncWrite};

use crate::api::sftp_types::{EntryKind, RemoteEntry};
use crate::engine::sftp::{RemotePath, SftpBrowser};

/// What copying needs to know about one file or folder.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Meta {
    pub is_dir: bool,
    pub size: u64,
    /// Seconds since 1970, when known.
    pub modified: Option<i64>,
}

pub type Reader = Box<dyn AsyncRead + Unpin + Send>;
pub type Writer = Box<dyn AsyncWrite + Unpin + Send>;

/// This device, or a server.
#[derive(Clone)]
pub enum FileStore {
    Local,
    Remote(Arc<SftpBrowser>),
}

impl FileStore {
    /// True when both are this device, or the very same SFTP session.
    /// Two sessions to one server cannot be told apart and count as different.
    pub fn same_as(&self, other: &FileStore) -> bool {
        match (self, other) {
            (FileStore::Local, FileStore::Local) => true,
            (FileStore::Remote(a), FileStore::Remote(b)) => Arc::ptr_eq(a, b),
            _ => false,
        }
    }

    /// True when `path` is `dir` itself or somewhere inside it. On this
    /// device "/" and "\" count the same (Windows takes both).
    pub fn is_inside(&self, path: &str, dir: &str) -> bool {
        match self {
            FileStore::Local => Path::new(path).starts_with(dir),
            FileStore::Remote(_) => {
                let dir = dir.trim_end_matches('/');
                path == dir || path.strip_prefix(dir).is_some_and(|rest| rest.starts_with('/'))
            }
        }
    }

    pub fn join(&self, dir: &str, name: &str) -> String {
        match self {
            FileStore::Local => Path::new(dir).join(name).to_string_lossy().into_owned(),
            FileStore::Remote(_) => RemotePath::join(dir, name),
        }
    }

    /// The last part of a path: "notes.txt" for "/home/a/notes.txt".
    pub fn name_of(&self, path: &str) -> String {
        match self {
            FileStore::Local => Path::new(path).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| path.to_owned()),
            FileStore::Remote(_) => path.trim_end_matches('/').rsplit('/').next().unwrap_or(path).to_owned(),
        }
    }

    pub fn parent(&self, path: &str) -> String {
        match self {
            FileStore::Local => Path::new(path).parent().map(|p| p.to_string_lossy().into_owned()).unwrap_or_else(|| path.to_owned()),
            FileStore::Remote(_) => RemotePath::parent(path),
        }
    }

    /// The file or folder at `path` (links followed), or None if nothing is there.
    pub async fn stat(&self, path: &str) -> anyhow::Result<Option<Meta>> {
        match self {
            FileStore::Local => match tokio::fs::metadata(path).await {
                Ok(m) => Ok(Some(Meta { is_dir: m.is_dir(), size: if m.is_dir() { 0 } else { m.len() }, modified: local_modified(&m) })),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
                Err(e) => Err(e.into()),
            },
            FileStore::Remote(sftp) => match sftp.session().metadata(path).await {
                Ok(a) => Ok(Some(Meta { is_dir: a.is_dir(), size: if a.is_dir() { 0 } else { a.size.unwrap_or(0) }, modified: a.mtime.map(i64::from) })),
                Err(SftpError::Status(s)) if s.status_code == StatusCode::NoSuchFile => Ok(None),
                Err(e) => Err(e.into()),
            },
        }
    }

    /// Folder contents, folders first, then files, each sorted by name.
    pub async fn list(&self, dir: &str) -> anyhow::Result<Vec<RemoteEntry>> {
        match self {
            FileStore::Remote(sftp) => sftp.list(dir).await,
            FileStore::Local => {
                let mut entries = Vec::new();
                let mut read = tokio::fs::read_dir(dir).await?;
                while let Some(item) = read.next_entry().await? {
                    let path = item.path();
                    let own = tokio::fs::symlink_metadata(&path).await?;
                    // A broken link has no target to read; it shows as a link that cannot open.
                    let target = tokio::fs::metadata(&path).await.ok();
                    let kind = if own.file_type().is_symlink() {
                        EntryKind::Symlink
                    } else if own.is_dir() {
                        EntryKind::Directory
                    } else if own.is_file() {
                        EntryKind::File
                    } else {
                        EntryKind::Other
                    };
                    let meta = target.as_ref().unwrap_or(&own);
                    entries.push(RemoteEntry {
                        name: item.file_name().to_string_lossy().into_owned(),
                        path: path.to_string_lossy().into_owned(),
                        kind,
                        is_dir: meta.is_dir(),
                        size: if meta.is_dir() { 0 } else { meta.len() },
                        permissions: local_mode(meta),
                        modified: local_modified(meta),
                    });
                }
                entries.sort_by(|a, b| b.is_dir.cmp(&a.is_dir).then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase())));
                Ok(entries)
            }
        }
    }

    pub async fn make_dir(&self, path: &str) -> anyhow::Result<()> {
        match self {
            FileStore::Local => Ok(tokio::fs::create_dir(path).await?),
            FileStore::Remote(sftp) => sftp.make_dir(path).await,
        }
    }

    pub async fn open_read(&self, path: &str) -> anyhow::Result<Reader> {
        Ok(match self {
            FileStore::Local => Box::new(tokio::fs::File::open(path).await?),
            FileStore::Remote(sftp) => Box::new(sftp.session().open(path).await?),
        })
    }

    /// Creates or empties the file at `path` for writing.
    pub async fn open_write(&self, path: &str) -> anyhow::Result<Writer> {
        Ok(match self {
            FileStore::Local => Box::new(tokio::fs::File::create(path).await?),
            FileStore::Remote(sftp) => {
                Box::new(sftp.session().open_with_flags(path, OpenFlags::CREATE | OpenFlags::TRUNCATE | OpenFlags::WRITE).await?)
            }
        })
    }

    /// Deletes a file, or a folder with everything inside it. A link is
    /// deleted itself; what it points to stays.
    pub async fn remove(&self, path: &str) -> anyhow::Result<()> {
        match self {
            FileStore::Remote(sftp) => sftp.remove(path).await,
            FileStore::Local => {
                let own = tokio::fs::symlink_metadata(path).await?;
                if own.is_dir() {
                    Ok(tokio::fs::remove_dir_all(path).await?)
                } else {
                    Ok(tokio::fs::remove_file(path).await?)
                }
            }
        }
    }

    /// Moves `from` to `to`, replacing a file already at `to`.
    pub async fn replace(&self, from: &str, to: &str) -> anyhow::Result<()> {
        match self {
            FileStore::Local => Ok(tokio::fs::rename(from, to).await?),
            FileStore::Remote(sftp) => {
                // Plain SFTP rename refuses to replace, so the old file goes first.
                if sftp.session().try_exists(to).await.unwrap_or(false) {
                    sftp.session().remove_file(to).await?;
                }
                Ok(sftp.session().rename(from, to).await?)
            }
        }
    }

    /// Sets a file's last-change time, so a copy keeps the original's.
    pub async fn set_modified(&self, path: &str, secs: i64) -> anyhow::Result<()> {
        match self {
            FileStore::Local => {
                let path = PathBuf::from(path);
                let time = UNIX_EPOCH + Duration::from_secs(secs.max(0) as u64);
                tokio::task::spawn_blocking(move || std::fs::File::options().write(true).open(path)?.set_modified(time)).await??;
                Ok(())
            }
            FileStore::Remote(sftp) => {
                let secs = u32::try_from(secs.max(0)).unwrap_or(u32::MAX);
                let mut attrs = FileAttributes::empty();
                // The protocol sets both times together.
                attrs.atime = Some(secs);
                attrs.mtime = Some(secs);
                Ok(sftp.session().set_metadata(path, attrs).await?)
            }
        }
    }
}

fn local_modified(meta: &std::fs::Metadata) -> Option<i64> {
    meta.modified().ok().and_then(|t| t.duration_since(UNIX_EPOCH).ok()).map(|d| d.as_secs() as i64)
}

#[cfg(unix)]
fn local_mode(meta: &std::fs::Metadata) -> u32 {
    use std::os::unix::fs::PermissionsExt;
    meta.permissions().mode() & 0o7777
}

#[cfg(not(unix))]
fn local_mode(meta: &std::fs::Metadata) -> u32 {
    match (meta.is_dir(), meta.permissions().readonly()) {
        (true, _) => 0o755,
        (false, true) => 0o444,
        (false, false) => 0o644,
    }
}

#[cfg(test)]
mod tests {
    use super::FileStore;

    #[test]
    fn knows_when_a_path_is_inside_a_folder() {
        let local = FileStore::Local;
        assert!(local.is_inside("/a/b", "/a/b"));
        assert!(local.is_inside("/a/b/c", "/a/b"));
        assert!(local.is_inside("/a/b/c", "/a/b/"));
        assert!(!local.is_inside("/a/bc", "/a/b"));
        assert!(!local.is_inside("/a", "/a/b"));
        #[cfg(windows)]
        assert!(local.is_inside(r"C:\x/y\z", r"C:\x\y"));
    }
}
