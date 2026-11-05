import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../app/theme_look.dart';
import '../../data/command_history.dart';
import '../common/widgets.dart';
import 'command_actions.dart';
import 'command_target.dart';

/// A row of recent commands for this host, above the keys. Pinned ones
/// come first; while the user types, only commands that start with or
/// contain the typed text are shown. Tap puts a command on the line, a
/// long press offers run, pin and delete. The history button on the left
/// opens the full list.
class CommandStrip extends StatelessWidget {
  const CommandStrip({super.key, required this.target, required this.onOpenHistory, this.compact = false});

  final CommandTarget target;
  final VoidCallback onOpenHistory;

  /// A lower row, for phones in landscape.
  final bool compact;

  static const height = 44.0;
  static const compactHeight = 36.0;

  /// More chips than this are never useful in one row.
  static const maxChips = 40;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.watch(context);
    final rowHeight = compact ? compactHeight : height;
    return ListenableBuilder(
      listenable: target,
      builder: (context, _) {
        final hostId = target.hostId;
        final history = store.commandHistory;
        final entries = hostId == null ? const <HistoryEntry>[] : history.suggest(hostId, target.typedLine).take(maxChips).toList();
        final String? hint;
        if (hostId == null) {
          hint = 'Save this host to keep its commands';
        } else if (history.recent(hostId).isEmpty) {
          hint = 'Commands you run show up here';
        } else if (entries.isEmpty) {
          hint = 'No recent command matches';
        } else {
          hint = null;
        }
        return SizedBox(
          height: rowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HistoryButton(onTap: onOpenHistory, size: rowHeight),
              Expanded(
                child: hint != null
                    ? _StripHint(hint)
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(right: 8),
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) => _CommandChip(
                          entry: entries[i],
                          onTap: () => target.insert(entries[i].command),
                          onLongPress: () => CommandActions.show(context, target: target, hostId: hostId!, entry: entries[i]),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Opens the full history of the host.
class _HistoryButton extends StatelessWidget {
  const _HistoryButton({required this.onTap, required this.size});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return SizedBox(
      width: size + 4,
      child: Semantics(
        button: true,
        label: 'Command history',
        excludeSemantics: true,
        child: Tooltip(
          message: 'Command history',
          child: InkWell(
            canRequestFocus: false,
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Icon(Icons.history, color: colors.muted, size: 22),
          ),
        ),
      ),
    );
  }
}

/// One recent command. Pinned ones carry a pin and an accent edge, so
/// the state never depends on colour alone.
class _CommandChip extends StatelessWidget {
  const _CommandChip({required this.entry, required this.onTap, required this.onLongPress});

  final HistoryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Long commands are cut with an ellipsis; the full text is in the
  /// long-press sheet.
  static const maxTextWidth = 220.0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final radius = BorderRadius.circular(AppStyleTheme.of(context).shapes.chip);
    final text = Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.text);
    return Semantics(
      button: true,
      label: '${entry.command}${entry.pinned ? ', pinned' : ''}',
      hint: 'Long press for run, pin and delete',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: colors.raised,
          shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: entry.pinned ? colors.accent : colors.outline)),
          child: InkWell(
            canRequestFocus: false,
            borderRadius: radius,
            onTap: onTap,
            onLongPress: onLongPress,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (entry.pinned) ...[
                      Icon(Icons.push_pin, size: 14, color: colors.accent),
                      const SizedBox(width: 4),
                    ],
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: maxTextWidth),
                      child: MonoText(entry.command, maxLines: 1, style: text),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A muted sentence where the chips would be.
class _StripHint extends StatelessWidget {
  const _StripHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.muted),
      ),
    );
  }
}
