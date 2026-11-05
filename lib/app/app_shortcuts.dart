import 'package:flutter/services.dart';

/// App-wide keyboard shortcuts.
abstract final class AppShortcuts {
  /// Ctrl+Shift+T opens the theme switcher.
  static bool isThemeSwitcher(KeyEvent event) => event is KeyDownEvent && isThemeSwitcherKey(event);

  /// The same keys pressed, held or let go. The terminal lets them all
  /// through instead of sending them to the server.
  static bool isThemeSwitcherKey(KeyEvent event) {
    final keys = HardwareKeyboard.instance;
    return event.logicalKey == LogicalKeyboardKey.keyT && keys.isControlPressed && keys.isShiftPressed;
  }
}
