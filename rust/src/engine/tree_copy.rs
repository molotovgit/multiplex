//! Copies a file or a whole folder from one [`FileStore`] to another:
//! phone to server, server to phone, or server to server (the data then
//! flows through the phone). Progress covers the whole folder.

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio_util::sync::CancellationToken;

use crate::api::sftp_types::{EntryKind, TransferProgress};
use crate::api::transfer_types::{ConflictPolicy, CopyReport};
use crate::engine::events::SharedSink;
use crate::engine::file_store::{FileStore, Meta};
use crate::engine::sftp::ProgressReporter;

const CHUNK: usize = 256 * 1024;

/// One file to copy.
#[derive(Debug, Clone)]
struct Job {
    from: String,
    to: String,
    size: u64,
    modified: Option<i64>,
}

/// Everything a folder copy will do, worked out before any data moves so
/// the progress bar knows the total.
#[derive(Debug, Default)]
struct Plan {
    /// Folders to create, parents before children.
    folders: Vec<String>,
    files: Vec<Job>,
    /// Links to folders, which are not followed (they can loop).
    skipped_links: u32,
}

/// Copies `src` on `from` into the folder `dest_dir` on `to`.
pub async fn copy_item(
    from: &FileStore,
    src: &str,
    to: &FileStore,
    dest_dir: &str,
    policy: ConflictPolicy,
    progress: SharedSink<TransferProgress>,
    cancel: CancellationToken,
) -> anyhow::Result<CopyReport> {
    let meta = from.stat(src).await?.ok_or_else(|| anyhow::anyhow!("\"{src}\" is no longer there"))?;
    let name = from.name_of(src);
    let mut target = to.join(dest_dir, &name);
    let same_store = from.same_as(to);
    if same_store && meta.is_dir && to.is_inside(&target, src) {
        anyhow::bail!("a folder cannot be copied into itself");
    }
    let existing = to.stat(&target).await?;
    if let Some(there) = existing {
        let same_place = same_store && to.is_inside(&target, src) && to.is_inside(src, &target);
        match policy {
            ConflictPolicy::KeepBoth => target = free_name(to, dest_dir, &name, meta.is_dir).await?,
            _ if same_place => anyhow::bail!("this is already in that folder"),
            _ if there.is_dir != meta.is_dir => {
                let what = if there.is_dir { "folder" } else { "file" };
                anyhow::bail!("a {what} called \"{name}\" is already there");
            }
            ConflictPolicy::Skip if !meta.is_dir => {
                return Ok(CopyReport { target, copied: 0, skipped: 1, bytes: 0 });
            }
            _ => {}
        }
    }

    let plan = plan(from, src, &meta, to, &target, &cancel).await?;
    let total = plan.files.iter().map(|f| f.size).sum();
    let mut reporter = ProgressReporter::new(progress, total);
    for folder in &plan.folders {
        if to.stat(folder).await?.is_none() {
            to.make_dir(folder).await?;
        }
    }
    let mut report = CopyReport { target, copied: 0, skipped: plan.skipped_links, bytes: 0 };
    let mut done = 0u64;
    for job in &plan.files {
        if cancel.is_cancelled() {
            anyhow::bail!("transfer cancelled");
        }
        if policy == ConflictPolicy::Skip && to.stat(&job.to).await?.is_some() {
            report.skipped += 1;
            done += job.size;
            reporter.update(done);
            continue;
        }
        let sent = copy_file(from, &job.from, to, &job.to, job.modified, done, &mut reporter, &cancel).await?;
        done += sent;
        report.copied += 1;
        report.bytes += sent;
    }
    reporter.finish(done);
    Ok(report)
}

/// Copies one file. The data goes to "name.part" next to the target and
/// replaces it only when complete, so a failed or cancelled copy never
/// leaves half a file or destroys the one that was there. The copy keeps
/// the original's last-change time when the target allows it. Returns the
/// bytes copied; `base` is what earlier files already added to `reporter`.
#[allow(clippy::too_many_arguments)]
pub(crate) async fn copy_file(
    from: &FileStore,
    src: &str,
    to: &FileStore,
    dst: &str,
    modified: Option<i64>,
    base: u64,
    reporter: &mut ProgressReporter,
    cancel: &CancellationToken,
) -> anyhow::Result<u64> {
    let partial = format!("{dst}.part");
    let mut reader = from.open_read(src).await?;
    let mut writer = to.open_write(&partial).await?;
    let copied = async {
        let mut buf = vec![0u8; CHUNK];
        let mut done = 0u64;
        loop {
            let read = tokio::select! {
                _ = cancel.cancelled() => anyhow::bail!("transfer cancelled"),
                read = reader.read(&mut buf) => read?,
            };
            if read == 0 {
                break;
            }
            writer.write_all(&buf[..read]).await?;
            done += read as u64;
            reporter.update(base + done);
        }
        writer.shutdown().await?;
        Ok(done)
    }
    .await;
    drop(writer);
    let sent = match copied {
        Ok(sent) => sent,
        Err(err) => {
            let _ = to.remove(&partial).await;
            return Err(err);
        }
    };
    if let Err(err) = to.replace(&partial, dst).await {
        let _ = to.remove(&partial).await;
        return Err(err);
    }
    if let Some(secs) = modified {
        // Some servers and phone folders refuse; the copy is still good.
        let _ = to.set_modified(dst, secs).await;
    }
    Ok(sent)
}

/// Walks the source without recursion and lists every folder to make and
/// file to copy.
async fn plan(from: &FileStore, src: &str, meta: &Meta, to: &FileStore, target: &str, cancel: &CancellationToken) -> anyhow::Result<Plan> {
    let mut plan = Plan::default();
    if !meta.is_dir {
        plan.files.push(Job { from: src.to_owned(), to: target.to_owned(), size: meta.size, modified: meta.modified });
        return Ok(plan);
    }
    plan.folders.push(target.to_owned());
    let mut pending = vec![(src.to_owned(), target.to_owned())];
    while let Some((dir, dest)) = pending.pop() {
        if cancel.is_cancelled() {
            anyhow::bail!("transfer cancelled");
        }
        for entry in from.list(&dir).await? {
            let out = to.join(&dest, &entry.name);
            match entry.kind {
                EntryKind::Directory => {
                    plan.folders.push(out.clone());
                    pending.push((entry.path, out));
                }
                EntryKind::File => plan.files.push(Job { from: entry.path, to: out, size: entry.size, modified: entry.modified }),
                EntryKind::Symlink if !entry.is_dir => match from.stat(&entry.path).await? {
                    // A link to a file: copy what it points to.
                    Some(m) => plan.files.push(Job { from: entry.path, to: out, size: m.size, modified: m.modified }),
                    None => plan.skipped_links += 1,
                },
                EntryKind::Symlink | EntryKind::Other => plan.skipped_links += 1,
            }
        }
    }
    Ok(plan)
}

/// "name (1).ext", "name (2).ext"... the first that is free in `dir`.
/// Folders keep their whole name before the number.
async fn free_name(store: &FileStore, dir: &str, name: &str, is_dir: bool) -> anyhow::Result<String> {
    let dot = if is_dir { None } else { name.rfind('.').filter(|&i| i > 0) };
    let (stem, ext) = match dot {
        Some(i) => (&name[..i], &name[i..]),
        None => (name, ""),
    };
    for n in 1..10_000 {
        let candidate = store.join(dir, &format!("{stem} ({n}){ext}"));
        if store.stat(&candidate).await?.is_none() {
            return Ok(candidate);
        }
    }
    anyhow::bail!("no free name found for \"{name}\"")
}
