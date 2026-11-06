import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/sessions/terminal_controller.dart';
import 'package:multiplex/src/rust/api/ssh.dart';
import 'package:multiplex/src/rust/api/terminal.dart';
import 'package:multiplex/src/rust/api/terminal_types.dart';
import 'package:multiplex/ui/terminal/search/terminal_search_bar.dart';
import 'package:multiplex/ui/terminal/split_panes.dart';
import 'package:multiplex/ui/terminal/terminal_screen.dart';

/// A shell with one line of text that records searches and pastes.
class TextShell implements RemoteShell {
  TextShell(this.text);

  final String text;
  final searched = <String>[];
  final pasted = <String>[];
  final _events = StreamController<ShellEvent>();

  @override
  Stream<ShellEvent> events() => _events.stream;

  @override
  TerminalFrame frame() => TerminalFrame(
        rows: 1,
        cols: 40,
        lines: [TerminalLine(key: BigInt.from(text.hashCode), runs: [TextRun(col: 0, width: text.length, text: text, fg: 0xFFFFFFFF, bg: 0, style: 0)])],
        cursor: const TerminalCursor(row: 0, col: 0, visible: true, shape: CursorShape.block, color: 0),
        scrollOffset: 0,
        scrollbackLen: 0,
        alternateScreen: false,
        mouseReporting: false,
        title: '',
        background: 0,
        foreground: 0,
      );

  @override
  List<SearchMatch> find({required String query, required bool caseSensitive}) {
    searched.add(query);
    final at = text.indexOf(query);
    return at < 0 ? const [] : [SearchMatch(line: 0, col: at, width: query.length)];
  }

  @override
  void paste({required String text}) => pasted.add(text);

  @override
  String textBetween({required int startRow, required int startCol, required int endRow, required int endCol}) => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class TestSessions extends SessionManager {
  TestSessions(super.store);

  final added = <LiveSession>[];

  @override
  List<LiveSession> get sessions => List.unmodifiable(added);

  @override
  Iterable<TerminalController> get terminals => added.expand((s) => s.terminals);
}

class UpSsh implements SshSession {
  @override
  bool isConnected() => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

TextShell shellOf(TerminalController t) => t.shell as TextShell;

void main() {
  testWidgets('find and paste checks work in both split panes, each on its own terminal', (tester) async {
    tester.view.physicalSize = const Size(1000, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await VaultStore.open(MemoryBackend());
    store.updateSettings(store.settings.copyWith(keyboard: {...store.settings.keyboard, 'enabled': false}));
    final sessions = TestSessions(store);
    final session = LiveSession(id: 's', host: const Host(id: 'h', label: 'Web', address: 'web'), ssh: UpSsh());
    final left = TerminalController(shell: TextShell('left error'), title: 'left', sessionId: 's');
    final right = TerminalController(shell: TextShell('right error'), title: 'right', sessionId: 's');
    session.terminals.addAll([left, right]);
    sessions.added.add(session);
    await tester.pumpWidget(AppScope(
      vault: store,
      manager: sessions,
      child: MaterialApp(theme: AppTheme.build(BuiltInThemes.matteBlack), home: TerminalScreen(session: session, controller: left)),
    ));
    await tester.pump();

    await tester.tap(find.byTooltip('Split: two terminals side by side'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'right'));
    await tester.pumpAndSettle();
    expect(find.byKey(SplitPanes.dividerKey), findsOneWidget);

    // Both panes' pastes go through the check.
    expect(left.confirmPaste, isNotNull);
    expect(right.confirmPaste, isNotNull);

    // The right pane has the focus: Find searches its terminal only.
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(TerminalSearchBar), matching: find.byType(TextField)), 'error');
    await tester.pump();
    expect(shellOf(right).searched, ['error']);
    expect(shellOf(left).searched, isEmpty);
    expect(find.text('1 of 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();

    // A risky paste in the right pane asks first; Cancel keeps it out.
    unawaited(right.pasteChecked('sudo reboot'));
    await tester.pumpAndSettle();
    expect(find.text('Paste this?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(shellOf(right).pasted, isEmpty);

    await tester.pumpWidget(const SizedBox());
    // Leaving the screen takes the checks back off.
    expect(left.confirmPaste, isNull);
    expect(right.confirmPaste, isNull);
    sessions.dispose();
  });
}
