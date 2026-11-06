import 'dart:async';

import 'package:multiplex/src/rust/api/terminal.dart';
import 'package:multiplex/src/rust/api/terminal_types.dart';

/// A shell without a server: records what is sent to it and shows an
/// empty screen. Methods a test does not need do nothing.
class FakeShell implements RemoteShell {
  final sent = <String>[];
  final eventController = StreamController<ShellEvent>.broadcast();

  @override
  Stream<ShellEvent> events() => eventController.stream;

  @override
  TerminalFrame frame() => TerminalFrame(
        rows: 2,
        cols: 60,
        lines: [TerminalLine(key: BigInt.zero, runs: const []), TerminalLine(key: BigInt.one, runs: const [])],
        cursor: TerminalCursor(row: 0, col: cursorCol, visible: true, shape: CursorShape.block, color: 0),
        scrollOffset: 0,
        scrollbackLen: 0,
        alternateScreen: false,
        mouseReporting: false,
        title: '',
        background: 0,
        foreground: 0,
      );

  @override
  void sendText({required String text, required KeyModifiers mods}) => sent.add(mods.ctrl ? 'ctrl+$text' : text);

  @override
  void sendKey({required TerminalKey key, required KeyModifiers mods}) => sent.add('<${key.name}>');

  @override
  void paste({required String text}) => sent.add('paste:$text');

  @override
  String textBetween({required int startRow, required int startCol, required int endRow, required int endCol}) {
    final line = row0.padRight(60);
    return startRow == 0 ? line.substring(startCol.clamp(0, 60), (endCol + 1).clamp(0, 60)) : '';
  }

  @override
  String visibleText() => '';

  @override
  bool isClosed() => false;

  /// The pauses asked of the recording, in order.
  final recordingPauses = <bool>[];

  /// Text shown on the screen's first row, for prompts.
  String row0 = '';

  /// Where the cursor is in [frame].
  int cursorCol = 0;

  @override
  bool stopRecording() => true;

  @override
  void setRecordingPaused({required bool paused}) => recordingPauses.add(paused);

  @override
  bool get isDisposed => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
