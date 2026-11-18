import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/screen_cast.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/ui/computers/screen_cast_screen.dart';

/// Android's part, standing in: always allowed, never a picture.
class _Capture extends CameraCapture {
  final pieces_ = StreamController<Uint8List>.broadcast();
  int stopped = 0;

  @override
  Future<bool> start({required int bitrate}) async => true;

  @override
  Future<void> stop() async => stopped++;

  @override
  Stream<Uint8List> pieces() => pieces_.stream;
}

class _Window extends ScreenWindow {
  bool closed = false;

  @override
  ScreenWrote write(Uint8List bytes) => const ScreenWrote();

  @override
  Stream<String> get ended => const Stream.empty();

  @override
  void close() => closed = true;
}

void main() {
  const desk = Host(id: 'c', label: 'Desk', address: 'desk', computer: true);

  Future<(PhoneCast, _Window)> page(WidgetTester tester, CastKind kind, {_Capture? camera}) async {
    final store = await VaultStore.open(MemoryBackend());
    final sessions = SessionManager(store);
    addTearDown(sessions.dispose);
    final cast = PhoneCast(capture: camera ?? _Capture());
    final window = _Window();
    await tester.pumpWidget(
      AppScope(
        vault: store,
        manager: sessions,
        child: MaterialApp(
          home: ScreenCastScreen(host: desk, kind: kind, cast: cast, camera: camera, open: () async => window),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    return (cast, window);
  }

  testWidgets('the phone screen page starts and stops, and says which is the case', (tester) async {
    final (cast, window) = await page(tester, CastKind.screen);
    expect(find.text('Show this phone\'s screen on Desk'), findsOneWidget);
    expect(find.text('Back camera'), findsNothing, reason: 'only the camera has a choice of cameras');
    await tester.tap(find.text('Show the screen'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(cast.showingOn?.title, 'Desk');
    expect(find.text('This phone\'s screen is showing on Desk'), findsOneWidget);
    await tester.tap(find.text('Stop showing'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(window.closed, isTrue);
    expect(find.text('Show the screen'), findsOneWidget);
  });

  testWidgets('the camera page lets the camera be chosen before it starts, not while it runs', (tester) async {
    final camera = _Capture();
    final (cast, _) = await page(tester, CastKind.camera, camera: camera);
    expect(find.text('Use this phone as a camera for Desk'), findsOneWidget);
    await tester.tap(find.text('Front camera'));
    await tester.pump();
    expect(camera.front, isTrue);
    await tester.tap(find.text('Start the camera'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Desk is using this phone\'s camera'), findsOneWidget);
    // Running: the choice is fixed.
    await tester.tap(find.text('Back camera'));
    await tester.pump();
    expect(camera.front, isTrue);
    await tester.tap(find.text('Stop the camera'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(cast.showingOn, isNull);
    expect(camera.stopped, 1);
  });

  testWidgets('the microphone page has its own words', (tester) async {
    await page(tester, CastKind.microphone);
    expect(find.text('Microphone'), findsOneWidget);
    expect(find.text('Use this phone as a microphone for Desk'), findsOneWidget);
    await tester.tap(find.text('Start the microphone'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Desk is using this phone\'s microphone'), findsOneWidget);
    await tester.tap(find.text('Stop the microphone'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Start the microphone'), findsOneWidget);
  });

  testWidgets('a problem is said on the page', (tester) async {
    final store = await VaultStore.open(MemoryBackend());
    final sessions = SessionManager(store);
    addTearDown(sessions.dispose);
    final cast = PhoneCast(capture: _Capture());
    await tester.pumpWidget(
      AppScope(
        vault: store,
        manager: sessions,
        child: MaterialApp(
          home: ScreenCastScreen(
            host: desk,
            kind: CastKind.microphone,
            cast: cast,
            open: () async => throw Exception('The phone\'s microphone needs ffmpeg and pactl'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Start the microphone'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('needs ffmpeg and pactl'), findsOneWidget);
    expect(find.text('Start the microphone'), findsOneWidget);
  });
}
