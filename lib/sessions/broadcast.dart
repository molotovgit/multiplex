import 'package:flutter/foundation.dart';

import '../src/rust/api/terminal.dart';
import 'terminal_controller.dart';

/// "Broadcast" mode: a group of terminals that all get what is typed in
/// any one of them, to run the same commands on several servers at once.
class Broadcast extends ChangeNotifier {
  final Set<TerminalController> _members = {};

  bool get on => _members.length > 1;

  /// How many terminals take the typing, the one typed in included.
  int get size => _members.length;

  bool includes(TerminalController terminal) => on && _members.contains(terminal);

  List<TerminalController> get members => List.unmodifiable(_members);

  /// Starts with [terminals]; fewer than two is no broadcast at all.
  void start(Iterable<TerminalController> terminals) {
    _members
      ..clear()
      ..addAll(terminals.where((t) => !t.ended));
    if (_members.length < 2) _members.clear();
    notifyListeners();
  }

  void stop() {
    if (_members.isEmpty) return;
    _members.clear();
    notifyListeners();
  }

  /// A terminal closed: it leaves the group (and the group ends when one
  /// is left).
  void remove(TerminalController terminal) {
    if (!_members.remove(terminal)) return;
    if (_members.length < 2) _members.clear();
    notifyListeners();
  }

  /// Sends input typed in [from] to the other members, if [from] is one.
  /// Terminals that ended or are reconnecting are skipped.
  void forward(TerminalController from, void Function(RemoteShell shell) send) {
    if (!includes(from)) return;
    for (final other in _members) {
      if (identical(other, from) || other.ended || other.reconnecting) continue;
      send(other.shell);
    }
  }
}
