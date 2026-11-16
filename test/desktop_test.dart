import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/connect_flow.dart';
import 'package:multiplex/sessions/shell_launch.dart';
import 'package:multiplex/src/rust/api/ssh_types.dart';
import 'package:multiplex/ui/desktop/desktop_gestures.dart';
import 'package:multiplex/ui/desktop/desktop_keys.dart';
import 'package:multiplex/ui/desktop/desktop_settings.dart';

import 'security/fakes.dart';

const _key = HostKeyInfo(algorithm: 'ssh-ed25519', fingerprint: 'SHA256:home', publicKey: 'ssh-ed25519 AAAAhome');
const _other = HostKeyInfo(algorithm: 'ssh-ed25519', fingerprint: 'SHA256:other', publicKey: 'ssh-ed25519 AAAAother');

void main() {
  group('home first, away route when out of reach', () {
    late VaultStore store;
    setUp(() async {
      store = await VaultStore.open(MemoryBackend());
      store.saveHost(const Host(id: 'vps', label: 'VPS', address: 'vps.example', username: 'jump', password: 'pw'));
      store.saveHost(const Host(id: 'away', label: 'Desk via VPS', address: 'localhost', port: 2222, username: 'me', password: 'pw', jumpHostId: 'vps'));
      store.saveHost(const Host(id: 'home', label: 'Desk', address: '192.168.1.20', username: 'me', password: 'pw', awayHostId: 'away'));
    });

    test('home is tried quickly, then the away route', () async {
      final connector = FakeConnector();
      final flow = ConnectFlow(store, const SilentPrompter(), unlock: FakeUnlock(), connector: connector.call);
      await expectLater(flow.connect(store.host('home')!), throwsA(isA<ConnectFailure>()));
      expect(connector.attempts.map((o) => '${o.host}:${o.port}'), ['192.168.1.20:22', 'localhost:2222']);
      expect(connector.attempts.first.connectTimeoutSecs, lessThanOrEqualTo(5), reason: 'home must not hold up the away route');
      expect(connector.attempts.last.jump?.host, 'vps.example');
    });

    test('another machine at the home address means away, without a warning', () async {
      store.trustHostKey('192.168.1.20', 22, _key);
      final connector = FakeConnector([const ConnectError.hostKeyChanged(host: '192.168.1.20', port: 22, key: _other)]);
      final prompter = FakePrompter();
      final flow = ConnectFlow(store, prompter, unlock: FakeUnlock(), connector: connector.call);
      await expectLater(flow.connect(store.host('home')!), throwsA(isA<ConnectFailure>()));
      expect(prompter.asked, isEmpty);
      expect(connector.attempts.last.port, 2222);
    });

    test('without an away route nothing changes', () async {
      final connector = FakeConnector();
      final flow = ConnectFlow(store, const SilentPrompter(), unlock: FakeUnlock(), connector: connector.call);
      await expectLater(flow.connect(store.host('away')!), throwsA(isA<ConnectFailure>()));
      expect(connector.attempts, hasLength(1));
      expect(connector.attempts.single.connectTimeoutSecs, greaterThan(5));
    });

    test('deleting the away host clears the link', () {
      store.deleteHost('away');
      expect(store.host('home')!.awayHostId, isNull);
    });

    test('the link survives a save and load', () {
      final host = store.host('home')!;
      expect(Host.fromJson(host.toJson()).awayHostId, 'away');
    });
  });

  group('typing on a US layout', () {
    test('letters, capitals, digits and symbols', () {
      expect(UsLayout.stroke('a')!.code, 30);
      expect(UsLayout.stroke('A')!.shift, isTrue);
      expect(UsLayout.stroke('1')!.code, 2);
      expect(UsLayout.stroke('!')!.code, 2);
      expect(UsLayout.stroke('!')!.shift, isTrue);
      expect(UsLayout.stroke('?')!.code, 53);
      expect(UsLayout.stroke('\n')!.code, LinuxKey.enter);
    });

    test('text it cannot type goes through the clipboard', () {
      expect(UsLayout.canType('ls -la ~/Code'), isTrue);
      expect(UsLayout.canType('Привет'), isFalse);
      expect(UsLayout.canType('café'), isFalse);
    });

    test('F-keys', () {
      expect(LinuxKey.function(1), 59);
      expect(LinuxKey.function(10), 68);
      expect(LinuxKey.function(12), 88);
    });
  });

  group('viewport', () {
    const view = Size(400, 800);
    const remote = Size(1600, 900);

    test('fits and maps both ways', () {
      final v = DesktopViewport()..layout(view, remote, zoom: 1);
      expect(v.k, closeTo(0.25, 1e-9));
      final p = v.toScreen(const Offset(800, 450));
      expect(v.toRemote(p).dx, closeTo(800, 1e-6));
      expect(p.dx, closeTo(200, 1e-6), reason: 'centred');
    });

    test('pinch keeps the point under the fingers', () {
      final v = DesktopViewport()..layout(view, remote, zoom: 1);
      const focal = Offset(200, 400);
      final before = v.toRemote(focal);
      v.zoomAround(focal, 2, view, remote);
      expect(v.zoom, closeTo(2, 1e-9));
      expect(v.toRemote(focal).dx, closeTo(before.dx, 1e-6));
    });

    test('never zooms out past the whole screen', () {
      final v = DesktopViewport()..layout(view, remote, zoom: 1);
      v.zoomAround(const Offset(10, 10), 0.2, view, remote);
      expect(v.zoom, closeTo(1, 1e-9));
    });
  });

  test('settings fall back to defaults and keep what they know', () {
    final s = DesktopSettings.fromJson({'touch': 'direct', 'screen': 'nonsense', 'textSize': 9});
    expect(s.touch, DesktopTouchMode.direct);
    expect(s.screen, DesktopScreenMode.mirror, reason: 'like gliff: the real monitor by default');
    expect(s.textSize, 2.0);
    expect(DesktopSettings.fromJson(s.toJson()).touch, DesktopTouchMode.direct);
  });
}
