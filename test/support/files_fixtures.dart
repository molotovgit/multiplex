// Fakes and sample data shared by the file screen tests.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/sftp.dart';
import 'package:multiplex/src/rust/api/sftp_types.dart';
import 'package:multiplex/src/rust/api/ssh.dart';
import 'package:multiplex/ui/files/files_screen.dart';
import 'package:multiplex/ui/files/remote_paths.dart';
import 'package:multiplex/ui/files/transfer_queue.dart';

/// A server kept in memory. Records every change it is asked to make.
class FakeFiles implements RemoteFiles {
  FakeFiles(this.tree);

  final Map<String, List<RemoteEntry>> tree;
  final Map<String, String> texts = {};
  final List<String> calls = [];

  @override
  Future<String> home() async => '/home/ann';
  @override
  Future<String> canonicalize({required String path}) async => path;
  @override
  Future<List<RemoteEntry>> list({required String dir}) async => tree[dir] ?? (throw AnyhowException('no such folder'));
  @override
  Future<RemoteEntry> stat({required String path}) async => tree[RemotePaths.parent(path)]!.firstWhere((e) => e.path == path);
  @override
  Future<void> remove({required String path}) async {
    calls.add('remove $path');
    tree[RemotePaths.parent(path)]?.removeWhere((e) => e.path == path);
  }

  @override
  Future<void> rename({required String from, required String to}) async => calls.add('rename $from $to');
  @override
  Future<void> makeDir({required String path}) async => calls.add('mkdir $path');
  @override
  Future<void> setPermissions({required String path, required int mode}) async => calls.add('chmod $path ${mode.toRadixString(8)}');
  @override
  Future<String> readText({required String path, required BigInt maxBytes}) async => texts[path]!;
  @override
  Future<void> writeText({required String path, required String text}) async => texts[path] = text;

  /// File contents for [download], by server path.
  final Map<String, List<int>> blobs = {};

  /// Writes the blob to [localPath], or fails like the core when there is none.
  @override
  Future<BigInt> download({required String remotePath, required String localPath, required FileTransfer transfer}) async {
    calls.add('download $remotePath');
    final bytes = blobs[remotePath];
    if (bytes == null) throw AnyhowException('no such file');
    await File(localPath).writeAsBytes(bytes);
    return BigInt.from(bytes.length);
  }

  /// Uploads are covered by the queue tests' fake tasks.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSsh implements SshSession {
  FakeSsh(this.files, {this.failOpens = 0});

  final FakeFiles files;
  int failOpens;
  bool connected = true;

  @override
  bool isConnected() => connected;
  @override
  Future<RemoteFiles> openFiles() async {
    if (failOpens-- > 0) throw AnyhowException('subsystem request failed');
    return files;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Progress and cancel; cancel makes the task fail the way the core does.
class FakeTransfer implements FileTransfer {
  final progress = StreamController<TransferProgress>();
  VoidCallback? onCancel;
  bool cancelled = false;

  @override
  void cancel() {
    cancelled = true;
    onCancel?.call();
  }

  @override
  bool isCancelled() => cancelled;
  @override
  Stream<TransferProgress> watch() => progress.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A transfer that finishes when the test says so.
class FakeTask extends TransferTask {
  FakeTask(this.name, {this.exclusiveKey});

  @override
  final String name;
  @override
  final String? exclusiveKey;
  final done = Completer<String>();
  FakeTransfer? transfer;
  bool tidied = false;

  bool get started => transfer != null;

  @override
  TransferDirection get direction => TransferDirection.download;
  @override
  String get remoteFolder => '/srv';
  @override
  Future<String> run(FileTransfer transfer) {
    final fake = this.transfer = transfer as FakeTransfer;
    fake.onCancel = () => done.completeError(AnyhowException('transfer cancelled'));
    return done.future;
  }

  @override
  Future<void> afterCancel() async => tidied = true;
}

/// Sample data and screen set-up shared by the tests.
abstract final class Fixtures {
  /// Octal modes written as numbers, since Dart has no 0o literals.
  static int octal(String digits) => int.parse(digits, radix: 8);

  static RemoteEntry entry(String dir, String name, {EntryKind kind = EntryKind.file, bool? isDir, int size = 10, String mode = '644'}) => RemoteEntry(
    name: name,
    path: RemotePaths.join(dir, name),
    kind: kind,
    isDir: isDir ?? kind == EntryKind.directory,
    size: BigInt.from(size),
    permissions: octal(mode),
    modified: DateTime(2024, 3, 2, 9, 7).millisecondsSinceEpoch ~/ 1000,
  );

  static Map<String, List<RemoteEntry>> tree() => {
    '/': [entry('/', 'home', kind: EntryKind.directory, mode: '755')],
    '/home': [entry('/home', 'ann', kind: EntryKind.directory, mode: '755')],
    '/home/ann': [
      entry('/home/ann', 'projects', kind: EntryKind.directory, mode: '755'),
      entry('/home/ann', 'www', kind: EntryKind.symlink, isDir: true, mode: '777'),
      entry('/home/ann', '.bashrc'),
      entry('/home/ann', 'big.iso', size: 5 * 1024 * 1024),
      entry('/home/ann', 'notes.txt', size: 2048),
    ],
    '/home/ann/projects': [entry('/home/ann/projects', 'main.rs')],
  };

  /// Makes the test screen phone sized (360 x 740).
  static void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Made outside the fake clock, so the 2-second timer is not "left running".
  static late VaultStore store;
  static late SessionManager sessions;

  /// Shows the files screen; pass [manager] to tick on the fake clock.
  static Future<void> showFiles(WidgetTester tester, FakeSsh ssh, {SessionManager? manager}) async {
    manager ??= sessions;
    final session = LiveSession(id: 's1', host: const Host(id: 'h1', label: 'Box', address: 'box.example'), ssh: ssh);
    await tester.pumpWidget(
      AppScope(
        vault: store,
        manager: manager,
        child: MaterialApp(theme: AppTheme.build(store.activeTheme), home: FilesScreen(session: session)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Every tap target is at least 48 by 48 and has a label (Material's
  /// own accessibility checks).
  static Future<void> checkTouchRules(WidgetTester tester) async {
    final semantics = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  }

  static Future<void> chooseAction(WidgetTester tester, String name, String action) async {
    await tester.tap(find.byTooltip('More actions for $name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(action).last);
    await tester.pumpAndSettle();
  }
}

