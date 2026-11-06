import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../src/rust/api/terminal.dart';
import '../src/rust/api/terminal_types.dart';
import 'command_capture.dart';
import 'command_timer.dart';
import 'paste_guard.dart';

/// Drives one terminal on screen: listens to the native shell, pulls a new
/// frame at most once per display frame, and forwards input.
///
/// Ctrl and Alt from the on-screen key bar are "sticky": tap Ctrl, then a
/// letter on the keyboard, and the letter is sent with Ctrl.
class TerminalController extends ChangeNotifier {
  TerminalController({
    required this.shell,
    required String title,
    required this.sessionId,
    this.number = 1,
    this.hostId,
    this.onCommand,
    this.onConnectionLost,
    this.onCommandDone,
    this.onInput,
    this.fixedSize = false,
    // The title is private and changes later, so it cannot be a named "this." parameter.
    // ignore: prefer_initializing_formals
  }) : _title = title {
    _events = shell.events().listen(_onEvent, onError: (_) => _end('The terminal stopped unexpectedly.'));
    pull();
  }

  final RemoteShell shell;

  /// The [LiveSession] this terminal belongs to.
  final String sessionId;

  /// The saved host, for its command history. Null for a host that is
  /// not saved.
  final String? hostId;

  /// Which terminal of its connection this is (1, 2, ...). Never reused
  /// while the connection is open, so it can name a tmux session.
  final int number;

  /// Told each command the user runs (read from the screen at Enter).
  final void Function(String command)? onCommand;

  /// Called when the connection drops, instead of ending the terminal;
  /// the session then tries to reconnect. Null: the terminal just ends.
  final VoidCallback? onConnectionLost;

  /// Told each command that finished, with how long it ran.
  final void Function(FinishedCommand done)? onCommandDone;

  /// Told every piece of input sent to this shell, as a function that
  /// sends it to a shell, so broadcast mode can send it to others too.
  final void Function(TerminalController from, void Function(RemoteShell shell) send)? onInput;

  /// Keeps the size the shell has (a recording plays at its own size).
  final bool fixedSize;

  /// How many screens show this terminal right now.
  int _views = 0;

  /// A terminal screen shows this terminal (for "done" notifications).
  bool get onScreen => _views > 0;

  void shownOnScreen() => _views++;

  void leftScreen() => _views = (_views - 1).clamp(0, 1 << 20);
  late final _timer = CommandTimer(onFinished: (done) => onCommandDone?.call(done));
  late final _capture = CommandCapture(onCommand: (command) => onCommand?.call(command), onRun: _timer.ran);
  late final StreamSubscription<ShellEvent> _events;

  TerminalFrame? _frame;
  String _title;
  String? _endReason;
  String? _reconnectNote;
  bool _pullPending = false;
  bool _ctrl = false;
  bool _alt = false;

  /// Called when the remote program rings the bell.
  VoidCallback? onBell;

  /// Called when the remote program copied text (OSC 52).
  void Function(String text)? onRemoteCopy;

  /// Asks the user about a paste that [PasteGuard] stopped; true pastes
  /// it. Without one, every paste goes straight through.
  Future<bool> Function(String text, List<String> reasons)? confirmPaste;

  TerminalFrame? get frame => _frame;
  String get title => _title;
  bool get ended => _endReason != null;
  String? get endReason => _endReason;

  /// The connection dropped and is being restored; the screen stays.
  bool get reconnecting => _reconnectNote != null;

  /// "Reconnecting…" and when the next try is, while [reconnecting].
  String? get reconnectNote => _reconnectNote;

  /// No input goes anywhere while the shell is gone or coming back.
  bool get _inputOff => ended || reconnecting;
  bool get ctrlLatched => _ctrl;
  bool get altLatched => _alt;

  /// The output is being recorded to a file.
  bool get recording => _recording;
  bool _recording = false;
  bool _recordingPaused = false;

  /// Starts recording the output to an asciinema file at [path].
  void startRecording(String path) {
    shell.startRecording(path: path, title: _title);
    _recording = true;
    _recordingPaused = false;
    notifyListeners();
  }

  /// Ends the recording; the file is complete after this.
  void stopRecording() {
    if (!_recording) return;
    _recording = false;
    shell.stopRecording();
    notifyListeners();
  }

  /// Never records while a password prompt is on screen.
  void _guardRecording(ScreenText screen) {
    if (!_recording) return;
    final prompt = PasswordPrompt.at(screen);
    if (prompt == _recordingPaused) return;
    _recordingPaused = prompt;
    shell.setRecordingPaused(paused: prompt);
  }

  /// What the user has typed on the current command line so far, read
  /// from the screen. Empty when no line is being typed.
  String get typedLine => _capture.typed;

  ScreenText? get _screen => _frame == null ? null : FrameScreenText(_frame!, shell);

  /// Takes the current screen from the native side and redraws.
  void pull() {
    _frame = shell.frame();
    if (_frame!.title.isNotEmpty) _title = _frame!.title;
    final screen = FrameScreenText(_frame!, shell);
    _capture.onFrame(screen);
    _timer.onFrame(screen);
    _guardRecording(screen);
    notifyListeners();
  }

  // Input.

  /// Text from the keyboard. Uses (and then releases) sticky Ctrl/Alt.
  void type(String text) {
    if (text.isEmpty || _inputOff) return;
    final mods = _takeModifiers();
    _beforeText(text, mods);
    _send((s) => s.sendText(text: text, mods: mods));
  }

  void key(TerminalKey key, {bool shift = false}) {
    if (_inputOff) return;
    final mods = _takeModifiers();
    _beforeKey(key);
    final all = KeyModifiers(ctrl: mods.ctrl, alt: mods.alt, shift: shift);
    _send((s) => s.sendKey(key: key, mods: all));
  }

  /// A key with explicit modifiers, from a hardware keyboard.
  void keyWith(TerminalKey key, KeyModifiers mods) {
    if (_inputOff) return;
    _beforeKey(key);
    _send((s) => s.sendKey(key: key, mods: mods));
  }

  void textWith(String text, KeyModifiers mods) {
    if (_inputOff) return;
    _beforeText(text, mods);
    _send((s) => s.sendText(text: text, mods: mods));
  }

  void paste(String text) {
    if (_inputOff || text.isEmpty) return;
    // A paste of several lines runs them at once: not one command to keep.
    if (text.contains('\n') || text.contains('\r')) {
      _capture.cancel();
    } else {
      _capture.input(_screen);
    }
    _send((s) => s.paste(text: text));
  }

  void _send(void Function(RemoteShell shell) send) {
    send(shell);
    onInput?.call(this, send);
  }

  // Command capture: tell it about each key before the key is sent, so
  // it sees the screen as it was.

  void _beforeKey(TerminalKey key) {
    if (key == TerminalKey.enter) {
      _capture.enter(_screen);
    } else {
      _capture.input(_screen);
    }
  }

  void _beforeText(String text, KeyModifiers mods) {
    if (mods.ctrl && CaptureKeys.cancelling.contains(text.toLowerCase())) {
      _capture.cancel();
    } else {
      _capture.input(_screen);
    }
  }

  /// Pastes what the user brought from elsewhere (the clipboard, the
  /// phone keyboard's clipboard): several lines or a risky command are
  /// shown to the user first. Text the app itself puts in, such as a
  /// recent command, uses [paste] directly.
  Future<void> pasteChecked(String text) async {
    if (_inputOff || text.isEmpty) return;
    final reasons = PasteGuard.reasons(text);
    final ask = confirmPaste;
    if (reasons.isNotEmpty && ask != null && !await ask(text, reasons)) return;
    paste(text);
  }

  Future<void> pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    await pasteChecked(data?.text ?? '');
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

  void resize(int cols, int rows) {
    if (!fixedSize) shell.resize(cols: cols, rows: rows);
  }

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

  /// Every place `query` appears on the screen and in the scrollback.
  List<SearchMatch> find(String query, {required bool caseSensitive}) => shell.find(query: query, caseSensitive: caseSensitive);

  /// Scrolls so a line found by [find] shows, and redraws.
  void revealLine(int line) {
    shell.revealLine(line: line);
    pull();
  }

  void setPalette(TerminalPalette palette) {
    shell.setPalette(palette: palette);
    pull();
  }

  // Reconnecting.

  /// Shows the "Reconnecting…" state with [note].
  void showReconnecting(String note) {
    if (ended) return;
    _capture.cancel();
    _reconnectNote = note;
    notifyListeners();
  }

  /// The shell is back on a new connection.
  void reconnected() {
    if (_reconnectNote == null) return;
    _reconnectNote = null;
    pull();
  }

  /// The connection could not be restored.
  void connectionGone(String reason) {
    _reconnectNote = null;
    _end(reason);
  }

  void close() {
    shell.close();
    _end('Closed.');
  }

  @override
  void dispose() {
    stopRecording();
    _capture.flush();
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
      case ShellEvent_CommandStarted():
        _timer.markStarted();
      case ShellEvent_CommandFinished(:final exitCode):
        _timer.markFinished(exitCode);
      case ShellEvent_Disconnected():
        _timer.reset();
        final lost = onConnectionLost;
        if (lost == null) {
          _end('The connection was lost.');
        } else {
          showReconnecting('Reconnecting…');
          lost();
        }
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
    stopRecording();
    _reconnectNote = null;
    _endReason = reason;
    pull();
  }
}

/// Keys that matter to the command capture.
abstract final class CaptureKeys {
  /// With Ctrl these abandon the line: Ctrl+C, Ctrl+D, Ctrl+G.
  static const cancelling = {'c', 'd', 'g'};
}
