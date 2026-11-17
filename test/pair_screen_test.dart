import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/pairing_flow.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/pairing.dart';
import 'package:multiplex/ui/pair/pair_screen.dart';

/// Pairing without a computer: a code is good when it says so.
class _Flow extends PairingFlow {
  _Flow(super.store, {this.scanned});

  final String? scanned;
  int pairs = 0;

  @override
  Future<String?> scan() async => scanned;

  @override
  PairingInfo read(String code) {
    if (!code.startsWith('MPX1.')) throw Exception('This is not a Multiplex pairing code');
    return const PairingInfo(name: 'desk', user: 'me', port: 22, addresses: ['192.168.1.20'], tailscale: 'desk', hostKey: 'ssh-ed25519 AAAA', secondsLeft: 200);
  }

  @override
  Future<Host> pair(String code) async {
    pairs++;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (code.contains('used')) throw Exception('The computer no longer accepts this code (it was used, or it expired). Show a new one with `multiplex pair`.');
    return const Host(id: 'c', label: 'desk', address: '192.168.1.20', computer: true, tailscaleName: 'desk');
  }
}

void main() {
  late VaultStore store;
  setUp(() async => store = await VaultStore.open(MemoryBackend()));

  Future<_Flow> open(WidgetTester tester, {String? scanned}) async {
    final flow = _Flow(store, scanned: scanned);
    final sessions = SessionManager(store);
    addTearDown(sessions.dispose);
    await tester.pumpWidget(AppScope(vault: store, manager: sessions, child: MaterialApp(home: PairScreen(flow: flow))));
    return flow;
  }

  testWidgets('scanning a code pairs and says so', (tester) async {
    final flow = await open(tester, scanned: 'MPX1.good');
    await tester.tap(find.text('Scan the code'));
    await tester.pump();
    expect(find.text('Pairing with desk…'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Paired with desk'), findsOneWidget);
    expect(find.textContaining('on your home network and from anywhere over Tailscale'), findsOneWidget);
    expect(find.text('Open the desktop'), findsOneWidget);
    expect(flow.pairs, 1);
  });

  testWidgets('closing the scanner changes nothing', (tester) async {
    final flow = await open(tester);
    await tester.tap(find.text('Scan the code'));
    await tester.pumpAndSettle();
    expect(find.text('Scan the code'), findsOneWidget);
    expect(flow.pairs, 0);
  });

  testWidgets('a pasted code that is not one is explained, and nothing is tried', (tester) async {
    final flow = await open(tester);
    await tester.enterText(find.byType(TextField), 'https://example.com');
    await tester.pump();
    await tester.ensureVisible(find.text('Pair with this code'));
    await tester.tap(find.text('Pair with this code'));
    await tester.pumpAndSettle();
    expect(find.text('This is not a Multiplex pairing code'), findsOneWidget);
    expect(flow.pairs, 0);
  });

  testWidgets('a used code brings back the scanner with the reason', (tester) async {
    await open(tester, scanned: 'MPX1.used');
    await tester.tap(find.text('Scan the code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no longer accepts this code'), findsOneWidget);
    expect(find.text('Scan the code'), findsOneWidget);
  });
}
