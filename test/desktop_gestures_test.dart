import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/sessions/desktop_controller.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/ssh.dart';
import 'package:multiplex/ui/desktop/desktop_gestures.dart';
import 'package:multiplex/ui/desktop/desktop_settings.dart';

/// A connection that is always up and does nothing.
class _Ssh implements SshSession {
  @override
  bool isConnected() => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late DesktopController controller;
  late DesktopViewport viewport;
  late List<String> log;
  const view = Size(800, 400);

  Future<void> pump(WidgetTester tester, {DesktopSettings settings = const DesktopSettings(haptics: false)}) async {
    final session = LiveSession(id: 's', host: const Host(id: 'h', label: 'Desk', address: 'desk'), ssh: _Ssh());
    controller = DesktopController(session: session, settings: settings, onConnectionLost: () {});
    viewport = DesktopViewport()..layout(view, controller.remoteSize, zoom: 1);
    log = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.fromSize(
            size: view,
            child: DesktopGestures(
              controller: controller,
              viewport: viewport,
              viewSize: view,
              onViewChanged: () => log.add('view'),
              onTapEmpty: () {},
              onToggleZoom: (at) => log.add('zoom'),
              onSwitchScreen: (step) => log.add('screen $step'),
              onClicked: () => log.add('click'),
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );
  }

  Future<List<TestGesture>> fingers(WidgetTester tester, List<Offset> at) async {
    final origin = tester.getTopLeft(find.byType(DesktopGestures));
    return [for (final p in at) await tester.startGesture(origin + p)];
  }

  testWidgets('a tap is one click and says so', (tester) async {
    await pump(tester);
    final g = await fingers(tester, [const Offset(300, 200)]);
    await tester.pump(const Duration(milliseconds: 60));
    await g.single.up();
    expect(log, ['click']);
  });

  testWidgets('a three-finger tap toggles the zoom and clicks nothing', (tester) async {
    await pump(tester);
    final g = await fingers(tester, const [Offset(300, 200), Offset(380, 200), Offset(460, 200)]);
    await tester.pump(const Duration(milliseconds: 80));
    for (final f in g) {
      await f.up();
    }
    expect(log, ['zoom']);
  });

  testWidgets('a three-finger swipe left goes to the next screen, right to the previous', (tester) async {
    await pump(tester);
    for (final (dx, expected) in [(-160.0, 'screen 1'), (160.0, 'screen -1')]) {
      log.clear();
      final g = await fingers(tester, const [Offset(300, 200), Offset(380, 200), Offset(460, 200)]);
      for (var i = 0; i < 8; i++) {
        for (final f in g) {
          await f.moveBy(Offset(dx / 8, 0));
        }
      }
      await tester.pump(const Duration(milliseconds: 400));
      for (final f in g) {
        await f.up();
      }
      expect(log, [expected]);
    }
  });

  testWidgets('while zoomed, a three-finger drag pans the view instead of switching screens', (tester) async {
    await pump(tester);
    viewport.zoomAround(const Offset(400, 200), 3, view, controller.remoteSize);
    final before = viewport.origin;
    final g = await fingers(tester, const [Offset(300, 200), Offset(380, 200), Offset(460, 200)]);
    for (var i = 0; i < 8; i++) {
      for (final f in g) {
        await f.moveBy(const Offset(-20, 0));
      }
    }
    await tester.pump(const Duration(milliseconds: 400));
    for (final f in g) {
      await f.up();
    }
    expect(viewport.origin.dx, lessThan(before.dx), reason: 'the picture moved with the fingers');
    expect(log.where((e) => e.startsWith('screen')), isEmpty);
  });

  testWidgets('a pinch zooms the view', (tester) async {
    await pump(tester);
    final g = await fingers(tester, const [Offset(350, 200), Offset(450, 200)]);
    for (var i = 0; i < 6; i++) {
      await g[0].moveBy(const Offset(-15, 0));
      await g[1].moveBy(const Offset(15, 0));
    }
    for (final f in g) {
      await f.up();
    }
    expect(viewport.zoom, greaterThan(1.5));
    expect(log, isNot(contains('click')));
  });
}
