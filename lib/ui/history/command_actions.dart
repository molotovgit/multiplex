import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/command_history.dart';
import '../common/widgets.dart';
import 'command_target.dart';

/// What can be done with one recent command: run it now, put it on the
/// line, pin or unpin it, or delete it. Opened by a long press.
abstract final class CommandActions {
  static Future<void> show(BuildContext context, {required CommandTarget target, required String hostId, required HistoryEntry entry}) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (context) => _CommandActionsSheet(target: target, hostId: hostId, entry: entry),
    );
  }
}

class _CommandActionsSheet extends StatelessWidget {
  const _CommandActionsSheet({required this.target, required this.hostId, required this.entry});

  final CommandTarget target;
  final String hostId;
  final HistoryEntry entry;

  void _then(BuildContext context, VoidCallback action) {
    Navigator.pop(context);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final store = AppScope.store(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: MonoText(entry.command, maxLines: 3, style: Theme.of(context).textTheme.titleSmall),
          ),
          ListTile(
            leading: const Icon(Icons.play_arrow),
            title: const Text('Run now'),
            onTap: () => _then(context, () => target.run(entry.command)),
          ),
          ListTile(
            leading: const Icon(Icons.input),
            title: const Text('Put on the command line'),
            onTap: () => _then(context, () => target.insert(entry.command)),
          ),
          ListTile(
            leading: Icon(entry.pinned ? Icons.push_pin : Icons.push_pin_outlined),
            title: Text(entry.pinned ? 'Unpin' : 'Pin to the front'),
            onTap: () => _then(context, () => store.pinCommand(hostId, entry.command, !entry.pinned)),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: colors.danger),
            title: Text('Delete from history', style: TextStyle(color: colors.danger)),
            onTap: () => _then(context, () => store.deleteCommand(hostId, entry.command)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
