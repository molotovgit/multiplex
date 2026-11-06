import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/app_settings.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/command_capture.dart';
import 'package:multiplex/sessions/command_timer.dart';
import 'package:multiplex/sessions/done_notifier.dart';

import 'command_history_test.dart' show FakeScreen;

void main() {
  group('command timer, reading the screen', () {
    late FakeScreen screen;
    late List<FinishedCommand> done;
    late DateTime now;
    late CommandTimer timer;
    late CommandCapture capture;

    setUp(() {
      screen = FakeScreen();
      done = [];
      now = DateTime(2026, 11, 6, 9);
      timer = CommandTimer(onFinished: done.add, clock: () => now);
      capture = CommandCapture(onCommand: (_) {}, onRun: timer.ran);
    });

    void frame() {
      capture.onFrame(screen);
      timer.onFrame(screen);
    }

    /// Types [command] after the prompt on [row] and presses Enter; the
    /// shell answers by moving to the next row.
    void run(int row, String command, {int? next}) {
      screen.show(row, r'web:~$ ');
      capture.input(screen);
      screen.show(row, 'web:~\$ $command');
      frame();
      capture.enter(screen);
      screen.moveTo(next ?? row + 1, 0);
      frame();
    }

    test('a command ends when its prompt comes back', () {
      run(0, 'make all');
      now = now.add(const Duration(seconds: 72));
      screen.show(1, 'built');
      frame();
      expect(done, isEmpty);
      screen.show(2, r'web:~$ ');
      frame();
      expect(done.single.command, 'make all');
      expect(done.single.took, const Duration(seconds: 72));
    });

    test('the prompt on the same bottom row still counts once the cursor left it', () {
      // A full screen: the prompt comes back on the very row it was on.
      run(5, 'sleep 30', next: 5);
      now = now.add(const Duration(seconds: 30));
      screen.show(5, r'web:~$ ');
      frame();
      expect(done.single.command, 'sleep 30');
    });

    test('nothing is timed inside a full-screen program', () {
      run(0, 'vim notes');
      screen.alternateScreen = true;
      screen.show(0, r'web:~$ ');
      frame();
      expect(done, isEmpty);
      screen.alternateScreen = false;
      screen.show(3, r'web:~$ ');
      frame();
      expect(done.single.command, 'vim notes');
    });

    test('shell integration marks win over the screen', () {
      timer.markStarted();
      run(0, 'cargo build');
      now = now.add(const Duration(seconds: 12));
      // The prompt is back but the shell has not said the command ended.
      screen.show(2, r'web:~$ ');
      frame();
      expect(done, isEmpty);
      timer.markFinished(101);
      expect(done.single.command, 'cargo build');
      expect(done.single.exitCode, 101);
      expect(done.single.took, const Duration(seconds: 12));
    });
  });

  group('done notifications', () {
    late VaultStore store;
    late List<(String, String)> posted;
    late bool inFront;
    late DoneNotifier notifier;

    setUp(() async {
      store = await VaultStore.open(MemoryBackend());
      posted = [];
      inFront = true;
      notifier = DoneNotifier(store, post: (t, b) async => posted.add((t, b)), appInFront: () => inFront);
    });

    const long = FinishedCommand('npm run build', Duration(minutes: 1, seconds: 12));

    test('says what finished, where and how long it took', () {
      expect(notifier.finished('web', long, terminalOnScreen: false), isTrue);
      expect(posted.single, ('Done on web', 'npm run build (1m 12s)'));
      expect(DoneNotifier.text('web', const FinishedCommand('make', Duration(seconds: 42), exitCode: 2)), ('Failed on web', 'make (42s, exit code 2)'));
      expect(DoneNotifier.took(const Duration(hours: 2, minutes: 5)), '2h 5m');
    });

    test('only for long commands the user is not watching', () {
      expect(notifier.finished('web', const FinishedCommand('ls', Duration(seconds: 9)), terminalOnScreen: false), isFalse);
      expect(notifier.finished('web', long, terminalOnScreen: true), isFalse);
      inFront = false;
      expect(notifier.finished('web', long, terminalOnScreen: true), isTrue);
      expect(posted, hasLength(1));
    });

    test('the setting turns it off and is saved', () {
      store.updateSettings(store.settings.copyWith(notifyWhenDone: false));
      expect(notifier.finished('web', long, terminalOnScreen: false), isFalse);
      expect(AppSettings.fromJson(store.settings.toJson()).notifyWhenDone, isFalse);
      expect(AppSettings.fromJson(const {}).notifyWhenDone, isTrue);
    });
  });
}
