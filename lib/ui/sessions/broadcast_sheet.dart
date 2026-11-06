import 'package:flutter/material.dart';

import '../../app/app_motion.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../sessions/session_manager.dart';
import '../../sessions/terminal_controller.dart';
import '../common/widgets.dart';

/// Picks the terminals for broadcast mode: what is typed in one of them
/// goes to all of them.
class BroadcastSheet extends StatefulWidget {
  const BroadcastSheet({super.key, required this.sessions});

  final SessionManager sessions;

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        sheetAnimationStyle: AppMotion.of(context).sheet,
        builder: (_) => BroadcastSheet(sessions: AppScope.sessions(context)),
      );

  @override
  State<BroadcastSheet> createState() => _BroadcastSheetState();
}

class _BroadcastSheetState extends State<BroadcastSheet> {
  late final Set<TerminalController> _picked = {...widget.sessions.broadcast.members};

  List<(LiveSession, TerminalController)> get _open => [
        for (final session in widget.sessions.sessions)
          for (final terminal in session.terminals)
            if (!terminal.ended) (session, terminal),
      ];

  void _start() {
    widget.sessions.broadcast.start(_picked);
    Navigator.pop(context);
    Toast.show(context, 'Typing in one of them now goes to all ${_picked.length}');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final open = _open;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Broadcast', style: text.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Pick the terminals. Every key and paste in one of them is sent to all of them.',
                    style: text.bodyMedium?.copyWith(color: colors.muted),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (session, terminal) in open)
                    CheckboxListTile(
                      value: _picked.contains(terminal),
                      onChanged: (on) => setState(() => on == true ? _picked.add(terminal) : _picked.remove(terminal)),
                      title: Text(terminal.title),
                      subtitle: MonoText(session.host.target, style: text.bodySmall?.copyWith(color: colors.muted), maxLines: 1),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  if (widget.sessions.broadcast.on)
                    TextButton(
                      onPressed: () {
                        widget.sessions.broadcast.stop();
                        Navigator.pop(context);
                      },
                      child: const Text('Stop broadcast'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _picked.length >= 2 ? _start : null,
                    child: Text(_picked.length >= 2 ? 'Broadcast to ${_picked.length}' : 'Pick at least 2'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
