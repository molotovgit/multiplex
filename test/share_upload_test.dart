import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/platform/incoming_actions.dart';
import 'package:multiplex/platform/incoming_actions_handler.dart';
import 'package:multiplex/sessions/phone_outbox.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/sftp.dart';
import 'package:multiplex/src/rust/api/sftp_types.dart';
import 'package:multiplex/src/rust/api/ssh.dart';
import 'package:multiplex/ui/files/remote_paths.dart';
import 'package:multiplex/ui/files/transfer_queue.dart';
import 'package:multiplex/ui/share/share_upload_screen.dart';

RemoteEntry folder(String dir, String name) =>
    RemoteEntry(name: name, path: RemotePaths.join(dir, name), kind: EntryKind.directory, isDir: true, size: BigInt.zero, permissions: 493, modified: null);

/// A server with a home folder and a www folder; records uploads.
class FakeFiles implements RemoteFiles {
  final uploads = <String>[];
  final tree = {
    '/home/ann': [folder('/home/ann', 'www')],
    '/home/ann/www': <RemoteEntry>[],
  };

  @override
  Future<String> home() async => '/home/ann';
  @override
  Future<String> canonicalize({required String path}) async => path;
  @override
  Future<List<RemoteEntry>> list({required String dir}) async => tree[dir] ?? (throw AnyhowException('no such folder'));
  @override
  Future<RemoteEntry> stat({required String path}) async =>
      tree.containsKey(path) ? folder(RemotePaths.parent(path), RemotePaths.name(path)) : throw AnyhowException('no such file');
  @override
  Future<BigInt> upload({required String localPath, required String remotePath, required FileTransfer transfer}) async {
    expect(File(localPath).existsSync(), isTrue, reason: 'the shared copy is still there while it uploads');
    uploads.add(remotePath);
    return BigInt.from(File(localPath).lengthSync());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSsh implements SshSession {
  FakeSsh(this.files);

  final FakeFiles files;

  @override
  bool isConnected() => true;
  @override
  Future<RemoteFiles> openFiles() async => files;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTransfer implements FileTransfer {
  @override
  Stream<TransferProgress> watch() => const Stream.empty();
  @override
  bool isCancelled() => false;
  @override
  void cancel() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('share-test'));
  tearDown(() => temp.deleteSync(recursive: true));

  SharedFile shared(String name) {
    final file = File('${temp.path}${Platform.pathSeparator}$name')..writeAsStringSync('hello $name');
    return SharedFile(name: name, path: file.path);
  }

  Future<(VaultStore, SessionManager, FakeFiles)> pump(WidgetTester tester, List<SharedFile> files, {String? remembered}) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await VaultStore.open(MemoryBackend());
    store.saveHost(Host(id: 'web', label: 'Web', address: 'web.example.org', username: 'ann', uploadFolder: remembered));
    final sessions = SessionManager(store);
    final remote = FakeFiles();
    final queue = TransferQueue(newTransfer: FakeTransfer.new);
    await tester.pumpWidget(
      AppScope(
        vault: store,
        manager: sessions,
        child: MaterialApp(
          theme: AppTheme.build(BuiltInThemes.matteBlack),
          home: ShareUploadScreen(
            files: files,
            connect: (_, host) async => LiveSession(id: 's', host: host, ssh: FakeSsh(remote)),
            queueFor: (_) => queue,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (store, sessions, remote);
  }

  Future<void> pickWeb(WidgetTester tester) async {
    expect(find.text('Upload to which server?'), findsOneWidget, reason: 'the server question comes up by itself');
    await tester.tap(find.text('Web'));
    await tester.pumpAndSettle();
  }

  testWidgets('pick a server, upload to its home folder, remember the folder, tidy up the copies', (tester) async {
    final files = [shared('photo.jpg'), shared('notes.txt')];
    final (store, sessions, remote) = await pump(tester, files);
    expect(find.text('Upload 2 files'), findsOneWidget);
    await pickWeb(tester);
    expect(find.text('/home/ann'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Upload'));
      await tester.pump();
      // Uploads use real file reads and deletes.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(remote.uploads, ['/home/ann/photo.jpg', '/home/ann/notes.txt']);
    expect(find.text('Uploaded 2 of 2 to /home/ann on Web.'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(store.host('web')!.uploadFolder, '/home/ann');
    for (final f in files) {
      expect(File(f.path).existsSync(), isFalse, reason: '${f.name} copy deleted after its upload');
    }
    await store.flush();
    sessions.dispose();
  });

  testWidgets('starts in the folder used last time, and another folder can be picked', (tester) async {
    final (store, sessions, _) = await pump(tester, [shared('a.txt')], remembered: '/home/ann/www');
    await pickWeb(tester);
    expect(find.text('/home/ann/www'), findsOneWidget);

    await tester.tap(find.text('/home/ann/www'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a folder'), findsOneWidget);
    await tester.tap(find.text('Folder above'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this folder'));
    await tester.pumpAndSettle();
    expect(find.text('/home/ann'), findsOneWidget);
    await store.flush();
    sessions.dispose();
  });

  testWidgets('a remembered folder that is gone falls back to home', (tester) async {
    final (store, sessions, _) = await pump(tester, [shared('a.txt')], remembered: '/srv/old');
    await pickWeb(tester);
    expect(find.text('/home/ann'), findsOneWidget);
    await store.flush();
    sessions.dispose();
  });

  testWidgets('leaving without uploading deletes the copies', (tester) async {
    final file = shared('a.txt');
    final (store, sessions, _) = await pump(tester, [file]);
    await tester.tapAt(const Offset(10, 10)); // closes the server sheet
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect(File(file.path).existsSync(), isFalse);
    await store.flush();
    sessions.dispose();
  });

  testWidgets('a share from Android opens the upload page', (tester) async {
    final channel = _OneShot(ShareAction([shared('a.txt')]));
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await VaultStore.open(MemoryBackend());
    final sessions = SessionManager(store);
    await tester.pumpWidget(
      AppScope(
        vault: store,
        manager: sessions,
        child: MaterialApp(
          theme: AppTheme.build(BuiltInThemes.matteBlack),
          home: IncomingActionsHandler(
            channel: channel,
            child: const Scaffold(body: Text('home')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Upload 1 file'), findsOneWidget);
    await store.flush();
    sessions.dispose();
  });

  group('a paired computer', () {
    final asked = <String>[];

    Future<FakeFiles> pumpWithDesk(WidgetTester tester, List<SharedFile> files, {String? text}) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      asked.clear();
      final store = await VaultStore.open(MemoryBackend());
      store
        ..saveHost(const Host(id: 'web', label: 'Web', address: 'web.example.org', username: 'ann'))
        ..saveHost(const Host(id: 'desk', label: 'Desk', address: 'desk', username: 'ann', computer: true, pairedAs: 'My phone'));
      final sessions = SessionManager(store);
      addTearDown(sessions.dispose);
      final remote = FakeFiles();
      final queue = TransferQueue(newTransfer: FakeTransfer.new);
      await tester.pumpWidget(
        AppScope(
          vault: store,
          manager: sessions,
          child: MaterialApp(
            theme: AppTheme.build(BuiltInThemes.matteBlack),
            home: ShareUploadScreen(
              files: files,
              text: text,
              connect: (_, host) async => LiveSession(id: 's', host: host, ssh: FakeSsh(remote)),
              queueFor: (_) => queue,
              computer: _FakeComputer(asked),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Let the store's delayed save run, so no timer outlives the test.
      await tester.pump(const Duration(milliseconds: 500));
      return remote;
    }

    testWidgets('files go to its Downloads in one tap, and it is told what arrived', (tester) async {
      final remote = await pumpWithDesk(tester, [shared('photo.jpg'), shared('notes.txt')]);
      expect(find.text('Send 2 files'), findsOneWidget);
      expect(find.text('Upload to which server?'), findsNothing, reason: 'the computer is offered first; no picker pops up');
      await tester.runAsync(() async {
        await tester.tap(find.text('Send to Desk'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(remote.uploads, ['/home/ann/Downloads/photo.jpg', '/home/ann/Downloads/notes.txt']);
      expect(asked, ['inbox', 'received My phone: photo.jpg, notes.txt']);
      expect(find.text('Sent 2 of 2 to Desk, into its Downloads folder.'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('picked by name in the share sheet: files are sent with nothing more to tap', (tester) async {
      final remote = FakeFiles();
      final queue = TransferQueue(newTransfer: FakeTransfer.new);
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      asked.clear();
      final store = await VaultStore.open(MemoryBackend());
      store.saveHost(const Host(id: 'desk', label: 'Desk', address: 'desk', username: 'ann', computer: true, pairedAs: 'My phone'));
      final sessions = SessionManager(store);
      addTearDown(sessions.dispose);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          AppScope(
            vault: store,
            manager: sessions,
            child: MaterialApp(
              theme: AppTheme.build(BuiltInThemes.matteBlack),
              home: ShareUploadScreen(
                files: [shared('photo.jpg')],
                sendTo: 'desk',
                connect: (_, host) async => LiveSession(id: 's', host: host, ssh: FakeSsh(remote)),
                queueFor: (_) => queue,
                computer: _FakeComputer(asked),
              ),
            ),
          ),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      expect(remote.uploads, ['/home/ann/Downloads/photo.jpg']);
      expect(find.text('Sent 1 of 1 to Desk, into its Downloads folder.'), findsOneWidget);
    });

    testWidgets('shared text goes onto its clipboard', (tester) async {
      await pumpWithDesk(tester, [shared('shared-text.txt')], text: 'a note to self');
      expect(find.text('Share text'), findsOneWidget);
      expect(find.text('Open on Desk'), findsNothing, reason: 'not a link');
      await tester.tap(find.text('Copy to Desk'));
      await tester.pumpAndSettle();
      expect(asked, ['copy a note to self']);
    });

    testWidgets('a shared link can open in its browser', (tester) async {
      await pumpWithDesk(tester, [shared('shared-text.txt')], text: ' https://example.org/page ');
      await tester.tap(find.text('Open on Desk'));
      await tester.pumpAndSettle();
      expect(asked, ['open https://example.org/page']);
    });

    testWidgets('a computer out of reach: the files can wait and go later', (tester) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = await VaultStore.open(MemoryBackend());
      store.saveHost(const Host(id: 'desk', label: 'Desk', address: 'desk', username: 'ann', computer: true));
      final sessions = SessionManager(store);
      addTearDown(sessions.dispose);
      final outbox = PhoneOutbox(root: () async => Directory('${temp.path}/outbox'));
      final files = [shared('photo.jpg')];
      await tester.pumpWidget(
        AppScope(
          vault: store,
          manager: sessions,
          child: MaterialApp(
            theme: AppTheme.build(BuiltInThemes.matteBlack),
            home: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => ShareUploadScreen(files: files, connect: (_, _) async => null, outbox: outbox, computer: _FakeComputer(asked)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Send when it is next connected'), findsNothing);
      await tester.tap(find.text('Send to Desk'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Send when it is next connected'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.runAsync(() async {
        expect((await outbox.waiting('desk')).map((f) => f.name), ['photo.jpg']);
      });
      expect(File(files.single.path).existsSync(), isFalse, reason: 'moved into the outbox, which keeps it');
    });

    testWidgets('a plain server is still one tap further', (tester) async {
      await pumpWithDesk(tester, [shared('photo.jpg')]);
      expect(find.text('Or upload to a server'), findsOneWidget);
      await tester.tap(find.text('Choose a server'));
      await tester.pumpAndSettle();
      expect(find.text('Upload to which server?'), findsOneWidget);
    });
  });
}

class _OneShot implements IncomingChannel {
  _OneShot(this.action);

  IncomingAction? action;

  @override
  void listen(void Function() onChanged) {}
  @override
  void stop() {}
  @override
  Future<List<IncomingAction>> take() async {
    final a = action;
    action = null;
    return a == null ? const [] : [a];
  }
}

/// A computer that writes down what it was asked.
class _FakeComputer extends ComputerShare {
  const _FakeComputer(this.asked);

  final List<String> asked;

  @override
  Future<String> inbox(LiveSession session) async {
    asked.add('inbox');
    return '/home/ann/Downloads';
  }

  @override
  Future<void> received(LiveSession session, String phone, List<String> names) async => asked.add('received $phone: ${names.join(', ')}');

  @override
  Future<void> copy(LiveSession session, String text) async => asked.add('copy $text');

  @override
  Future<void> open(LiveSession session, String url) async => asked.add('open $url');

  @override
  bool isLink(String text) => text.trim().startsWith('https://');
}
