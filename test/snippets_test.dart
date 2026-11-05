import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/ssh_types.dart';
import 'package:multiplex/ui/keys/authorized_keys.dart';
import 'package:multiplex/ui/snippets/host_picker.dart';
import 'package:multiplex/ui/snippets/run_output_view.dart';
import 'package:multiplex/ui/snippets/snippet_list.dart';
import 'package:multiplex/ui/snippets/snippets_screen.dart';

/// A phone-sized app with a fresh vault (which starts with a few
/// snippets) around the widget under test.
class Harness {
  Harness(this.store, this.sessions);

  final VaultStore store;
  final SessionManager sessions;

  static Future<Harness> pump(WidgetTester tester, Widget Function() home, {void Function(VaultStore)? fill}) async {
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await VaultStore.open(MemoryBackend());
    fill?.call(store);
    final sessions = SessionManager(store);
    await tester.pumpWidget(AppScope(
      vault: store,
      manager: sessions,
      child: MaterialApp(theme: AppTheme.build(BuiltInThemes.matteBlack), home: home()),
    ));
    await tester.pumpAndSettle();
    return Harness(store, sessions);
  }

  /// A plain page with one button that runs [action].
  static Widget launcher(Future<void> Function(BuildContext) action) =>
      Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () => action(context), child: const Text('Open'))));

  Future<void> finish() async {
    await store.flush();
    sessions.dispose();
  }
}

void main() {
  group('search', () {
    const snippet = Snippet(id: 's', name: 'Restart web', command: 'sudo systemctl restart nginx');

    test('matches words in the name or the command, ignoring case', () {
      expect(SnippetFilter.matches(snippet, ''), isTrue);
      expect(SnippetFilter.matches(snippet, 'WEB'), isTrue);
      expect(SnippetFilter.matches(snippet, 'nginx restart'), isTrue);
      expect(SnippetFilter.matches(snippet, 'apache'), isFalse);
    });

    test('a long command shows its first line in lists', () {
      expect(SnippetText.preview('cd /srv\nmake'), 'cd /srv …');
      expect(SnippetText.preview('df -h'), 'df -h');
    });
  });

  testWidgets('the list shows name and command and can be searched', (tester) async {
    final app = await Harness.pump(tester, () => const SnippetsScreen());
    expect(find.text('Disk usage'), findsOneWidget);
    expect(find.text('df -h'), findsOneWidget);
    expect(find.byTooltip('Run on a host'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'free');
    await tester.pump();
    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('Disk usage'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nothing-like-this');
    await tester.pump();
    expect(find.textContaining('No snippets match'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Clear search'));
    await tester.pump();
    expect(find.text('Disk usage'), findsOneWidget, reason: 'a failed search offers the way back');

    await tester.enterText(find.byType(TextField), 'disk');
    await tester.pump();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.text('Disk usage'), findsOneWidget);
    await app.finish();
  });

  testWidgets('a new snippet needs a name and a command, then is saved', (tester) async {
    final app = await Harness.pump(tester, () => const SnippetsScreen());
    final before = app.store.snippets.length;
    await tester.tap(find.text('New snippet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save snippet'));
    await tester.pump();
    expect(find.text('Enter a name for the snippet.'), findsOneWidget);
    expect(find.text('Enter the command to run.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Uptime');
    await tester.enterText(find.widgetWithText(TextFormField, 'Command'), 'uptime');
    await tester.tap(find.text('Press Enter after inserting'));
    await tester.tap(find.text('Save snippet'));
    await tester.pumpAndSettle();

    expect(app.store.snippets.length, before + 1);
    final saved = app.store.snippets.last;
    expect(saved.name, 'Uptime');
    expect(saved.command, 'uptime');
    expect(saved.runImmediately, isFalse);
    expect(find.text('Uptime'), findsOneWidget, reason: 'back on the list');
    await app.finish();
  });

  testWidgets('a snippet can be edited and deleted', (tester) async {
    final app = await Harness.pump(tester, () => const SnippetsScreen());
    await tester.tap(find.text('Disk usage'));
    await tester.pumpAndSettle();
    expect(find.text('Edit snippet'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Command'), 'df -hT');
    await tester.tap(find.text('Save snippet'));
    await tester.pumpAndSettle();
    expect(app.store.snippets.firstWhere((s) => s.id == 'starter-disk').command, 'df -hT');

    await tester.tap(find.text('Disk usage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete snippet'));
    await tester.pumpAndSettle();
    expect(find.textContaining('undo this'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete snippet'));
    await tester.pumpAndSettle();
    expect(app.store.snippets.where((s) => s.id == 'starter-disk'), isEmpty);
    expect(find.text('Disk usage'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(app.store.snippets.where((s) => s.id == 'starter-disk').single.command, 'df -hT');
    expect(find.text('Disk usage'), findsOneWidget, reason: 'Undo brings it back');
    await app.finish();
  });

  testWidgets('the picker returns the snippet that was tapped', (tester) async {
    Snippet? picked;
    final app = await Harness.pump(tester, () => Harness.launcher((context) async => picked = await SnippetPicker.show(context)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Insert a snippet'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'journal');
    await tester.pump();
    await tester.tap(find.text('Recent system log'));
    await tester.pumpAndSettle();
    expect(picked?.id, 'starter-logs');
    await app.finish();
  });

  testWidgets('with no snippets, the picker makes one and returns it', (tester) async {
    Snippet? picked;
    final app = await Harness.pump(
      tester,
      () => Harness.launcher((context) async => picked = await SnippetPicker.show(context)),
      fill: (store) {
        for (final s in store.snippets) {
          store.deleteSnippet(s.id);
        }
      },
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('No snippets yet'), findsOneWidget);
    await tester.tap(find.text('New snippet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'List files');
    await tester.enterText(find.widgetWithText(TextFormField, 'Command'), 'ls -la');
    await tester.tap(find.text('Save snippet'));
    await tester.pumpAndSettle();
    expect(picked?.command, 'ls -la');
    expect(app.store.snippets.single.name, 'List files');
    await app.finish();
  });

  testWidgets('the host picker says when there are no hosts', (tester) async {
    final app = await Harness.pump(tester, () => Harness.launcher((context) => HostPicker.pick(context, title: 'Run on which host?')));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('No saved hosts'), findsOneWidget);
    await app.finish();
  });

  testWidgets('the host picker returns the host that was tapped', (tester) async {
    Host? picked;
    final app = await Harness.pump(
      tester,
      () => Harness.launcher((context) async => picked = await HostPicker.pick(context, title: 'Run on which host?')),
      fill: (store) => store.saveHost(const Host(id: 'h', label: 'Web', address: 'web.example.com', username: 'root')),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('root@web.example.com'), findsOneWidget);
    await tester.tap(find.text('Web'));
    await tester.pumpAndSettle();
    expect(picked?.id, 'h');
    await app.finish();
  });

  testWidgets('command output shows the exit code and both streams, with copy', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    const output = ExecOutput(stdout: '/dev/sda1 20G', stderr: 'df: /mnt: permission denied', exitCode: 1, truncated: true);
    final app = await Harness.pump(tester, () => const Scaffold(body: RunOutputView(output: output)));
    expect(find.text('Finished with exit code 1'), findsOneWidget);
    expect(find.text('/dev/sda1 20G'), findsOneWidget);
    expect(find.text('df: /mnt: permission denied'), findsOneWidget);
    expect(find.textContaining('cut off after 1 MiB'), findsOneWidget);
    await tester.tap(find.byTooltip('Copy error output'));
    await tester.pump();
    expect(copied, 'df: /mnt: permission denied');
    await app.finish();
  });

  testWidgets('silent commands and installed keys say so instead of showing output', (tester) async {
    const silent = ExecOutput(stdout: '', stderr: '', exitCode: 0, truncated: false);
    const installed = ExecOutput(stdout: AuthorizedKeys.addedMarker, stderr: '', exitCode: 0, truncated: false);
    final app = await Harness.pump(
      tester,
      () => Scaffold(
        body: Column(children: [
          const RunOutputView(output: silent),
          RunOutputView(output: installed, verdict: AuthorizedKeys.verdict(installed, 'web')),
        ]),
      ),
    );
    expect(find.text('The command printed nothing.'), findsOneWidget);
    expect(find.textContaining('Key installed on web'), findsOneWidget);
    expect(find.text(AuthorizedKeys.addedMarker), findsNothing);
    await app.finish();
  });
}
