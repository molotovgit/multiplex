import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../sessions/session_manager.dart';
import '../common/widgets.dart';
import 'file_actions.dart';
import 'files_widgets.dart';
import 'folder_browser.dart';
import 'folder_view.dart';
import 'transfer_panel.dart';
import 'transfer_queue.dart';

/// Remote file browser (SFTP) for one live session.
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key, required this.session});

  final LiveSession session;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  late final FolderBrowser _browser = FolderBrowser(() => widget.session.ssh.openFiles());
  late final TransferQueue _queue = TransferQueue.of(widget.session);
  ConnectionWatch? _connection;
  FileActions? _actions;
  StreamSubscription<TransferJob>? _finished;

  /// Uploads finished since the last "Uploaded" message, so a batch of
  /// files gets one message instead of one per file.
  int _uploadsDone = 0;

  @override
  void initState() {
    super.initState();
    _browser.start();
    _finished = _queue.finished.listen(_transferEnded);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The session manager re-checks connections on a timer; it is only
    // reachable through the context, so this waits until now.
    if (_connection == null) {
      final connection = ConnectionWatch(widget.session, AppScope.sessions(context));
      _connection = connection;
      _actions = FileActions(session: widget.session, browser: _browser, queue: _queue, connection: connection);
    }
  }

  @override
  void dispose() {
    _finished?.cancel();
    _connection?.dispose();
    _browser.dispose();
    super.dispose();
  }

  /// Refreshes after an upload into this folder, and says where a
  /// download was saved or why a transfer failed.
  void _transferEnded(TransferJob job) {
    if (!mounted) return;
    final upload = job.direction == TransferDirection.upload;
    if (upload && job.task.remoteFolder == _browser.path && _browser.status == BrowserStatus.ready) _browser.refresh();
    switch (job.state) {
      case TransferState.done when upload:
        _uploadsDone++;
        final stillUploading = _queue.jobs.any((j) => j.isActive && j.direction == TransferDirection.upload);
        if (!stillUploading) {
          Toast.show(context, _uploadsDone == 1 ? 'Uploaded ${job.name}' : 'Uploaded $_uploadsDone files');
          _uploadsDone = 0;
        }
      case TransferState.done:
        FileToasts.saved(context, job.result ?? '');
      case TransferState.failed:
        _connection?.check();
        Toast.show(context, 'Could not ${upload ? 'upload' : 'download'} "${job.name}". ${job.error}');
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = _connection!;
    final actions = _actions!;
    return ListenableBuilder(
      listenable: Listenable.merge([_browser, connection]),
      builder: (context, _) {
        final connected = connection.value;
        final ready = _browser.status == BrowserStatus.ready;
        final canAct = ready && connected;
        return Scaffold(
          appBar: AppBar(
            title: Text('Files on ${widget.session.host.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              if (ready) ...[
                IconButton(
                  tooltip: 'Up one folder',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: canAct && _browser.canGoUp ? () => actions.up(context) : null,
                ),
                IconButton(
                  tooltip: 'New folder',
                  icon: const Icon(Icons.create_new_folder_outlined),
                  onPressed: canAct ? () => actions.newFolder(context) : null,
                ),
                _FolderMenu(browser: _browser, actions: actions, connected: connected),
              ],
            ],
          ),
          // The app bar covers the top; this keeps notches and the gesture
          // bar clear of the list and path bar at the sides and bottom.
          body: SafeArea(
            top: false,
            child: FilesWidth(
              child: Column(
                children: [
                  if (!connected) const ConnectionLostBanner(),
                  Expanded(child: _FilesBody(session: widget.session, browser: _browser, actions: actions, connected: connected)),
                ],
              ),
            ),
          ),
          floatingActionButton: canAct
              ? FloatingActionButton.extended(
                  onPressed: () => actions.upload(context),
                  icon: const Icon(Icons.upload),
                  label: const Text('Upload files'),
                )
              : null,
          bottomNavigationBar: TransferPanel(queue: _queue),
        );
      },
    );
  }
}

/// What fills the screen: a spinner while opening, an error with a way to
/// try again, or the open folder.
class _FilesBody extends StatelessWidget {
  const _FilesBody({required this.session, required this.browser, required this.actions, required this.connected});

  final LiveSession session;
  final FolderBrowser browser;
  final FileActions actions;
  final bool connected;

  @override
  Widget build(BuildContext context) => switch (browser.status) {
    BrowserStatus.opening => BusyMessage('Opening files on ${session.host.title}'),
    BrowserStatus.failed => EmptyState(
      icon: Icons.error_outline,
      title: 'Could not open the files',
      message: '${browser.openError} Check that the server allows SFTP, then try again.',
      actionLabel: connected ? 'Try again' : null,
      onAction: connected ? browser.start : null,
    ),
    BrowserStatus.ready => FolderView(browser: browser, actions: actions, connected: connected),
  };
}

/// The app bar's overflow menu: less common folder actions and the
/// hidden-files switch.
class _FolderMenu extends StatelessWidget {
  const _FolderMenu({required this.browser, required this.actions, required this.connected});

  final FolderBrowser browser;
  final FileActions actions;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuItem>(
      tooltip: 'More options',
      onSelected: (item) {
        switch (item) {
          case _MenuItem.goTo:
            actions.goTo(context);
          case _MenuItem.home:
            actions.goHome(context);
          case _MenuItem.refresh:
            actions.refresh(context);
          case _MenuItem.hidden:
            browser.toggleHidden();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: _MenuItem.goTo, enabled: connected, child: const Text('Go to folder')),
        PopupMenuItem(value: _MenuItem.home, enabled: connected, child: const Text('Go to home folder')),
        PopupMenuItem(value: _MenuItem.refresh, enabled: connected, child: const Text('Refresh')),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(value: _MenuItem.hidden, checked: browser.showHidden, child: const Text('Show hidden files')),
      ],
    );
  }
}

enum _MenuItem { goTo, home, refresh, hidden }
