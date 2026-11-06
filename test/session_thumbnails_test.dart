import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/sessions/terminal_controller.dart';
import 'package:multiplex/src/rust/api/ssh_types.dart';
import 'package:multiplex/ui/sessions/sessions_screen.dart';
import 'package:multiplex/ui/sessions/terminal_thumbnail.dart';
import 'package:multiplex/ui/terminal/terminal_screen.dart';

import 'split_terminal_features_test.dart' show TestSessions, TextShell, UpSsh;

/// A connected session that can describe itself, as the Sessions card asks.
class _InfoSsh extends UpSsh {
  @override
  SessionInfo info() => const SessionInfo(
        host: 'web',
        port: 22,
        username: 'root',
        hostKey: HostKeyInfo(algorithm: 'ssh-ed25519', fingerprint: 'SHA256:test', publicKey: 'ssh-ed25519 AAAA test'),
      );
}

void main() {
  testWidgets('each open terminal shows a live preview that opens it', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await VaultStore.open(MemoryBackend());
    final sessions = TestSessions(store);
    final session = LiveSession(id: 's', host: const Host(id: 'h', label: 'Web', address: 'web'), ssh: _InfoSsh());
    final first = TerminalController(shell: TextShell('hello from one'), title: 'one', sessionId: 's');
    final second = TerminalController(shell: TextShell('hello from two'), title: 'two', sessionId: 's', number: 2);
    session.terminals.addAll([first, second]);
    sessions.added.add(session);
    await tester.pumpWidget(AppScope(
      vault: store,
      manager: sessions,
      child: MaterialApp(theme: AppTheme.build(BuiltInThemes.matteBlack), home: const SessionsScreen()),
    ));
    await tester.pump();

    expect(find.byType(TerminalThumbnail), findsNWidgets(2));
    final preview = tester.widget<TerminalThumbnail>(find.byType(TerminalThumbnail).first);
    expect(preview.controller, same(first));
    // The preview draws the terminal itself, with the real painter.
    expect(find.descendant(of: find.byType(TerminalThumbnail).first, matching: find.byType(CustomPaint)), findsWidgets);

    await tester.tap(find.text('two'));
    await tester.pumpAndSettle();
    expect(find.byType(TerminalScreen), findsOneWidget);
    expect(tester.widget<TerminalScreen>(find.byType(TerminalScreen)).controller, same(second));
    await tester.pumpWidget(const SizedBox());
    sessions.dispose();
    await tester.pump(const Duration(seconds: 5));
  });
}
