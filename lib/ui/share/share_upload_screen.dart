import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../platform/incoming_actions.dart';
import '../../sessions/computer_links.dart';
import '../../sessions/phone_outbox.dart';
import '../../sessions/session_manager.dart';
import '../../src/rust/api/sftp.dart';
import '../common/widgets.dart';
import '../computers/scan_text.dart';
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
import '../../src/rust/api/share.dart';

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

/// What a paired computer does with something shared to it. The real
/// ones are commands in the Rust core; tests replace them.
class ComputerShare {
  const ComputerShare();

  /// The folder files go to (its Downloads).
  Future<String> inbox(LiveSession session) => session.ssh.shareInbox();

  /// Has the computer say on its screen what arrived.
  Future<void> received(LiveSession session, String phone, List<String> names) => session.ssh.shareReceived(phone: phone, names: names);

  Future<void> copy(LiveSession session, String text) => session.ssh.shareCopy(text: text);

  Future<void> open(LiveSession session, String url) => session.ssh.shareOpen(url: url);

  /// Whether text is a web link the computer would open.
  bool isLink(String text) => shareIsLink(text: text.trim());
}

/// "Upload to a server" for files shared from another app: pick a saved
/// host and a folder there (the one used last time for that host, or the
/// home folder), then the files upload over SFTP with progress.
class ShareUploadScreen extends StatefulWidget {
  const ShareUploadScreen({
    super.key,
    required this.files,
    this.text,
    this.connect,
    this.queueFor,
    this.computer = const ComputerShare(),
    this.outbox,
    this.sendTo,
  });

  /// Where files wait for a computer that is out of reach. Replaced in tests.
  final PhoneOutbox? outbox;

  /// The id of the paired computer chosen by name in Android's share
  /// sheet: files go to it at once, with nothing more to tap.
  final String? sendTo;

  final List<SharedFile> files;

  /// Set when text was shared, not files: a paired computer takes it on
  /// its clipboard, or opens it when it is a link.
  final String? text;

  /// What a paired computer does with a share. Replaced in tests.
  final ComputerShare computer;

  /// Replaced in tests; connects the way the rest of the app does.
  final Future<LiveSession?> Function(BuildContext context, Host host)? connect;
  final TransferQueue Function(LiveSession session)? queueFor;

  static Future<void> open(BuildContext context, List<SharedFile> files, {String? text, String? sendTo}) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ShareUploadScreen(files: files, text: text, sendTo: sendTo),
    ),
  );

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

  /// A computer that could not be reached just now.
  Host? _unreached;

  /// The files were handed to the outbox.
  bool _kept = false;

  bool get _started => _jobs.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Most of the time there is only one question left: which server. With
    // a paired computer, that one is offered first, one tap away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = AppScope.store(context);
      // Picked by name in the share sheet: files are on their way already.
      // (For text there is still a choice: its clipboard, or its browser.)
      final chosen = store.host(widget.sendTo);
      if (chosen != null && chosen.computer && widget.text == null) {
        _sendTo(chosen);
      } else if (store.hosts.every((h) => !h.computer)) {
        _pickHost();
      }
    });
  }

  @override
  void dispose() {
    // Files that never started uploading are not needed any more.
    if (!_started && !_kept) {
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

  /// Connects to a paired computer, showing a problem instead of throwing.
  Future<LiveSession?> _reach(Host computer) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      return await (widget.connect ?? HostConnector.connect)(context, computer);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The files wait on the phone and go when the computer is next connected.
  Future<void> _sendLater(Host computer) async {
    final outbox = widget.outbox ?? ComputerLinks.app?.outbox ?? PhoneOutbox();
    setState(() => _busy = true);
    try {
      for (final file in widget.files) {
        await outbox.add(computer.id, name: file.name, path: file.path);
      }
      // They are the outbox's now; leaving must not delete them.
      _kept = true;
      if (!mounted) return;
      final count = widget.files.length;
      Toast.show(context, '${count == 1 ? 'It goes' : 'They go'} to ${computer.title} when it is next connected');
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _problem = 'Could not keep the files for later. ${ErrorText.of(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One tap: the files go into the computer's Downloads folder.
  Future<void> _sendTo(Host computer) async {
    if (_started || _busy) return;
    final session = await _reach(computer);
    if (session == null) {
      // Out of reach (or cancelled): they can wait for it.
      if (mounted) setState(() => _unreached = computer);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final remote = await session.ssh.openFiles();
      final folder = await widget.computer.inbox(session);
      if (!mounted) return;
      final queue = (widget.queueFor ?? TransferQueue.of)(session);
      setState(() {
        _host = computer;
        _remote = remote;
        _queue = queue;
        _folder = folder;
        _jobs = [for (final file in widget.files) queue.add(UploadTask(files: remote, source: SharedUploadSource(file), remoteFolder: folder))];
      });
      // Once they are all there, the computer says so on its screen.
      void whenDone() {
        if (_jobs.any((j) => j.isActive)) return;
        queue.removeListener(whenDone);
        final arrived = [
          for (final j in _jobs)
            if (j.state == TransferState.done) j.name,
        ];
        if (arrived.isNotEmpty) unawaited(widget.computer.received(session, computer.pairedAs ?? 'your phone', arrived).catchError((_) {}));
      }

      queue.addListener(whenDone);
      whenDone();
    } catch (error) {
      if (mounted) setState(() => _problem = 'Could not send to ${computer.title}. ${ErrorText.of(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shared text: onto the computer's clipboard, or opened in its browser.
  Future<void> _textTo(Host computer, {required bool open}) async {
    if (_busy) return;
    final text = widget.text!;
    final session = await _reach(computer);
    if (session == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await (open ? widget.computer.open(session, text.trim()) : widget.computer.copy(session, text));
      if (!mounted) return;
      Toast.show(context, open ? 'Opened on ${computer.title}' : 'Copied to ${computer.title}\'s clipboard');
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _problem = ErrorText.of(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    // With a paired computer it is sending; to a plain server, uploading.
    final verb = AppScope.watch(context).hosts.any((h) => h.computer) ? 'Send' : 'Upload';
    return Scaffold(
      appBar: AppBar(title: Text(widget.text != null ? 'Share text' : '$verb ${count == 1 ? '1 file' : '$count files'}')),
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
    final text = widget.text;
    final computers = AppScope.watch(context).hosts.where((h) => h.computer).toList();
    return ListView(
      children: [
        if (computers.isNotEmpty) ...[
          const SectionHeader('Computers'),
          for (final computer in computers) ...[
            if (text == null) ...[
              ListTile(
                leading: const Icon(Icons.computer),
                title: Text('Send to ${computer.title}'),
                subtitle: const Text('Into its Downloads folder'),
                enabled: !_busy,
                onTap: () => _sendTo(computer),
              ),
              // One picture: the computer can also read what is written in it.
              if (widget.files.length == 1 && ScanText.isPicture(widget.files.single.name))
                ListTile(
                  leading: const Icon(Icons.document_scanner_outlined),
                  title: Text('Copy its text to ${computer.title}'),
                  subtitle: const Text('The computer reads the picture; the text goes onto its clipboard'),
                  enabled: !_busy,
                  onTap: () => ScanText.fromPicture(context, computer, widget.files.single.path),
                ),
              if (_unreached?.id == computer.id)
                Padding(
                  padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => _sendLater(computer),
                      icon: const Icon(Icons.schedule_send_outlined),
                      label: const Text('Send when it is next connected'),
                    ),
                  ),
                ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.content_paste_go_outlined),
                title: Text('Copy to ${computer.title}'),
                subtitle: const Text('Onto its clipboard'),
                enabled: !_busy,
                onTap: () => _textTo(computer, open: false),
              ),
              if (widget.computer.isLink(text))
                ListTile(
                  leading: const Icon(Icons.open_in_browser),
                  title: Text('Open on ${computer.title}'),
                  subtitle: const Text('In its browser'),
                  enabled: !_busy,
                  onTap: () => _textTo(computer, open: true),
                ),
            ],
          ],
        ],
        SectionHeader(computers.isEmpty ? 'Server' : 'Or upload to a server'),
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
                // A computer needs no path: it is "its Downloads folder".
                _host!.computer
                    ? (active ? 'Sending to ${_host!.title}…' : 'Sent $done of ${_jobs.length} to ${_host!.title}, into its Downloads folder.')
                    : (active
                          ? 'Uploading to ${RemotePaths.name(_folder!)} on ${_host!.title}…'
                          : 'Uploaded $done of ${_jobs.length} to $_folder on ${_host!.title}.'),
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
