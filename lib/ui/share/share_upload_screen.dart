import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../platform/incoming_actions.dart';
import '../../sessions/session_manager.dart';
import '../../src/rust/api/sftp.dart';
import '../common/widgets.dart';
import '../files/file_format.dart';
import '../files/remote_paths.dart';
import '../files/transfer_panel.dart';
import '../files/transfer_queue.dart';
import '../files/transfer_tasks.dart';
import '../hosts/host_connector.dart';
import '../keys/page_width.dart';
import '../snippets/host_picker.dart';
import '../snippets/remote_runner.dart';
import 'remote_folder_picker.dart';

/// A file another app shared. The copy in the app's cache is deleted once
/// its upload has ended, however it ended.
class SharedUploadSource extends UploadSource {
  SharedUploadSource(SharedFile file) : super(name: file.name, path: file.path);

  @override
  Future<void> release() async {
    await super.release();
    await SharedFiles.delete(path!);
  }
}

/// Removes the cached copies of shared files.
abstract final class SharedFiles {
  static Future<void> delete(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Already gone; Android also clears old shares by itself.
    }
  }
}

/// "Upload to a server" for files shared from another app: pick a saved
/// host and a folder there (the one used last time for that host, or the
/// home folder), then the files upload over SFTP with progress.
class ShareUploadScreen extends StatefulWidget {
  const ShareUploadScreen({super.key, required this.files, this.connect, this.queueFor});

  final List<SharedFile> files;

  /// Replaced in tests; connects the way the rest of the app does.
  final Future<LiveSession?> Function(BuildContext context, Host host)? connect;
  final TransferQueue Function(LiveSession session)? queueFor;

  static Future<void> open(BuildContext context, List<SharedFile> files) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShareUploadScreen(files: files)));

  @override
  State<ShareUploadScreen> createState() => _ShareUploadScreenState();
}

class _ShareUploadScreenState extends State<ShareUploadScreen> {
  Host? _host;
  RemoteFiles? _remote;
  TransferQueue? _queue;
  String? _folder;
  String? _problem;
  bool _busy = false;
  List<TransferJob> _jobs = const [];

  bool get _started => _jobs.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Most of the time there is only one question left: which server.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickHost());
  }

  @override
  void dispose() {
    // Files that never started uploading are not needed any more.
    if (!_started) {
      for (final file in widget.files) {
        SharedFiles.delete(file.path);
      }
    }
    super.dispose();
  }

  Future<void> _pickHost() async {
    if (_started || _busy) return;
    final host = await HostPicker.pick(context, title: 'Upload to which server?');
    if (host == null || !mounted) return;
    setState(() {
      _busy = true;
      _problem = null;
      _host = host;
      _remote = null;
      _folder = null;
    });
    try {
      final session = await (widget.connect ?? HostConnector.connect)(context, host);
      if (session == null || !mounted) {
        if (mounted) setState(() => _host = null);
        return;
      }
      final remote = await session.ssh.openFiles();
      final folder = await _startFolder(remote, host.uploadFolder);
      if (!mounted) return;
      setState(() {
        _remote = remote;
        _queue = (widget.queueFor ?? TransferQueue.of)(session);
        _folder = folder;
      });
    } catch (error) {
      if (mounted) setState(() => _problem = 'Could not open the files of ${host.title}. ${ErrorText.of(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The folder used last time, if it is still there; otherwise home.
  static Future<String> _startFolder(RemoteFiles remote, String? remembered) async {
    if (remembered != null) {
      try {
        if ((await remote.stat(path: remembered)).isDir) return remembered;
      } catch (_) {
        // Gone or not allowed any more: start at home instead.
      }
    }
    return remote.home();
  }

  Future<void> _pickFolder() async {
    final remote = _remote;
    if (remote == null) return;
    final folder = await RemoteFolderPicker.pick(context, files: remote, start: _folder);
    if (folder != null && mounted) setState(() => _folder = folder);
  }

  void _upload() {
    final host = _host, remote = _remote, queue = _queue, folder = _folder;
    if (host == null || remote == null || queue == null || folder == null) return;
    // Remembered for next time.
    final store = AppScope.store(context);
    final saved = store.host(host.id);
    if (saved != null) store.saveHost(saved.copyWith(uploadFolder: () => folder));
    setState(() {
      _jobs = [for (final file in widget.files) queue.add(UploadTask(files: remote, source: SharedUploadSource(file), remoteFolder: folder))];
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.files.length;
    return Scaffold(
      appBar: AppBar(title: Text(count == 1 ? 'Upload 1 file' : 'Upload $count files')),
      body: PageWidth(child: _started ? _progress(context) : _choices(context)),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _started
              ? ListenableBuilder(
                  listenable: _queue!,
                  builder: (context, _) =>
                      FilledButton(onPressed: () => Navigator.pop(context), child: Text(_jobs.any((j) => j.isActive) ? 'Hide (keeps uploading)' : 'Done')),
                )
              : FilledButton.icon(onPressed: _remote != null && !_busy ? _upload : null, icon: const Icon(Icons.upload_outlined), label: const Text('Upload')),
        ),
      ),
    );
  }

  Widget _choices(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final host = _host;
    return ListView(
      children: [
        const SectionHeader('Server'),
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: Text(host?.title ?? 'Choose a server'),
          subtitle: host == null ? null : MonoText(host.target, maxLines: 1),
          trailing: _busy ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.chevron_right),
          onTap: _busy ? null : _pickHost,
        ),
        if (_folder != null) ...[
          const SectionHeader('Folder'),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: MonoText(_folder!, maxLines: 2),
            subtitle: const Text('Tap to choose another folder'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickFolder,
          ),
        ],
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_problem!, style: TextStyle(color: colors.danger)),
          ),
        const SectionHeader('Files'),
        for (final file in widget.files)
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_sizeOf(file)),
          ),
      ],
    );
  }

  Widget _progress(BuildContext context) {
    return ListenableBuilder(
      listenable: _queue!,
      builder: (context, _) {
        final done = _jobs.where((j) => j.state == TransferState.done).length;
        final active = _jobs.any((j) => j.isActive);
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                active ? 'Uploading to ${RemotePaths.name(_folder!)} on ${_host!.title}…' : 'Uploaded $done of ${_jobs.length} to $_folder on ${_host!.title}.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final job in _jobs) TransferRow(job: job, onCancel: () => _queue!.cancel(job)),
          ],
        );
      },
    );
  }

  static String _sizeOf(SharedFile file) {
    try {
      return FileSizes.human(BigInt.from(File(file.path).lengthSync()));
    } on FileSystemException {
      return 'Size unknown';
    }
  }
}
