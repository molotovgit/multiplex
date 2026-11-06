//! Keeps two folders in step: works out what differs by size and change
//! time (a plan the user sees first), then applies it. Nothing is deleted
//! unless the plan was made with "mirror" on.

use std::collections::{BTreeMap, HashSet};

use tokio_util::sync::CancellationToken;

use crate::api::sftp_types::{EntryKind, TransferProgress};
use crate::api::transfer_types::{SyncAction, SyncActionKind, SyncDirection, SyncReason, SyncReport};
use crate::engine::events::SharedSink;
use crate::engine::file_store::{FileStore, Meta};
use crate::engine::sftp::ProgressReporter;
use crate::engine::tree_copy::copy_file;

/// Everything under a folder, by path inside it ("a/b.txt").
pub type Tree = BTreeMap<String, Meta>;

/// Change times this close count as the same: FAT cards and some servers
/// keep times to 2 seconds.
pub const TIME_SLACK: i64 = 2;

/// Lists everything under `root` without recursion. Links to folders are
/// left out (they can loop); links to files count as the file.
pub async fn walk(store: &FileStore, root: &str, cancel: &CancellationToken) -> anyhow::Result<Tree> {
    let mut tree = Tree::new();
    let mut pending = vec![(root.to_owned(), String::new())];
    while let Some((dir, rel)) = pending.pop() {
        if cancel.is_cancelled() {
            anyhow::bail!("sync cancelled");
        }
        for entry in store.list(&dir).await? {
            let path = if rel.is_empty() { entry.name.clone() } else { format!("{rel}/{}", entry.name) };
            match entry.kind {
                EntryKind::Directory => {
                    tree.insert(path.clone(), Meta { is_dir: true, size: 0, modified: entry.modified });
                    pending.push((entry.path, path));
                }
                EntryKind::File => {
                    tree.insert(path, Meta { is_dir: false, size: entry.size, modified: entry.modified });
                }
                EntryKind::Symlink if !entry.is_dir => {
                    if let Some(meta) = store.stat(&entry.path).await? {
                        tree.insert(path, meta);
                    }
                }
                EntryKind::Symlink | EntryKind::Other => {}
            }
        }
    }
    Ok(tree)
}

/// True when two files look the same: same size, and the same time when
/// both sides know it.
fn same(a: &Meta, b: &Meta) -> bool {
    a.size == b.size
        && match (a.modified, b.modified) {
            (Some(x), Some(y)) => (x - y).abs() <= TIME_SLACK,
            _ => true,
        }
}

fn action(path: &str, kind: SyncActionKind, reason: SyncReason, meta: &Meta) -> SyncAction {
    let copies = matches!(kind, SyncActionKind::CopyToLeft | SyncActionKind::CopyToRight);
    SyncAction { path: path.to_owned(), kind, reason, is_dir: meta.is_dir, size: if copies && !meta.is_dir { meta.size } else { 0 } }
}

/// True when some entry in `tree` lies inside folder `dir`.
fn has_children(tree: &Tree, dir: &str) -> bool {
    let prefix = format!("{dir}/");
    tree.range(prefix.clone()..).next().is_some_and(|(k, _)| k.starts_with(&prefix))
}

/// The plan: what to copy which way, what to delete, and what clashes.
pub fn plan(left: &Tree, right: &Tree, direction: SyncDirection, mirror: bool) -> Vec<SyncAction> {
    let mut out = match direction {
        SyncDirection::ToRight => one_way(left, right, mirror, SyncActionKind::CopyToRight, SyncActionKind::DeleteOnRight),
        SyncDirection::ToLeft => one_way(right, left, mirror, SyncActionKind::CopyToLeft, SyncActionKind::DeleteOnLeft),
        SyncDirection::Both => both_ways(left, right),
    };
    out.sort_by(|a, b| a.path.cmp(&b.path));
    out
}

fn one_way(src: &Tree, dst: &Tree, mirror: bool, copy: SyncActionKind, delete: SyncActionKind) -> Vec<SyncAction> {
    let mut out = Vec::new();
    for (path, meta) in src {
        match dst.get(path) {
            None if meta.is_dir => {
                // A missing folder comes along with its files; only an empty one needs its own step.
                if !has_children(src, path) {
                    out.push(action(path, copy, SyncReason::New, meta));
                }
            }
            None => out.push(action(path, copy, SyncReason::New, meta)),
            Some(there) if there.is_dir != meta.is_dir => out.push(action(path, SyncActionKind::Conflict, SyncReason::TypeClash, meta)),
            Some(there) if !meta.is_dir && !same(meta, there) => out.push(action(path, copy, SyncReason::Changed, meta)),
            Some(_) => {}
        }
    }
    if mirror {
        let mut gone: Vec<&str> = Vec::new();
        for (path, meta) in dst {
            if src.contains_key(path) || gone.iter().any(|g| path.starts_with(&format!("{g}/"))) {
                continue;
            }
            gone.push(path);
            out.push(action(path, delete, SyncReason::Extra, meta));
        }
    }
    out
}

fn both_ways(left: &Tree, right: &Tree) -> Vec<SyncAction> {
    let mut out = Vec::new();
    for (path, l) in left {
        match right.get(path) {
            None if l.is_dir && has_children(left, path) => {}
            None => out.push(action(path, SyncActionKind::CopyToRight, SyncReason::New, l)),
            Some(r) if r.is_dir != l.is_dir => out.push(action(path, SyncActionKind::Conflict, SyncReason::TypeClash, l)),
            Some(r) if !l.is_dir && !same(l, r) => match (l.modified, r.modified) {
                (Some(a), Some(b)) if a > b + TIME_SLACK => out.push(action(path, SyncActionKind::CopyToRight, SyncReason::Newer, l)),
                (Some(a), Some(b)) if b > a + TIME_SLACK => out.push(action(path, SyncActionKind::CopyToLeft, SyncReason::Newer, r)),
                _ => out.push(action(path, SyncActionKind::Conflict, SyncReason::Undecided, l)),
            },
            Some(_) => {}
        }
    }
    for (path, r) in right {
        if left.contains_key(path) || (r.is_dir && has_children(right, path)) {
            continue;
        }
        out.push(action(path, SyncActionKind::CopyToLeft, SyncReason::New, r));
    }
    out
}

/// Runs a plan. Each step that fails is noted and the rest carry on;
/// conflicts are skipped. Progress covers the bytes copied.
pub async fn apply(
    left: &FileStore,
    left_root: &str,
    right: &FileStore,
    right_root: &str,
    actions: &[SyncAction],
    progress: SharedSink<TransferProgress>,
    cancel: CancellationToken,
) -> anyhow::Result<SyncReport> {
    let total = actions.iter().map(|a| a.size).sum();
    let mut reporter = ProgressReporter::new(progress, total);
    let mut report = SyncReport { copied: 0, deleted: 0, failed: Vec::new() };
    let mut made: HashSet<String> = HashSet::new();
    let mut done = 0u64;
    for step in actions {
        if cancel.is_cancelled() {
            anyhow::bail!("sync cancelled");
        }
        let result = match step.kind {
            SyncActionKind::Conflict => continue,
            SyncActionKind::CopyToRight => copy_step(left, left_root, right, right_root, step, &mut made, done, &mut reporter, &cancel).await,
            SyncActionKind::CopyToLeft => copy_step(right, right_root, left, left_root, step, &mut made, done, &mut reporter, &cancel).await,
            SyncActionKind::DeleteOnRight => right.remove(&inside(right, right_root, &step.path)).await.map(|_| 0),
            SyncActionKind::DeleteOnLeft => left.remove(&inside(left, left_root, &step.path)).await.map(|_| 0),
        };
        match result {
            Ok(bytes) => {
                done += bytes;
                if matches!(step.kind, SyncActionKind::DeleteOnLeft | SyncActionKind::DeleteOnRight) {
                    report.deleted += 1;
                } else {
                    report.copied += 1;
                }
            }
            Err(_) if cancel.is_cancelled() => anyhow::bail!("sync cancelled"),
            Err(err) => {
                done += step.size;
                report.failed.push(format!("{}: {err}", step.path));
            }
        }
        reporter.update(done);
    }
    reporter.finish(done);
    Ok(report)
}

/// `root` + "a/b/c" in the store's own path style.
fn inside(store: &FileStore, root: &str, rel: &str) -> String {
    rel.split('/').fold(root.to_owned(), |path, part| store.join(&path, part))
}

#[allow(clippy::too_many_arguments)]
async fn copy_step(
    from: &FileStore,
    from_root: &str,
    to: &FileStore,
    to_root: &str,
    step: &SyncAction,
    made: &mut HashSet<String>,
    base: u64,
    reporter: &mut ProgressReporter,
    cancel: &CancellationToken,
) -> anyhow::Result<u64> {
    // Make the folders on the way, each checked only once per sync.
    let parts: Vec<&str> = step.path.split('/').collect();
    let folders = if step.is_dir { parts.len() } else { parts.len() - 1 };
    let mut path = to_root.to_owned();
    for part in &parts[..folders] {
        path = to.join(&path, part);
        if made.insert(path.clone()) && to.stat(&path).await?.is_none() {
            to.make_dir(&path).await?;
        }
    }
    if step.is_dir {
        return Ok(0);
    }
    let src = inside(from, from_root, &step.path);
    let meta = from.stat(&src).await?.ok_or_else(|| anyhow::anyhow!("it is no longer there"))?;
    copy_file(from, &src, to, &inside(to, to_root, &step.path), meta.modified, base, reporter, cancel).await
}

#[cfg(test)]
mod tests {
    use super::*;

    fn file(size: u64, t: i64) -> Meta {
        Meta { is_dir: false, size, modified: Some(t) }
    }

    fn dir() -> Meta {
        Meta { is_dir: true, size: 0, modified: None }
    }

    fn tree(items: &[(&str, Meta)]) -> Tree {
        items.iter().map(|(p, m)| ((*p).to_owned(), *m)).collect()
    }

    fn steps(plan: &[SyncAction]) -> Vec<String> {
        plan.iter().map(|a| format!("{:?} {:?} {}", a.kind, a.reason, a.path)).collect()
    }

    #[test]
    fn one_way_copies_new_and_changed_and_deletes_only_when_mirroring() {
        let left = tree(&[("a.txt", file(1, 100)), ("b.txt", file(2, 100)), ("c.txt", file(3, 100)), ("docs", dir()), ("docs/x.md", file(4, 100)), ("empty", dir())]);
        let right = tree(&[("a.txt", file(1, 101)), ("b.txt", file(9, 100)), ("old", dir()), ("old/y", file(1, 1)), ("z.log", file(1, 1))]);
        let plain = plan(&left, &right, SyncDirection::ToRight, false);
        assert_eq!(
            steps(&plain),
            ["CopyToRight Changed b.txt", "CopyToRight New c.txt", "CopyToRight New docs/x.md", "CopyToRight New empty"],
            "a.txt is within the 2-second slack; docs comes with its file"
        );
        assert_eq!(plain[0].size, 2);
        let mirror = plan(&left, &right, SyncDirection::ToRight, true);
        assert_eq!(steps(&mirror)[4..], ["DeleteOnRight Extra old", "DeleteOnRight Extra z.log"], "old/y goes with its folder");
        let back = plan(&left, &right, SyncDirection::ToLeft, false);
        assert_eq!(steps(&back), ["CopyToLeft Changed b.txt", "CopyToLeft New old/y", "CopyToLeft New z.log"]);
    }

    #[test]
    fn both_ways_newer_wins_and_unclear_cases_wait_for_the_user() {
        let left = tree(&[("new-here", file(1, 5)), ("edited", file(5, 500)), ("older", file(5, 100)), ("same-time", file(1, 300)), ("clash", dir())]);
        let right = tree(&[("new-there", file(1, 5)), ("edited", file(4, 100)), ("older", file(6, 400)), ("same-time", file(2, 300)), ("clash", file(1, 1))]);
        assert_eq!(
            steps(&plan(&left, &right, SyncDirection::Both, true)),
            [
                "Conflict TypeClash clash",
                "CopyToRight Newer edited",
                "CopyToRight New new-here",
                "CopyToLeft New new-there",
                "CopyToLeft Newer older",
                "Conflict Undecided same-time",
            ]
        );
    }

    #[test]
    fn unknown_times_compare_by_size_only() {
        let left = tree(&[("a", Meta { is_dir: false, size: 3, modified: None })]);
        assert!(plan(&left, &tree(&[("a", file(3, 9))]), SyncDirection::ToRight, false).is_empty());
        assert_eq!(plan(&left, &tree(&[("a", file(4, 9))]), SyncDirection::ToRight, false).len(), 1);
    }
}
