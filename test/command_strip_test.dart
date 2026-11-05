import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/terminal_types.dart';
import 'package:multiplex/ui/history/command_history_sheet.dart';
import 'package:multiplex/ui/history/command_strip.dart';
import 'package:multiplex/ui/history/command_target.dart';
import 'package:multiplex/ui/keyboard/key_sink.dart';
import 'package:multiplex/ui/keyboard/keyboard_settings.dart';
import 'package:multiplex/ui/keyboard/terminal_keyboard_panel.dart';

/// Remembers what the strip and sheet asked for.
class FakeTarget extends ChangeNotifier implements CommandTarget {
  FakeTarget({this.hostId = 'h1'});

  @override
  final String? hostId;

  final inserted = <String>[];
  final ran = <String>[];
  String _typed = '';

  @override
  String get typedLine => _typed;

  set typed(String value) {
    _typed = value;
    notifyListeners();
  }

  @override
  void insert(String command) => inserted.add(command);

  @override
  void run(String command) => ran.add(command);
}

/// Swallows keyboard output.
class SilentSink implements KeySink {
  @override
  void sendText(String text, KeyModifiers mods) {}

  @override
  void sendKey(TerminalKey key, KeyModifiers mods) {}

  @override
  void pasteClipboard() {}
}

abstract final class StripFixture {
  static Future<(VaultStore, SessionManager)> pump(WidgetTester tester, Widget body) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await VaultStore.open(MemoryBackend());
    store.saveHost(const Host(id: 'h1', label: 'Build box', address: 'box.example.com', username: 'root'));
    for (final c in ['uptime', 'git status', 'git log', 'df -h']) {
      store.recordCommand('h1', c);
    }
    store.pinCommand('h1', 'uptime', true);
    final sessions = SessionManager(store);
    await tester.pumpWidget(AppScope(
      vault: store,
      manager: sessions,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) => MaterialApp(theme: AppTheme.build(store.activeTheme), home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: body))),
      ),
    ));
    await tester.pumpAndSettle();
    return (store, sessions);
  }

  static Future<void> finish(WidgetTester tester, SessionManager sessions) async {
    await tester.pump(const Duration(seconds: 2));
    sessions.dispose();
  }

  static List<String> chipOrder(WidgetTester tester) {
    final labels = <String>[];
    for (final c in ['uptime', 'git status', 'git log', 'df -h']) {
      final f = find.text(c);
      if (f.evaluate().isNotEmpty) labels.add(c);
    }
    labels.sort((a, b) => tester.getTopLeft(find.text(a)).dx.compareTo(tester.getTopLeft(find.text(b)).dx));
    return labels;
  }
}

void main() {
  testWidgets('the strip puts pinned first, filters while typing, and inserts on tap', (tester) async {
    final target = FakeTarget();
    final (_, sessions) = await StripFixture.pump(tester, CommandStrip(target: target, onOpenHistory: () {}));
    // The row scrolls: the chips past the edge are not built yet.
    expect(StripFixture.chipOrder(tester).take(3), ['uptime', 'df -h', 'git log']);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);

    target.typed = 'git';
    await tester.pump();
    expect(StripFixture.chipOrder(tester), ['git log', 'git status']);
    await tester.tap(find.text('git status'));
    expect(target.inserted, ['git status']);

    target.typed = 'zzz';
    await tester.pump();
    expect(find.text('No recent command matches'), findsOneWidget);
    await StripFixture.finish(tester, sessions);
  });

  testWidgets('long press offers run, pin and delete', (tester) async {
    final target = FakeTarget();
    final (store, sessions) = await StripFixture.pump(tester, CommandStrip(target: target, onOpenHistory: () {}));
    await tester.longPress(find.text('df -h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run now'));
    await tester.pumpAndSettle();
    expect(target.ran, ['df -h']);

    await tester.longPress(find.text('df -h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin to the front'));
    await tester.pumpAndSettle();
    expect(store.commandHistory.ordered('h1').take(2).map((e) => e.command), ['df -h', 'uptime']);

    await tester.longPress(find.text('git log'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete from history'));
    await tester.pumpAndSettle();
    expect(find.text('git log'), findsNothing);
    await StripFixture.finish(tester, sessions);
  });

  testWidgets('the strip explains itself when there is nothing to show', (tester) async {
    final (store, sessions) = await StripFixture.pump(tester, CommandStrip(target: FakeTarget(hostId: null), onOpenHistory: () {}));
    expect(find.text('Save this host to keep its commands'), findsOneWidget);
    store.clearCommands('h1');
    await StripFixture.finish(tester, sessions);
  });

  testWidgets('the history sheet searches, pins and clears after asking', (tester) async {
    final target = FakeTarget();
    final (store, sessions) = await StripFixture.pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => CommandHistorySheet.openFor(context, target),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Command history'), findsOneWidget);
    expect(find.text('git status'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'LOG');
    await tester.pumpAndSettle();
    expect(find.text('git status'), findsNothing);
    expect(find.text('git log'), findsOneWidget);
    await tester.tap(find.byTooltip('Pin'));
    await tester.pumpAndSettle();
    expect(store.commandHistory.ordered('h1').where((e) => e.pinned).map((e) => e.command), containsAll(['git log', 'uptime']));

    await tester.tap(find.byTooltip('Clear search'));
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(find.text('Clear the command history?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear all'));
    await tester.pumpAndSettle();
    expect(store.commandHistory.recent('h1'), isEmpty);
    expect(find.text('No commands yet'), findsOneWidget);
    await StripFixture.finish(tester, sessions);
  });

  testWidgets('tapping a command in the sheet puts it on the line and closes the sheet', (tester) async {
    final target = FakeTarget();
    final (_, sessions) = await StripFixture.pump(
      tester,
      Builder(
        builder: (context) => TextButton(onPressed: () => CommandHistorySheet.openFor(context, target), child: const Text('Open')),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('df -h'));
    await tester.pumpAndSettle();
    expect(target.inserted, ['df -h']);
    expect(find.text('Command history'), findsNothing);
    await StripFixture.finish(tester, sessions);
  });

  testWidgets('the keyboard shows the strip unless the setting is off, and has a History key', (tester) async {
    final target = FakeTarget();
    var historyOpened = 0;
    final (store, sessions) = await StripFixture.pump(
      tester,
      TerminalKeyboardPanel.withSink(
        sink: SilentSink(),
        commands: target,
        onHistory: () => historyOpened++,
        onSnippets: () {},
        onHide: () {},
        onSwitchToSystem: () {},
      ),
    );
    expect(find.byType(CommandStrip), findsOneWidget);
    await tester.tap(find.text('uptime'));
    expect(target.inserted, ['uptime']);
    await tester.tap(find.bySemanticsLabel('Command history').first);
    expect(historyOpened, 1);

    await tester.tap(find.text('Fn'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Command history').last);
    expect(historyOpened, 2);

    const KeyboardSettings(showRecentCommands: false).saveTo(store);
    await tester.pumpAndSettle();
    expect(find.byType(CommandStrip), findsNothing);
    await StripFixture.finish(tester, sessions);
  });
}
