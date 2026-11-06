import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/broadcast.dart';
import 'package:multiplex/sessions/connect_flow.dart';
import 'package:multiplex/sessions/shell_launch.dart';
import 'package:multiplex/sessions/terminal_controller.dart';
import 'package:multiplex/src/rust/api/ssh_types.dart';
import 'package:multiplex/ui/terminal/split_controller.dart';

import 'security/fakes.dart';
import 'support/fake_shell.dart';

void main() {
  group('a reconnect and the security rules', () {
    late VaultStore store;
    setUp(() async {
      store = await VaultStore.open(MemoryBackend());
      store.saveHost(const Host(id: 'h', label: 'Bank', address: 'bank', username: 'me', password: 'pw', askUnlock: true));
    });

    test('an approved session reconnects without asking for the fingerprint again', () async {
      final unlock = FakeUnlock();
      final connector = FakeConnector();
      final flow = ConnectFlow(store, const SilentPrompter(), unlock: unlock, connector: connector.call, ownerConfirmed: true);
      await expectLater(flow.connect(store.host('h')!), throwsA(isA<ConnectFailure>()));
      expect(unlock.reasons, isEmpty);
      expect(connector.attempts, hasLength(1));
    });

    test('a new connection to the host still asks', () async {
      final unlock = FakeUnlock();
      final flow = ConnectFlow(store, const SilentPrompter(), unlock: unlock, connector: FakeConnector().call);
      await expectLater(flow.connect(store.host('h')!), throwsA(isA<ConnectFailure>()));
      expect(unlock.reasons, hasLength(1));
    });

    test('a one-time code stops the reconnect instead of asking', () async {
      final connector = FakeConnector([const ConnectError.codeNeeded(host: 'bank', prompt: 'Code: ')]);
      final flow = ConnectFlow(store, const SilentPrompter(), unlock: FakeUnlock(), connector: connector.call, ownerConfirmed: true);
      await expectLater(flow.connect(store.host('h')!), throwsA(isA<ConnectCancelled>()));
      expect(connector.attempts, hasLength(1));
    });
  });

  group('split panes', () {
    late List<FakeShell> shells;
    late List<TerminalController> terminals;
    late Broadcast broadcast;
    late SplitController split;

    setUp(() {
      broadcast = Broadcast();
      shells = List.generate(2, (_) => FakeShell());
      terminals = [for (final s in shells) TerminalController(shell: s, title: 't', sessionId: 's', onInput: broadcast.forward)];
      split = SplitController(primary: terminals[0], primaryFocus: FocusNode());
    });

    testWidgets('the second pane counts as on screen while it is shown', (tester) async {
      split.open(terminals[1]);
      expect(terminals[1].onScreen, isTrue);
      expect(split.visible(shown: true), terminals);
      expect(split.visible(shown: false), [terminals[0]]);
      var told = 0;
      split.addListener(() => told++);
      // Its reconnect or recording state reaches the screen.
      terminals[1].showReconnecting('Reconnecting…');
      expect(told, 1);
      split.close();
      expect(terminals[1].onScreen, isFalse);
      terminals[1].reconnected();
      expect(told, 2, reason: 'only the close; no longer listening');
    });

    testWidgets('typing in either pane reaches the broadcast group', (tester) async {
      split.open(terminals[1]);
      broadcast.start(terminals);
      split.typing(shown: true).type('a');
      split.focus(second: false);
      split.typing(shown: true).type('b');
      expect(shells[0].sent, ['a', 'b']);
      expect(shells[1].sent, ['a', 'b']);
    });
  });
}
