import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/command_history.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_document.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/command_capture.dart';
import 'package:multiplex/src/rust/api/terminal_types.dart';

/// A terminal screen made of plain strings. Rows in [wrapped] continue in
/// the next row, the way the real terminal joins them.
class FakeScreen implements ScreenText {
  FakeScreen({this.cols = 40, int rows = 6}) : lines = List.filled(rows, '', growable: true);

  final List<String> lines;
  final wrapped = <int>{};

  @override
  final int cols;

  @override
  int cursorRow = 0;

  @override
  int cursorCol = 0;

  @override
  bool alternateScreen = false;

  @override
  bool scrolledBack = false;

  @override
  int get rows => lines.length;

  /// Puts [text] on [row] and the cursor after it.
  void show(int row, String text) {
    lines[row] = text;
    cursorRow = row;
    cursorCol = text.length;
  }

  void moveTo(int row, int col) {
    cursorRow = row;
    cursorCol = col;
  }

  @override
  String between(int startRow, int startCol, int endRow, int endCol) {
    final out = StringBuffer();
    for (var r = startRow; r <= endRow; r++) {
      final line = lines[r].padRight(cols);
      final from = r == startRow ? startCol : 0;
      final to = r == endRow ? endCol + 1 : cols;
      final cells = from >= to ? '' : line.substring(from.clamp(0, cols), to.clamp(0, cols));
      // A wrapped row keeps its blanks: they are part of the line.
      out.write(r < endRow && wrapped.contains(r) ? cells : cells.trimRight());
      if (r < endRow && !wrapped.contains(r)) out.write('\n');
    }
    return out.toString();
  }

  @override
  bool rowIsFull(int row) => lines[row].length >= cols;
}

/// A capture with its recorded commands.
class CaptureProbe {
  CaptureProbe() {
    capture = CommandCapture(onCommand: commands.add);
  }

  final commands = <String>[];
  late final CommandCapture capture;

  /// Types [text] after the prompt on [row]: first key, then the echo.
  void type(FakeScreen s, int row, String prompt, String text) {
    s.show(row, prompt);
    capture.input(s);
    s.show(row, '$prompt$text');
    capture.onFrame(s);
  }

  /// Enter, then the shell's answer: the cursor goes to the next row.
  void enter(FakeScreen s) {
    capture.enter(s);
    s.moveTo((s.cursorRow + 1).clamp(0, s.rows - 1), 0);
    capture.onFrame(s);
  }
}

void main() {
  group('history rules', () {
    test('newest first, duplicates move to the top and count their uses', () {
      final h = CommandHistory();
      h.record('a', 'ls');
      h.record('a', 'pwd');
      h.record('a', '  ls  ');
      expect(h.recent('a').map((e) => e.command), ['ls', 'pwd']);
      expect(h.recent('a').first.uses, 2);
    });

    test('empty and very long lines are not kept', () {
      final h = CommandHistory();
      expect(h.record('a', '   '), isFalse);
      expect(h.record('a', 'x' * (CommandHistory.maxLength + 1)), isFalse);
      expect(h.recent('a'), isEmpty);
    });

    test('each host keeps at most 200, dropping the oldest unpinned', () {
      final h = CommandHistory();
      h.record('a', 'keep me');
      h.setPinned('a', 'keep me', true);
      for (var i = 0; i < 250; i++) {
        h.record('a', 'cmd $i');
      }
      final list = h.recent('a');
      expect(list, hasLength(CommandHistory.maxPerHost));
      expect(list.first.command, 'cmd 249');
      expect(list.any((e) => e.command == 'cmd 0'), isFalse);
      expect(list.any((e) => e.command == 'keep me'), isTrue, reason: 'pinned survives the cap');
    });

    test('pinned commands come first and hosts are kept apart', () {
      final h = CommandHistory();
      h.record('a', 'one');
      h.record('a', 'two');
      h.record('a', 'three');
      h.setPinned('a', 'one', true);
      h.record('b', 'other');
      expect(h.ordered('a').map((e) => e.command), ['one', 'three', 'two']);
      expect(h.ordered('b').map((e) => e.command), ['other']);
      h.delete('a', 'three');
      h.clear('b');
      expect(h.ordered('a').map((e) => e.command), ['one', 'two']);
      expect(h.recent('b'), isEmpty);
    });

    test('suggestions: starts-with before contains, pinned first, case ignored', () {
      final h = CommandHistory();
      for (final c in ['git status', 'echo git', 'Git log', 'ls']) {
        h.record('a', c);
      }
      h.setPinned('a', 'git status', true);
      expect(h.suggest('a', 'git').map((e) => e.command), ['git status', 'Git log', 'echo git']);
      expect(h.suggest('a', '').first.command, 'git status');
      expect(h.suggest('a', 'ls'), isEmpty, reason: 'the exact line is not suggested again');
      expect(h.search('a', 'LOG').map((e) => e.command), ['Git log']);
    });

    test('JSON round trip, and damaged JSON is read as far as it goes', () {
      final h = CommandHistory();
      h.record('a', 'ls', at: DateTime(2026, 1, 2));
      h.record('a', 'top', at: DateTime(2026, 1, 3));
      h.setPinned('a', 'ls', true);
      final back = CommandHistory.fromJson(jsonDecode(jsonEncode(h.toJson())));
      expect(back.ordered('a').map((e) => (e.command, e.pinned)), [('ls', true), ('top', false)]);
      expect(back.recent('a').last.lastUsed, DateTime(2026, 1, 2));

      final damaged = CommandHistory.fromJson({
        'a': [
          {'command': 'ok'},
          {'command': ''},
          'junk',
          {'command': 'ok'},
        ],
        'b': 'junk',
      });
      expect(damaged.recent('a').map((e) => e.command), ['ok']);
      expect(damaged.hosts, ['a']);
      expect(CommandHistory.fromJson(null).hosts, isEmpty);
    });

    test('merging a backup keeps both sides and the newer use', () {
      final mine = CommandHistory()..record('a', 'ls', at: DateTime(2026, 1, 1));
      final theirs = CommandHistory()
        ..record('a', 'ls', at: DateTime(2026, 2, 1))
        ..record('a', 'df', at: DateTime(2026, 1, 15))
        ..setPinned('a', 'df', true);
      mine.mergeFrom(theirs);
      expect(mine.recent('a').map((e) => e.command), ['ls', 'df']);
      expect(mine.recent('a').first.lastUsed, DateTime(2026, 2, 1));
      expect(mine.ordered('a').first.command, 'df');
    });
  });

  group('history in the vault', () {
    test('the store records, pins and deletes, and backups carry the history', () async {
      final store = await VaultStore.open(MemoryBackend());
      store.saveHost(const Host(id: 'h1', label: 'Box', address: 'box.example.com', username: 'root', authMode: AuthMode.password));
      store.recordCommand('h1', 'uptime');
      store.recordCommand('h1', 'df -h');
      store.pinCommand('h1', 'uptime', true);
      expect(store.commandHistory.ordered('h1').map((e) => e.command), ['uptime', 'df -h']);

      final backup = store.exportJson();
      expect(jsonDecode(backup), contains('commandHistory'));
      final restored = await VaultStore.open(MemoryBackend());
      restored.importJson(backup, replace: true);
      expect(restored.commandHistory.ordered('h1').map((e) => e.command), ['uptime', 'df -h']);

      store.deleteCommand('h1', 'df -h');
      expect(store.commandHistory.recent('h1').map((e) => e.command), ['uptime']);
      store.deleteHost('h1');
      expect(store.commandHistory.recent('h1'), isEmpty, reason: 'deleting a host deletes its history');
      await store.flush();
    });

    test('a vault without history still opens', () {
      final doc = VaultDocument.fromJson(const {'format': 1});
      expect(doc.commandHistory.hosts, isEmpty);
    });
  });

  group('capture', () {
    test('the prompt is stripped and the command recorded at Enter', () {
      final s = FakeScreen();
      final p = CaptureProbe();
      p.type(s, 0, 'user@box:~\$ ', 'ls -la');
      expect(p.capture.typed, 'ls -la');
      p.enter(s);
      expect(p.commands, ['ls -la']);
      expect(p.capture.typed, '');
    });

    test('a completion that arrives after Enter is included', () {
      final s = FakeScreen();
      final p = CaptureProbe();
      p.type(s, 0, '\$ ', 'cd Doc');
      p.capture.enter(s);
      s.show(0, '\$ cd Documents/');
      s.moveTo(1, 0);
      p.capture.onFrame(s);
      expect(p.commands, ['cd Documents/']);
    });

    test('a command longer than one row is read across the wrap', () {
      final s = FakeScreen(cols: 20);
      final p = CaptureProbe();
      const command = 'echo aaaaaaaaaa bbbbbbbbbb cccccccccc dddd';
      s.show(0, '\$ ');
      p.capture.input(s);
      s.lines[0] = '\$ ${command.substring(0, 18)}';
      s.lines[1] = command.substring(18, 38);
      s.lines[2] = command.substring(38);
      s.wrapped.addAll({0, 1});
      s.moveTo(2, command.length - 38);
      p.capture.onFrame(s);
      p.enter(s);
      expect(p.commands, [command]);
    });

    test('the prompt is found again after the screen scrolled', () {
      final s = FakeScreen(cols: 10, rows: 5);
      final p = CaptureProbe();
      s.show(4, '\$ ');
      p.capture.input(s);
      // The wrap pushed everything up one row.
      s.lines
        ..[3] = '\$ abcdefgh'
        ..[4] = 'ijkl';
      s.wrapped.add(3);
      s.moveTo(4, 4);
      p.capture.onFrame(s);
      p.capture.enter(s);
      // Enter scrolls again: the command moves up, the cursor starts a row.
      s.lines
        ..[2] = '\$ abcdefgh'
        ..[3] = 'ijkl'
        ..[4] = '';
      s.wrapped
        ..clear()
        ..add(2);
      s.moveTo(4, 0);
      p.capture.onFrame(s);
      expect(p.commands, ['abcdefghijkl']);
    });

    test('nothing is recorded in a full-screen program', () {
      final s = FakeScreen()..alternateScreen = true;
      final p = CaptureProbe();
      p.type(s, 0, ':', 'wq');
      p.enter(s);
      expect(p.commands, isEmpty);
    });

    test('nothing is recorded when typing did not echo (a password)', () {
      final s = FakeScreen();
      final p = CaptureProbe();
      s.show(0, 'Password: ');
      p.capture.input(s);
      p.capture.onFrame(s);
      p.enter(s);
      expect(p.commands, isEmpty);
    });

    test('a slow echo that only shows after Enter still counts', () {
      final s = FakeScreen();
      final p = CaptureProbe();
      s.show(0, '\$ ');
      p.capture.input(s);
      p.capture.enter(s);
      s.lines[0] = '\$ uptime';
      s.moveTo(1, 0);
      p.capture.onFrame(s);
      expect(p.commands, ['uptime']);
    });

    test('Ctrl+C drops the line; empty, space-led and masked lines are skipped', () {
      final s = FakeScreen();
      final p = CaptureProbe();
      p.type(s, 0, '\$ ', 'rm -rf build');
      p.capture.cancel();
      p.enter(s);
      p.type(s, 1, '\$ ', '');
      p.enter(s);
      p.type(s, 2, '\$ ', ' secret-thing');
      p.enter(s);
      p.type(s, 3, 'Password: ', '******');
      p.enter(s);
      expect(p.commands, isEmpty);
    });

    test('a command waiting for the answer is kept when the next key comes', () {
      final s = FakeScreen();
      final p = CaptureProbe();
      p.type(s, 0, '\$ ', 'make');
      p.capture.enter(s);
      p.capture.input(s);
      expect(p.commands, ['make']);
    });

    test('row length is measured from the frame runs', () {
      TextRun run(int col, String text, {int? width}) => TextRun(col: col, width: width ?? text.length, text: text, fg: 0, bg: 0, style: 0);
      final line = TerminalLine(key: BigInt.zero, runs: [run(0, '\$ '), run(2, 'ls   ')]);
      expect(RowCells.lastUsedCell(line), 4);
      final wide = TerminalLine(key: BigInt.zero, runs: [run(0, 'abc'), run(3, '界', width: 2)]);
      expect(RowCells.lastUsedCell(wide), 5);
    });
  });
}
