import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../src/rust/api/sftp_types.dart';
import '../../common/widgets.dart';
import '../entry_tile.dart';
import '../path_bar.dart';
import '../text_prompt_dialog.dart';
import 'file_pane.dart';

/// One pane: where it is, the folder path, and the list with ticks.
/// Tapping a folder opens it; tapping a file (or long-pressing anything)
/// ticks it for copying.
class PaneView extends StatelessWidget {
  const PaneView({super.key, required this.pane, required this.title, required this.active, required this.onChoosePlace, this.onTouched, this.extraActions = const []});

  final FilePane pane;

  /// "Left" or "Right", so screen reader users know which side this is.
  final String title;

  /// The pane the copy button copies from, outlined in the accent colour.
  final bool active;
  final VoidCallback onChoosePlace;
  final VoidCallback? onTouched;

  /// More menu entries, such as adding files from the system picker.
  final List<PaneAction> extraActions;

  Future<void> _open(BuildContext context, String path) async {
    onTouched?.call();
    final error = await pane.open(path);
    if (error != null && context.mounted) Toast.show(context, 'Could not open that folder. $error');
  }

  Future<void> _goTo(BuildContext context) async {
    final typed = await TextPromptDialog.show(context, title: 'Go to folder', label: 'Folder path', action: 'Open folder', initial: pane.path, mono: true);
    if (typed != null && context.mounted) await _open(context, typed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Semantics(
      container: true,
      label: '$title side',
      child: Listener(
        onPointerDown: (_) => onTouched?.call(),
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: active ? colors.accent : colors.outline, width: 2))),
          child: ListenableBuilder(
            listenable: pane,
            builder: (context, _) => Column(
              children: [
                _PaneHeader(pane: pane, onChoosePlace: onChoosePlace, onUp: () => _open(context, pane.side.parent(path: pane.path)), extraActions: extraActions),
                if (pane.source != null && pane.path.isNotEmpty)
                  PathBar(path: pane.path, onOpen: (path) => _open(context, path), onGoTo: () => _goTo(context)),
                SizedBox(height: 4, child: pane.loading ? const LinearProgressIndicator(minHeight: 4) : null),
                Expanded(child: _PaneBody(pane: pane, onChoosePlace: onChoosePlace, onOpen: (path) => _open(context, path))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A menu entry a screen adds to a pane.
class PaneAction {
  const PaneAction(this.label, this.onSelected);

  final String label;
  final VoidCallback onSelected;
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({required this.pane, required this.onChoosePlace, required this.onUp, required this.extraActions});

  final FilePane pane;
  final VoidCallback onChoosePlace;
  final VoidCallback onUp;
  final List<PaneAction> extraActions;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final source = pane.source;
    final count = pane.selected.length;
    final icon = switch (source) {
      ServerSource() => Icons.dns_outlined,
      PhoneSource(:final root) => root.icon,
      null => Icons.add_circle_outline,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
      child: Row(
        children: [
          Expanded(
            child: TextButton.icon(
              style: TextButton.styleFrom(alignment: Alignment.centerLeft, minimumSize: const Size(48, 48)),
              onPressed: onChoosePlace,
              icon: Icon(icon),
              label: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(source?.label ?? 'Choose a place', maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (count > 0)
                    Text('$count ticked', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted))
                  else if (source != null)
                    Text('Tap to change', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted)),
                ],
              ),
            ),
          ),
          if (source != null) ...[
            IconButton(tooltip: 'Up one folder', icon: const Icon(Icons.arrow_upward), onPressed: pane.canGoUp && !pane.loading ? onUp : null),
            PopupMenuButton<VoidCallback>(
              tooltip: 'Pane options',
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                PopupMenuItem(value: pane.selectAll, child: const Text('Tick all')),
                PopupMenuItem(value: pane.clearSelection, enabled: count > 0, child: const Text('Clear ticks')),
                PopupMenuItem(value: pane.refresh, child: const Text('Refresh')),
                CheckedPopupMenuItem(value: pane.toggleHidden, checked: pane.showHidden, child: const Text('Show hidden files')),
                for (final extra in extraActions) PopupMenuItem(value: extra.onSelected, child: Text(extra.label)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PaneBody extends StatelessWidget {
  const _PaneBody({required this.pane, required this.onChoosePlace, required this.onOpen});

  final FilePane pane;
  final VoidCallback onChoosePlace;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    if (pane.source == null) {
      return EmptyState(
        icon: Icons.swap_horiz,
        title: 'Choose a place',
        message: 'Pick this phone or one of your servers to copy to or from.',
        actionLabel: 'Choose place',
        onAction: onChoosePlace,
      );
    }
    final error = pane.error;
    if (error != null && pane.allEntries.isEmpty) {
      return EmptyState(icon: Icons.error_outline, title: 'Could not open this folder', message: error, actionLabel: 'Try again', onAction: pane.refresh);
    }
    if (pane.path.isEmpty) return const SizedBox.shrink();
    final entries = pane.entries;
    if (entries.isEmpty) {
      return EmptyState(
        icon: Icons.folder_open,
        title: 'This folder is empty',
        message: pane.allEntries.isEmpty ? 'Copies you make into this folder show up here.' : 'Only hidden files are here. Show them from the pane menu.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        return _PaneRow(key: ValueKey(entry.path), entry: entry, ticked: pane.isSelected(entry), onToggle: () => pane.toggle(entry), onOpen: () => onOpen(entry.path));
      },
    );
  }
}

class _PaneRow extends StatelessWidget {
  const _PaneRow({super.key, required this.entry, required this.ticked, required this.onToggle, required this.onOpen});

  final RemoteEntry entry;
  final bool ticked;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final canTick = entry.kind != EntryKind.other;
    return ListTile(
      selected: ticked,
      selectedTileColor: colors.accent.withValues(alpha: 0.10),
      contentPadding: const EdgeInsets.only(left: 4, right: 16),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: 'Tick ${entry.name}',
            child: Checkbox(value: ticked, onChanged: canTick ? (_) => onToggle() : null),
          ),
          EntryIcon(entry),
        ],
      ),
      title: MonoText(entry.name, maxLines: 1),
      subtitle: EntryDetails(entry),
      onTap: entry.isDir ? onOpen : (canTick ? onToggle : null),
      onLongPress: canTick ? onToggle : null,
    );
  }
}
