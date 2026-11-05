import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/lock_gate.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';

/// Answers the unlock prompt the way a test says.
class _FakeUnlock extends DeviceUnlock {
  _FakeUnlock(this.answers, {this.anyLock = true});

  /// One per prompt: true, false, or an exception to throw.
  final List<Object> answers;
  final bool anyLock;
  int asked = 0;

  @override
  Future<bool> confirm() async {
    final answer = answers[asked++ % answers.length];
    if (answer is bool) return answer;
    throw answer;
  }

  @override
  Future<bool> hasAnyLock() async => anyLock;
}

Future<SessionManager> _pump(WidgetTester tester, _FakeUnlock unlock) async {
  final store = await VaultStore.open(MemoryBackend());
  store.updateSettings(store.settings.copyWith(appLock: true));
  final sessions = SessionManager(store);
  await tester.pumpWidget(AppScope(
    vault: store,
    manager: sessions,
    child: MaterialApp(
      theme: AppTheme.build(store.activeTheme),
      home: LockGate(unlock: unlock, child: const Text('the app')),
    ),
  ));
  await tester.pumpAndSettle();
  return sessions;
}

Future<void> _finish(WidgetTester tester, SessionManager sessions) async {
  await tester.pump(const Duration(seconds: 2));
  sessions.dispose();
}

void main() {
  testWidgets('a confirmed fingerprint opens the app', (tester) async {
    final sessions = await _pump(tester, _FakeUnlock([true]));
    expect(find.text('the app'), findsOneWidget);
    await _finish(tester, sessions);
  });

  testWidgets('cancelling the prompt (Back) keeps the app locked', (tester) async {
    final unlock = _FakeUnlock([const LocalAuthException(code: LocalAuthExceptionCode.userCanceled)]);
    final sessions = await _pump(tester, unlock);
    expect(find.text('the app'), findsNothing);
    expect(find.text('Multiplex is locked'), findsOneWidget);
    expect(find.text('Unlock was cancelled.'), findsOneWidget);
    await _finish(tester, sessions);
  });

  testWidgets('a failed check, a timeout or a lockout keep it locked; Unlock asks again', (tester) async {
    final unlock = _FakeUnlock([
      false,
      const LocalAuthException(code: LocalAuthExceptionCode.timeout),
      const LocalAuthException(code: LocalAuthExceptionCode.temporaryLockout),
      true,
    ]);
    final sessions = await _pump(tester, unlock);
    for (var i = 0; i < 2; i++) {
      expect(find.text('the app'), findsNothing);
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
    }
    expect(find.text('the app'), findsNothing);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('the app'), findsOneWidget);
    expect(unlock.asked, 4);
    await _finish(tester, sessions);
  });

  testWidgets('a phone with no lock at all is let in rather than shut out', (tester) async {
    final sessions = await _pump(tester, _FakeUnlock([const LocalAuthException(code: LocalAuthExceptionCode.noCredentialsSet)]));
    expect(find.text('the app'), findsOneWidget);
    await _finish(tester, sessions);
  });

  testWidgets('an unexpected error opens only when the phone has no lock', (tester) async {
    final locked = await _pump(tester, _FakeUnlock([StateError('boom')]));
    expect(find.text('the app'), findsNothing);
    await _finish(tester, locked);
  });

  testWidgets('an unexpected error on a phone with no lock opens the app', (tester) async {
    final sessions = await _pump(tester, _FakeUnlock([StateError('boom')], anyLock: false));
    expect(find.text('the app'), findsOneWidget);
    await _finish(tester, sessions);
  });
}
