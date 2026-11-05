import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../app/theme_look.dart';
import '../../sessions/session_manager.dart';
import '../../sessions/terminal_controller.dart';

/// The connection's terminals as tabs above the text, shown when the
/// theme's style asks for it. Tapping a tab switches to that terminal;
/// the plus opens another one.
class TerminalTabStrip extends StatelessWidget {
  const TerminalTabStrip({super.key, required this.session, required this.current, required this.onSelect, required this.onNew});

  final LiveSession session;
  final TerminalController current;
  final ValueChanged<TerminalController> onSelect;
  final VoidCallback onNew;

  /// Each tab is a full touch target.
  static const height = 48.0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final look = AppStyleTheme.of(context);
    return ListenableBuilder(
      listenable: AppScope.sessions(context),
      builder: (context, _) => Material(
        color: look.surfaces.bar,
        // Outlined styles draw a line between the tabs and the text.
        shape: Border(bottom: look.surfaces.side == BorderSide.none ? BorderSide.none : BorderSide(color: colors.outline)),
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final terminal in session.terminals)
                      _TerminalTab(terminal: terminal, selected: identical(terminal, current), onTap: () => onSelect(terminal)),
                  ],
                ),
              ),
              IconButton(tooltip: 'New terminal', icon: const Icon(Icons.add), onPressed: onNew),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tab: the terminal's title, underlined in the accent when it is
/// the one on screen.
class _TerminalTab extends StatelessWidget {
  const _TerminalTab({required this.terminal, required this.selected, required this.onTap});

  final TerminalController terminal;
  final bool selected;
  final VoidCallback onTap;

  /// Long titles stop here and end in an ellipsis.
  static const _maxWidth = 180.0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme.labelLarge?.copyWith(color: selected ? colors.text : colors.muted);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(AppStyleTheme.of(context).shapes.chip),
        child: Container(
          constraints: const BoxConstraints(maxWidth: _maxWidth, minWidth: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? colors.accent : Colors.transparent, width: 2)),
          ),
          child: Text(terminal.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text),
        ),
      ),
    );
  }
}
