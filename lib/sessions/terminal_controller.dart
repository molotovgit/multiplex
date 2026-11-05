import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../src/rust/api/terminal.dart';
import '../src/rust/api/terminal_types.dart';

/// Drives one terminal on screen: listens to the native shell, pulls a new
/// frame at most once per display frame, and forwards input.
///
/// Ctrl and Alt from the on-screen key bar are "sticky": tap Ctrl, then a
/// letter on the keyboard, and the letter is sent with Ctrl.
class TerminalController extends ChangeNotifier {
  // The title is private and changes later, so it cannot be a named "this." parameter.
  // ignore: prefer_initializing_formals
  TerminalController({required this.shell, required String title, required this.sessionId}) : _title = title {
    _events = shell.events().listen(_onEvent, onError: (_) => _end('The terminal stopped unexpectedly.'));
    pull();
  }

  final RemoteShell shell;

  /// The [LiveSession] this terminal belongs to.
  final String sessionId;
  late final StreamSubscription<ShellEvent> _events;

  TerminalFrame? _frame;
  String _title;
  String? _endReason;
  bool _pullPending = false;
  bool _ctrl = false;
  bool _alt = false;

  /// Called when the remote program rings the bell.
  VoidCallback? onBell;

  /// Called when the remote program copied text (OSC 52).
  void Function(String text)? onRemoteCopy;

  TerminalFrame? get frame => _frame;
  String get title => _title;
  bool get ended => _endReason != null;
  String? get endReason => _endReason;
  bool get ctrlLatched => _ctrl;
  bool get altLatched => _alt;

  /// Takes the current screen from the native side and redraws.
  void pull() {
    _frame = shell.frame();
    if (_frame!.title.isNotEmpty) _title = _frame!.title;
    notifyListeners();
  }

  // Input.

  /// Text from the keyboard. Uses (and then releases) sticky Ctrl/Alt.
  void type(String text) {
    if (text.isEmpty || ended) return;
    shell.sendText(text: text, mods: _takeModifiers());
  }

  void key(TerminalKey key, {bool shift = false}) {
    if (ended) return;
    final mods = _takeModifiers();
    shell.sendKey(key: key, mods: KeyModifiers(ctrl: mods.ctrl, alt: mods.alt, shift: shift));
  }

  /// A key with explicit modifiers, from a hardware keyboard.
  void keyWith(TerminalKey key, KeyModifiers mods) {
    if (!ended) shell.sendKey(key: key, mods: mods);
  }

  void textWith(String text, KeyModifiers mods) {
    if (!ended) shell.sendText(text: text, mods: mods);
  }

  void paste(String text) {
    if (!ended && text.isNotEmpty) shell.paste(text: text);
  }

  Future<void> pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    paste(data?.text ?? '');
  }

  void toggleCtrl() {
    _ctrl = !_ctrl;
    notifyListeners();
  }

  void toggleAlt() {
    _alt = !_alt;
    notifyListeners();
  }

  // View.

  void resize(int cols, int rows) => shell.resize(cols: cols, rows: rows);

  /// Scroll by whole lines (positive = back in history).
  void scroll(int lines, int row, int col) {
    if (lines == 0) return;
    if (shell.scroll(lines: lines, row: row, col: col)) pull();
  }

  /// Returns true when the tap went to the program as a mouse click.
  bool click(int row, int col) => shell.click(row: row, col: col);

  void scrollToBottom() {
    shell.scrollToBottom();
    pull();
  }

  String textBetween(int startRow, int startCol, int endRow, int endCol) =>
      shell.textBetween(startRow: startRow, startCol: startCol, endRow: endRow, endCol: endCol);

  void setPalette(TerminalPalette palette) {
    shell.setPalette(palette: palette);
    pull();
  }

  void close() {
    shell.close();
    _end('Closed.');
  }

  @override
  void dispose() {
    _events.cancel();
    if (!ended) shell.close();
    super.dispose();
  }

  KeyModifiers _takeModifiers() {
    final mods = KeyModifiers(ctrl: _ctrl, alt: _alt, shift: false);
    if (_ctrl || _alt) {
      _ctrl = false;
      _alt = false;
      notifyListeners();
    }
    return mods;
  }

  void _onEvent(ShellEvent event) {
    switch (event) {
      case ShellEvent_Changed():
        _schedulePull();
      case ShellEvent_Title(:final field0):
        _title = field0;
        notifyListeners();
      case ShellEvent_Bell():
        onBell?.call();
      case ShellEvent_Clipboard(:final field0):
        onRemoteCopy?.call(field0);
      case ShellEvent_Exited(:final code):
        _end(code == null ? 'The shell ended.' : 'The shell ended with exit code $code.');
      case ShellEvent_Disconnected():
        _end('The connection was lost.');
    }
  }

  /// Many changes between two display frames become one pull.
  void _schedulePull() {
    if (_pullPending) return;
    _pullPending = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _pullPending = false;
      pull();
    });
  }

  void _end(String reason) {
    if (ended) return;
    _endReason = reason;
    pull();
  }
}
