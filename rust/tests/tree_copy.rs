//! Copying files and folders between file stores. Both sides are folders
//! on this machine here; the server side uses the same code paths through
//! SFTP calls, covered by the live-server test.

use std::fs;
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::{Duration, UNIX_EPOCH};

use multiplex_core::api::sftp_types::TransferProgress;
use multiplex_core::api::transfer_types::ConflictPolicy;
use multiplex_core::engine::file_store::FileStore;
use multiplex_core::engine::tree_copy::copy_item;
use tokio_util::sync::CancellationToken;

fn p(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn write(path: &Path, text: &str) {
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, text).unwrap();
}

fn set_time(path: &Path, secs: u64) {
    fs::File::options().write(true).open(path).unwrap().set_modified(UNIX_EPOCH + Duration::from_secs(secs)).unwrap();
}

fn mtime(path: &Path) -> u64 {
    fs::metadata(path).unwrap().modified().unwrap().duration_since(UNIX_EPOCH).unwrap().as_secs()
}

/// A progress sink that remembers every update.
fn recorder() -> (Arc<Mutex<Vec<TransferProgress>>>, multiplex_core::engine::events::SharedSink<TransferProgress>) {
    let seen = Arc::new(Mutex::new(Vec::new()));
    let sink = seen.clone();
    (seen, Arc::new(move |p: TransferProgress| {
        sink.lock().unwrap().push(p);
        true
    }))
}

/// Every file under `root` with its contents, as "relative path=text".
fn snapshot(root: &Path) -> Vec<String> {
    let mut out = Vec::new();
    let mut pending = vec![root.to_path_buf()];
    while let Some(dir) = pending.pop() {
        for entry in fs::read_dir(&dir).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                pending.push(path);
            } else {
                let rel = path.strip_prefix(root).unwrap().to_string_lossy().replace('\\', "/");
                out.push(format!("{rel}={}", fs::read_to_string(&path).unwrap()));
            }
        }
    }
    out.sort();
    out
}

#[tokio::test]
async fn copies_a_folder_tree_with_times_and_whole_progress() {
    let (from, to) = (tempfile::tempdir().unwrap(), tempfile::tempdir().unwrap());
    let site = from.path().join("site");
    write(&site.join("index.html"), "<h1>hi</h1>");
    write(&site.join("css/main.css"), "body{}");
    write(&site.join("img/deep/logo.svg"), "<svg/>");
    fs::create_dir_all(site.join("empty")).unwrap();
    set_time(&site.join("index.html"), 1_700_000_000);

    let (seen, sink) = recorder();
    let report = copy_item(&FileStore::Local, &p(&site), &FileStore::Local, &p(to.path()), ConflictPolicy::Replace, sink, CancellationToken::new())
        .await
        .unwrap();

    let copied = to.path().join("site");
    assert_eq!(report.target, p(&copied));
    assert_eq!((report.copied, report.skipped, report.bytes), (3, 0, 23));
    assert_eq!(snapshot(&copied), snapshot(&site));
    assert!(copied.join("empty").is_dir(), "empty folders come along");
    assert_eq!(mtime(&copied.join("index.html")), 1_700_000_000, "the copy keeps the original's time");
    let last = *seen.lock().unwrap().last().unwrap();
    assert_eq!((last.transferred, last.total), (23, 23));
}

#[tokio::test]
async fn skip_leaves_what_is_there_and_fills_in_the_rest() {
    let (from, to) = (tempfile::tempdir().unwrap(), tempfile::tempdir().unwrap());
    write(&from.path().join("conf/a.ini"), "new a");
    write(&from.path().join("conf/b.ini"), "new b");
    write(&to.path().join("conf/a.ini"), "old a");

    let (_, sink) = recorder();
    let report = copy_item(&FileStore::Local, &p(&from.path().join("conf")), &FileStore::Local, &p(to.path()), ConflictPolicy::Skip, sink, CancellationToken::new())
        .await
        .unwrap();
    assert_eq!((report.copied, report.skipped), (1, 1));
    assert_eq!(snapshot(&to.path().join("conf")), ["a.ini=old a", "b.ini=new b"]);

    // A single file that is there is skipped without touching it.
    let (_, sink) = recorder();
    let report = copy_item(&FileStore::Local, &p(&from.path().join("conf/a.ini")), &FileStore::Local, &p(&to.path().join("conf")), ConflictPolicy::Skip, sink, CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(report.skipped, 1);
    assert_eq!(fs::read_to_string(to.path().join("conf/a.ini")).unwrap(), "old a");
}

#[tokio::test]
async fn replace_overwrites_and_keep_both_picks_a_free_name() {
    let (from, to) = (tempfile::tempdir().unwrap(), tempfile::tempdir().unwrap());
    write(&from.path().join("notes.txt"), "new");
    write(&to.path().join("notes.txt"), "old");
    write(&to.path().join("notes (1).txt"), "older");
    let src = p(&from.path().join("notes.txt"));

    let (_, sink) = recorder();
    let kept = copy_item(&FileStore::Local, &src, &FileStore::Local, &p(to.path()), ConflictPolicy::KeepBoth, sink, CancellationToken::new()).await.unwrap();
    assert_eq!(kept.target, p(&to.path().join("notes (2).txt")));
    assert_eq!(fs::read_to_string(to.path().join("notes.txt")).unwrap(), "old");

    let (_, sink) = recorder();
    copy_item(&FileStore::Local, &src, &FileStore::Local, &p(to.path()), ConflictPolicy::Replace, sink, CancellationToken::new()).await.unwrap();
    assert_eq!(fs::read_to_string(to.path().join("notes.txt")).unwrap(), "new");
    assert!(!to.path().join("notes.txt.part").exists());

    // Keep both on a folder numbers the whole folder name.
    write(&from.path().join("logs.d/x.log"), "x");
    fs::create_dir_all(to.path().join("logs.d")).unwrap();
    let (_, sink) = recorder();
    let kept = copy_item(&FileStore::Local, &p(&from.path().join("logs.d")), &FileStore::Local, &p(to.path()), ConflictPolicy::KeepBoth, sink, CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(kept.target, p(&to.path().join("logs.d (1)")));
}

#[tokio::test]
async fn refuses_copies_that_would_destroy_or_loop() {
    let dir = tempfile::tempdir().unwrap();
    write(&dir.path().join("app/main.py"), "print(1)");
    write(&dir.path().join("other/app"), "a file, not a folder");
    let app = p(&dir.path().join("app"));
    let local = FileStore::Local;

    let (_, sink) = recorder();
    let into_itself = copy_item(&local, &app, &local, &p(&dir.path().join("app/sub")), ConflictPolicy::Replace, sink, CancellationToken::new()).await;
    assert!(into_itself.unwrap_err().to_string().contains("into itself"));

    let (_, sink) = recorder();
    let onto_itself = copy_item(&local, &p(&dir.path().join("app/main.py")), &local, &app, ConflictPolicy::Replace, sink, CancellationToken::new()).await;
    assert!(onto_itself.is_err());
    assert_eq!(fs::read_to_string(dir.path().join("app/main.py")).unwrap(), "print(1)", "the file survives");

    let (_, sink) = recorder();
    let clash = copy_item(&local, &app, &local, &p(&dir.path().join("other")), ConflictPolicy::Replace, sink, CancellationToken::new()).await;
    assert!(clash.unwrap_err().to_string().contains("a file called \"app\""));
}

#[tokio::test]
async fn a_cancelled_copy_leaves_no_half_files() {
    let (from, to) = (tempfile::tempdir().unwrap(), tempfile::tempdir().unwrap());
    write(&from.path().join("big.bin"), &"x".repeat(1 << 20));
    write(&to.path().join("big.bin"), "the old one");
    let cancel = CancellationToken::new();
    cancel.cancel();
    let (_, sink) = recorder();
    let result = copy_item(&FileStore::Local, &p(&from.path().join("big.bin")), &FileStore::Local, &p(to.path()), ConflictPolicy::Replace, sink, cancel).await;
    assert!(result.unwrap_err().to_string().contains("cancelled"));
    assert_eq!(fs::read_to_string(to.path().join("big.bin")).unwrap(), "the old one");
    assert!(!to.path().join("big.bin.part").exists());
}

#[tokio::test]
async fn lists_local_folders_like_server_folders() {
    let dir = tempfile::tempdir().unwrap();
    write(&dir.path().join("b.txt"), "12345");
    fs::create_dir_all(dir.path().join("a-folder")).unwrap();
    write(&dir.path().join("C.txt"), "");
    let entries = FileStore::Local.list(&p(dir.path())).await.unwrap();
    let names: Vec<_> = entries.iter().map(|e| (e.name.as_str(), e.is_dir, e.size)).collect();
    assert_eq!(names, [("a-folder", true, 0), ("b.txt", false, 5), ("C.txt", false, 0)]);
    assert_eq!(entries[1].path, p(&dir.path().join("b.txt")));
    assert!(FileStore::Local.stat(&p(&dir.path().join("nope"))).await.unwrap().is_none());
}
