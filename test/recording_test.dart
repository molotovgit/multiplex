import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/cast_file.dart';
import 'package:multiplex/sessions/cast_player.dart';
import 'package:multiplex/sessions/recordings.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/sessions/terminal_controller.dart';
import 'package:multiplex/ui/sessions/recordings_screen.dart';

import 'support/fake_shell.dart';

class FakeCastScreen implements CastScreen {
  final shown = <String>[];

  @override
  void feed(String text) => shown.add(text);

  @override
  void resize(int cols, int rows) => shown.add('[${cols}x$rows]');

  @override
  void reset() => shown.add('[reset]');
}

const sample = '{"version": 2, "width": 100, "height": 30, "timestamp": 1, "title": "web"}\n'
    r'[0.5, "o", "$ make\r\n"]'
    '\n'
    '[1.0, "r", "90x20"]\n'
    '[1.0, "o", "built"]\n'
    r'[61.0, "o", "\r\ndone"]'
    '\n'
    '[61.5, "o", "cut sh';

void main() {
  group('cast file', () {
    test('reads the header and the events, skipping a cut-off last line', () {
      final cast = CastFile.parse(sample);
      expect((cast.width, cast.height, cast.title), (100, 30, 'web'));
      expect(cast.events.map((e) => e.data), ['\$ make\r\n', '90x20', 'built', '\r\ndone']);
      expect(cast.duration, 61.0);
    });

    test('anything else is refused with a plain message', () {
      expect(() => CastFile.parse(''), throwsFormatException);
      expect(() => CastFile.parse('hello'), throwsFormatException);
      expect(() => CastFile.parse('{"version": 1}'), throwsFormatException);
    });
  });

  group('player', () {
    testWidgets('plays in time, cuts long pauses and goes faster', (tester) async {
      final screen = FakeCastScreen();
      final player = CastPlayer(CastFile.parse(sample), screen)..play();
      await tester.pump(const Duration(milliseconds: 400));
      expect(screen.shown, isEmpty);
      await tester.pump(const Duration(milliseconds: 200));
      expect(screen.shown, ['\$ make\r\n']);
      // The resize and the output at the same moment come together.
      await tester.pump(const Duration(milliseconds: 500));
      expect(screen.shown.skip(1), ['[90x20]', 'built']);
      // A minute of quiet plays as two seconds, half that at 2x.
      player.setSpeed(2);
      await tester.pump(const Duration(milliseconds: 1001));
      expect(screen.shown.last, '\r\ndone');
      expect(player.finished, isTrue);
      expect(player.playing, isFalse);
      player.dispose();
    });

    testWidgets('pauses, and plays again from the start', (tester) async {
      final screen = FakeCastScreen();
      final player = CastPlayer(CastFile.parse(sample), screen)..play();
      player.pause();
      await tester.pump(const Duration(seconds: 5));
      expect(screen.shown, isEmpty);
      player.setSpeed(4);
      player.play();
      await tester.pump(const Duration(seconds: 2));
      expect(player.finished, isTrue);
      player.play();
      expect(screen.shown.where((s) => s == '[reset]'), hasLength(1));
      player.dispose();
    });
  });

  testWidgets('recording pauses while a password prompt is on screen', (tester) async {
    final shell = FakeShell();
    final terminal = TerminalController(shell: shell, title: 'web', sessionId: 's');
    void show(String row) {
      shell.row0 = row;
      shell.cursorCol = row.length;
      terminal.pull();
    }

    terminal.startRecording('x.cast');
    expect(terminal.recording, isTrue);
    show('[sudo] password for alice: ');
    show(r'alice@web:~$ ');
    show(r'alice@web:~$ ls');
    expect(shell.recordingPauses, [true, false]);
    show('Enter passphrase for key /home/a/.ssh/id: ');
    expect(shell.recordingPauses.last, isTrue);
    terminal.stopRecording();
    expect(terminal.recording, isFalse);
  });

  group('library', () {
    late Directory root;
    setUp(() async => root = await Directory.systemTemp.createTemp('mpx-rec'));
    tearDown(() => root.delete(recursive: true));

    test('names files by host and time, lists newest first, deletes', () async {
      final library = RecordingLibrary(root: () async => root);
      final path = await library.newPath('Web Server', at: DateTime(2026, 11, 6, 14, 5, 12));
      expect(path, endsWith('web-server-20261106-140512.cast'));
      await File(path).writeAsString(sample);
      final list = await library.list();
      expect(list.single.label, 'web-server 2026-11-06 14.05');
      await library.delete(list.single);
      expect(await library.list(), isEmpty);
    });

    testWidgets('the Recordings screen lists them', (tester) async {
      final library = RecordingLibrary(root: () async => root);
      await tester.runAsync(() async {
        await File(await library.newPath('web', at: DateTime(2026, 1, 2, 3, 4, 5))).writeAsString(sample);
      });
      final store = await VaultStore.open(MemoryBackend());
      final sessions = SessionManager(store);
      // The list is read from disk, which needs real time.
      await tester.runAsync(() async {
        await tester.pumpWidget(AppScope(
          vault: store,
          manager: sessions,
          child: MaterialApp(theme: AppTheme.build(store.activeTheme), home: RecordingsScreen(library: library)),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(find.text('web 2026-01-02 03.04'), findsOneWidget);
      expect(RecordingText.size(2400000), '2.3 MB');
      await tester.pump(const Duration(seconds: 2));
      sessions.dispose();
    });
  });
}
