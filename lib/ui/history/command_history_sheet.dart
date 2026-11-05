import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/command_history.dart';
import '../common/widgets.dart';
import 'command_target.dart';

/// The full command history of one host in a bottom sheet: search, pin,
/// delete, run, and clear everything (after asking).
class CommandHistorySheet extends StatefulWidget {
  const CommandHistorySheet({super.key, required this.hostId, required this.hostName, required this.target, this.scroll});

  final String hostId;
  final String hostName;
  final CommandTarget target;

  /// The sheet's drag controller, so dragging the list moves the sheet.
  final ScrollController? scroll;

  /// Opens the history of the target's host, or says why there is none.
  static Future<void> openFor(BuildContext context, CommandTarget target) async {
    final hostId = target.hostId;
    if (hostId == null) {
      Toast.show(context, 'Command history is kept for saved hosts');
      return;
    }
    final name = AppScope.store(context).host(hostId)?.title ?? 'this host';
    await show(context, hostId: hostId, hostName: name, target: target);
  }

  static Future<void> show(BuildContext context, {required String hostId, required String hostName, required CommandTarget target}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scroll) => CommandHistorySheet(hostId: hostId, hostName: hostName, target: target, scroll: scroll),
      ),
    );
  }

  @override
  State<CommandHistorySheet> createState() => _CommandHistorySheetState();
}

class _CommandHistorySheetState extends State<CommandHistorySheet> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _clearAll(int count) async {
    final ok = await Confirm.ask(
      context,
      title: 'Clear the command history?',
      message: 'All $count commands for ${widget.hostName} are removed, pinned ones too.',
      action: 'Clear all',
    );
    if (!ok || !mounted) return;
    AppScope.store(context).clearCommands(widget.hostId);
    Toast.show(context, 'Command history cleared');
  }

  void _pick(String command, {required bool run}) {
    Navigator.pop(context);
    run ? widget.target.run(command) : widget.target.insert(command);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final history = AppScope.watch(context).commandHistory;
    final total = history.recent(widget.hostId).length;
    final entries = history.search(widget.hostId, _search.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 12, 8),
          child: Row(
            children: [
              Expanded(child: Text('Command history', style: text.titleLarge)),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: colors.danger),
                onPressed: total == 0 ? null : () => _clearAll(total),
                child: const Text('Clear all'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _search,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search commands',
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(tooltip: 'Clear search', icon: const Icon(Icons.close), onPressed: _search.clear),
            ),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? _EmptyHistory(searching: _search.text.isNotEmpty)
              : ListView.builder(
                  controller: widget.scroll,
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _HistoryTile(
                    entry: entries[i],
                    onInsert: () => _pick(entries[i].command, run: false),
                    onRun: () => _pick(entries[i].command, run: true),
                    onPin: () => AppScope.store(context).pinCommand(widget.hostId, entries[i].command, !entries[i].pinned),
                    onDelete: () => AppScope.store(context).deleteCommand(widget.hostId, entries[i].command),
                  ),
                ),
        ),
      ],
    );
  }
}

/// One command: tap puts it on the line; the buttons pin, run or delete.
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.onInsert, required this.onRun, required this.onPin, required this.onDelete});

  final HistoryEntry entry;
  final VoidCallback onInsert, onRun, onPin, onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return ListTile(
      leading: Icon(entry.pinned ? Icons.push_pin : Icons.history, color: entry.pinned ? colors.accent : colors.muted),
      title: MonoText(entry.command, maxLines: 2),
      subtitle: Text(HistoryWords.uses(entry)),
      onTap: onInsert,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: entry.pinned ? 'Unpin' : 'Pin',
            icon: Icon(entry.pinned ? Icons.push_pin : Icons.push_pin_outlined),
            onPressed: onPin,
          ),
          PopupMenuButton<VoidCallback>(
            tooltip: 'More',
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              PopupMenuItem(value: onRun, child: const ListTile(leading: Icon(Icons.play_arrow), title: Text('Run now'))),
              PopupMenuItem(
                value: onDelete,
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: colors.danger),
                  title: Text('Delete', style: TextStyle(color: colors.danger)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown when there is nothing to list.
class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) => searching
      ? const EmptyState(icon: Icons.search_off, title: 'No commands match', message: 'Try a shorter part of the command.')
      : const EmptyState(
          icon: Icons.history,
          title: 'No commands yet',
          message: 'Commands you run on this host show up here, newest first.',
        );
}

/// Plain words for history details.
abstract final class HistoryWords {
  static String uses(HistoryEntry entry) {
    final times = entry.uses == 1 ? 'Ran once' : 'Ran ${entry.uses} times';
    return '$times, last ${when(entry.lastUsed, DateTime.now())}';
  }

  /// "just now", "5 minutes ago", "3 hours ago", "2 days ago", or the date.
  static String when(DateTime at, DateTime now) {
    final d = now.difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return d.inMinutes == 1 ? '1 minute ago' : '${d.inMinutes} minutes ago';
    if (d.inDays < 1) return d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago';
    if (d.inDays < 30) return d.inDays == 1 ? 'yesterday' : '${d.inDays} days ago';
    return '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
  }
}
