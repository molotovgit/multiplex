import 'package:flutter/material.dart';

import '../../app/app_motion.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../sessions/session_manager.dart';
import '../../sessions/terminal_controller.dart';
import '../common/widgets.dart';

/// What the user picked for the second pane: a terminal that is already
/// open, or a new one on [session] when [terminal] is null.
class SplitChoice {
  const SplitChoice(this.session, this.terminal);

  final LiveSession session;
  final TerminalController? terminal;
}

/// Asks which terminal to show next to the current one.
abstract final class SplitPicker {
  static Future<SplitChoice?> pick(BuildContext context, {required TerminalController current}) {
    return showModalBottomSheet<SplitChoice>(
      context: context,
      sheetAnimationStyle: AppMotion.of(context).sheet,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SplitPickerSheet(current: current),
    );
  }

  /// Turns a choice into a terminal, opening a new one when asked.
  static Future<TerminalController> resolve(BuildContext context, SplitChoice choice) async =>
      choice.terminal ?? await AppScope.sessions(context).openTerminal(choice.session);
}

/// Every open terminal of every connection, plus "New terminal" per
/// connection.
class SplitPickerSheet extends StatelessWidget {
  const SplitPickerSheet({super.key, required this.current});

  final TerminalController current;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final sessions = AppScope.sessions(context).sessions.where((s) => s.connected).toList();
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Show next to this terminal', style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final session in sessions) ...[
              SectionHeader(session.host.title),
              for (final terminal in session.terminals.where((t) => !identical(t, current) && !t.ended))
                ListTile(
                  leading: const Icon(Icons.terminal),
                  title: Text(terminal.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: MonoText(session.host.target, style: TextStyle(color: colors.muted), maxLines: 1),
                  onTap: () => Navigator.pop(context, SplitChoice(session, terminal)),
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New terminal'),
                subtitle: Text('On ${session.host.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(context, SplitChoice(session, null)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
