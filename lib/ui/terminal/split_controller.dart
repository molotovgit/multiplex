import 'package:flutter/widgets.dart';

import '../../sessions/session_manager.dart';
import '../../sessions/terminal_controller.dart';
import '../history/command_target.dart';

/// Whether the screen has room for two terminals side by side: a phone
/// held sideways, or any screen at least [minWidth] wide.
abstract final class SplitLayout {
  static const minWidth = 840.0;

  static bool allows(Size size) => size.width >= minWidth || size.width > size.height;

  static bool of(BuildContext context) => allows(MediaQuery.sizeOf(context));
}

/// Two terminals on one screen: the screen's own ([primary]) and an
/// optional second one from any open session. Keeps which pane has the
/// focus (where typing goes) and where the divider is.
class SplitController extends ChangeNotifier {
  SplitController({required this.primary, required this.primaryFocus});

  final TerminalController primary;
  final FocusNode primaryFocus;

  /// The second pane's own focus, for hardware keys and the phone's
  /// keyboard.
  final secondFocus = FocusNode(debugLabel: 'second terminal');

  /// The panes may not get narrower than this share of the width.
  static const minFraction = 0.2;

  TerminalController? _second;
  bool _secondFocused = false;
  double _fraction = 0.5;
  final _targets = Expando<TerminalCommandTarget>('commands');

  TerminalController? get second => _second;
  bool get isOpen => _second != null;
  bool get secondFocused => _second != null && _secondFocused;

  /// The left pane's share of the width.
  double get fraction => _fraction;

  /// Shows [terminal] in the second pane and gives it the focus.
  void open(TerminalController terminal) {
    if (identical(terminal, primary)) return;
    _release();
    _second = terminal;
    // Its reconnect, recording and broadcast state show on this screen,
    // and it counts as on screen for "done" notifications.
    terminal.addListener(notifyListeners);
    terminal.shownOnScreen();
    _secondFocused = true;
    secondFocus.requestFocus();
    notifyListeners();
  }

  /// Back to one terminal.
  void close() {
    if (_second == null) return;
    _release();
    _second = null;
    _secondFocused = false;
    primaryFocus.requestFocus();
    notifyListeners();
  }

  /// Makes the left (false) or right (true) pane the one that types.
  void focus({required bool second}) {
    final want = second && _second != null;
    (want ? secondFocus : primaryFocus).requestFocus();
    if (want == _secondFocused) return;
    _secondFocused = want;
    notifyListeners();
  }

  void setFraction(double value) {
    final clamped = value.clamp(minFraction, 1 - minFraction);
    if (clamped == _fraction) return;
    _fraction = clamped;
    notifyListeners();
  }

  /// Where typing goes. [shown] is false while the screen is too narrow
  /// for two panes; then only the primary one is on screen.
  TerminalController typing({required bool shown}) => shown && secondFocused ? _second! : primary;

  FocusNode focusNode({required bool shown}) => shown && secondFocused ? secondFocus : primaryFocus;

  /// Picked recent commands go to the same terminal as typing.
  TerminalCommandTarget commands({required bool shown}) {
    final terminal = typing(shown: shown);
    return _targets[terminal] ??= TerminalCommandTarget(terminal);
  }

  /// Closes the second pane once its terminal was closed elsewhere.
  void dropClosed(SessionManager sessions) {
    final s = _second;
    if (s != null && !sessions.terminals.contains(s)) close();
  }

  void _release() {
    _second?.removeListener(notifyListeners);
    _second?.leftScreen();
  }

  /// The terminals on screen: the primary one, and the second pane's
  /// when [shown].
  List<TerminalController> visible({required bool shown}) => [primary, if (shown && _second != null) _second!];

  @override
  void dispose() {
    _release();
    secondFocus.dispose();
    super.dispose();
  }
}
