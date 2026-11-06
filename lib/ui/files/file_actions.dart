import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../sessions/session_manager.dart';
import '../../src/rust/api/sftp_types.dart';
import '../common/widgets.dart';
import 'entry_tile.dart';
import 'file_editor_screen.dart';
import 'file_format.dart';
import 'files_widgets.dart';
import 'folder_browser.dart';
import 'permissions_dialog.dart';
import 'preview/preview_files.dart';
import 'preview/preview_screen.dart';
import 'remote_paths.dart';
import 'text_prompt_dialog.dart';
import 'transfer_queue.dart';
import 'transfer_tasks.dart';

/// Everything the user can do on the files screen, each step with its
/// dialog, the server call and a message when it fails. Each method takes
/// the screen's context and checks it is still there after every wait.
class FileActions {
  FileActions({required this.session, required this.browser, required this.queue, required this.connection});

  final LiveSession session;
  final FolderBrowser browser;
  final TransferQueue queue;
  final ConnectionWatch connection;

  /// Runs one server call with the progress bar showing. On failure:
  /// re-checks the connection and shows what failed and why. Returns true
  /// on success.
  Future<bool> _attempt(BuildContext context, String failure, Future<void> Function() call) async {
    try {
      await browser.track(call);
      return true;
    } catch (error) {
      connection.check();
      if (context.mounted) Toast.show(context, '$failure. ${FileErrors.message(error)}');
      return false;
    }
  }

  /// Says a change worked and offers to put it back. Undo is only offered
  /// where reversing is a single cheap call (rename, permissions).
  void _doneWithUndo(BuildContext context, String message, String undoFailure, Future<void> Function() undo) {
    if (!context.mounted) return;
    FileToasts.withAction(
      context,
      message,
      label: 'Undo',
      onPressed: () async {
        if (await _attempt(context, undoFailure, undo)) await browser.refresh();
      },
    );
  }

  /// Waits for a browser step and shows its error, if there is one.
  Future<void> _report(BuildContext context, String failure, Future<String?> step) async {
    final error = await step;
    if (error == null) return;
    connection.check();
    if (context.mounted) Toast.show(context, '$failure. $error');
  }

  Future<void> openFolder(BuildContext context, String path) =>
      _report(context, 'Could not open ${RemotePaths.name(path)}', browser.open(path));

  Future<void> up(BuildContext context) => _report(context, 'Could not open the folder above', browser.up());

  Future<void> refresh(BuildContext context) => _report(context, 'Could not refresh this folder', browser.refresh());

  Future<void> goHome(BuildContext context) => openFolder(context, browser.home);

  Future<void> goTo(BuildContext context) async {
    final typed = await TextPromptDialog.show(
      context,
      title: 'Go to folder',
      label: 'Folder path',
      hint: '/var/log',
      message: 'Type a full path, or start with ~ for your home folder.',
      action: 'Open folder',
      initial: browser.path,
      mono: true,
    );
    if (typed == null || !context.mounted) return;
    await _report(context, 'Could not open $typed', browser.goTo(typed));
  }

  /// Opens a folder, a picture or PDF in the preview, or any other file
  /// in the editor. Files over the limits get an offer to download them.
  Future<void> open(BuildContext context, RemoteEntry entry) async {
    if (entry.isDir) return openFolder(context, entry.path);
    if (entry.kind == EntryKind.other) {
      Toast.show(context, '"${entry.name}" is a special file, such as a device or a socket, so it cannot be opened.');
      return;
    }
    var target = entry;
    if (entry.kind == EntryKind.symlink) {
      // The list shows the link itself; the size that matters is the target's.
      final found = await _attempt(context, 'Could not follow the link "${entry.name}"', () async {
        target = await browser.files.stat(path: entry.path);
      });
      if (!found || !context.mounted) return;
    }
    final preview = PreviewKind.of(entry.name);
    if (preview != null) return _preview(context, entry, target, preview);
    if (target.size > BigInt.from(FileEditorScreen.maxBytes)) {
      final download = await Confirm.ask(
        context,
        title: 'Too big to open here',
        message: '"${entry.name}" is ${FileSizes.human(target.size)}. Files up to 1 MB open in the editor. '
            'Download it to open it on this device instead.',
        action: 'Download file',
        destructive: false,
      );
      if (download && context.mounted) this.download(context, entry);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => FileEditorScreen(session: session, files: browser.files, path: entry.path, name: entry.name)),
    );
    // Shows the new size and date if the file was saved.
    await browser.refresh();
  }

  /// Shows a picture or PDF without saving it. Very big ones are offered
  /// as a download instead.
  Future<void> _preview(BuildContext context, RemoteEntry entry, RemoteEntry target, PreviewKind kind) async {
    if (target.size > BigInt.from(kind.maxBytes)) {
      final download = await Confirm.ask(
        context,
        title: 'Too big to preview',
        message: '"${entry.name}" is ${FileSizes.human(target.size)}, too big to show here. Download it to open it on this device instead.',
        action: 'Download file',
        destructive: false,
      );
      if (download && context.mounted) this.download(context, entry);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PreviewScreen(files: browser.files, entry: entry, kind: kind, onDownload: () => download(context, entry)),
      ),
    );
  }

  /// Runs what the user picked in an entry's menu.
  Future<void> run(BuildContext context, RemoteEntry entry, EntryAction action) => switch (action) {
    EntryAction.rename => rename(context, entry),
    EntryAction.permissions => permissions(context, entry),
    EntryAction.copyPath => Toast.copy(context, entry.path, what: 'Path copied'),
    EntryAction.download => Future.sync(() => download(context, entry)),
    EntryAction.delete => delete(context, entry),
  };

  /// Says what is wrong with a name for something new in this folder.
  String? _nameProblem(String name, {String? except}) {
    final problem = RemotePaths.nameProblem(name);
    if (problem != null) return problem;
    if (name != except && browser.entryNamed(name) != null) return 'Something called "$name" is already in this folder. Choose another name.';
    return null;
  }

  Future<void> rename(BuildContext context, RemoteEntry entry) async {
    final name = await TextPromptDialog.show(
      context,
      title: 'Rename',
      label: 'New name',
      action: 'Rename',
      initial: entry.name,
      selectStem: !entry.isDir,
      validate: (text) => _nameProblem(text, except: entry.name),
    );
    if (name == null || name == entry.name || !context.mounted) return;
    final to = RemotePaths.join(RemotePaths.parent(entry.path), name);
    if (!await _attempt(context, 'Could not rename "${entry.name}"', () => browser.files.rename(from: entry.path, to: to))) return;
    await browser.refresh();
    if (!context.mounted) return;
    _doneWithUndo(context, 'Renamed to $name', 'Could not change the name back', () => browser.files.rename(from: to, to: entry.path));
  }

  Future<void> permissions(BuildContext context, RemoteEntry entry) async {
    var target = entry;
    String? note;
    if (entry.kind == EntryKind.symlink) {
      // Changing a link's permissions changes what it points to, so show those.
      final found = await _attempt(context, 'Could not follow the link "${entry.name}"', () async {
        target = await browser.files.stat(path: entry.path);
      });
      if (!found || !context.mounted) return;
      note = 'This is a link. The change applies to what it points to.';
    }
    final mode = await PermissionsDialog.show(context, name: entry.name, mode: target.permissions, kind: target.kind, note: note);
    if (mode == null || !context.mounted) return;
    final before = target.permissions & FileModes.mask;
    if (mode == before) return;
    final changed = await _attempt(
      context,
      'Could not change the permissions of "${entry.name}"',
      () => browser.files.setPermissions(path: entry.path, mode: mode),
    );
    if (!changed) return;
    await browser.refresh();
    if (!context.mounted) return;
    _doneWithUndo(
      context,
      'Permissions of ${entry.name} set to ${FileModes.octal(mode)}',
      'Could not put the permissions back',
      () => browser.files.setPermissions(path: entry.path, mode: before),
    );
  }

  Future<void> delete(BuildContext context, RemoteEntry entry) async {
    final (what, message) = switch (entry.kind) {
      EntryKind.directory => ('folder', 'The folder and everything inside it will be deleted from the server. This cannot be undone.'),
      EntryKind.symlink => ('link', 'Only the link is deleted. What it points to stays on the server.'),
      _ => ('file', 'The file will be deleted from the server. This cannot be undone.'),
    };
    final sure = await Confirm.ask(context, title: 'Delete "${entry.name}"?', message: message, action: 'Delete $what');
    if (!sure || !context.mounted) return;
    if (!await _attempt(context, 'Could not delete "${entry.name}"', () => browser.files.remove(path: entry.path))) return;
    await browser.refresh();
    if (context.mounted) Toast.show(context, 'Deleted ${entry.name}');
  }

  Future<void> newFolder(BuildContext context) async {
    final name = await TextPromptDialog.show(
      context,
      title: 'New folder',
      label: 'Folder name',
      action: 'Create folder',
      validate: (text) => _nameProblem(text),
    );
    if (name == null || !context.mounted) return;
    final path = RemotePaths.join(browser.path, name);
    if (!await _attempt(context, 'Could not create the folder "$name"', () => browser.files.makeDir(path: path))) return;
    await browser.refresh();
    if (context.mounted) Toast.show(context, 'Created folder $name');
  }

  /// Queues a download. The panel shows its progress; the screen shows
  /// where it was saved once it is done.
  void download(BuildContext context, RemoteEntry entry) {
    queue.add(DownloadTask(files: browser.files, entry: entry));
  }

  /// Picks local files and uploads each into the current folder, after
  /// asking before any file on the server is replaced.
  Future<void> upload(BuildContext context) async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(dialogTitle: 'Choose files to upload');
    } catch (error) {
      if (context.mounted) Toast.show(context, 'Could not open the file picker. ${FileErrors.message(error)}');
      return;
    }
    if (picked.isEmpty || !context.mounted) return;
    final folder = browser.path;
    final clashes = picked.where((f) => browser.entryNamed(f.name) != null).toList();
    final folderClash = clashes.where((f) => browser.entryNamed(f.name)!.isDir).firstOrNull;
    if (folderClash != null) {
      Toast.show(context, 'A folder called "${folderClash.name}" is already here, so a file with that name cannot be uploaded. Rename one of them first.');
      return;
    }
    if (clashes.isNotEmpty) {
      final names = clashes.length == 1 ? '"${clashes.first.name}" is' : '${clashes.length} of these files are';
      final replace = await Confirm.ask(
        context,
        title: clashes.length == 1 ? 'Replace file?' : 'Replace ${clashes.length} files?',
        message: '$names already in this folder. Uploading replaces ${clashes.length == 1 ? 'it' : 'them'} on the server.',
        action: clashes.length == 1 ? 'Replace file' : 'Replace files',
      );
      if (!replace) return;
    }
    for (final file in picked) {
      queue.add(UploadTask(files: browser.files, source: UploadSource.picked(file), remoteFolder: folder));
    }
  }
}
