import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../src/rust/api/sftp_types.dart';
import '../common/widgets.dart';
import 'file_format.dart';

/// Things the user can do with one file or folder.
enum EntryAction {
  rename('Rename', Icons.drive_file_rename_outline),
  permissions('Permissions', Icons.lock_outline),
  copyPath('Copy path', Icons.content_copy),
  download('Download', Icons.download_outlined),
  delete('Delete', Icons.delete_outline);

  const EntryAction(this.label, this.icon);

  final String label;
  final IconData icon;

  /// Folders cannot be downloaded (only single files can), and neither can
  /// devices or sockets.
  static List<EntryAction> forEntry(RemoteEntry entry) => [rename, permissions, copyPath, if (!entry.isDir && entry.kind != EntryKind.other) download, delete];
}

/// The icon for an entry: folder, file, link to a folder, link, or other.
class EntryIcon extends StatelessWidget {
  const EntryIcon(this.entry, {super.key});

  final RemoteEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final isLink = entry.kind == EntryKind.symlink;
    final (icon, color, label) = switch (entry.kind) {
      EntryKind.directory => (Icons.folder, colors.accent, 'Folder'),
      EntryKind.symlink when entry.isDir => (Icons.folder, colors.accent, 'Link to a folder'),
      EntryKind.symlink => (Icons.link, colors.muted, 'Link'),
      EntryKind.file => (Icons.insert_drive_file_outlined, colors.muted, 'File'),
      EntryKind.other => (Icons.memory_outlined, colors.muted, 'Special file'),
    };
    final glyph = Icon(icon, color: color, semanticLabel: label);
    if (!isLink || !entry.isDir) return glyph;
    // A folder with a small link mark in the corner.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        glyph,
        Positioned(
          right: -4,
          bottom: -4,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: colors.background, shape: BoxShape.circle),
            child: Icon(Icons.link, size: 12, color: colors.text),
          ),
        ),
      ],
    );
  }
}

/// Size, date and permissions under the name.
class EntryDetails extends StatelessWidget {
  const EntryDetails(this.entry, {super.key});

  final RemoteEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted);
    final parts = [if (entry.kind == EntryKind.file) FileSizes.human(entry.size), if (entry.modified != null) FileDates.short(entry.modified)];
    // A Wrap, not a Row: with large text the permissions move to their
    // own line instead of running off the edge.
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        if (parts.isNotEmpty) Text(parts.join('  ·  '), style: small, maxLines: 1, overflow: TextOverflow.ellipsis),
        MonoText(FileModes.describe(entry.permissions, entry.kind), style: small, maxLines: 1),
      ],
    );
  }
}

/// One row of the file list. Tap opens it; the menu button and a long
/// press offer the other actions. With [enabled] off (connection lost)
/// the row only shows information.
class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.entry, required this.enabled, required this.onOpen, required this.onAction});

  final RemoteEntry entry;
  final bool enabled;
  final VoidCallback onOpen;
  final ValueChanged<EntryAction> onAction;

  Future<void> _showSheet(BuildContext context) async {
    final action = await EntryActionSheet.show(context, entry);
    if (action != null) onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      leading: EntryIcon(entry),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: EntryDetails(entry),
      onTap: enabled ? onOpen : null,
      onLongPress: enabled ? () => _showSheet(context) : null,
      trailing: enabled
          ? PopupMenuButton<EntryAction>(
              tooltip: 'More actions for ${entry.name}',
              icon: const Icon(Icons.more_vert),
              onSelected: onAction,
              itemBuilder: (context) => [for (final action in EntryAction.forEntry(entry)) PopupMenuItem(value: action, child: _ActionLabel(action))],
            )
          : null,
    );
  }
}

/// The same actions as a bottom sheet, which suits a long press on a phone.
class EntryActionSheet extends StatelessWidget {
  const EntryActionSheet({super.key, required this.entry});

  final RemoteEntry entry;

  static Future<EntryAction?> show(BuildContext context, RemoteEntry entry) => showModalBottomSheet<EntryAction>(
    context: context,
    builder: (_) => EntryActionSheet(entry: entry),
  );

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    // Scrolls when large text makes the list taller than the sheet.
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Row(
                children: [
                  EntryIcon(entry),
                  const SizedBox(width: 16),
                  Expanded(child: MonoText(entry.name, maxLines: 1, style: Theme.of(context).textTheme.titleSmall)),
                ],
              ),
            ),
            const Divider(),
            for (final action in EntryAction.forEntry(entry))
              ListTile(
                leading: Icon(action.icon, color: action == EntryAction.delete ? colors.danger : null),
                title: Text(action.label, style: action == EntryAction.delete ? Theme.of(context).textTheme.bodyLarge?.copyWith(color: colors.danger) : null),
                onTap: () => Navigator.pop(context, action),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// An action in the row's menu: icon and word, red for delete.
class _ActionLabel extends StatelessWidget {
  const _ActionLabel(this.action);

  final EntryAction action;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final danger = action == EntryAction.delete;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(action.icon, color: danger ? colors.danger : null),
      title: Text(action.label, style: danger ? Theme.of(context).textTheme.bodyLarge?.copyWith(color: colors.danger) : null),
    );
  }
}
