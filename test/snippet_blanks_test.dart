import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/ui/snippets/snippet_blanks_sheet.dart';
import 'package:multiplex/ui/snippets/snippet_editor_screen.dart';
import 'package:multiplex/ui/snippets/snippet_template.dart';

void main() {
  group('template', () {
    test('finds names and defaults, each name once, in order', () {
      final t = SnippetTemplate('scp {file} {user:root}@{host}:{dir:/tmp} && echo {file}');
      expect(t.blanks, const [SnippetBlank('file', ''), SnippetBlank('user', 'root'), SnippetBlank('host', ''), SnippetBlank('dir', '/tmp')]);
    });

    test('leaves shell braces alone', () {
      for (final command in [r'echo ${HOME}', 'find . -exec rm {} \\;', 'cp a.{txt,bak}', r"awk '{print $1}'", 'echo {1abc}', 'echo { x }']) {
        expect(SnippetTemplate(command).hasBlanks, isFalse, reason: command);
      }
    });

    test('fills every place a name appears, defaults for missing values', () {
      final t = SnippetTemplate('ping -c {count:3} {host}; echo {host}');
      expect(t.fill({'host': 'db'}), 'ping -c 3 db; echo db');
      expect(t.fill({'host': 'db', 'count': '10'}), 'ping -c 10 db; echo db');
      expect(t.fill({'host': '', 'count': ''}), 'ping -c  ; echo ');
    });

    test('start values prefer what was typed last time', () {
      final t = SnippetTemplate('ssh {user:root}@{host}');
      expect(t.startValues(const {}), {'user': 'root', 'host': ''});
      expect(t.startValues(const {'user': 'pekka', 'other': 'x'}), {'user': 'pekka', 'host': ''});
    });

    test('remembered values survive a save and load, old snippets load without them', () {
      const s = Snippet(id: 'a', name: 'n', command: 'c {x}', lastValues: {'x': '1'});
      expect(Snippet.fromJson(s.toJson()).lastValues, {'x': '1'});
      expect(Snippet.fromJson(const {'id': 'a', 'name': 'n', 'command': 'c'}).lastValues, isEmpty);
      expect(Snippet.fromJson(const {'id': 'a', 'lastValues': {'x': 2, 'y': 'ok'}}).lastValues, {'y': 'ok'});
    });
  });

  group('sheet', () {
    Future<(VaultStore, SessionManager)> pump(WidgetTester tester, Widget home, {List<Snippet> snippets = const []}) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = await VaultStore.open(MemoryBackend());
      for (final s in snippets) {
        store.saveSnippet(s);
      }
      final sessions = SessionManager(store);
      await tester.pumpWidget(AppScope(
        vault: store,
        manager: sessions,
        child: MaterialApp(theme: AppTheme.build(BuiltInThemes.matteBlack), home: home),
      ));
      await tester.pumpAndSettle();
      return (store, sessions);
    }

    Future<void> finish(VaultStore store, SessionManager sessions) async {
      await store.flush();
      sessions.dispose();
    }

    Widget launcher(Snippet Function(VaultStore) snippet, void Function(String?) done, {bool remember = true}) => Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => done(await SnippetBlanks.fill(context, snippet(AppScope.store(context)), remember: remember)),
              child: const Text('Open'),
            ),
          ),
        );

    testWidgets('asks once for each blank, prefilled, and remembers the values', (tester) async {
      const snippet = Snippet(id: 'tail', name: 'Tail a log', command: 'tail -n {lines:50} {file}; wc -l {file}');
      String? result;
      final (store, sessions) = await pump(tester, launcher((s) => s.snippets.firstWhere((x) => x.id == 'tail'), (r) => result = r), snippets: [snippet]);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Tail a log'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'lines'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'file'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      expect(find.text('Default: 50'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'file'), '/var/log/syslog');
      await tester.pump();
      expect(find.text('tail -n 50 /var/log/syslog; wc -l /var/log/syslog'), findsOneWidget);
      await tester.tap(find.text('Use these values'));
      await tester.pumpAndSettle();
      expect(result, 'tail -n 50 /var/log/syslog; wc -l /var/log/syslog');
      expect(store.snippets.firstWhere((x) => x.id == 'tail').lastValues, {'lines': '50', 'file': '/var/log/syslog'});

      // Next time the last value is already there.
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '/var/log/syslog'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await finish(store, sessions);
    });

    testWidgets('a snippet without blanks needs no sheet', (tester) async {
      String? result = 'unset';
      final (store, sessions) = await pump(tester, launcher((_) => const Snippet(id: 'x', name: 'Disk', command: r'df -h ${HOME}'), (r) => result = r));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Use these values'), findsNothing);
      expect(result, r'df -h ${HOME}');
      await finish(store, sessions);
    });

    testWidgets('not remembered when asked not to', (tester) async {
      const snippet = Snippet(id: 'p', name: 'Ping', command: 'ping {host}');
      final (store, sessions) = await pump(tester, launcher((s) => snippet, (_) {}, remember: false), snippets: [snippet]);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'example.org');
      await tester.tap(find.text('Use these values'));
      await tester.pumpAndSettle();
      expect(store.snippets.firstWhere((x) => x.id == 'p').lastValues, isEmpty);
      await finish(store, sessions);
    });

    testWidgets('the editor explains the blank syntax', (tester) async {
      final (store, sessions) = await pump(tester, const SnippetEditorScreen());
      expect(find.textContaining('{name:default}'), findsOneWidget);
      await finish(store, sessions);
    });
  });
}
