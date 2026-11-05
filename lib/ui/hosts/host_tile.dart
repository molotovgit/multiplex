import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/vault_store.dart';
import '../common/widgets.dart';
import '../files/files_screen.dart';
import '../tunnels/tunnels_screen.dart';
import 'host_connector.dart';
import 'host_editor_screen.dart';

/// One saved host in the list. Tap connects; the menu has the rest.
class HostTile extends StatelessWidget {
  const HostTile({super.key, required this.host, this.compactMenu = false});

  final Host host;

  /// Leaves out Move up / Move down (for the Recent shortcuts, which are
  /// not in the arranged order).
  final bool compactMenu;

  Future<void> _openFiles(BuildContext context) async {
    final session = await HostConnector.connect(context, host);
    if (session != null && context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => FilesScreen(session: session)));
    }
  }

  void _open(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  void _duplicate(BuildContext context) {
    final copy = Host.fromJson({...host.toJson(), 'id': VaultStore.newId(), 'label': '${host.title} copy', 'lastConnectedAt': null});
    AppScope.store(context).saveHost(copy);
    Toast.show(context, 'Saved a copy of ${host.title}');
  }

  Future<void> _delete(BuildContext context) async {
    final store = AppScope.store(context);
    final tunnels = store.forwardsFor(host.id).length;
    final ok = await Confirm.ask(
      context,
      title: 'Delete ${host.title}?',
      message: tunnels == 0 ? 'The saved host and its password are removed.' : 'The saved host, its password and its $tunnels tunnels are removed.',
      action: 'Delete host',
    );
    if (!ok || !context.mounted) return;
    final saved = host;
    final savedTunnels = store.forwardsFor(host.id);
    store.deleteHost(host.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted ${saved.title}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            store.saveHost(saved);
            for (final rule in savedTunnels) {
              store.saveForward(rule);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final connected = AppScope.sessions(context).sessionFor(host.id) != null;
    final jump = AppScope.store(context).host(host.jumpHostId);
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      minVerticalPadding: 8,
      onTap: () => HostConnector.openTerminal(context, host),
      leading: _HostBadge(host: host, connected: connected),
      title: Text(host.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          Flexible(
            child: MonoText(host.target, style: text.bodySmall?.copyWith(color: colors.muted), maxLines: 1),
          ),
          if (jump != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.alt_route, size: 14, color: colors.muted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'via ${jump.title}',
                style: text.bodySmall?.copyWith(color: colors.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
      trailing: PopupMenuButton<int>(
        tooltip: 'Actions for ${host.title}',
        onSelected: (choice) => switch (choice) {
          0 => HostConnector.openTerminal(context, host),
          1 => _openFiles(context),
          2 => _open(context, TunnelsScreen(host: host)),
          3 => _open(context, HostEditorScreen(host: host)),
          4 => _duplicate(context),
          6 => AppScope.store(context).moveHost(host.id, -1),
          7 => AppScope.store(context).moveHost(host.id, 1),
          _ => _delete(context),
        },
        itemBuilder: (_) => [
          if (!compactMenu) ...const [
            PopupMenuItem(
              value: 6,
              child: ListTile(leading: Icon(Icons.arrow_upward), title: Text('Move up')),
            ),
            PopupMenuItem(
              value: 7,
              child: ListTile(leading: Icon(Icons.arrow_downward), title: Text('Move down')),
            ),
            PopupMenuDivider(),
          ],
          PopupMenuItem(
            value: 0,
            child: ListTile(leading: Icon(Icons.terminal), title: Text('Open terminal')),
          ),
          PopupMenuItem(
            value: 1,
            child: ListTile(leading: Icon(Icons.folder_outlined), title: Text('Browse files')),
          ),
          PopupMenuItem(
            value: 2,
            child: ListTile(leading: Icon(Icons.swap_horiz), title: Text('Tunnels')),
          ),
          PopupMenuDivider(),
          PopupMenuItem(
            value: 3,
            child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit')),
          ),
          PopupMenuItem(
            value: 4,
            child: ListTile(leading: Icon(Icons.copy_outlined), title: Text('Duplicate')),
          ),
          PopupMenuItem(
            value: 5,
            child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete')),
          ),
        ],
      ),
    );
  }
}

/// A rounded square with the host's first letter in its tag colour, and a
/// green dot while connected.
class _HostBadge extends StatelessWidget {
  const _HostBadge({required this.host, required this.connected});

  final Host host;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final tag = host.colorTag == 0 ? colors.accent : TagColors.of(host.colorTag);
    final letter = host.title.isEmpty ? '?' : host.title.characters.first.toUpperCase();
    return Semantics(
      label: connected ? 'Connected' : null,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(color: tag.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: Text(
                letter,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: tag, fontWeight: FontWeight.w600),
              ),
            ),
            if (connected)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(color: colors.background, shape: BoxShape.circle),
                  child: const StatusDot(live: true, size: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
