import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';

/// A phone-sized app with a fresh vault, for the security tests.
class SecurityHarness {
  SecurityHarness(this.store, this.sessions);

  final VaultStore store;
  final SessionManager sessions;

  static Future<SecurityHarness> pump(WidgetTester tester, Widget home, {void Function(VaultStore)? fill}) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await VaultStore.open(MemoryBackend());
    fill?.call(store);
    final sessions = SessionManager(store);
    await tester.pumpWidget(AppScope(
      vault: store,
      manager: sessions,
      child: MaterialApp(theme: AppTheme.build(BuiltInThemes.matteBlack), home: home),
    ));
    await tester.pumpAndSettle();
    return SecurityHarness(store, sessions);
  }

  /// Writes pending saves and stops the session ticker, so no timers are
  /// left when the test ends.
  Future<void> finish() async {
    await store.flush();
    sessions.dispose();
  }
}

/// A button that opens something and keeps what it returned.
class Opener<T> extends StatelessWidget {
  const Opener(this.open, this.results, {super.key});

  final Future<T> Function(BuildContext context) open;
  final List<T> results;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(child: TextButton(onPressed: () async => results.add(await open(context)), child: const Text('open'))),
      );
}
