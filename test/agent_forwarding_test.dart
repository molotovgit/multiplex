import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/ui/hosts/host_editor_screen.dart';

void main() {
  test('the choice is saved and old hosts default to off', () {
    const host = Host(id: 'h', label: 'Git', address: 'git', authMode: AuthMode.key, keyId: 'k', forwardAgent: true);
    expect(Host.fromJson(host.toJson()).forwardAgent, isTrue);
    expect(Host.fromJson(const {'id': 'h', 'address': 'git'}).forwardAgent, isFalse);
  });

  Future<(VaultStore, SessionManager)> pump(WidgetTester tester, Host host) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final store = await VaultStore.open(MemoryBackend());
    store.saveKey(StoredKey(
      id: 'k',
      name: 'Phone key',
      privatePem: 'not used here',
      publicOpenssh: 'ssh-ed25519 AAAA',
      fingerprint: 'SHA256:x',
      algorithm: 'ssh-ed25519',
      createdAt: DateTime(2026),
    ));
    store.saveHost(host);
    final sessions = SessionManager(store);
    await tester.pumpWidget(AppScope(
      vault: store,
      manager: sessions,
      child: MaterialApp(theme: AppTheme.build(store.activeTheme), home: HostEditorScreen(host: host)),
    ));
    await tester.pump();
    final tile = find.widgetWithText(SwitchListTile, 'Forward my key (agent forwarding)');
    await tester.scrollUntilVisible(tile, 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(tile);
    await tester.pump();
    return (store, sessions);
  }

  testWidgets('a key host can forward its key, with a warning', (tester) async {
    const host = Host(id: 'h1', label: 'Git', address: 'git.example.com', username: 'git', authMode: AuthMode.key, keyId: 'k');
    final (store, sessions) = await pump(tester, host);
    expect(find.textContaining("the server's admin could use it too"), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Forward my key (agent forwarding)'));
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    expect(store.host('h1')!.forwardAgent, isTrue);
    await tester.pump(const Duration(seconds: 2));
    sessions.dispose();
  });

  testWidgets('a password host has no key to forward', (tester) async {
    const host = Host(id: 'h2', label: 'Web', address: 'web.example.com', username: 'root');
    final (_, sessions) = await pump(tester, host);
    final tile = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Forward my key (agent forwarding)'));
    expect(tile.onChanged, isNull);
    expect(find.text('Needs a key login: choose a key under Login first.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    sessions.dispose();
  });
}
