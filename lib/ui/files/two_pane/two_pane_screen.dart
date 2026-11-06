import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme.dart';
import '../../../sessions/session_manager.dart';
import '../../../src/rust/api/sftp.dart';
import '../../../src/rust/api/transfer_types.dart';
import '../../common/widgets.dart';
import '../../hosts/host_connector.dart';
import '../file_format.dart';
import '../transfer_panel.dart';
import '../transfer_queue.dart';
import '../transfer_tasks.dart';
import 'copy_task.dart';
import 'file_pane.dart';
import 'pane_view.dart';
import 'phone_storage.dart';
import 'place_picker.dart';

/// Two places side by side (one at a time on a narrow phone): this
/// phone's folders or any saved server on either side. Tick files and
/// folders on one side and copy them into the folder open on the other;
/// between two servers the data streams through the phone.
class TwoPaneScreen extends StatefulWidget {
  const TwoPaneScreen({super.key, this.session, this.queue, this.phoneRoots, this.newPane, this.copier, this.openFiles});

  /// A server to show on the right from the start.
  final LiveSession? session;
  final TransferQueue? queue;
  final Future<List<PhoneRoot>> Function()? phoneRoots;
  final FilePane Function()? newPane;
  final Copier? copier;
  final Future<RemoteFiles> Function(LiveSession session)? openFiles;

  /// Copies carry on, and stay listed, after the screen closes.
  static final sharedQueue = TransferQueue();

  /// Panes side by side from this width up.
  static const wideWidth = 720.0;

  /// One SFTP channel per connection for this screen, reused when the same
  /// server is picked again.
  static final _files = Expando<Future<RemoteFiles>>('two-pane files');

  static Future<RemoteFiles> filesFor(LiveSession session) => _files[session] ??= session.ssh.openFiles();

  @override
  State<TwoPaneScreen> createState() => _TwoPaneScreenState();
}

class _TwoPaneScreenState extends State<TwoPaneScreen> {
  late final FilePane _left = (widget.newPane ?? FilePane.new)();
  late final FilePane _right = (widget.newPane ?? FilePane.new)();
  late final TransferQueue _queue = widget.queue ?? TwoPaneScreen.sharedQueue;
  StreamSubscription<TransferJob>? _finished;

  /// The side the copy button copies from.
  bool _rightActive = false;

  @override
  void initState() {
    super.initState();
    _finished = _queue.finished.listen(_copyEnded);
    _start();
  }

  @override
  void dispose() {
    _finished?.cancel();
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  Future<List<PhoneRoot>> _roots() => (widget.phoneRoots ?? PhoneStorage.roots)();

  Future<RemoteFiles> _filesFor(LiveSession session) => (widget.openFiles ?? TwoPaneScreen.filesFor)(session);

  Future<void> _start() async {
    try {
      final roots = await _roots();
      await _left.showPhone(roots.first);
      final session = widget.session;
      if (session != null) {
        await _right.showServer(session, await _filesFor(session));
        if (mounted) setState(() => _rightActive = true);
      }
    } catch (error) {
      if (mounted) Toast.show(context, 'Could not open a place. ${FileErrors.message(error)}');
    }
  }

  FilePane get _from => _rightActive ? _right : _left;
  FilePane get _to => _rightActive ? _left : _right;

  void _activate(bool right) {
    if (_rightActive != right) setState(() => _rightActive = right);
  }

  Future<void> _choosePlace(FilePane pane) async {
    final store = AppScope.store(context);
    final sessions = AppScope.sessions(context);
    final roots = await _roots();
    final offerAccess = !await PhoneStorage.hasAllFilesAccess();
    if (!mounted) return;
    final choice = await PlacePicker.show(
      context,
      roots: roots,
      hosts: store.hosts,
      connected: {for (final s in sessions.sessions) if (s.connected) s.host.id},
      offerAccess: offerAccess,
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case PhonePlace(:final root):
        await pane.showPhone(root);
      case AllowAccessPlace():
        await PhoneStorage.askAllFilesAccess();
        if (mounted) Toast.show(context, 'Turn on access for Multiplex, come back, then choose Phone storage.');
      case ServerPlace(:final host):
        final session = await HostConnector.connect(context, host);
        if (session == null || !mounted) return;
        try {
          await pane.showServer(session, await _filesFor(session));
        } catch (error) {
          if (mounted) Toast.show(context, 'Could not open the files on ${host.title}. ${FileErrors.message(error)}');
        }
    }
  }

  Future<void> _copy() async {
    final from = _from, to = _to;
    final items = from.selected;
    final target = to.source;
    if (items.isEmpty || target == null || !to.ready) return;
    if (_samePlace(from, to)) {
      Toast.show(context, 'Both sides show the same folder. Open another folder on one side first.');
      return;
    }
    final clashes = [for (final item in items) if (to.entryNamed(item.name) != null) item.name];
    // With no clash known, "keep both" is the safe choice should one appear meanwhile.
    var policy = ConflictPolicy.keepBoth;
    if (clashes.isNotEmpty) {
      final picked = await ConflictDialog.ask(context, names: clashes, folder: '${target.label}: ${to.path}');
      if (picked == null) return;
      policy = picked;
    }
    for (final item in items) {
      _queue.add(
        CopyTask(from: from.side, entry: item, to: to.side, toDir: to.path, toLabel: target.label, policy: policy, copier: widget.copier),
      );
    }
    from.clearSelection();
    if (mounted) Toast.show(context, 'Copying ${items.length == 1 ? items.first.name : '${items.length} items'} to ${target.label}');
  }

  static bool _samePlace(FilePane a, FilePane b) {
    if (a.path != b.path) return false;
    return switch ((a.source, b.source)) {
      (PhoneSource(), PhoneSource()) => true,
      (ServerSource(session: final x), ServerSource(session: final y)) => identical(x, y),
      _ => false,
    };
  }

  /// Shows new files on a side that a copy just went into, and says why
  /// a copy failed.
  void _copyEnded(TransferJob job) {
    final task = job.task;
    if (task is! CopyTask || !mounted) return;
    for (final pane in [_left, _right]) {
      if (pane.source != null && identical(pane.side, task.to) && pane.path == task.toDir) pane.refresh();
    }
    if (job.state == TransferState.failed) Toast.show(context, 'Could not copy "${job.name}". ${job.error}');
  }

  /// Copies files from the system picker into the phone folder on show.
  Future<void> _addFromPicker(FilePane pane) async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(dialogTitle: 'Choose files to add');
    } catch (error) {
      if (mounted) Toast.show(context, 'Could not open the file picker. ${FileErrors.message(error)}');
      return;
    }
    if (picked.isEmpty) return;
    try {
      for (final file in picked) {
        final source = UploadSource.picked(file);
        final local = await source.prepare();
        final name = LocalNames.safe(file.name, windows: Platform.isWindows);
        final target = LocalNames.free(pane.path, name, exists: (p) => File(p).existsSync(), separator: Platform.pathSeparator);
        await File(local).copy(target);
        await source.release();
      }
    } catch (error) {
      if (mounted) Toast.show(context, 'Could not add the files. ${FileErrors.message(error)}');
    }
    await pane.refresh();
  }

  Widget _pane(FilePane pane, {required bool right}) => PaneView(
    pane: pane,
    title: right ? 'Right' : 'Left',
    active: _rightActive == right,
    onTouched: () => _activate(right),
    onChoosePlace: () => _choosePlace(pane),
    extraActions: [if (pane.source is PhoneSource) PaneAction('Add files from the picker', () => _addFromPicker(pane))],
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_left, _right]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Copy between places')),
        body: SafeArea(
          top: false,
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= TwoPaneScreen.wideWidth) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _pane(_left, right: false)),
                    VerticalDivider(width: 1, color: AppColorsTheme.of(context).outline),
                    Expanded(child: _pane(_right, right: true)),
                  ],
                );
              }
              return Column(
                children: [
                  _SideSwitch(left: _left, right: _right, showRight: _rightActive, onChanged: _activate),
                  Expanded(child: _rightActive ? _pane(_right, right: true) : _pane(_left, right: false)),
                ],
              );
            },
          ),
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CopyBar(from: _from, to: _to, pointsRight: !_rightActive, onCopy: _copy),
            TransferPanel(queue: _queue),
          ],
        ),
      ),
    );
  }
}

/// On a narrow phone: which side is on screen.
class _SideSwitch extends StatelessWidget {
  const _SideSwitch({required this.left, required this.right, required this.showRight, required this.onChanged});

  final FilePane left;
  final FilePane right;
  final bool showRight;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    String label(FilePane pane, String side) {
      final count = pane.selected.length;
      final name = pane.source?.label ?? side;
      return count > 0 ? '$name ($count)' : name;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: false, icon: const Icon(Icons.looks_one_outlined), label: Text(label(left, 'Left'), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ButtonSegment(value: true, icon: const Icon(Icons.looks_two_outlined), label: Text(label(right, 'Right'), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          selected: {showRight},
          onSelectionChanged: (picked) => onChanged(picked.first),
        ),
      ),
    );
  }
}

/// The one main action, in thumb reach: copy the ticked items into the
/// folder open on the other side. Only shows while something is ticked.
class _CopyBar extends StatelessWidget {
  const _CopyBar({required this.from, required this.to, required this.pointsRight, required this.onCopy});

  final FilePane from;
  final FilePane to;
  final bool pointsRight;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final count = from.selected.length;
    if (count == 0) return const SizedBox(width: double.infinity);
    final colors = AppColorsTheme.of(context);
    final target = to.source;
    final what = count == 1 ? '1 item' : '$count items';
    return Material(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: target != null && to.ready ? onCopy : null,
            icon: Icon(pointsRight ? Icons.arrow_forward : Icons.arrow_back),
            label: Text(target == null ? 'Choose a place on the other side' : 'Copy $what to ${target.label}', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
  }
}
