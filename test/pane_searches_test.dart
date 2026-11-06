import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/sessions/terminal_controller.dart';
import 'package:multiplex/src/rust/api/terminal.dart';
import 'package:multiplex/src/rust/api/terminal_types.dart';
import 'package:multiplex/ui/terminal/search/pane_searches.dart';

/// A shell whose whole text is a list of lines.
class LinesShell implements RemoteShell {
  LinesShell(this.lines);

  final List<String> lines;
  final revealed = <int>[];
  final _events = StreamController<ShellEvent>();

  @override
  Stream<ShellEvent> events() => _events.stream;

  @override
  TerminalFrame frame() => const TerminalFrame(
        rows: 2,
        cols: 20,
        lines: [],
        cursor: TerminalCursor(row: 0, col: 0, visible: true, shape: CursorShape.block, color: 0),
        scrollOffset: 0,
        scrollbackLen: 0,
        alternateScreen: false,
        mouseReporting: false,
        title: '',
        background: 0,
        foreground: 0,
      );

  @override
  List<SearchMatch> find({required String query, required bool caseSensitive}) => [
        for (var i = 0; i < lines.length; i++)
          if (lines[i].contains(query)) SearchMatch(line: i, col: lines[i].indexOf(query), width: query.length),
      ];

  @override
  void revealLine({required int line}) => revealed.add(line);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each split pane has its own search over its own terminal', () {
    final left = LinesShell(['error one', 'ok']);
    final right = LinesShell(['fine', 'error two', 'error three']);
    final a = TerminalController(shell: left, title: 'a', sessionId: 's1');
    final b = TerminalController(shell: right, title: 'b', sessionId: 's2');
    final searches = PaneSearches();
    addTearDown(searches.dispose);

    expect(identical(searches.of(a), searches.of(a)), isTrue);
    searches.of(a)
      ..open()
      ..setQuery('error');
    searches.of(b)
      ..open()
      ..setQuery('error');
    expect(searches.of(a).counter, '1 of 1');
    expect(searches.of(b).counter, '2 of 2');
    // Moving through one pane's matches scrolls only that pane.
    searches.of(b).previous();
    expect(left.revealed, [0]);
    expect(right.revealed, [2, 1]);
    searches.of(a).close();
    expect(searches.of(b).isOpen, isTrue);
  });

  test('tells the screen when any pane search changes', () {
    final a = TerminalController(shell: LinesShell(['x']), title: 'a', sessionId: 's1');
    final searches = PaneSearches();
    addTearDown(searches.dispose);
    var told = 0;
    searches.addListener(() => told++);
    searches.of(a).open();
    expect(told, 1);
  });
}
