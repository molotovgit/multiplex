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
