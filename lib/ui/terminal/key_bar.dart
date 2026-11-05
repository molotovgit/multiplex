import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../sessions/terminal_controller.dart';
import 'key_bar_items.dart';

/// The row of extra keys above the phone keyboard: Esc, Tab, sticky Ctrl
/// and Alt, arrows and the symbols that are hard to reach. The user picks
/// and orders the keys in settings.
class KeyBar extends StatelessWidget {
  const KeyBar({super.key, required this.controller, required this.onSnippets, required this.keepFocus});

  final TerminalController controller;
  final VoidCallback onSnippets;

  /// Called after each press so the keyboard stays open.
  final VoidCallback keepFocus;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    final colors = AppColorsTheme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([store, controller]),
      builder: (context, _) {
        final items = KeyBarItems.resolve(store.settings.keyBar);
        if (items.isEmpty) return const SizedBox.shrink();
        return Material(
          color: colors.surface,
          child: SafeArea(
            top: false,
            child: SizedBox(
              // 44 dp keys plus 4 dp above and below: big enough to hit
              // reliably, small enough to leave room for the terminal.
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                children: [
                  for (final item in items)
                    _KeyButton(
                      item: item,
                      latched:
                          (item.action == KeyBarAction.ctrl && controller.ctrlLatched) || (item.action == KeyBarAction.alt && controller.altLatched),
                      onPressed: () => _press(item),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _press(KeyBarItem item) {
    switch (item.action) {
      case KeyBarAction.key:
        controller.key(item.key!);
      case KeyBarAction.text:
        controller.type(item.text!);
      case KeyBarAction.ctrl:
        controller.toggleCtrl();
      case KeyBarAction.alt:
        controller.toggleAlt();
      case KeyBarAction.paste:
        controller.pasteClipboard();
      case KeyBarAction.snippets:
        onSnippets();
        return;
    }
    keepFocus();
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.item, required this.latched, required this.onPressed});

  final KeyBarItem item;

  /// Sticky Ctrl/Alt is on.
  final bool latched;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final fg = latched ? colors.onAccent : colors.text;
    return Padding(
      // 4 dp on each side gives the 8 dp gap between keys.
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: item.name,
        excludeFromSemantics: true,
        child: Material(
          color: latched ? colors.accent : colors.raised,
          borderRadius: BorderRadius.circular(8),
          child: Semantics(
            button: true,
            toggled: item.action == KeyBarAction.ctrl || item.action == KeyBarAction.alt ? latched : null,
            label: item.name,
            child: InkWell(
              // Never take focus away from the terminal's keyboard.
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(8),
              onTap: onPressed,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    child: item.icon != null
                        ? Icon(item.icon, size: 20, color: fg)
                        : Text(
                            item.label,
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
