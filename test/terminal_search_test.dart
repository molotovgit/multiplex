import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/src/rust/api/terminal_types.dart';
import 'package:multiplex/ui/terminal/search/terminal_search.dart';
import 'package:multiplex/ui/terminal/search/terminal_search_bar.dart';
import 'package:multiplex/ui/terminal/terminal_marks.dart';

/// Searches a list of lines instead of a terminal.
class FakeSource implements SearchSource {
  FakeSource(this.lines);

  List<String> lines;
  final revealed = <int>[];
  int searches = 0;

  @override
  List<SearchMatch> find(String query, {required bool caseSensitive}) {
    searches++;
    final found = <SearchMatch>[];
    for (var i = 0; i < lines.length; i++) {
      final line = caseSensitive ? lines[i] : lines[i].toLowerCase();
      final q = caseSensitive ? query : query.toLowerCase();
      var at = line.indexOf(q);
      while (at >= 0) {
        found.add(SearchMatch(line: i, col: at, width: q.length));
        at = line.indexOf(q, at + q.length);
      }
    }
    return found;
  }

  @override
  void reveal(int line) => revealed.add(line);
}

TerminalFrame frameAt({required int scrollbackLen, required int scrollOffset, int rows = 4}) => TerminalFrame(
      rows: rows,
      cols: 40,
      lines: const [],
      cursor: const TerminalCursor(row: 0, col: 0, visible: true, shape: CursorShape.block, color: 0),
      scrollOffset: scrollOffset,
      scrollbackLen: scrollbackLen,
      alternateScreen: false,
      mouseReporting: false,
      title: '',
      background: 0,
      foreground: 0,
    );

void main() {
  final lines = ['boot ok', 'Error: disk', 'fine', 'error again', 'all good', 'last error'];

  group('TerminalSearch', () {
    test('starts on the newest match and counts like "3 of 3"', () {
      final source = FakeSource(lines);
      final search = TerminalSearch(source)..open();
      search.setQuery('error');
      expect(search.matches.map((m) => m.line), [1, 3, 5]);
      expect(search.counter, '3 of 3');
      expect(source.revealed, [5]);
    });

    test('older and newer wrap round and scroll the view to the match', () {
      final source = FakeSource(lines);
      final search = TerminalSearch(source)..open();
      search.setQuery('error');
      search.previous();
      expect(search.counter, '2 of 3');
      search.previous();
      search.previous();
      expect(search.counter, '3 of 3');
      search.next();
      expect(search.counter, '1 of 3');
      expect(source.revealed, [5, 3, 1, 5, 1]);
    });

    test('says when nothing matches, and nothing while empty', () {
      final search = TerminalSearch(FakeSource(lines))..open();
      expect(search.counter, '');
      search.setQuery('zebra');
      expect(search.counter, 'No matches');
      expect(search.currentMatch, isNull);
      search.next(); // does nothing, does not throw
    });

    test('match case narrows the matches', () {
      final search = TerminalSearch(FakeSource(lines))..open();
      search.setQuery('Error');
      expect(search.matches, hasLength(3));
      search.toggleCaseSensitive();
      expect(search.matches.map((m) => m.line), [1]);
    });

    test('turns matches into screen rows of the current view', () {
      final search = TerminalSearch(FakeSource(lines))..open();
      search.setQuery('error');
      // 6 lines, 4 rows, scrolled back 1: the view shows lines 1 to 4.
      final frame = frameAt(scrollbackLen: 2, scrollOffset: 1);
      expect(search.visibleIn(frame), [const CellSpan(0, 0, 5), const CellSpan(2, 0, 5)]);
      // The current match (line 5) is below the view.
      expect(search.currentIn(frame), isNull);
      search.previous();
      expect(search.currentIn(frame), const CellSpan(2, 0, 5));
      expect(search.visibleIn(frame), [const CellSpan(0, 0, 5)]);
    });

    test('shows no marks once closed', () {
      final search = TerminalSearch(FakeSource(lines))..open();
      search.setQuery('error');
      search.close();
      expect(search.visibleIn(frameAt(scrollbackLen: 2, scrollOffset: 0)), isEmpty);
    });

    test('searches again shortly after new output and keeps the current match', () async {
      final source = FakeSource([...lines]);
      final search = TerminalSearch(source, refreshDelay: Duration.zero)..open();
      search.setQuery('error');
      search.previous(); // line 3
      source.lines = [...lines, 'new error'];
      search.screenChanged();
      search.screenChanged(); // a burst of output is one search
      expect(source.searches, 1);
      await Future<void>.delayed(Duration.zero);
      expect(source.searches, 2);
      expect(search.matches, hasLength(4));
      expect(search.currentMatch?.line, 3);
      expect(search.counter, '2 of 4');
    });

    test('does not search again while closed', () async {
      final source = FakeSource(lines);
      final search = TerminalSearch(source, refreshDelay: Duration.zero)..open();
      search.setQuery('error');
      search.close();
      search.screenChanged();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(source.searches, 1);
    });
  });

  group('TerminalSearchBar', () {
    Future<(TerminalSearch, FakeSource, List<String>)> pump(WidgetTester tester) async {
      final source = FakeSource(lines);
      final search = TerminalSearch(source)..open();
      final closed = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TerminalSearchBar(search: search, onClose: () => closed.add('closed'))),
      ));
      await tester.pump();
      return (search, source, closed);
    }

    testWidgets('typing searches and shows the count', (tester) async {
      final (search, _, _) = await pump(tester);
      await tester.enterText(find.byType(TextField), 'error');
      await tester.pump();
      expect(find.text('3 of 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Older match'));
      await tester.pump();
      expect(find.text('2 of 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Newer match'));
      await tester.pump();
      expect(search.counter, '3 of 3');
    });

    testWidgets('match case and close', (tester) async {
      final (search, _, closed) = await pump(tester);
      await tester.enterText(find.byType(TextField), 'Error');
      await tester.pump();
      await tester.tap(find.byTooltip('Match case: off'));
      await tester.pump();
      expect(find.text('1 of 1'), findsOneWidget);
      await tester.tap(find.byTooltip('Close search'));
      await tester.pump();
      expect(search.isOpen, isFalse);
      expect(closed, ['closed']);
    });

    testWidgets('the step buttons are off with no matches', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'zebra');
      await tester.pump();
      expect(find.text('No matches'), findsOneWidget);
      final older = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.keyboard_arrow_up));
      expect(older.onPressed, isNull);
    });
  });
}
