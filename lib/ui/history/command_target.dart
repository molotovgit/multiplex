import 'package:flutter/foundation.dart';

import '../../sessions/terminal_controller.dart';
import '../../src/rust/api/terminal_types.dart';

/// Where recent commands go when the user picks one, and what the user
/// has typed so far (to filter the suggestions). Notifies when that
/// changes.
abstract interface class CommandTarget implements Listenable {
  /// The saved host whose history to show; null when the host is not
  /// saved (no history is kept then).
  String? get hostId;

  /// The text after the prompt on the current line.
  String get typedLine;

  /// Puts [command] on the line in place of what was typed.
  void insert(String command);

  /// Puts [command] on the line and runs it.
  void run(String command);
}

/// Sends picked commands to a terminal.
class TerminalCommandTarget implements CommandTarget {
  TerminalCommandTarget(this.controller);

  final TerminalController controller;

  @override
  String? get hostId => controller.hostId;

  @override
  String get typedLine => controller.typedLine;

  @override
  void insert(String command) {
    // Remove what was typed: go to the end of the line, then one
    // Backspace per character, so the pick replaces it.
    final typed = controller.typedLine;
    if (typed.isNotEmpty) {
      controller.key(TerminalKey.end);
      for (var i = 0; i < typed.runes.length; i++) {
        controller.key(TerminalKey.backspace);
      }
    }
    controller.paste(command);
  }

  @override
  void run(String command) {
    insert(command);
    controller.key(TerminalKey.enter);
  }

  @override
  void addListener(VoidCallback listener) => controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => controller.removeListener(listener);
}

/// A target with no terminal and no history: the keyboard preview in
/// settings.
class NoCommandTarget implements CommandTarget {
  const NoCommandTarget();

  @override
  String? get hostId => null;

  @override
  String get typedLine => '';

  @override
  void insert(String command) {}

  @override
  void run(String command) {}

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
