import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/sessions/terminal_controller.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/src/rust/api/ssh.dart';
import 'package:multiplex/src/rust/api/terminal.dart';
import 'package:multiplex/src/rust/api/terminal_types.dart';
import 'package:multiplex/ui/terminal/split_controller.dart';
import 'package:multiplex/ui/terminal/split_panes.dart';
import 'package:multiplex/ui/terminal/terminal_screen.dart';

/// A shell that only records what is typed into it.
class FakeShell implements RemoteShell {
  final typed = <String>[];
  final _events = StreamController<ShellEvent>();

  @override
  Stream<ShellEvent> events() => _events.stream;

  @override
  TerminalFrame frame() => TerminalFrame(
    rows: 1,
    cols: 1,
    lines: [TerminalLine(key: BigInt.zero, runs: [])],
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
  void sendText({required String text, required KeyModifiers mods}) => typed.add(text);

  @override
  void sendKey({required TerminalKey key, required KeyModifiers mods}) => typed.add(key.name);

  @override
  String textBetween({required int startRow, required int startCol, required int endRow, required int endCol}) => '';

  @override
  String visibleText() => '';

  @override
  bool click({required int row, required int col}) => false;

  @override
  bool scroll({required int lines, required int row, required int col}) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Sessions put in by the test, since real ones need a server.
class TestSessions extends SessionManager {
  TestSessions(super.store);

  final added = <LiveSession>[];

  @override
  List<LiveSession> get sessions => List.unmodifiable(added);

  @override
  Iterable<TerminalController> get terminals => added.expand((s) => s.terminals);
}

/// A connection that is always up and does nothing.
class FakeSsh implements SshSession {
  @override
  bool isConnected() => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

TerminalController fakeTerminal(String title) => TerminalController(shell: FakeShell(), title: title, sessionId: 's');

FakeShell shellOf(TerminalController t) => t.shell as FakeShell;

void main() {
  group('layout', () {
    test('split is offered in landscape and on wide screens only', () {
      expect(SplitLayout.allows(const Size(400, 800)), isFalse, reason: 'phone, upright');
      expect(SplitLayout.allows(const Size(800, 400)), isTrue, reason: 'phone, sideways');
      expect(SplitLayout.allows(const Size(840, 1200)), isTrue, reason: 'big tablet, upright');
      expect(SplitLayout.allows(const Size(700, 1000)), isFalse, reason: 'small tablet, upright');
    });
  });

  group('controller', () {
    late FocusNode focus;
    setUp(() => focus = FocusNode());
    tearDown(() => focus.dispose());

    test('typing goes to the focused pane, and back to the first on close', () {
      final a = fakeTerminal('a'), b = fakeTerminal('b');
      final split = SplitController(primary: a, primaryFocus: focus);
      expect(split.typing(shown: true), same(a));

      split.open(b);
      expect(split.secondFocused, isTrue, reason: 'a new pane takes the focus');
      split.typing(shown: true).type('ls');
      expect(shellOf(b).typed, ['ls']);
      expect(shellOf(a).typed, isEmpty);

      split.focus(second: false);
      split.typing(shown: true).type('pwd');
      expect(shellOf(a).typed, ['pwd']);

      split.focus(second: true);
      expect(split.typing(shown: false), same(a), reason: 'too narrow: only the first pane is on screen');

      split.close();
      expect(split.isOpen, isFalse);
      expect(split.typing(shown: true), same(a));
      split.dispose();
    });

    test('the divider stays within limits', () {
      final split = SplitController(primary: fakeTerminal('a'), primaryFocus: focus);
      split.setFraction(0.05);
      expect(split.fraction, SplitController.minFraction);
      split.setFraction(0.99);
      expect(split.fraction, 1 - SplitController.minFraction);
      split.dispose();
    });

    test('picked commands follow the focused pane', () {
      final a = fakeTerminal('a'), b = fakeTerminal('b');
      final split = SplitController(primary: a, primaryFocus: focus)..open(b);
      expect(split.commands(shown: true).controller, same(b));
      expect(split.commands(shown: true), same(split.commands(shown: true)), reason: 'one target per terminal');
      split.focus(second: false);
      expect(split.commands(shown: true).controller, same(a));
      split.dispose();
    });

    test('a pane whose terminal was closed elsewhere goes away', () async {
      final store = await VaultStore.open(MemoryBackend());
      final sessions = SessionManager(store);
      final split = SplitController(primary: fakeTerminal('a'), primaryFocus: focus)..open(fakeTerminal('b'));
      split.dropClosed(sessions);
      expect(split.isOpen, isFalse);
      split.dispose();
      sessions.dispose();
    });
  });

  group('panes', () {
    Future<(SplitController, SessionManager)> pump(WidgetTester tester, {Size size = const Size(1000, 500), required bool shown}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final split = SplitController(primary: fakeTerminal('left'), primaryFocus: focus);
      final store = await VaultStore.open(MemoryBackend());
      final sessions = SessionManager(store);
      await tester.pumpWidget(
        AppScope(
          vault: store,
          manager: sessions,
          child: MaterialApp(
            theme: AppTheme.build(BuiltInThemes.matteBlack),
            home: Scaffold(
              body: SplitPanes(
                split: split,
                shown: shown,
                paneFor: (terminal, focus) => Focus(
                  focusNode: focus,
                  child: Center(child: Text('pane ${terminal.title}')),
                ),
              ),
            ),
          ),
        ),
      );
      return (split, sessions);
    }

    testWidgets('two panes side by side; touch focuses, the divider drags, close goes back to one', (tester) async {
      final (split, sessions) = await pump(tester, shown: true);
      expect(find.text('pane left'), findsOneWidget);
      expect(find.byKey(SplitPanes.dividerKey), findsNothing);

      // The pane is opened directly here; the screen gets it from the picker.
      split.open(fakeTerminal('right'));
      await tester.pump();
      expect(find.text('pane right'), findsOneWidget);
      expect(tester.getCenter(find.text('pane left')).dx, lessThan(tester.getCenter(find.text('pane right')).dx));
      expect(split.secondFocused, isTrue);

      await tester.tap(find.text('pane left'));
      await tester.pump();
      expect(split.secondFocused, isFalse);
      expect(split.primaryFocus.hasFocus, isTrue);

      await tester.drag(find.byKey(SplitPanes.dividerKey), const Offset(200, 0));
      await tester.pump();
      expect(split.fraction, greaterThan(0.6));

      await tester.tap(find.byTooltip('Close this pane'));
      await tester.pump();
      expect(split.isOpen, isFalse);
      expect(find.text('pane right'), findsNothing);
      split.dispose();
      sessions.dispose();
    });

    testWidgets('only the first pane when the screen is too narrow', (tester) async {
      final (split, sessions) = await pump(tester, size: const Size(400, 800), shown: false);
      split.open(fakeTerminal('right'));
      await tester.pump();
      expect(find.text('pane left'), findsOneWidget);
      expect(find.text('pane right'), findsNothing);
      split.dispose();
      sessions.dispose();
    });
  });

  group('screen', () {
    testWidgets('sideways, Split shows a second terminal and the key bar types into the touched pane', (tester) async {
      tester.view.physicalSize = const Size(1000, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = await VaultStore.open(MemoryBackend());
      // The phone's own keyboard and the plain key bar keep this test small.
      store.updateSettings(store.settings.copyWith(keyboard: {...store.settings.keyboard, 'enabled': false}));
      final sessions = TestSessions(store);
      const host = Host(id: 'h', label: 'Web', address: 'web');
      final session = LiveSession(id: 's', host: host, ssh: FakeSsh());
      final left = fakeTerminal('left'), right = fakeTerminal('right');
      session.terminals.addAll([left, right]);
      sessions.added.add(session);
      await tester.pumpWidget(
        AppScope(
          vault: store,
          manager: sessions,
          child: MaterialApp(
            theme: AppTheme.build(BuiltInThemes.matteBlack),
            home: TerminalScreen(session: session, controller: left),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Split: two terminals side by side'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'right'));
      await tester.pumpAndSettle();
      expect(find.byKey(SplitPanes.dividerKey), findsOneWidget);
      expect(find.byTooltip('Back to one terminal'), findsOneWidget);

      // The new pane has the focus: a key from the bar goes there.
      await tester.tap(find.text('Tab'));
      await tester.pump();
      expect(shellOf(right).typed, ['tab']);
      expect(shellOf(left).typed, isEmpty);

      // Touch the left pane, then type again.
      await tester.tapAt(tester.getTopLeft(find.byKey(SplitPanes.dividerKey)) - const Offset(100, -100));
      await tester.pump();
      await tester.tap(find.text('Tab'));
      await tester.pump();
      expect(shellOf(left).typed, ['tab']);

      await tester.tap(find.byTooltip('Close this pane'));
      await tester.pumpAndSettle();
      expect(find.byKey(SplitPanes.dividerKey), findsNothing);
      await tester.pumpWidget(const SizedBox());
      sessions.dispose();
    });

    testWidgets('upright on a phone there is no Split button', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = await VaultStore.open(MemoryBackend());
      final sessions = SessionManager(store);
      final session = LiveSession(
        id: 's',
        host: const Host(id: 'h', label: 'Web', address: 'web'),
        ssh: FakeSsh(),
      );
      final left = fakeTerminal('left');
      session.terminals.add(left);
      await tester.pumpWidget(
        AppScope(
          vault: store,
          manager: sessions,
          child: MaterialApp(
            theme: AppTheme.build(BuiltInThemes.matteBlack),
            home: TerminalScreen(session: session, controller: left),
          ),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Split: two terminals side by side'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      sessions.dispose();
    });
  });
}
