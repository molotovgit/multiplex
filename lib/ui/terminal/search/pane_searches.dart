import 'package:flutter/foundation.dart';

import '../../../sessions/terminal_controller.dart';
import 'terminal_search.dart';

/// One search per terminal on screen, so each split pane finds text in
/// its own output and keeps its own query and matches.
class PaneSearches extends ChangeNotifier {
  final _byTerminal = <TerminalController, TerminalSearch>{};

  /// The search of `terminal`, made the first time it is asked for. It
  /// searches again whenever that terminal's screen changes.
  TerminalSearch of(TerminalController terminal) => _byTerminal.putIfAbsent(terminal, () {
        final search = TerminalSearch(ControllerSearchSource(terminal));
        terminal.addListener(search.screenChanged);
        search.addListener(notifyListeners);
        return search;
      });

  @override
  void dispose() {
    for (final MapEntry(key: terminal, value: search) in _byTerminal.entries) {
      terminal.removeListener(search.screenChanged);
      search.dispose();
    }
    _byTerminal.clear();
    super.dispose();
  }
}
