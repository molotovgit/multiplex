import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/sftp.dart';
import 'package:multiplex/src/rust/api/sftp_types.dart';
import 'package:multiplex/src/rust/api/transfer.dart';
import 'package:multiplex/src/rust/api/transfer_types.dart';
import 'package:multiplex/ui/files/remote_paths.dart';
import 'package:multiplex/ui/files/transfer_queue.dart';
import 'package:multiplex/ui/files/two_pane/file_pane.dart';
import 'package:multiplex/ui/files/two_pane/phone_storage.dart';
import 'package:multiplex/ui/files/two_pane/two_pane_screen.dart';

import 'support/files_fixtures.dart';

/// One side kept in memory: folders by path.
class FakeSide implements FileSide {
  FakeSide(this.tree, {this.phone = false});

  final Map<String, List<RemoteEntry>> tree;
  final bool phone;

  @override
  bool isPhone() => phone;
  @override
  Future<List<RemoteEntry>> list({required String dir}) async => List.of(tree[dir] ?? (throw StateError('no such folder')));
  @override
  String join({required String dir, required String name}) => RemotePaths.join(dir, name);
  @override
  String parent({required String path}) => RemotePaths.parent(path);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records each copy and puts the item into the target folder.
class FakeCopier {
  final calls = <String>[];

  Future<CopyReport> call({
    required FileSide from,
    required String fromPath,
    required FileSide to,
    required String toDir,
    required ConflictPolicy onConflict,
    required FileTransfer transfer,
  }) async {
    calls.add('$fromPath -> $toDir (${onConflict.name})');
    final name = RemotePaths.name(fromPath);
    final target = (to as FakeSide).tree[toDir]!;
    target.removeWhere((e) => e.name == name);
    target.add(Fixtures.entry(toDir, name));
    return CopyReport(target: RemotePaths.join(toDir, name), copied: 1, skipped: 0, bytes: BigInt.from(10));
  }
}

void main() {
  setUpAll(() async {
    Fixtures.store = await VaultStore.open(MemoryBackend());
    Fixtures.sessions = SessionManager(Fixtures.store);
  });
  tearDownAll(() => Fixtures.sessions.dispose());

  const appFiles = PhoneRoot(label: 'App files', path: '/phone/app', icon: Icons.folder_special_outlined);

  late FakeSide phone;
  late FakeSide server;
  late FakeCopier copier;
  late TransferQueue queue;

  setUp(() {
    phone = FakeSide({
      '/phone/app': [Fixtures.entry('/phone/app', 'Multiplex downloads', kind: EntryKind.directory)],
      '/phone/app/Multiplex downloads': [],
    }, phone: true);
    server = FakeSide(Fixtures.tree());
    copier = FakeCopier();
    queue = TransferQueue(newTransfer: FakeTransfer.new);
  });
  tearDown(() => queue.dispose());

  Future<void> show(WidgetTester tester, {bool withServer = true}) async {
    final files = FakeFiles(Fixtures.tree());
    final session = LiveSession(id: 's1', host: const Host(id: 'h1', label: 'Box', address: 'box.example'), ssh: FakeSsh(files));
    await tester.pumpWidget(
      AppScope(
        vault: Fixtures.store,
        manager: Fixtures.sessions,
        child: MaterialApp(
          theme: AppTheme.build(Fixtures.store.activeTheme),
          home: TwoPaneScreen(
            session: withServer ? session : null,
            queue: queue,
            phoneRoots: () async => [appFiles],
            newPane: () => FilePane(phoneSide: () => phone, serverSide: (_) => server),
            copier: copier.call,
            openFiles: (_) async => files,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('on a phone: one side at a time, tick on the server, copy to the phone', (tester) async {
    Fixtures.phone(tester);
    await show(tester);
    // The server opened in its home folder, and is the side on screen.
    expect(find.text('projects'), findsOneWidget);
    expect(find.text('Copy between places'), findsOneWidget);
    await Fixtures.checkTouchRules(tester);

    await tester.tap(find.text('notes.txt'));
    await tester.pumpAndSettle();
    expect(find.text('Box (1)'), findsOneWidget);
    expect(find.text('Copy 1 item to App files'), findsOneWidget);
    await tester.tap(find.text('Copy 1 item to App files'));
    await tester.pumpAndSettle();
    expect(copier.calls, ['/home/ann/notes.txt -> /phone/app (keepBoth)']);
    expect(find.text('Copy 1 item to App files'), findsNothing, reason: 'ticks clear once queued');
    expect(queue.jobs.single.state, TransferState.done);

    // The phone side shows the new file.
    await tester.tap(find.text('App files'));
    await tester.pumpAndSettle();
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('Multiplex downloads'), findsOneWidget);
  });

  testWidgets('asks what to do about names already there', (tester) async {
    Fixtures.phone(tester);
    phone.tree['/phone/app']!.add(Fixtures.entry('/phone/app', 'notes.txt'));
    await show(tester);
    await tester.tap(find.text('notes.txt'));
    await tester.tap(find.text('big.iso'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy 2 items to App files'));
    await tester.pumpAndSettle();
    expect(find.text('"notes.txt" is already there'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(copier.calls, isEmpty);
    expect(find.text('Copy 2 items to App files'), findsOneWidget, reason: 'the ticks stay after cancelling');

    await tester.tap(find.text('Copy 2 items to App files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(copier.calls, ['/home/ann/big.iso -> /phone/app (skip)', '/home/ann/notes.txt -> /phone/app (skip)']);
  });

  testWidgets('folders open in the pane; the copy goes to the folder open on the other side', (tester) async {
    Fixtures.phone(tester);
    await show(tester);
    await tester.tap(find.text('App files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Multiplex downloads'));
    await tester.pumpAndSettle();
    expect(find.text('This folder is empty'), findsOneWidget);
    await tester.tap(find.text('Box'));
    await tester.pumpAndSettle();
    // Tick a folder with its box: tapping its name would open it.
    await tester.tap(find.bySemanticsLabel('Tick projects'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy 1 item to App files'));
    await tester.pumpAndSettle();
    expect(copier.calls, ['/home/ann/projects -> /phone/app/Multiplex downloads (keepBoth)']);
  });

  testWidgets('wide screens show both sides; an empty side offers to choose a place', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await show(tester, withServer: false);
    expect(find.text('Multiplex downloads'), findsOneWidget);
    expect(find.text('Choose place'), findsOneWidget);
    await Fixtures.checkTouchRules(tester);
    await tester.tap(find.text('Choose place'));
    await tester.pumpAndSettle();
    expect(find.text('This phone'), findsOneWidget);
    expect(find.text('No saved servers yet. Add one on the Hosts screen.'), findsOneWidget);
    await tester.tap(find.text('App files').last);
    await tester.pumpAndSettle();
    expect(find.text('Multiplex downloads'), findsNWidgets(2));

    // Both sides on the same folder: nothing to copy into.
    await tester.tap(find.bySemanticsLabel('Tick Multiplex downloads').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Copy 1 item'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Both sides show the same folder'), findsOneWidget);
    expect(copier.calls, isEmpty);
  });
}
