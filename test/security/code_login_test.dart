import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/otp_account.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/connect_flow.dart';
import 'package:multiplex/src/rust/api/ssh_types.dart';

import 'fakes.dart';

const _bastion = Host(id: 'h1', label: 'Bastion', address: 'bastion', username: 'alice', password: 'pw');
const _inner = Host(id: 'h2', label: 'Inner', address: 'inner', username: 'alice', password: 'pw', jumpHostId: 'h1');
final _linked = OtpAccount(id: 'o1', issuer: 'Bastion', secret: 'JBSWY3DPEHPK3PXP', hostId: 'h1', createdAt: DateTime(2026));

ConnectError _code(String host) => ConnectError.codeNeeded(host: host, prompt: 'Verification code:');
ConnectError _refused(String host) => ConnectError.authFailed(host: host, tried: const ['keyboard-interactive'], serverAccepts: const []);

Future<(ConnectFlow, FakePrompter, FakeConnector)> _flow(List<ConnectError> errors) async {
  final store = await VaultStore.open(MemoryBackend());
  store.saveHost(_bastion);
  store.saveHost(_inner);
  store.saveOtp(_linked);
  final prompter = FakePrompter();
  final connector = FakeConnector(errors);
  return (ConnectFlow(store, prompter, unlock: FakeUnlock(), connector: connector.call), prompter, connector);
}

void main() {
  test('a code question offers the linked accounts and sends the answer once', () async {
    final (flow, prompter, connector) = await _flow([_code('bastion')]);
    prompter.codes.add(' 123456 ');
    await expectLater(flow.connect(_bastion), throwsA(isA<ConnectFailure>()));
    expect(prompter.asked, ['code bastion "Verification code:"']);
    expect(prompter.offered.single.single.id, 'o1');
    expect(connector.attempts.first.credentials.oneTimeCode, isNull);
    expect(connector.attempts.last.credentials.oneTimeCode, '123456');
  });

  test('cancelling the code question does not connect', () async {
    final (flow, prompter, connector) = await _flow([_code('bastion')]);
    await expectLater(flow.connect(_bastion), throwsA(isA<ConnectCancelled>()));
    expect(connector.attempts, hasLength(1));
  });

  test('a refused code asks for a new code first, then also the password', () async {
    final (flow, prompter, connector) = await _flow([_code('bastion'), _refused('bastion'), _code('bastion'), _refused('bastion'), _code('bastion')]);
    prompter.codes.addAll(['111111', '222222', '333333']);
    await expectLater(flow.connect(_bastion), throwsA(isA<ConnectFailure>()));
    expect(prompter.asked, [
      'code bastion "Verification code:"',
      'code bastion "Verification code:" wrong',
      'password bastion wrong',
      'code bastion "Verification code:" wrong',
    ]);
    expect(connector.attempts.map((o) => o.credentials.oneTimeCode), [null, '111111', null, '222222', null, '333333']);
  });

  test('a code for the jump host goes to the jump host, with its own linked accounts', () async {
    final (flow, prompter, connector) = await _flow([_code('bastion'), _code('inner')]);
    prompter.codes.addAll(['111111', '222222']);
    await expectLater(flow.connect(_inner), throwsA(isA<ConnectFailure>()));
    expect(prompter.offered.first.single.id, 'o1');
    expect(prompter.offered.last, isEmpty);
    final last = connector.attempts.last;
    expect(last.jump!.credentials.oneTimeCode, '111111');
    expect(last.credentials.oneTimeCode, '222222');
  });
}
