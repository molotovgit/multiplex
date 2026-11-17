import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/platform/phone_bridge.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/ui/computers/computer_card.dart';
import 'package:multiplex/ui/computers/computer_screen.dart';
import 'package:multiplex/ui/computers/computer_sharing_screen.dart';
import 'package:multiplex/ui/hosts/host_arrangement.dart';
import 'package:multiplex/ui/hosts/hosts_screen.dart';
import 'package:multiplex/ui/pair/pair_screen.dart';

const _desk = Host(id: 'c', label: 'Desk', address: '192.168.0.10', username: 'me', computer: true, tailscaleName: 'desk');
const _server = Host(id: 's', label: 'Web server', address: 'web.example.com', username: 'me');

void main() {
  late VaultStore store;
  setUp(() async => store = await VaultStore.open(MemoryBackend()));

  Future<void> home(WidgetTester tester) async {
    final sessions = SessionManager(store);
    addTearDown(sessions.dispose);
    await tester.pumpWidget(
      AppScope(
        vault: store,
        manager: sessions,
        child: const MaterialApp(home: HostsScreen()),
      ),
    );
    // Let the store's delayed save run, so no timer outlives the test.
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('first run is one screen: pair your computer', (tester) async {
    await home(tester);
    expect(find.text('Pair your computer'), findsOneWidget);
    expect(find.text('Add an SSH server instead'), findsOneWidget);
    await tester.tap(find.text('Pair a computer'));
    await tester.pumpAndSettle();
    expect(find.byType(PairScreen), findsOneWidget);
  });

  testWidgets('computers come first, as cards; servers stay a list below', (tester) async {
    store
      ..saveHost(_server)
      ..saveHost(_desk);
    await home(tester);
    expect(find.text('Computers'), findsOneWidget);
    expect(find.text('Servers'), findsOneWidget);
    expect(find.byType(ComputerCard), findsOneWidget);
    expect(tester.getTopLeft(find.byType(ComputerCard)).dy, lessThan(tester.getTopLeft(find.text('Web server')).dy));
    // The card carries the three things done most, each one tap from Home.
    final card = find.byType(ComputerCard);
    expect(find.descendant(of: card, matching: find.text('Desktop')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.byTooltip('Terminal')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.byTooltip('Files')), findsOneWidget);
    // A computer is not also a row in the server list.
    expect(HostArrangement.of(store).entries.whereType<HostEntry>().map((e) => e.host.id), ['s']);
  });

  testWidgets('a computer card opens its page: every feature as a tile', (tester) async {
    store.saveHost(_desk);
    await home(tester);
    await tester.tap(find.text('Desk'));
    await tester.pumpAndSettle();
    expect(find.byType(ComputerScreen), findsOneWidget);
    for (final tile in [
      'Desktop',
      'Panel',
      'Touchpad',
      'Terminal',
      'Files',
      'Extend screen',
      'Phone screen',
      'Camera',
      'Microphone',
      'Speaker',
      'Scan text',
      'Agents',
      'Tunnels',
      'Status',
    ]) {
      // There are more tiles than fit on one screen: the page scrolls.
      await tester.scrollUntilVisible(
        find.text(tile),
        120,
        scrollable: find.descendant(of: find.byType(ComputerScreen), matching: find.byType(Scrollable)).first,
      );
      expect(find.text(tile), findsOneWidget, reason: tile);
    }
  });

  testWidgets('a computer whose network card is known can be woken', (tester) async {
    // Tall enough that the grid builds its last tile.
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    store.saveHost(_desk.copyWith(mac: () => 'aa:bb:cc:dd:ee:ff'));
    final sessions = SessionManager(store);
    addTearDown(sessions.dispose);
    final sent = <String>[];
    await tester.pumpWidget(
      AppScope(
        vault: store,
        manager: sessions,
        child: MaterialApp(
          home: Scaffold(
            body: ComputerScreen(hostId: 'c', wake: (mac, home) async => sent.add('$mac $home')),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('Wake'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wake'));
    await tester.pumpAndSettle();
    expect(sent, ['aa:bb:cc:dd:ee:ff 192.168.0.10']);
    expect(find.textContaining('Wake signal sent to Desk'), findsOneWidget);
  });

  testWidgets('without a network card address there is no Wake tile', (tester) async {
    store.saveHost(_desk);
    await home(tester);
    await tester.tap(find.text('Desk'));
    await tester.pumpAndSettle();
    expect(find.text('Panel'), findsOneWidget);
    expect(find.text('Wake'), findsNothing);
  });

  testWidgets('sharing: the clipboard and notification switches are saved; access is asked for', (tester) async {
    // Tall enough for every switch: this screen keeps growing.
    await tester.binding.setSurfaceSize(const Size(500, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    store.saveHost(_desk);
    final sessions = SessionManager(store);
    addTearDown(sessions.dispose);
    final phone = _NoAccessPhone();
    await tester.pumpWidget(
      AppScope(
        vault: store,
        manager: sessions,
        child: MaterialApp(
          home: ComputerSharingScreen(hostId: 'c', phone: phone),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(store.host('c')!.shareClipboard, isTrue);
    await tester.tap(find.text('Share the clipboard'));
    await tester.pump();
    expect(store.host('c')!.shareClipboard, isFalse);

    expect(find.text('Open Notification access'), findsNothing);
    await tester.tap(find.textContaining("Show this phone's notifications"));
    await tester.pumpAndSettle();
    expect(store.host('c')!.mirrorNotifications, isTrue);
    await tester.ensureVisible(find.text('Open Notification access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Notification access'));
    expect(phone.opened, 1);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('removing a computer takes it off Home', (tester) async {
    store.saveHost(_desk);
    await home(tester);
    await tester.tap(find.text('Desk'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More for Desk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove this computer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(store.hosts, isEmpty);
    expect(find.text('Pair your computer'), findsOneWidget);
  });
}

/// A phone where Android has not given notification access yet.
class _NoAccessPhone extends PhoneBridge {
  _NoAccessPhone();

  int opened = 0;

  @override
  Future<bool> notificationAccess() async => false;

  @override
  Future<void> openNotificationAccess() async => opened++;
}
