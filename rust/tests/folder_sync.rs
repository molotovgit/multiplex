//! Folder sync end to end between two folders on this machine.

use std::fs;
use std::path::Path;
use std::sync::Arc;
use std::time::{Duration, UNIX_EPOCH};

use multiplex_core::api::transfer_types::{SyncActionKind, SyncDirection};
use multiplex_core::engine::file_store::FileStore;
use multiplex_core::engine::folder_sync::{apply, plan, walk};
use tokio_util::sync::CancellationToken;

fn write(path: &Path, text: &str, secs: u64) {
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, text).unwrap();
    fs::File::options().write(true).open(path).unwrap().set_modified(UNIX_EPOCH + Duration::from_secs(secs)).unwrap();
}

async fn sync(left: &Path, right: &Path, direction: SyncDirection, mirror: bool) -> (usize, multiplex_core::api::transfer_types::SyncReport) {
    let (l, r) = (left.to_string_lossy().into_owned(), right.to_string_lossy().into_owned());
    let cancel = CancellationToken::new();
    let a = walk(&FileStore::Local, &l, &cancel).await.unwrap();
    let b = walk(&FileStore::Local, &r, &cancel).await.unwrap();
    let steps = plan(&a, &b, direction, mirror);
    let report = apply(&FileStore::Local, &l, &FileStore::Local, &r, &steps, Arc::new(|_| true), cancel).await.unwrap();
    (steps.len(), report)
}

#[tokio::test]
async fn a_second_sync_finds_nothing_to_do() {
    let (phone, server) = (tempfile::tempdir().unwrap(), tempfile::tempdir().unwrap());
    write(&phone.path().join("photos/2026/a.jpg"), "aaa", 1_700_000_000);
    write(&phone.path().join("notes.md"), "hello", 1_700_000_100);
    fs::create_dir_all(phone.path().join("empty")).unwrap();
    write(&server.path().join("notes.md"), "old", 1_600_000_000);

    let (steps, report) = sync(phone.path(), server.path(), SyncDirection::ToRight, false).await;
    assert_eq!((steps, report.copied, report.failed.len()), (3, 3, 0));
    assert_eq!(fs::read_to_string(server.path().join("photos/2026/a.jpg")).unwrap(), "aaa");
    assert_eq!(fs::read_to_string(server.path().join("notes.md")).unwrap(), "hello");
    assert!(server.path().join("empty").is_dir());

    // Times were kept, so the folders now match.
    let (steps, _) = sync(phone.path(), server.path(), SyncDirection::ToRight, false).await;
    assert_eq!(steps, 0);
}

#[tokio::test]
async fn mirror_deletes_extras_and_both_ways_moves_the_newer_file() {
    let (phone, server) = (tempfile::tempdir().unwrap(), tempfile::tempdir().unwrap());
    write(&phone.path().join("keep.txt"), "k", 100);
    write(&server.path().join("keep.txt"), "k", 100);
    write(&server.path().join("stale/old.txt"), "x", 100);

    let (_, plain) = sync(phone.path(), server.path(), SyncDirection::ToRight, false).await;
    assert_eq!(plain.deleted, 0);
    assert!(server.path().join("stale/old.txt").exists(), "nothing is deleted without mirror");

    let (_, mirrored) = sync(phone.path(), server.path(), SyncDirection::ToRight, true).await;
    assert_eq!(mirrored.deleted, 1);
    assert!(!server.path().join("stale").exists());

    write(&server.path().join("keep.txt"), "edited on the server", 5_000);
    let (_, both) = sync(phone.path(), server.path(), SyncDirection::Both, false).await;
    assert_eq!(both.copied, 1);
    assert_eq!(fs::read_to_string(phone.path().join("keep.txt")).unwrap(), "edited on the server");
}

#[tokio::test]
async fn conflicts_are_listed_but_never_applied() {
    let (phone, server) = (tempfile::tempdir().unwrap(), tempfile::tempdir().unwrap());
    write(&phone.path().join("a"), "file here", 100);
    fs::create_dir_all(server.path().join("a")).unwrap();
    let cancel = CancellationToken::new();
    let l = walk(&FileStore::Local, &phone.path().to_string_lossy(), &cancel).await.unwrap();
    let r = walk(&FileStore::Local, &server.path().to_string_lossy(), &cancel).await.unwrap();
    let steps = plan(&l, &r, SyncDirection::ToRight, true);
    assert_eq!(steps.len(), 1);
    assert_eq!(steps[0].kind, SyncActionKind::Conflict);
    let (_, report) = sync(phone.path(), server.path(), SyncDirection::ToRight, true).await;
    assert_eq!((report.copied, report.deleted), (0, 0));
    assert!(server.path().join("a").is_dir());
}
