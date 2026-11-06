import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/broadcast.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/sessions/terminal_controller.dart';
import 'package:multiplex/src/rust/api/terminal_types.dart';
import 'package:multiplex/ui/terminal/broadcast_banner.dart';

import 'support/fake_shell.dart';

void main() {
  group('broadcast', () {
    late Broadcast broadcast;
    late List<FakeShell> shells;
    late List<TerminalController> terminals;

    setUp(() {
      broadcast = Broadcast();
      shells = List.generate(4, (_) => FakeShell());
      terminals = [
        for (final (i, shell) in shells.indexed) TerminalController(shell: shell, title: 'T$i', sessionId: 's', onInput: broadcast.forward),
      ];
    });

    testWidgets('keys and pastes in one member go to every member', (tester) async {
      broadcast.start(terminals.take(3));
      expect(broadcast.size, 3);
      terminals[0].type('ls');
      terminals[0].key(TerminalKey.enter);
      terminals[1].paste('uptime');
      expect(shells[0].sent, ['ls', '<enter>', 'paste:uptime']);
      expect(shells[1].sent, ['ls', '<enter>', 'paste:uptime']);
      expect(shells[2].sent, ['ls', '<enter>', 'paste:uptime']);
      // Not picked: gets nothing, and its own typing stays its own.
      expect(shells[3].sent, isEmpty);
      terminals[3].type('x');
      expect(shells[0].sent, hasLength(3));
    });

    testWidgets('sticky Ctrl goes along', (tester) async {
      broadcast.start(terminals.take(2));
      terminals[0].toggleCtrl();
      terminals[0].type('c');
      expect(shells[1].sent, ['ctrl+c']);
    });

    testWidgets('stopping, or closing down to one terminal, ends it', (tester) async {
      broadcast.start(terminals.take(2));
      broadcast.remove(terminals[1]);
      expect(broadcast.on, isFalse);
      terminals[0].type('a');
      expect(shells[1].sent, isEmpty);
      broadcast.start(terminals.take(3));
      broadcast.stop();
      terminals[0].type('b');
      expect(shells[1].sent, isEmpty);
      broadcast.start(terminals.take(1));
      expect(broadcast.on, isFalse, reason: 'one terminal is no broadcast');
    });
  });

  testWidgets('the banner says how many terminals get the typing and stops', (tester) async {
    final store = await VaultStore.open(MemoryBackend());
    final sessions = SessionManager(store);
    var stopped = 0;
    await tester.pumpWidget(AppScope(
      vault: store,
      manager: sessions,
      child: MaterialApp(
        theme: AppTheme.build(store.activeTheme),
        home: Scaffold(body: BroadcastBanner(count: 3, onStop: () => stopped++)),
      ),
    ));
    expect(find.text('Typing to 3 terminals'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    expect(stopped, 1);
    expect(tester.getSize(find.widgetWithText(TextButton, 'Stop')).height, greaterThanOrEqualTo(44));
    await tester.pump(const Duration(seconds: 2));
    sessions.dispose();
  });
}
