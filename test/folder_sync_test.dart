import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/sync_pairs.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_document.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/sftp.dart';
import 'package:multiplex/src/rust/api/transfer_types.dart';
import 'package:multiplex/ui/files/sync/sync_backend.dart';
import 'package:multiplex/ui/files/sync/sync_pairs_screen.dart';

import 'support/files_fixtures.dart';

/// Answers with a fixed plan and records what was applied.
class FakeBackend implements SyncBackend {
  FakeBackend(this.steps);

  final List<SyncAction> steps;
  List<SyncAction>? applied;

  @override
  Future<List<SyncAction>> plan(SyncPair pair, FileTransfer transfer) async => steps;

  @override
  Future<SyncReport> apply(SyncPair pair, List<SyncAction> actions, FileTransfer transfer) async {
    applied = actions;
    return SyncReport(copied: actions.where((a) => !SyncWords.isDelete(a)).length, deleted: actions.where(SyncWords.isDelete).length, failed: const []);
  }
}

SyncAction step(String path, SyncActionKind kind, SyncReason reason, {int size = 0}) =>
    SyncAction(path: path, kind: kind, reason: reason, isDir: false, size: BigInt.from(size));

void main() {
  const host = Host(id: 'h1', label: 'Box', address: 'box.example');

  setUpAll(() async {
    Fixtures.store = await VaultStore.open(MemoryBackend());
    Fixtures.sessions = SessionManager(Fixtures.store);
  });
  tearDownAll(() => Fixtures.sessions.dispose());
  tearDown(() {
    for (final pair in Fixtures.store.syncPairsFor(host.id)) {
      Fixtures.store.deleteSyncPair(pair.id);
    }
  });

  group('saved pairs', () {
    test('round-trip through the vault, and old vaults without pairs still open', () {
      final pair = SyncPair(id: 'p1', hostId: 'h1', name: 'Site', phonePath: '/phone/site', serverPath: '/var/www', way: SyncWay.both, mirror: true, lastSyncedAt: DateTime.utc(2026, 11, 6));
      final doc = VaultDocument.fromJson(VaultDocument(syncPairs: [pair]).toJson());
      final back = doc.syncPairs.single;
      expect([back.name, back.phonePath, back.serverPath, back.way, back.mirror, back.lastSyncedAt], ['Site', '/phone/site', '/var/www', SyncWay.both, true, DateTime.utc(2026, 11, 6)]);
      expect(back.mirrors, isFalse, reason: 'mirror never applies to two-way syncs');
      expect(VaultDocument.fromJson({'hosts': []}).syncPairs, isEmpty);
      expect(SyncPair.fromJson({'id': 'x', 'way': 'sideways'}).way, SyncWay.toServer);
    });

    test('deleting a host deletes its sync pairs', () async {
      final store = await VaultStore.open(MemoryBackend());
      store.saveHost(host);
      store.saveSyncPair(const SyncPair(id: 'p1', hostId: 'h1', name: 'Site', phonePath: '/a', serverPath: '/b'));
      store.deleteHost('h1');
      expect(store.syncPairsFor('h1'), isEmpty);
      store.dispose();
    });
  });

  group('screens', () {
    Future<void> show(WidgetTester tester, {FakeBackend? backend}) async {
      Fixtures.phone(tester);
      final session = LiveSession(id: 's1', host: host, ssh: FakeSsh(FakeFiles(Fixtures.tree())));
      await tester.pumpWidget(
        AppScope(
          vault: Fixtures.store,
          manager: Fixtures.sessions,
          child: MaterialApp(
            theme: AppTheme.build(Fixtures.store.activeTheme),
            home: SyncPairsScreen(
              session: session,
              serverPath: '/home/ann',
              backend: () async => backend ?? FakeBackend(const []),
              newTransfer: FakeTransfer.new,
              pickFolder: () async => '/phone/photos',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a new pair: checks its fields, asks before mirror, and is saved', (tester) async {
      await show(tester);
      expect(find.text('No folders kept in sync yet'), findsOneWidget);
      await tester.tap(find.text('New sync pair'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '/home/ann'), findsOneWidget, reason: 'starts at the folder open in Files');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Give the pair a name'), findsOneWidget);
      expect(find.text('Choose a folder on this phone.'), findsOneWidget);
      await Fixtures.checkTouchRules(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Photos');
      await tester.tap(find.byTooltip('Choose phone folder'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '/phone/photos'), findsOneWidget);

      await tester.tap(find.text('Mirror (delete extra files)'));
      await tester.pumpAndSettle();
      expect(find.text('Delete extra files?'), findsOneWidget);
      await tester.tap(find.text('Turn on mirror'));
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isTrue);
      // Two-way syncs never delete.
      await tester.tap(find.text('Both ways, newer wins'));
      await tester.pumpAndSettle();
      final box = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
      expect([box.value, box.onChanged], [false, null]);
      await tester.tap(find.text('Phone to server'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = Fixtures.store.syncPairsFor(host.id).single;
      expect([saved.name, saved.phonePath, saved.serverPath, saved.way, saved.mirrors], ['Photos', '/phone/photos', '/home/ann', SyncWay.toServer, true]);
      expect(find.text('Photos'), findsOneWidget);
      expect(find.textContaining('Never synced'), findsOneWidget);
    });

    testWidgets('sync now shows the plan first, confirms deletes, and skips conflicts', (tester) async {
      Fixtures.store.saveSyncPair(const SyncPair(id: 'p1', hostId: 'h1', name: 'Site', phonePath: '/phone/site', serverPath: '/var/www', mirror: true));
      final backend = FakeBackend([
        step('index.html', SyncActionKind.copyToRight, SyncReason.changed, size: 2048),
        step('old.css', SyncActionKind.deleteOnRight, SyncReason.extra),
        step('img', SyncActionKind.conflict, SyncReason.typeClash),
      ]);
      await show(tester, backend: backend);
      await tester.tap(find.text('Sync now'));
      await tester.pumpAndSettle();
      expect(find.text('Copy to the server (1)'), findsOneWidget);
      expect(find.text('Delete on the server (1)'), findsOneWidget);
      expect(find.text('Needs you: left alone (1)'), findsOneWidget);
      expect(find.textContaining('Nothing has changed yet'), findsOneWidget);
      expect(backend.applied, isNull);
      await Fixtures.checkTouchRules(tester);

      await tester.tap(find.text('Sync 2 changes'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 1 item?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.applied, isNull, reason: 'backing out of the delete warning changes nothing');

      await tester.tap(find.text('Sync 2 changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync and delete'));
      await tester.pumpAndSettle();
      expect(backend.applied!.map((a) => a.path), ['index.html', 'old.css']);
      expect(find.text('Folders are in step'), findsOneWidget);
      expect(find.text('Copied 1, deleted 1.'), findsOneWidget);
      expect(Fixtures.store.syncPairsFor(host.id).single.lastSyncedAt, isNotNull);
    });

    testWidgets('folders already in step say so and offer nothing to run', (tester) async {
      Fixtures.store.saveSyncPair(const SyncPair(id: 'p1', hostId: 'h1', name: 'Site', phonePath: '/phone/site', serverPath: '/var/www'));
      await show(tester);
      await tester.tap(find.text('Sync now'));
      await tester.pumpAndSettle();
      expect(find.text('Already in step'), findsOneWidget);
      expect(find.textContaining('Sync '), findsOneWidget, reason: 'only the title');
    });
  });
}
