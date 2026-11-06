
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/sftp_types.dart';
import 'package:multiplex/ui/files/file_format.dart';
import 'package:multiplex/ui/files/remote_paths.dart';
import 'package:multiplex/ui/files/transfer_panel.dart';
import 'package:multiplex/ui/files/transfer_queue.dart';
import 'package:multiplex/ui/files/transfer_tasks.dart';

import 'support/files_fixtures.dart';

void main() {
  group('formatting', () {
    test('paths join, split and resolve like the core does', () {
      expect(RemotePaths.join('/home/a', 'x.txt'), '/home/a/x.txt');
      expect(RemotePaths.join('/', 'etc'), '/etc');
      expect(RemotePaths.parent('/home/a/x.txt'), '/home/a');
      expect(RemotePaths.parent('/etc'), '/');
      expect(RemotePaths.parent('/home/a/'), '/home');
      expect(RemotePaths.parent('x'), '.');
      expect(RemotePaths.segments('/home/ann').map((s) => '${s.label}=${s.path}'), ['/=/', 'home=/home', 'ann=/home/ann']);
      expect(RemotePaths.resolve('~/logs', current: '/srv', home: '/home/ann'), '/home/ann/logs');
      expect(RemotePaths.resolve('../etc', current: '/srv', home: '/home/ann'), '/srv/../etc');
      expect(RemotePaths.resolve('/var', current: '/srv', home: '/home/ann'), '/var');
      expect(RemotePaths.nameProblem('a/b'), isNotNull);
      expect(RemotePaths.nameProblem('..'), isNotNull);
      expect(RemotePaths.nameProblem('ok.txt'), isNull);
    });

    test('sizes, modes, dates and errors read plainly', () {
      expect(FileSizes.human(BigInt.zero), '0 B');
      expect(FileSizes.human(BigInt.from(1536)), '1.5 KB');
      expect(FileSizes.human(BigInt.from(10 * 1024)), '10 KB');
      expect(FileSizes.human(BigInt.from(1048575)), '1.0 MB');
      expect(FileSizes.human(BigInt.from(5) * BigInt.from(1024 * 1024 * 1024)), '5.0 GB');
      expect(FileModes.describe(Fixtures.octal('755'), EntryKind.directory), 'drwxr-xr-x');
      expect(FileModes.describe(Fixtures.octal('644'), EntryKind.file), '-rw-r--r--');
      expect(FileModes.describe(Fixtures.octal('4755'), EntryKind.file), '-rwsr-xr-x');
      expect(FileModes.describe(Fixtures.octal('1777'), EntryKind.directory), 'drwxrwxrwt');
      expect(FileModes.octal(Fixtures.octal('644')), '644');
      expect(FileModes.octal(Fixtures.octal('4755')), '4755');
      expect(FileModes.parseOctal('0600'), Fixtures.octal('600'));
      expect(FileModes.parseOctal('68'), isNull);
      final now = DateTime(2026, 11, 5, 18);
      int at(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
      expect(FileDates.short(at(DateTime(2026, 11, 5, 14, 5)), now: now), 'Today 14:05');
      expect(FileDates.short(at(DateTime(2026, 3, 2, 9, 7)), now: now), '2 Mar 09:07');
      expect(FileDates.short(at(DateTime(2024, 12, 31, 10)), now: now), '31 Dec 2024');
      expect(FileErrors.message(AnyhowException('timeout\n\nCaused by:\n  sftp status 3')), 'Timeout.');
      expect(
        FileErrors.message(AnyhowException('Permission denied: Permission denied')),
        'Permission denied. Your account on the server is not allowed to do this.',
      );
    });

    test('local names stay safe and never replace a file', () {
      final taken = {'/d/a.txt', '/d/a (1).txt', '/d/.bashrc'};
      expect(LocalNames.free('/d', 'a.txt', exists: taken.contains), '/d/a (2).txt');
      expect(LocalNames.free('/d', '.bashrc', exists: taken.contains), '/d/.bashrc (1)');
      expect(LocalNames.free('/d', 'b.txt', exists: taken.contains), '/d/b.txt');
      expect(LocalNames.safe('a:b?.txt', windows: true), 'a_b_.txt');
      expect(LocalNames.safe('con.txt', windows: true), '_con.txt');
      expect(LocalNames.safe('dots. ', windows: true), 'dots');
      expect(LocalNames.safe('a:b', windows: false), 'a:b');
      final files = FakeFiles({});
      DownloadTask task(String name) => DownloadTask(files: files, entry: Fixtures.entry('/srv', name));
      expect(task('notes.txt').exclusiveKey, task('Notes.TXT').exclusiveKey);
      expect(task('notes.txt').exclusiveKey, isNot(task('notes.log').exclusiveKey));
    });
  });

  group('transfer queue', () {
    TransferQueue newQueue() => TransferQueue(newTransfer: FakeTransfer.new);

    test('runs two at a time, in order, and reports each ending', () async {
      final queue = newQueue();
      final ended = <String>[];
      queue.finished.listen((job) => ended.add('${job.name} ${job.state.name}'));
      final tasks = [FakeTask('a'), FakeTask('b'), FakeTask('c')];
      final jobs = [for (final t in tasks) queue.add(t)];
      expect(tasks.map((t) => t.started), [true, true, false]);
      tasks[0].transfer!.progress.add(TransferProgress(transferred: BigInt.from(50), total: BigInt.from(200)));
      await pumpEventQueue();
      expect(jobs[0].fraction, 0.25);
      tasks[0].done.complete('/local/a');
      await pumpEventQueue();
      expect(jobs[0].state, TransferState.done);
      expect(jobs[0].result, '/local/a');
      expect(tasks[2].started, isTrue);
      expect(ended, ['a done']);
      queue.dispose();
    });

    test('keeps tasks with the same key apart', () async {
      final queue = newQueue();
      final first = FakeTask('notes.txt', exclusiveKey: 'notes');
      final second = FakeTask('notes.log', exclusiveKey: 'notes');
      final other = FakeTask('todo.txt', exclusiveKey: 'todo');
      queue
        ..add(first)
        ..add(second)
        ..add(other);
      expect([first.started, second.started, other.started], [true, false, true]);
      first.done.complete('/x');
      await pumpEventQueue();
      expect(second.started, isTrue);
      queue.dispose();
    });

    test('cancels waiting and running jobs, and says why one failed', () async {
      final queue = TransferQueue(maxRunning: 1, newTransfer: FakeTransfer.new);
      final running = FakeTask('a');
      final waiting = FakeTask('b');
      final failing = FakeTask('c');
      final runningJob = queue.add(running);
      final waitingJob = queue.add(waiting);
      final failingJob = queue.add(failing);
      queue.cancel(waitingJob);
      expect(waitingJob.state, TransferState.cancelled);
      queue.cancel(runningJob);
      await pumpEventQueue();
      expect(runningJob.state, TransferState.cancelled);
      expect(running.tidied, isTrue);
      expect(waiting.started, isFalse);
      failing.done.completeError(AnyhowException('no space left on device'));
      await pumpEventQueue();
      expect(failingJob.state, TransferState.failed);
      expect(failingJob.error, 'No space left on device. Free up some space and try again.');
      queue.clearFinished();
      expect(queue.jobs, isEmpty);
      queue.dispose();
    });
  });

  group('files screen', () {
    setUpAll(() async {
      Fixtures.store = await VaultStore.open(MemoryBackend());
      Fixtures.sessions = SessionManager(Fixtures.store);
    });
    tearDownAll(() => Fixtures.sessions.dispose());

    testWidgets('lists the home folder, hides dot files, and opens folders', (tester) async {
      await Fixtures.showFiles(tester, FakeSsh(FakeFiles(Fixtures.tree())));
      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.text('.bashrc'), findsNothing);
      expect(find.textContaining('2.0 KB'), findsOneWidget);
      expect(find.text('-rw-r--r--'), findsWidgets);
      expect(find.text('Upload files'), findsOneWidget);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.ancestor(of: find.text('Show hidden files'), matching: find.byWidgetPredicate((w) => w is CheckedPopupMenuItem)));
      await tester.pumpAndSettle();
      expect(find.text('.bashrc'), findsOneWidget);
      await tester.tap(find.text('projects'));
      await tester.pumpAndSettle();
      expect(find.text('main.rs'), findsOneWidget);
      await tester.tap(find.text('home'));
      await tester.pumpAndSettle();
      expect(find.text('ann'), findsWidgets);
      await tester.tap(find.byTooltip('Up one folder'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsWidgets);
    });

    testWidgets('offers to try again when the files cannot open', (tester) async {
      await Fixtures.showFiles(tester, FakeSsh(FakeFiles(Fixtures.tree()), failOpens: 1));
      expect(find.text('Could not open the files'), findsOneWidget);
      expect(find.textContaining('Subsystem request failed.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('notes.txt'), findsOneWidget);
    });

    testWidgets('a dropped connection shows a banner and takes the actions away', (tester) async {
      final ssh = FakeSsh(FakeFiles(Fixtures.tree()));
      final manager = SessionManager(Fixtures.store); // Ticks on the fake clock.
      await Fixtures.showFiles(tester, ssh, manager: manager);
      ssh.connected = false;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle(); // The upload button animates away.
      expect(find.textContaining('connection to this server closed'), findsOneWidget);
      expect(find.text('Upload files'), findsNothing);
      expect(find.byTooltip('More actions for notes.txt'), findsNothing);
      manager.dispose();
    });

    testWidgets('permissions: boxes and number stay in step, and the change can be undone', (tester) async {
      final files = FakeFiles(Fixtures.tree());
      await Fixtures.showFiles(tester, FakeSsh(files));
      await Fixtures.chooseAction(tester, 'notes.txt', 'Permissions');
      await Fixtures.checkTouchRules(tester);
      expect(find.widgetWithText(TextField, '644'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).at(2)); // Owner can execute.
      await tester.pump();
      expect(find.widgetWithText(TextField, '744'), findsOneWidget);
      expect(find.text('-rwxr--r--'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '600');
      await tester.pump();
      expect(tester.widget<Checkbox>(find.byType(Checkbox).at(3)).value, isFalse); // Group can read.
      await tester.tap(find.text('Change permissions'));
      await tester.pumpAndSettle();
      expect(find.text('Permissions of notes.txt set to 600'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(files.calls, ['chmod /home/ann/notes.txt 600', 'chmod /home/ann/notes.txt 644']);
    });

    testWidgets('delete asks first and warns that folders go with their contents', (tester) async {
      final files = FakeFiles(Fixtures.tree());
      await Fixtures.showFiles(tester, FakeSsh(files));
      await Fixtures.chooseAction(tester, 'projects', 'Delete');
      expect(find.textContaining('everything inside it'), findsOneWidget);
      await tester.tap(find.text('Delete folder'));
      await tester.pumpAndSettle();
      expect(files.calls, ['remove /home/ann/projects']);
      expect(find.text('projects'), findsNothing);
      expect(find.text('Deleted projects'), findsOneWidget);
    });

    testWidgets('rename refuses a taken name, and can be undone', (tester) async {
      final files = FakeFiles(Fixtures.tree());
      await Fixtures.showFiles(tester, FakeSsh(files));
      await Fixtures.chooseAction(tester, 'notes.txt', 'Rename');
      await tester.enterText(find.byType(TextField), 'projects');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pump();
      expect(find.textContaining('already in this folder'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'todo.txt');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(find.text('Renamed to todo.txt'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(files.calls, ['rename /home/ann/notes.txt /home/ann/todo.txt', 'rename /home/ann/todo.txt /home/ann/notes.txt']);
    });

    testWidgets('the editor saves, and asks before throwing changes away', (tester) async {
      final files = FakeFiles(Fixtures.tree())..texts['/home/ann/notes.txt'] = 'hello';
      await Fixtures.showFiles(tester, FakeSsh(files));
      await tester.tap(find.text('notes.txt'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'hello'), findsOneWidget);
      expect(find.text('Save'), findsNothing); // Nothing to save yet.
      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.pumpAndSettle();
      expect(find.text('notes.txt (not saved)'), findsOneWidget);
      await Fixtures.checkTouchRules(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(files.texts['/home/ann/notes.txt'], 'hello world');
      expect(find.text('Saved notes.txt'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'scribble');
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.text('projects'), findsOneWidget);
      expect(files.texts['/home/ann/notes.txt'], 'hello world');
    });

    testWidgets('fits a phone at double text size; long press, copy path and big files work', (tester) async {
      Fixtures.phone(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final copied = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => copied.add(call.arguments));
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await Fixtures.showFiles(tester, FakeSsh(FakeFiles(Fixtures.tree())));
      expect(find.text('Upload files'), findsOneWidget);
      await Fixtures.checkTouchRules(tester);
      await tester.longPress(find.text('notes.txt'));
      await tester.pumpAndSettle();
      expect(find.text('Download'), findsOneWidget);
      await Fixtures.checkTouchRules(tester);
      await tester.tap(find.text('Copy path'));
      await tester.pumpAndSettle();
      expect(find.text('Path copied'), findsOneWidget);
      expect(copied.toString(), contains('/home/ann/notes.txt'));
      await tester.tap(find.text('big.iso'));
      await tester.pumpAndSettle();
      expect(find.text('Too big to open here'), findsOneWidget);
      expect(find.text('Download file'), findsOneWidget);
    });

    testWidgets('the transfer panel shows progress and lists every transfer', (tester) async {
      Fixtures.phone(tester);
      final queue = TransferQueue(newTransfer: FakeTransfer.new);
      final running = FakeTask('backup.tar');
      final failing = FakeTask('photo.jpg');
      queue
        ..add(running)
        ..add(failing);
      await tester.pumpWidget(MaterialApp(home: Scaffold(bottomNavigationBar: TransferPanel(queue: queue))));
      expect(find.text('Transfers: 2 running'), findsOneWidget);
      running.transfer!.progress.add(TransferProgress(transferred: BigInt.from(512), total: BigInt.from(2048)));
      failing.done.completeError(AnyhowException('permission denied'));
      await tester.pumpAndSettle();
      expect(find.text('Downloading backup.tar'), findsOneWidget);
      await tester.tap(find.text('Downloading backup.tar'));
      await tester.pumpAndSettle();
      expect(find.text('512 B of 2.0 KB'), findsOneWidget);
      expect(find.textContaining('Failed: Permission denied.'), findsOneWidget);
      await Fixtures.checkTouchRules(tester);
      await tester.tap(find.byTooltip('Cancel transfer'));
      await tester.pumpAndSettle();
      expect(find.text('Cancelled'), findsOneWidget);
      queue.dispose();
    });
  });
}
