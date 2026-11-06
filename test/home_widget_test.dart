import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/platform/home_widget_sync.dart';
import 'package:multiplex/platform/incoming_actions.dart';
import 'package:multiplex/platform/incoming_actions_handler.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/ui/hosts/host_editor_screen.dart';
import 'package:multiplex/ui/hosts/host_tile.dart';

Host host(String id, {bool favourite = false, String? password}) =>
    Host(id: id, label: 'Host $id', address: '$id.example.org', username: 'root', password: password, favourite: favourite);

/// An incoming channel the test fills by hand.
class FakeIncoming implements IncomingChannel {
  final waiting = <IncomingAction>[];
  void Function()? _onChanged;

  void push(IncomingAction action) {
    waiting.add(action);
    _onChanged?.call();
  }

  @override
  void listen(void Function() onChanged) => _onChanged = onChanged;

  @override
  void stop() => _onChanged = null;

  @override
  Future<List<IncomingAction>> take() async {
    final all = List.of(waiting);
    waiting.clear();
    return all;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('favourites', () {
    test('the flag survives a save and load; old hosts are not favourites', () {
      expect(Host.fromJson(host('a', favourite: true).toJson()).favourite, isTrue);
      expect(Host.fromJson(const {'id': 'a', 'address': 'x'}).favourite, isFalse);
    });

    test('the widget gets the first four favourites, id and name only', () {
      final hosts = [for (var i = 0; i < 6; i++) host('$i', favourite: i != 1, password: 'secret$i')];
      final list = jsonDecode(HomeWidgetSync.payload(hosts)) as List;
      expect(list, [
        {'id': '0', 'label': 'Host 0'},
        {'id': '2', 'label': 'Host 2'},
        {'id': '3', 'label': 'Host 3'},
        {'id': '4', 'label': 'Host 4'},
      ]);
      final text = HomeWidgetSync.payload(hosts);
      expect(text, isNot(contains('secret')));
      expect(text, isNot(contains('example.org')));
    });

    test('sends the list to Android only when it changes', () async {
      final sent = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('multiplex/widget'), (call) async {
        sent.add((call.arguments as Map)['json'] as String);
        return null;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('multiplex/widget'), null),
      );
      final store = await VaultStore.open(MemoryBackend());
      final sync = HomeWidgetSync(store);
      await Future<void>.delayed(Duration.zero);
      expect(sent, ['[]']);
      store.saveHost(host('a'));
      await Future<void>.delayed(Duration.zero);
      expect(sent, ['[]'], reason: 'not a favourite: nothing changed for the widget');
      store.saveHost(host('a', favourite: true));
      await Future<void>.delayed(Duration.zero);
      expect(sent.last, '[{"id":"a","label":"Host a"}]');
      sync.dispose();
      await store.flush();
    });
  });

  group('incoming', () {
    test('reads what Android sends, ignores the rest', () {
      expect(IncomingAction.parse({'type': 'connect', 'hostId': 'h1'}), isA<ConnectAction>().having((a) => a.hostId, 'hostId', 'h1'));
      expect(IncomingAction.parse({'type': 'connect', 'hostId': ''}), isNull);
      expect(IncomingAction.parse({'type': 'launch-missiles'}), isNull);
      expect(IncomingAction.parse('connect'), isNull);
      final share = IncomingAction.parse({
        'type': 'share',
        'files': [
          {'name': 'a.png', 'path': '/cache/a.png'},
          {'name': 1},
        ],
      });
      expect(share, isA<ShareAction>().having((a) => a.files.single.name, 'name', 'a.png'));
      expect(IncomingAction.parse({'type': 'share', 'files': []}), isNull);
    });
  });

  group('widgets', () {
    Future<(VaultStore, SessionManager)> pump(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = await VaultStore.open(MemoryBackend());
      store.saveHost(host('a'));
      final sessions = SessionManager(store);
      await tester.pumpWidget(
        AppScope(
          vault: store,
          manager: sessions,
          child: MaterialApp(theme: AppTheme.build(BuiltInThemes.matteBlack), home: home),
        ),
      );
      await tester.pumpAndSettle();
      return (store, sessions);
    }

    testWidgets('the host menu marks and unmarks a favourite', (tester) async {
      final (store, sessions) = await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(body: HostTile(host: AppScope.watch(context).host('a')!)),
        ),
      );
      await tester.tap(find.byTooltip('Actions for Host a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to favourites'));
      await tester.pumpAndSettle();
      expect(store.host('a')!.favourite, isTrue);
      expect(find.byIcon(Icons.star), findsOneWidget);
      await tester.tap(find.byTooltip('Actions for Host a'));
      await tester.pumpAndSettle();
      expect(find.text('Remove from favourites'), findsOneWidget);
      await store.flush();
      sessions.dispose();
    });

    testWidgets('the host editor has a favourite switch that saves', (tester) async {
      final (store, sessions) = await pump(tester, Builder(builder: (context) => HostEditorScreen(host: AppScope.store(context).host('a'))));
      await tester.ensureVisible(find.text('Favourite'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favourite'));
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(store.host('a')!.favourite, isTrue);
      await store.flush();
      sessions.dispose();
    });

    testWidgets('a widget tap on a host that is gone explains it instead of failing', (tester) async {
      final incoming = FakeIncoming()..waiting.add(const ConnectAction('deleted'));
      final (store, sessions) = await pump(
        tester,
        IncomingActionsHandler(
          channel: incoming,
          child: const Scaffold(body: Text('home')),
        ),
      );
      await tester.pump();
      expect(find.text('That host is no longer saved in Multiplex.'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await store.flush();
      sessions.dispose();
    });

    testWidgets('a widget tap on a saved host starts connecting to it', (tester) async {
      final incoming = FakeIncoming();
      final (store, sessions) = await pump(
        tester,
        IncomingActionsHandler(
          channel: incoming,
          child: const Scaffold(body: Text('home')),
        ),
      );
      // Comes in while the app is already open.
      incoming.push(const ConnectAction('a'));
      await tester.pump();
      await tester.pump();
      // Tests run without the native core, so the attempt itself fails;
      // the failure dialog shows the app did try to connect.
      expect(find.text('The connection failed'), findsOneWidget);
      await store.flush();
      sessions.dispose();
    });
  });
}
