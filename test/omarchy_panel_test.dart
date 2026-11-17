import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/desk_controller.dart';
import 'package:multiplex/sessions/error_text.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/desk_types.dart';
import 'package:multiplex/ui/computers/omarchy_panel.dart';

/// A computer that remembers what it was asked and answers with [now].
class _Link implements DeskLink {
  _Link(this.now);

  DeskState now;
  final asked = <DeskAction>[];
  final changes = StreamController<DeskState>.broadcast();
  bool stopped = false;
  Object? failWith;

  @override
  Future<DeskState> state() async {
    if (failWith != null) throw failWith!;
    return now;
  }

  @override
  Future<DeskState> act(DeskAction action) async {
    if (failWith != null) throw failWith!;
    asked.add(action);
    return now;
  }

  @override
  Future<List<DeskBinding>> bindings() async => const [
    DeskBinding(keys: 'SUPER + SPACE', title: 'Omarchy menu', run: true),
    DeskBinding(keys: 'SUPER + RETURN', title: 'Terminal', run: true),
    DeskBinding(keys: 'SUPER SHIFT + RETURN', title: 'Browser', run: true),
    DeskBinding(keys: 'SUPER + W / SUPER + Q', title: 'Close window', run: true),
    DeskBinding(keys: 'SUPER + C', title: 'Universal copy', run: false),
  ];

  @override
  Future<(Stream<DeskState>, void Function())> watch() async => (changes.stream, () => stopped = true);
}

DeskState _state({int active = 2, bool playing = false, bool floating = false}) => DeskState(
  monitors: [
    DeskMonitor(
      name: 'DP-1',
      focused: true,
      slots: [for (var i = 1; i <= 10; i++) DeskSlot(slot: i, windows: i <= 3 ? i : 0, active: i == active)],
    ),
    DeskMonitor(
      name: 'HDMI-A-1',
      focused: false,
      slots: [for (var i = 1; i <= 10; i++) DeskSlot(slot: i, windows: 0, active: i == 1)],
    ),
  ],
  window: DeskWindow(title: 'notes.md', class_: 'foot', floating: floating, fullscreen: false),
  media: DeskMedia(player: 'Spotify', playing: playing, title: 'A song', artist: 'A band'),
  volume: const DeskVolume(percent: 40, muted: false),
);

void main() {
  late _Link link;
  late DeskController controller;
  late List<String> pins;

  Future<void> pump(WidgetTester tester, {Size size = const Size(400, 900)}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    link = _Link(_state());
    controller = DeskController(link);
    pins = [];
    addTearDown(controller.dispose);
    final store = await VaultStore.open(MemoryBackend());
    final sessions = SessionManager(store);
    addTearDown(sessions.dispose);
    await tester.pumpWidget(
      AppScope(
        vault: store,
        manager: sessions,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: StatefulBuilder(
                builder: (context, setState) => OmarchyPanel(controller: controller, pins: pins, onPinsChanged: (next) => setState(() => pins = next)),
              ),
            ),
          ),
        ),
      ),
    );
    await controller.start();
    await tester.pumpAndSettle();
  }

  testWidgets('workspaces: tap shows one, hold sends the window there', (tester) async {
    await pump(tester);
    expect(find.bySemanticsLabel('Workspace 2, 2 windows'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Workspace 4, empty'));
    await tester.pumpAndSettle();
    expect(link.asked.single, const DeskAction.workspace(slot: 4, monitor: 'DP-1'));
    await tester.longPress(find.bySemanticsLabel('Workspace 7, empty'));
    await tester.pumpAndSettle();
    expect(link.asked.last, const DeskAction.moveWindow(slot: 7));
    expect(find.text('Moved the window to workspace 7'), findsOneWidget);
  });

  testWidgets('another monitor gets the focus from its chip', (tester) async {
    await pump(tester);
    await tester.tap(find.text('HDMI-A-1'));
    await tester.pumpAndSettle();
    expect(link.asked.single, const DeskAction.focusMonitor(name: 'HDMI-A-1'));
  });

  testWidgets('arrows move the focus, or the window after the switch between them', (tester) async {
    await pump(tester);
    expect(find.text('notes.md'), findsOneWidget);
    await tester.tap(find.byTooltip('Focus the window on the left'));
    await tester.tap(find.byTooltip('The arrows move the focus: switch to moving the window'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move the window on the left'));
    await tester.tap(find.text('Close'));
    await tester.tap(find.text('Float'));
    await tester.pumpAndSettle();
    expect(link.asked, const [
      DeskAction.focus(direction: DeskDirection.left),
      DeskAction.swap(direction: DeskDirection.left),
      DeskAction.close(),
      DeskAction.float(),
    ]);
  });

  testWidgets('launchers are the usual four that exist, and media keys work', (tester) async {
    await pump(tester);
    // The file manager is not among this computer's bindings, so three show.
    for (final title in ['Omarchy menu', 'Terminal', 'Browser', 'All shortcuts']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    await tester.tap(find.text('Terminal'));
    await tester.tap(find.byTooltip('Play'));
    await tester.tap(find.byTooltip('Volume up'));
    await tester.pumpAndSettle();
    expect(link.asked, const [DeskAction.bind(keys: 'SUPER + RETURN'), DeskAction.playPause(), DeskAction.volumeUp()]);
  });

  testWidgets('the list of all shortcuts searches, runs and pins', (tester) async {
    await pump(tester);
    await tester.tap(find.text('All shortcuts'));
    await tester.pumpAndSettle();
    expect(find.text('Universal copy'), findsOneWidget);
    await tester.enterText(find.byType(SearchBar), 'close');
    await tester.pumpAndSettle();
    expect(find.text('Universal copy'), findsNothing);
    await tester.tap(find.byTooltip('Pin Close window to the panel'));
    await tester.pumpAndSettle();
    expect(pins, [...OmarchyPanel.usualPins, 'SUPER + W / SUPER + Q']);
    // The row in the list (the new pin on the panel behind has the same words).
    await tester.tap(find.widgetWithText(ListTile, 'Close window'));
    await tester.pumpAndSettle();
    expect(link.asked.single, const DeskAction.bind(keys: 'SUPER + W / SUPER + Q'));
    // The sheet closed and the new pin is on the panel.
    expect(find.byType(SearchBar), findsNothing);
    expect(find.text('Close window'), findsOneWidget);
  });

  testWidgets('changes on the computer show by themselves', (tester) async {
    await pump(tester);
    link.changes.add(_state(active: 5, playing: true));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.bySemanticsLabel('Workspace 5, empty')), isSemantics(isSelected: true));
    expect(tester.getSemantics(find.bySemanticsLabel('Workspace 2, 2 windows')), isSemantics(isSelected: false));
    expect(find.byTooltip('Pause'), findsOneWidget);
  });

  testWidgets('a computer that cannot answer says why and can be asked again', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    link = _Link(_state())..failWith = Exception('This computer does not have the Multiplex package (or it is an old one). Install it there, then try again.');
    controller = DeskController(link);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OmarchyPanel(controller: controller, pins: const [], onPinsChanged: (_) {}),
        ),
      ),
    );
    await controller.start();
    await tester.pumpAndSettle();
    expect(find.textContaining('does not have the Multiplex package'), findsOneWidget);
    link.failWith = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('notes.md'), findsOneWidget);
  });

  testWidgets('a wide panel puts the ten workspaces on one row', (tester) async {
    await pump(tester, size: const Size(900, 500));
    final first = tester.getTopLeft(find.bySemanticsLabel('Workspace 1, 1 window'));
    final last = tester.getTopLeft(find.bySemanticsLabel('Workspace 10, empty'));
    expect(first.dy, last.dy);
    expect(tester.takeException(), isNull);
  });

  test('the controller stops listening when it is closed', () async {
    final link = _Link(_state());
    final controller = DeskController(link);
    await controller.start();
    controller.dispose();
    expect(link.stopped, isTrue);
  });

  test('core errors read as sentences', () {
    expect(errorSentence('AnyhowException(the computer has no binding for X)'), 'The computer has no binding for X');
    expect(errorSentence(Exception('It broke (badly)')), 'It broke (badly)');
    expect(errorSentence('AnyhowException(Refused.\n\nStack backtrace:\n 0: x)'), 'Refused.');
    expect(errorSentence(''), 'Something went wrong.');
  });
}
