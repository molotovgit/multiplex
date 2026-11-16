import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/connect_flow.dart';
import 'package:multiplex/sessions/shell_launch.dart';

import 'security/fakes.dart';

void main() {
  late VaultStore store;
  setUp(() async {
    store = await VaultStore.open(MemoryBackend());
    store.saveHost(const Host(id: 'j', label: 'Jump', address: 'jump.example', username: 'u', password: 'pw'));
    store.saveHost(const Host(id: 't', label: 'Desk', address: 'omarchy', username: 'me', password: 'pw', viaTailscale: true, jumpHostId: 'j'));
  });

  test('a Tailscale host waits for Tailscale, then connects through it without a jump host', () async {
    var asked = 0;
    final connector = FakeConnector();
    final flow = ConnectFlow(store, const SilentPrompter(), unlock: FakeUnlock(), connector: connector.call, tailscaleReady: () async => asked++);
    await expectLater(flow.connect(store.host('t')!), throwsA(isA<ConnectFailure>()));
    expect(asked, 1);
    expect(connector.attempts.single.viaTailscale, isTrue);
    expect(connector.attempts.single.host, 'omarchy');
    expect(connector.attempts.single.jump, isNull);
  });

  test('when Tailscale is not signed in, the user is told what to do and nothing connects', () async {
    final connector = FakeConnector();
    final flow = ConnectFlow(
      store,
      const SilentPrompter(),
      unlock: FakeUnlock(),
      connector: connector.call,
      tailscaleReady: () async => throw const ConnectFailure('Sign in to Tailscale first', 'Settings, Tailscale'),
    );
    await expectLater(flow.connect(store.host('t')!), throwsA(isA<ConnectFailure>().having((f) => f.title, 'title', contains('Tailscale'))));
    expect(connector.attempts, isEmpty);
  });

  test('other hosts never touch Tailscale', () async {
    final connector = FakeConnector();
    final flow = ConnectFlow(store, const SilentPrompter(), unlock: FakeUnlock(), connector: connector.call, tailscaleReady: () async => fail('not a Tailscale host'));
    await expectLater(flow.connect(store.host('j')!), throwsA(isA<ConnectFailure>()));
    expect(connector.attempts.single.viaTailscale, isFalse);
  });

  test('the setting survives a save and load', () {
    expect(Host.fromJson(store.host('t')!.toJson()).viaTailscale, isTrue);
    expect(Host.fromJson(const Host(id: 'x', label: '', address: 'a').toJson()).viaTailscale, isFalse);
  });
}
