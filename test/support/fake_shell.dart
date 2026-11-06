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
        cols: 20,
        lines: [TerminalLine(key: BigInt.zero, runs: const []), TerminalLine(key: BigInt.one, runs: const [])],
        cursor: const TerminalCursor(row: 0, col: 0, visible: true, shape: CursorShape.block, color: 0),
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
  String textBetween({required int startRow, required int startCol, required int endRow, required int endCol}) => '';

  @override
  String visibleText() => '';

  @override
  bool isClosed() => false;

  @override
  bool get isDisposed => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
