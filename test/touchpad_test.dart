import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/key_target.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/sessions/touchpad_controller.dart';
import 'package:multiplex/src/rust/api/touchpad.dart';
import 'package:multiplex/ui/computers/touchpad_screen.dart';
import 'package:multiplex/ui/desktop/desktop_keys.dart';

/// A touchpad that writes down what it was told.
class _Pipe implements TouchpadPipe {
  final log = <String>[];
  final _ended = StreamController<String>.broadcast();
  bool closed = false;

  @override
  void moveBy(double dx, double dy) => log.add('move ${dx.toStringAsFixed(1)} ${dy.toStringAsFixed(1)}');

  @override
  void scroll(double dx, double dy) => log.add('scroll ${dx.toStringAsFixed(1)} ${dy.toStringAsFixed(1)}');

  @override
  void button(TouchpadButton button, bool down) => log.add('${button.name} ${down ? 'down' : 'up'}');

  @override
  void key(int code, bool down) => log.add('key $code ${down ? 'down' : 'up'}');

  @override
  void paste(String text) => log.add('paste $text');

  @override
  void releaseAll() => log.add('release all');

  @override
  Stream<String> get ended => _ended.stream;

  @override
  void close() => closed = true;

  void end(String reason) => _ended.add(reason);
}

void main() {
  late _Pipe pipe;

  Future<void> open(WidgetTester tester, {Future<TouchpadPipe> Function()? opener, Size size = const Size(400, 800)}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    pipe = _Pipe();
    final store = await VaultStore.open(MemoryBackend());
    final sessions = SessionManager(store);
    addTearDown(sessions.dispose);
    await tester.pumpWidget(
      AppScope(
        vault: store,
        manager: sessions,
        child: MaterialApp(
          home: TouchpadScreen(title: 'Desk', open: opener ?? () async => pipe),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Offset at(WidgetTester tester, [Offset by = Offset.zero]) => tester.getCenter(find.byType(TouchpadSurface)) + by;

  testWidgets('a tap is a left click; a drag moves the pointer, faster when quick', (tester) async {
    await open(tester);
    await tester.tapAt(at(tester));
    expect(pipe.log, ['left down', 'left up']);
    pipe.log.clear();

    final finger = await tester.startGesture(at(tester));
    await finger.moveBy(const Offset(12, 0)); // past the slop: this one starts the move
    await finger.moveBy(const Offset(2, 0)); // slow
    await finger.moveBy(const Offset(36, 0)); // quick
    await finger.up();
    expect(pipe.log.length, 3);
    final slow = double.parse(pipe.log[1].split(' ')[1]);
    final quick = double.parse(pipe.log[2].split(' ')[1]);
    expect(slow / 2, closeTo(2.2 * (1 + 2 / 18), 0.1), reason: 'slow is nearly one to one with the base gain');
    expect(quick / 36, greaterThan(slow / 2 * 2), reason: 'a quick stroke goes much further per finger pixel');
    expect(pipe.log.any((l) => l.contains('down')), isFalse, reason: 'a drag is not a click');
  });

  testWidgets('two fingers scroll; a two-finger tap is the right button, three the middle', (tester) async {
    await open(tester);
    final a = await tester.startGesture(at(tester, const Offset(-30, 0)));
    final b = await tester.startGesture(at(tester, const Offset(30, 0)));
    await a.moveBy(const Offset(0, 20));
    await b.moveBy(const Offset(0, 20));
    await a.moveBy(const Offset(0, 10));
    await b.moveBy(const Offset(0, 10));
    await a.up();
    await b.up();
    expect(pipe.log.where((l) => l.startsWith('scroll')), isNotEmpty);
    expect(
      pipe.log.every((l) => l.startsWith('scroll 0.0 -') || l.startsWith('scroll -0.0 -')),
      isTrue,
      reason: 'fingers down the pad: the page goes up, as on a phone',
    );
    pipe.log.clear();

    final c = await tester.startGesture(at(tester, const Offset(-30, 0)));
    final d = await tester.startGesture(at(tester, const Offset(30, 0)));
    await c.up();
    await d.up();
    expect(pipe.log, ['right down', 'right up']);
    pipe.log.clear();

    final fingers = [
      for (final dx in [-40.0, 0.0, 40.0]) await tester.startGesture(at(tester, Offset(dx, 0))),
    ];
    for (final f in fingers) {
      await f.up();
    }
    expect(pipe.log, ['middle down', 'middle up']);
  });

  testWidgets('holding still, then moving, drags with the button held', (tester) async {
    await open(tester);
    final finger = await tester.startGesture(at(tester));
    await tester.pump(const Duration(milliseconds: 500));
    expect(pipe.log, ['left down']);
    expect(find.textContaining('Dragging'), findsOneWidget);
    await finger.moveBy(const Offset(30, 0));
    await finger.up();
    await tester.pump();
    expect(pipe.log.first, 'left down');
    expect(pipe.log.last, 'left up');
    expect(pipe.log.any((l) => l.startsWith('move')), isTrue);
  });

  testWidgets('the buttons under the thumb hold while pressed', (tester) async {
    await open(tester);
    final thumb = await tester.startGesture(tester.getCenter(find.text('Right click')));
    expect(pipe.log, ['right down']);
    await thumb.up();
    expect(pipe.log, ['right down', 'right up']);
  });

  testWidgets('keys: the key bar and the keyboard type on the computer', (tester) async {
    // Wide enough that the key bar shows Esc and Tab without scrolling.
    await open(tester, size: const Size(760, 800));
    await tester.tap(find.text('Esc'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(pipe.log, ['key ${LinuxKey.esc} down', 'key ${LinuxKey.esc} up']);
    pipe.log.clear();
    // Super, then a key: Super is held around it, once.
    await tester.tap(find.text('Super'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Tab'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(pipe.log, ['key ${LinuxKey.leftMeta} down', 'key ${LinuxKey.tab} down', 'key ${LinuxKey.tab} up', 'key ${LinuxKey.leftMeta} up']);
    pipe.log.clear();
    await tester.tap(find.byTooltip('Keyboard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('q'));
    await tester.pump();
    expect(pipe.log, ['key 16 down', 'key 16 up']);
  });

  test('typing: the US keyboard types, anything else is pasted', () async {
    final pipe = _Pipe();
    final pad = TouchpadController(() async => pipe);
    await pad.start();
    pad.type('aB');
    expect(pipe.log, ['key 30 down', 'key 30 up', 'key ${LinuxKey.leftShift} down', 'key 48 down', 'key 48 up', 'key ${LinuxKey.leftShift} up']);
    pipe.log.clear();
    pad.type('žluťoučký');
    expect(pipe.log, ['paste žluťoučký']);
    pad.dispose();
    expect(pipe.log.last, 'release all');
    expect(pipe.closed, isTrue);
    expect(pad.mods.values.every((m) => m == ModState.off), isTrue);
  });

  testWidgets('a computer without the package says so and can be asked again', (tester) async {
    var tries = 0;
    final good = _Pipe();
    await open(
      tester,
      opener: () async {
        if (tries++ == 0) throw Exception('This computer does not have the Multiplex package (or it is an old one). Install it there, then try again.');
        return good;
      },
    );
    expect(find.textContaining('does not have the Multiplex package'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byType(TouchpadSurface), findsOneWidget);
    // The computer's side stopping is shown, with its reason.
    good.end('The connection to the computer was lost.');
    await tester.pumpAndSettle();
    expect(find.text('The connection to the computer was lost.'), findsOneWidget);
  });
}
