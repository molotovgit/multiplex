//! Remote file browsing and transfers for Flutter.

use std::path::PathBuf;
use std::sync::Arc;

use flutter_rust_bridge::frb;
use tokio_util::sync::CancellationToken;

use crate::api::sftp_types::{RemoteEntry, TransferProgress};
use crate::engine::events::EventRelay;
use crate::engine::runtime::AsyncRuntime;
use crate::engine::sftp::{RemotePath, SftpBrowser};
use crate::frb_generated::StreamSink;

/// An SFTP session on a connection.
#[frb(opaque)]
pub struct RemoteFiles {
    inner: Arc<SftpBrowser>,
}

/// One upload or download: watch its progress and cancel it.
#[frb(opaque)]
pub struct FileTransfer {
    cancel: CancellationToken,
    progress: Arc<EventRelay<TransferProgress>>,
}

impl FileTransfer {
    #[frb(sync)]
    pub fn create() -> FileTransfer {
        FileTransfer { cancel: CancellationToken::new(), progress: Arc::new(EventRelay::new()) }
    }

    /// Progress updates as a stream. Listen before or after starting the
    /// transfer; early updates are kept.
    pub fn watch(&self, sink: StreamSink<TransferProgress>) {
        self.progress.attach(Arc::new(move |p| sink.add(p).is_ok()));
    }

    #[frb(sync)]
    pub fn cancel(&self) {
        self.cancel.cancel();
    }

    #[frb(sync)]
    pub fn is_cancelled(&self) -> bool {
        self.cancel.is_cancelled()
    }
}

impl RemoteFiles {
    pub(crate) fn new(inner: SftpBrowser) -> Self {
        Self { inner: Arc::new(inner) }
    }

    pub async fn home(&self) -> anyhow::Result<String> {
        let b = self.inner.clone();
        AsyncRuntime::run(async move { b.home().await }).await?
    }

    /// Resolves `..`, `.` and links into an absolute path.
    pub async fn canonicalize(&self, path: String) -> anyhow::Result<String> {
        let b = self.inner.clone();
        AsyncRuntime::run(async move { b.canonicalize(&path).await }).await?
    }

    pub async fn list(&self, dir: String) -> anyhow::Result<Vec<RemoteEntry>> {
        let b = self.inner.clone();
        AsyncRuntime::run(async move { b.list(&dir).await }).await?
    }

    pub async fn stat(&self, path: String) -> anyhow::Result<RemoteEntry> {
        let b = self.inner.clone();
        AsyncRuntime::run(async move { b.stat(&path).await }).await?
    }

    pub async fn make_dir(&self, path: String) -> anyhow::Result<()> {
        let b = self.inner.clone();
        AsyncRuntime::run(async move { b.make_dir(&path).await }).await?
    }

    pub async fn rename(&self, from: String, to: String) -> anyhow::Result<()> {
        let b = self.inner.clone();
        AsyncRuntime::run(async move { b.rename(&from, &to).await }).await?
    }

    pub async fn set_permissions(&self, path: String, mode: u32) -> anyhow::Result<()> {
        let b = self.inner.clone();
        AsyncRuntime::run(async move { b.set_permissions(&path, mode).await }).await?
    }

    /// Deletes a file, or a folder and everything in it.
    pub async fn remove(&self, path: String) -> anyhow::Result<()> {
        let b = self.inner.clone();
        AsyncRuntime::run(async move { b.remove(&path).await }).await?
    }

    pub async fn read_text(&self, path: String, max_bytes: u64) -> anyhow::Result<String> {
        let b = self.inner.clone();
        AsyncRuntime::run(async move { b.read_text(&path, max_bytes).await }).await?
    }

    pub async fn write_text(&self, path: String, text: String) -> anyhow::Result<()> {
        let b = self.inner.clone();
        AsyncRuntime::run(async move { b.write_text(&path, &text).await }).await?
    }

    /// Copies a file from this device to the server.
    pub async fn upload(
        &self,
        local_path: String,
        remote_path: String,
        transfer: &FileTransfer,
    ) -> anyhow::Result<u64> {
        let b = self.inner.clone();
        let cancel = transfer.cancel.clone();
        let sink = transfer.progress.clone();
        AsyncRuntime::run(async move { b.upload(&PathBuf::from(local_path), &remote_path, sink, cancel).await }).await?
    }

    /// Copies a file from the server to this device.
    pub async fn download(
        &self,
        remote_path: String,
        local_path: String,
        transfer: &FileTransfer,
    ) -> anyhow::Result<u64> {
        let b = self.inner.clone();
        let cancel = transfer.cancel.clone();
        let sink = transfer.progress.clone();
        AsyncRuntime::run(async move { b.download(&remote_path, &PathBuf::from(local_path), sink, cancel).await }).await?
    }
}

/// `dir` + `/` + `name`, the way the server expects paths.
#[frb(sync)]
pub fn remote_join(dir: String, name: String) -> String {
    RemotePath::join(&dir, &name)
}

/// The folder that contains `path`.
#[frb(sync)]
pub fn remote_parent(path: String) -> String {
    RemotePath::parent(&path)
}
