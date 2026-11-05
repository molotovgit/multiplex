//! Remote files over SFTP: list, create, rename, delete, change
//! permissions, read small files, and upload or download big ones with
//! progress and cancel.

use std::path::Path;
use std::time::{Duration, Instant, UNIX_EPOCH};

use russh_sftp::client::SftpSession;
use russh_sftp::protocol::{FileAttributes, FileType, OpenFlags};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio_util::sync::CancellationToken;

use crate::api::sftp_types::{EntryKind, RemoteEntry, TransferProgress};
use crate::engine::events::SharedSink;
use crate::engine::ssh::Connection;

/// Helpers for paths on the server, which always use `/`.
pub struct RemotePath;

impl RemotePath {
    pub fn join(dir: &str, name: &str) -> String {
        if dir.is_empty() || dir == "." {
            name.to_owned()
        } else if dir.ends_with('/') {
            format!("{dir}{name}")
        } else {
            format!("{dir}/{name}")
        }
    }

    /// The folder that contains `path` ("/" for top-level entries).
    pub fn parent(path: &str) -> String {
        let trimmed = path.trim_end_matches('/');
        match trimmed.rfind('/') {
            Some(0) => "/".to_owned(),
            Some(i) => trimmed[..i].to_owned(),
            None => ".".to_owned(),
        }
    }
}

/// Sends progress events at a calm pace so a fast transfer does not flood
/// the app with updates.
struct ProgressReporter {
    sink: SharedSink<TransferProgress>,
    total: u64,
    last: Instant,
}

impl ProgressReporter {
    const INTERVAL: Duration = Duration::from_millis(120);

    fn new(sink: SharedSink<TransferProgress>, total: u64) -> Self {
        let reporter = Self { sink, total, last: Instant::now() };
        reporter.sink.emit(TransferProgress { transferred: 0, total });
        reporter
    }

    fn update(&mut self, transferred: u64) {
        if self.last.elapsed() >= Self::INTERVAL {
            self.last = Instant::now();
            self.sink.emit(TransferProgress { transferred, total: self.total });
        }
    }

    fn finish(&self, transferred: u64) {
        self.sink.emit(TransferProgress { transferred, total: self.total.max(transferred) });
    }
}

/// An SFTP session on one connection.
pub struct SftpBrowser {
    sftp: SftpSession,
}

impl SftpBrowser {
    const CHUNK: usize = 256 * 1024;

    pub async fn open(conn: &Connection) -> anyhow::Result<Self> {
        let channel = conn.handle().channel_open_session().await?;
        channel.request_subsystem(true, "sftp").await?;
        let sftp = SftpSession::new(channel.into_stream()).await?;
        Ok(Self { sftp })
    }

    /// The folder the server starts in, usually the user's home.
    pub async fn home(&self) -> anyhow::Result<String> {
        Ok(self.sftp.canonicalize(".").await?)
    }

    pub async fn canonicalize(&self, path: &str) -> anyhow::Result<String> {
        Ok(self.sftp.canonicalize(path).await?)
    }

    /// Folder contents: folders first, then files, each sorted by name.
    pub async fn list(&self, dir: &str) -> anyhow::Result<Vec<RemoteEntry>> {
        let mut entries = Vec::new();
        for entry in self.sftp.read_dir(dir).await? {
            let name = entry.file_name();
            if name == "." || name == ".." {
                continue;
            }
            let path = RemotePath::join(dir, &name);
            let attrs = entry.metadata();
            let mut item = Self::entry(name, path, &attrs);
            if item.kind == EntryKind::Symlink {
                // Follow the link once to learn whether it can be opened.
                item.is_dir = self.sftp.metadata(&item.path).await.map(|m| m.is_dir()).unwrap_or(false);
            }
            entries.push(item);
        }
        entries.sort_by(|a, b| b.is_dir.cmp(&a.is_dir).then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase())));
        Ok(entries)
    }

    pub async fn stat(&self, path: &str) -> anyhow::Result<RemoteEntry> {
        let attrs = self.sftp.metadata(path).await?;
        let name = path.trim_end_matches('/').rsplit('/').next().unwrap_or(path).to_owned();
        Ok(Self::entry(name, path.to_owned(), &attrs))
    }

    pub async fn make_dir(&self, path: &str) -> anyhow::Result<()> {
        Ok(self.sftp.create_dir(path).await?)
    }

    pub async fn rename(&self, from: &str, to: &str) -> anyhow::Result<()> {
        Ok(self.sftp.rename(from, to).await?)
    }

    /// Changes the Unix permission bits, for example 0o755.
    pub async fn set_permissions(&self, path: &str, mode: u32) -> anyhow::Result<()> {
        let mut attrs = FileAttributes::empty();
        attrs.permissions = Some(mode & 0o7777);
        Ok(self.sftp.set_metadata(path, attrs).await?)
    }

    /// Deletes a file, or a folder with everything inside it.
    pub async fn remove(&self, path: &str) -> anyhow::Result<()> {
        let attrs = self.sftp.symlink_metadata(path).await?;
        if attrs.file_type() != FileType::Dir {
            return Ok(self.sftp.remove_file(path).await?);
        }
        // Walk the tree without recursion: collect folders, delete files,
        // then delete the folders deepest first.
        let mut folders = vec![path.to_owned()];
        let mut index = 0;
        while index < folders.len() {
            let dir = folders[index].clone();
            for entry in self.sftp.read_dir(&dir).await? {
                let name = entry.file_name();
                if name == "." || name == ".." {
                    continue;
                }
                let child = RemotePath::join(&dir, &name);
                if entry.file_type() == FileType::Dir {
                    folders.push(child);
                } else {
                    self.sftp.remove_file(&child).await?;
                }
            }
            index += 1;
        }
        for dir in folders.iter().rev() {
            self.sftp.remove_dir(dir).await?;
        }
        Ok(())
    }

    /// Reads a file as text, refusing files larger than `max_bytes`.
    pub async fn read_text(&self, path: &str, max_bytes: u64) -> anyhow::Result<String> {
        let size = self.sftp.metadata(path).await?.size.unwrap_or(0);
        anyhow::ensure!(size <= max_bytes, "the file is too big to open here ({size} bytes)");
        let bytes = self.sftp.read(path).await?;
        Ok(String::from_utf8_lossy(&bytes).into_owned())
    }

    /// Replaces a file's contents with `text`.
    pub async fn write_text(&self, path: &str, text: &str) -> anyhow::Result<()> {
        let mut file = self
            .sftp
            .open_with_flags(path, OpenFlags::CREATE | OpenFlags::TRUNCATE | OpenFlags::WRITE)
            .await?;
        file.write_all(text.as_bytes()).await?;
        file.shutdown().await?;
        Ok(())
    }

    /// Copies a local file to the server. Returns the bytes sent.
    ///
    /// The data goes to a temporary name next to the target and only
    /// replaces it once complete, so a cancelled or failed upload never
    /// destroys the file that was there before.
    pub async fn upload(
        &self,
        local: &Path,
        remote: &str,
        progress: SharedSink<TransferProgress>,
        cancel: CancellationToken,
    ) -> anyhow::Result<u64> {
        let mut source = tokio::fs::File::open(local).await?;
        let total = source.metadata().await?.len();
        let partial = format!("{remote}.part");
        let mut target = self
            .sftp
            .open_with_flags(&partial, OpenFlags::CREATE | OpenFlags::TRUNCATE | OpenFlags::WRITE)
            .await?;
        let copied = Self::copy(&mut source, &mut target, ProgressReporter::new(progress, total), &cancel).await;
        let finished = match copied {
            Ok(sent) => target.shutdown().await.map(|_| sent).map_err(anyhow::Error::from),
            Err(err) => Err(err),
        };
        let sent = match finished {
            Ok(sent) => sent,
            Err(err) => {
                drop(target);
                let _ = self.sftp.remove_file(&partial).await;
                return Err(err);
            }
        };
        // Plain SFTP rename refuses to replace an existing file, so the old
        // one is removed first, at the last possible moment.
        if self.sftp.try_exists(remote).await.unwrap_or(false) {
            self.sftp.remove_file(remote).await?;
        }
        self.sftp.rename(&partial, remote).await?;
        Ok(sent)
    }

    /// Copies a file from the server to this device. A cancelled or failed
    /// download leaves no half file behind.
    pub async fn download(
        &self,
        remote: &str,
        local: &Path,
        progress: SharedSink<TransferProgress>,
        cancel: CancellationToken,
    ) -> anyhow::Result<u64> {
        let total = self.sftp.metadata(remote).await?.size.unwrap_or(0);
        let mut source = self.sftp.open(remote).await?;
        // "notes.txt.part", not "notes.part": two downloads that share a
        // base name, or a user file called notes.part, never collide.
        let mut partial_name = local.as_os_str().to_owned();
        partial_name.push(".part");
        let partial = std::path::PathBuf::from(partial_name);
        let mut target = tokio::fs::File::create(&partial).await?;
        let result = Self::copy(&mut source, &mut target, ProgressReporter::new(progress, total), &cancel).await;
        match result {
            Ok(received) => {
                target.flush().await?;
                drop(target);
                tokio::fs::rename(&partial, local).await?;
                Ok(received)
            }
            Err(err) => {
                drop(target);
                let _ = tokio::fs::remove_file(&partial).await;
                Err(err)
            }
        }
    }

    async fn copy<R, W>(source: &mut R, target: &mut W, mut reporter: ProgressReporter, cancel: &CancellationToken) -> anyhow::Result<u64>
    where
        R: tokio::io::AsyncRead + Unpin,
        W: tokio::io::AsyncWrite + Unpin,
    {
        let mut buf = vec![0u8; Self::CHUNK];
        let mut done = 0u64;
        loop {
            let read = tokio::select! {
                _ = cancel.cancelled() => anyhow::bail!("transfer cancelled"),
                read = source.read(&mut buf) => read?,
            };
            if read == 0 {
                break;
            }
            target.write_all(&buf[..read]).await?;
            done += read as u64;
            reporter.update(done);
        }
        reporter.finish(done);
        Ok(done)
    }

    fn entry(name: String, path: String, attrs: &FileAttributes) -> RemoteEntry {
        let kind = match attrs.file_type() {
            FileType::Dir => EntryKind::Directory,
            FileType::File => EntryKind::File,
            FileType::Symlink => EntryKind::Symlink,
            FileType::Other => EntryKind::Other,
        };
        let modified = attrs
            .modified()
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64);
        RemoteEntry {
            name,
            path,
            kind,
            is_dir: kind == EntryKind::Directory,
            size: attrs.size.unwrap_or(0),
            permissions: attrs.permissions.unwrap_or(0) & 0o7777,
            modified,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::RemotePath;

    #[test]
    fn joins_and_splits_remote_paths() {
        assert_eq!(RemotePath::join("/home/a", "x.txt"), "/home/a/x.txt");
        assert_eq!(RemotePath::join("/", "etc"), "/etc");
        assert_eq!(RemotePath::join(".", "x"), "x");
        assert_eq!(RemotePath::parent("/home/a/x.txt"), "/home/a");
        assert_eq!(RemotePath::parent("/etc"), "/");
        assert_eq!(RemotePath::parent("/home/a/"), "/home");
        assert_eq!(RemotePath::parent("x"), ".");
    }
}
