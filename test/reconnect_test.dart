import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/reconnector.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/sessions/shell_launch.dart';
import 'package:multiplex/src/rust/api/ssh_types.dart';
import 'package:multiplex/ui/hosts/host_editor_screen.dart';
import 'package:multiplex/ui/terminal/reconnect_banner.dart';

/// Timers that only fire when the test says so.
class FakeTimers {
  final waits = <Duration>[];
  final _pending = <void Function()>[];
  DateTime now = DateTime(2026, 11, 6, 12);

  Timer start(Duration delay, void Function() callback) {
    waits.add(delay);
    _pending.add(callback);
    return _FakeTimer(() => _pending.remove(callback));
  }

  /// Moves the clock past the last wait and runs what was waiting.
  Future<void> fire() async {
    now = now.add(waits.last);
    final due = List.of(_pending);
    _pending.clear();
    for (final callback in due) {
      callback();
    }
    await Future<void>.delayed(Duration.zero);
  }

  bool get waiting => _pending.isNotEmpty;
}

class _FakeTimer implements Timer {
  _FakeTimer(this._cancel);

  final void Function() _cancel;
  bool _active = true;

  @override
  void cancel() {
    _active = false;
    _cancel();
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

void main() {
  group('reconnector', () {
    late FakeTimers timers;
    late List<ReconnectResult> results;
    late List<bool> done;
    late int tries;

    Reconnector make() => Reconnector(
          tryOnce: () async {
            tries++;
            return results.isEmpty ? ReconnectResult.retry : results.removeAt(0);
          },
          onStatus: (_) {},
          onDone: done.add,
          timer: timers.start,
          clock: () => timers.now,
        );

    setUp(() {
      timers = FakeTimers();
      results = [];
      done = [];
      tries = 0;
    });

    test('waits longer after each failure, up to 30 seconds', () async {
      final r = make()..start();
      for (var i = 0; i < 8; i++) {
        await timers.fire();
      }
      expect(timers.waits.map((d) => d.inSeconds).toList(), [1, 2, 4, 8, 15, 30, 30, 30, 30]);
      expect(tries, 8);
      expect(r.finished, isFalse);
    });

    test('stops once the connection is back', () async {
      results = [ReconnectResult.retry, ReconnectResult.connected];
      make().start();
      await timers.fire();
      await timers.fire();
      expect(done, [true]);
      expect(timers.waiting, isFalse);
    });

    test('never asks again once logging in would need the user', () async {
      results = [ReconnectResult.giveUp];
      make().start();
      await timers.fire();
      expect(done, [false]);
      expect(tries, 1);
      expect(timers.waiting, isFalse);
    });

    test('gives up after about five minutes', () async {
      final r = make()..start();
      while (!r.finished) {
        await timers.fire();
      }
      expect(done, [false]);
      final waited = timers.waits.fold(Duration.zero, (a, b) => a + b);
      expect(waited, greaterThanOrEqualTo(Reconnector.giveUpAfter));
      expect(waited, lessThan(Reconnector.giveUpAfter + const Duration(seconds: 31)));
    });

    test('tries at once when the network is back', () async {
      results = [ReconnectResult.connected];
      final r = make()..start();
      r.retryNow();
      await Future<void>.delayed(Duration.zero);
      expect(tries, 1);
      expect(done, [true]);
    });

    test('a cancelled reconnect never reports', () async {
      final r = make()..start();
      r.cancel();
      expect(timers.waiting, isFalse);
      r.retryNow();
      expect(tries, 0);
      expect(done, isEmpty);
    });
  });

  group('shell launch', () {
    const plain = Host(id: 'h', label: 'Box', address: 'box', startupCommand: 'cd /srv');
    final tmux = plain.copyWith(keepWithTmux: true);

    test('tmux takes over the startup command', () {
      expect(ShellLaunch.command(plain, 1), isNull);
      expect(ShellLaunch.startupCommand(plain), 'cd /srv');
      expect(ShellLaunch.startupCommand(tmux), isNull);
      final command = ShellLaunch.command(tmux, 3)!;
      expect(command, contains('tmux new -A -s multiplex-3'));
      // Falls back to a plain login shell with a note when tmux is missing.
      expect(command, contains('tmux is not installed'));
      expect(command, contains(r'exec "${SHELL:-/bin/sh}" -l'));
    });

    test('the tmux choice is saved and old hosts default to off', () {
      expect(Host.fromJson(tmux.toJson()).keepWithTmux, isTrue);
      expect(Host.fromJson(const {'id': 'h', 'address': 'box'}).keepWithTmux, isFalse);
    });

    test('a reconnect never asks anything', () async {
      const silent = SilentPrompter();
      const key = HostKeyInfo(algorithm: 'ssh-ed25519', fingerprint: 'SHA256:x', publicKey: 'ssh-ed25519 AAAA');
      expect(await silent.trustNewHost('box', 22, key), isFalse);
      expect(await silent.acceptChangedHost('box', 22, key, null), isFalse);
      expect(await silent.askPassword('box', 'root', wasWrong: false), isNull);
    });
  });

  group('screens', () {
    Future<(VaultStore, SessionManager)> pump(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final store = await VaultStore.open(MemoryBackend());
      final sessions = SessionManager(store);
      await tester.pumpWidget(AppScope(
        vault: store,
        manager: sessions,
        child: MaterialApp(theme: AppTheme.build(store.activeTheme), home: home),
      ));
      await tester.pump();
      return (store, sessions);
    }

    testWidgets('the host editor saves "Keep session with tmux"', (tester) async {
      const host = Host(id: 'h1', label: 'Box', address: 'box.example.com', username: 'root');
      final (store, sessions) = await pump(tester, const HostEditorScreen(host: host));
      store.saveHost(host);
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('Keep session with tmux'), 300, scrollable: list);
      expect(find.text('Startup command (optional)'), findsOneWidget);
      final tile = find.widgetWithText(SwitchListTile, 'Keep session with tmux');
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(tile);
      await tester.pump();
      // tmux keeps its own screen, so the startup command goes away.
      expect(find.text('Startup command (optional)'), findsNothing);
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      expect(store.host('h1')!.keepWithTmux, isTrue);
      await tester.pump(const Duration(seconds: 2));
      sessions.dispose();
    });

    testWidgets('the reconnect banner offers try now and stop', (tester) async {
      var tried = 0, stopped = 0;
      final (_, sessions) = await pump(
        tester,
        Scaffold(body: ReconnectBanner(note: 'Reconnecting… next try in 4 s', onTryNow: () => tried++, onStop: () => stopped++)),
      );
      expect(find.text('Reconnecting… next try in 4 s'), findsOneWidget);
      await tester.tap(find.text('Try now'));
      await tester.tap(find.text('Stop'));
      expect((tried, stopped), (1, 1));
      expect(tester.getSize(find.widgetWithText(TextButton, 'Stop')).height, greaterThanOrEqualTo(44));
      sessions.dispose();
    });
  });
}
