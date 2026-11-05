import 'package:flutter/material.dart';

import '../common/widgets.dart';
import 'entry_tile.dart';
import 'file_actions.dart';
import 'files_widgets.dart';
import 'folder_browser.dart';
import 'path_bar.dart';

/// The open folder: the path bar on top, then its files and folders.
/// Pull down to refresh.
class FolderView extends StatelessWidget {
  const FolderView({super.key, required this.browser, required this.actions, required this.connected});

  final FolderBrowser browser;
  final FileActions actions;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final entries = browser.entries;
    final Widget list = entries.isEmpty
        ? _EmptyFolder(browser: browser, connected: connected)
        : ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: FilesLayout.listBottomPadding),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final entry = entries[i];
              return EntryTile(
                key: ValueKey(entry.path),
                entry: entry,
                enabled: connected,
                onOpen: () => actions.open(context, entry),
                onAction: (action) => actions.run(context, entry, action),
              );
            },
          );
    return Column(
      children: [
        PathBar(
          path: browser.path,
          enabled: connected,
          onOpen: (path) => actions.openFolder(context, path),
          onGoTo: () => actions.goTo(context),
        ),
        // A thin bar while a folder loads; the old list stays meanwhile.
        SizedBox(height: 4, child: browser.loading ? const LinearProgressIndicator(minHeight: 4) : null),
        Expanded(
          child: connected ? RefreshIndicator(onRefresh: () => actions.refresh(context), child: list) : list,
        ),
      ],
    );
  }
}

/// What an empty folder says. If only hidden files are here, it offers
/// to show them; otherwise it points at the "Upload files" button, which
/// stays the screen's one main action.
class _EmptyFolder extends StatelessWidget {
  const _EmptyFolder({required this.browser, required this.connected});

  final FolderBrowser browser;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final hidden = browser.hiddenCount;
    final state = hidden > 0
        ? EmptyState(
            icon: Icons.visibility_off_outlined,
            title: 'Only hidden files here',
            message: 'This folder has $hidden hidden ${hidden == 1 ? 'item' : 'items'}, whose names start with a dot.',
            actionLabel: 'Show hidden files',
            onAction: browser.toggleHidden,
          )
        : EmptyState(
            icon: Icons.folder_open,
            title: 'This folder is empty',
            message: connected
                ? 'Files and folders on the server show up here. Tap Upload files to add some from this device.'
                : 'Files and folders on the server show up here.',
          );
    // Scrollable, so pull to refresh works on an empty folder too.
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [SliverFillRemaining(hasScrollBody: false, child: state)],
    );
  }
}
