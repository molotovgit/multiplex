import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/connect_flow.dart';
import 'package:multiplex/ui/hosts/host_editor_screen.dart';

import 'fakes.dart';
import 'harness.dart';

const _plain = Host(id: 'h1', label: 'Web', address: 'web', username: 'root', password: 'pw');
const _sensitive = Host(id: 'h2', label: 'Bank', address: 'bank', username: 'root', password: 'pw', askUnlock: true);

Future<(VaultStore, FakeConnector, FakeUnlock)> _setup({Object answer = true}) async {
  final store = await VaultStore.open(MemoryBackend());
  store.saveHost(_plain);
  store.saveHost(_sensitive);
  return (store, FakeConnector(), FakeUnlock(answer));
}

ConnectFlow _flow(VaultStore store, FakeConnector connector, FakeUnlock unlock) =>
    ConnectFlow(store, FakePrompter(), unlock: unlock, connector: connector.call);

void main() {
  group('ask for fingerprint before connecting', () {
    test('an ordinary host connects without asking', () async {
      final (store, connector, unlock) = await _setup();
      await expectLater(_flow(store, connector, unlock).connect(_plain), throwsA(isA<ConnectFailure>()));
      expect(unlock.reasons, isEmpty);
      expect(connector.attempts, hasLength(1));
    });

    test('a sensitive host asks first, then connects', () async {
      final (store, connector, unlock) = await _setup();
      await expectLater(_flow(store, connector, unlock).connect(_sensitive), throwsA(isA<ConnectFailure>()));
      expect(unlock.reasons, ['Confirm it is you to connect to Bank']);
      expect(connector.attempts, hasLength(1));
    });

    test('a refused or cancelled check does not connect at all', () async {
      for (final answer in <Object>[false, FakeUnlock.cancelled]) {
        final (store, connector, unlock) = await _setup(answer: answer);
        await expectLater(_flow(store, connector, unlock).connect(_sensitive), throwsA(isA<ConnectCancelled>()));
        expect(connector.attempts, isEmpty, reason: 'answer $answer');
      }
    });

    test('a phone without a screen lock or a broken prompt is refused with a reason', () async {
      for (final answer in <Object>[FakeUnlock.noLock, const LocalAuthException(code: LocalAuthExceptionCode.temporaryLockout), StateError('boom')]) {
        final (store, connector, unlock) = await _setup(answer: answer);
        await expectLater(_flow(store, connector, unlock).connect(_sensitive), throwsA(isA<ConnectFailure>()));
        expect(connector.attempts, isEmpty, reason: 'answer $answer');
      }
    });

    test('going through a sensitive jump host also asks', () async {
      final (store, connector, unlock) = await _setup(answer: false);
      final viaBank = _plain.copyWith(jumpHostId: () => _sensitive.id);
      await expectLater(_flow(store, connector, unlock).connect(viaBank), throwsA(isA<ConnectCancelled>()));
      expect(connector.attempts, isEmpty);
    });

    test('the option is saved, and old vaults read it as off', () {
      expect(Host.fromJson(_sensitive.toJson()).askUnlock, isTrue);
      final old = _plain.toJson()..remove('askUnlock');
      expect(Host.fromJson(old).askUnlock, isFalse);
    });
  });

  testWidgets('the host editor saves the option', (tester) async {
    final app = await SecurityHarness.pump(tester, const HostEditorScreen(host: _plain), fill: (s) => s.saveHost(_plain));
    final option = find.text('Ask for fingerprint before connecting');
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(app.store.host('h1')!.askUnlock, isTrue);
    await app.finish();
  });
}

