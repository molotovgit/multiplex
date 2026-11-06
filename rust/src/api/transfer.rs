//! Copying between any two places for Flutter: this device and servers.

use std::sync::Arc;

use flutter_rust_bridge::frb;

use crate::api::sftp::{FileTransfer, RemoteFiles};
use crate::api::sftp_types::RemoteEntry;
use crate::api::transfer_types::{ConflictPolicy, CopyReport};
use crate::engine::file_store::FileStore;
use crate::engine::runtime::AsyncRuntime;
use crate::engine::tree_copy;

/// One side of a copy: this device's storage, or a server's files.
#[frb(opaque)]
pub struct FileSide {
    pub(crate) store: FileStore,
}

impl FileSide {
    /// Files on this device, by their full paths.
    #[frb(sync)]
    pub fn phone() -> FileSide {
        FileSide { store: FileStore::Local }
    }

    /// Files on a server, through an open SFTP session.
    #[frb(sync)]
    pub fn server(files: &RemoteFiles) -> FileSide {
        FileSide { store: FileStore::Remote(Arc::clone(&files.inner)) }
    }

    #[frb(sync)]
    pub fn is_phone(&self) -> bool {
        matches!(self.store, FileStore::Local)
    }

    /// Folder contents: folders first, then files, each sorted by name.
    pub async fn list(&self, dir: String) -> anyhow::Result<Vec<RemoteEntry>> {
        let store = self.store.clone();
        AsyncRuntime::run(async move { store.list(&dir).await }).await?
    }

    pub async fn exists(&self, path: String) -> anyhow::Result<bool> {
        let store = self.store.clone();
        AsyncRuntime::run(async move { Ok(store.stat(&path).await?.is_some()) }).await?
    }

    pub async fn make_dir(&self, path: String) -> anyhow::Result<()> {
        let store = self.store.clone();
        AsyncRuntime::run(async move { store.make_dir(&path).await }).await?
    }

    /// `dir` + `name` the way this side writes paths.
    #[frb(sync)]
    pub fn join(&self, dir: String, name: String) -> String {
        self.store.join(&dir, &name)
    }

    /// The folder that holds `path`.
    #[frb(sync)]
    pub fn parent(&self, path: String) -> String {
        self.store.parent(&path)
    }
}

/// Copies the file or folder at `from_path` into the folder `to_dir` on
/// the other side. Progress and cancel go through `transfer`.
pub async fn copy_item(
    from: &FileSide,
    from_path: String,
    to: &FileSide,
    to_dir: String,
    on_conflict: ConflictPolicy,
    transfer: &FileTransfer,
) -> anyhow::Result<CopyReport> {
    let (source, target) = (from.store.clone(), to.store.clone());
    let cancel = transfer.cancel.clone();
    let sink = transfer.progress.clone();
    AsyncRuntime::run(async move { tree_copy::copy_item(&source, &from_path, &target, &to_dir, on_conflict, sink, cancel).await }).await?
}
