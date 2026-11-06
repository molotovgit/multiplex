import 'package:flutter/material.dart';

import '../../src/rust/api/sftp.dart';
import '../common/widgets.dart';
import '../files/folder_browser.dart';
import '../files/path_bar.dart';
import '../files/remote_paths.dart';
import '../files/text_prompt_dialog.dart';

/// Lets the user walk the server's folders and pick one. Closes with the
/// chosen folder's path, or null.
class RemoteFolderPicker extends StatefulWidget {
  const RemoteFolderPicker({super.key, required this.files, this.start});

  final RemoteFiles files;

  /// Where to begin; the home folder when null or when it cannot be opened.
  final String? start;

  static Future<String?> pick(BuildContext context, {required RemoteFiles files, String? start}) => Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => RemoteFolderPicker(files: files, start: start),
    ),
  );

  @override
  State<RemoteFolderPicker> createState() => _RemoteFolderPickerState();
}

class _RemoteFolderPickerState extends State<RemoteFolderPicker> {
  late final _browser = FolderBrowser(() async => widget.files);

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    await _browser.start();
    final start = widget.start;
    if (start != null && start != _browser.path && _browser.status == BrowserStatus.ready) await _browser.open(start);
  }

  @override
  void dispose() {
    _browser.dispose();
    super.dispose();
  }

  Future<void> _open(String path) async {
    final error = await _browser.open(path);
    if (error != null && mounted) Toast.show(context, 'Could not open ${RemotePaths.name(path)}. $error');
  }

  Future<void> _goTo() async {
    final typed = await TextPromptDialog.show(
      context,
      title: 'Go to folder',
      label: 'Folder path',
      hint: '/var/www',
      message: 'Type a full path, or start with ~ for your home folder.',
      action: 'Open folder',
      initial: _browser.path,
      mono: true,
    );
    if (typed == null || !mounted) return;
    final error = await _browser.goTo(typed);
    if (error != null && mounted) Toast.show(context, 'Could not open $typed. $error');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _browser,
      builder: (context, _) {
        final ready = _browser.status == BrowserStatus.ready;
        final folders = ready ? _browser.entries.where((e) => e.isDir).toList() : const [];
        return Scaffold(
          appBar: AppBar(
            title: const Text('Choose a folder'),
            bottom: _browser.loading ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
          ),
          body: switch (_browser.status) {
            BrowserStatus.opening => const Center(child: CircularProgressIndicator()),
            BrowserStatus.failed => EmptyState(icon: Icons.folder_off_outlined, title: 'Could not list the folders', message: _browser.openError ?? ''),
            BrowserStatus.ready => Column(
              children: [
                PathBar(path: _browser.path, onOpen: _open, onGoTo: _goTo, enabled: !_browser.loading),
                Expanded(
                  child: ListView(
                    children: [
                      if (_browser.canGoUp)
                        ListTile(
                          leading: const Icon(Icons.arrow_upward),
                          title: const Text('Folder above'),
                          onTap: () => _open(RemotePaths.parent(_browser.path)),
                        ),
                      if (folders.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No folders in here.', textAlign: TextAlign.center),
                        ),
                      for (final folder in folders)
                        ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => _open(folder.path),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          },
          bottomNavigationBar: ready
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      onPressed: _browser.loading ? null : () => Navigator.pop(context, _browser.path),
                      icon: const Icon(Icons.check),
                      label: const Text('Use this folder'),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }
}
