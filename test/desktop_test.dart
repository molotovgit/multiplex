import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/src/rust/api/terminal_types.dart';
import 'package:multiplex/ui/desktop/desktop_gestures.dart';
import 'package:multiplex/ui/desktop/desktop_key_sink.dart';
import 'package:multiplex/ui/desktop/desktop_keys.dart';
import 'package:multiplex/ui/desktop/desktop_settings.dart';

void main() {
  group('typing on a US layout', () {
    test('letters, capitals, digits and symbols', () {
      expect(UsLayout.stroke('a')!.code, 30);
      expect(UsLayout.stroke('A')!.shift, isTrue);
      expect(UsLayout.stroke('1')!.code, 2);
      expect(UsLayout.stroke('!')!.code, 2);
      expect(UsLayout.stroke('!')!.shift, isTrue);
      expect(UsLayout.stroke('?')!.code, 53);
      expect(UsLayout.stroke('\n')!.code, LinuxKey.enter);
    });

    test('text it cannot type goes through the clipboard', () {
      expect(UsLayout.canType('ls -la ~/Code'), isTrue);
      expect(UsLayout.canType('Привет'), isFalse);
      expect(UsLayout.canType('café'), isFalse);
    });

    test('F-keys', () {
      expect(LinuxKey.function(1), 59);
      expect(LinuxKey.function(10), 68);
      expect(LinuxKey.function(12), 88);
    });
  });

  group('viewport', () {
    const view = Size(400, 800);
    const remote = Size(1600, 900);

    test('fits and maps both ways', () {
      final v = DesktopViewport()..layout(view, remote, zoom: 1);
      expect(v.k, closeTo(0.25, 1e-9));
      final p = v.toScreen(const Offset(800, 450));
      expect(v.toRemote(p).dx, closeTo(800, 1e-6));
      expect(p.dx, closeTo(200, 1e-6), reason: 'centred');
    });

    test('pinch keeps the point under the fingers', () {
      final v = DesktopViewport()..layout(view, remote, zoom: 1);
      const focal = Offset(200, 400);
      final before = v.toRemote(focal);
      v.zoomAround(focal, 2, view, remote);
      expect(v.zoom, closeTo(2, 1e-9));
      expect(v.toRemote(focal).dx, closeTo(before.dx, 1e-6));
    });

    test('never zooms out past the whole screen', () {
      final v = DesktopViewport()..layout(view, remote, zoom: 1);
      v.zoomAround(const Offset(10, 10), 0.2, view, remote);
      expect(v.zoom, closeTo(1, 1e-9));
    });
  });

  test('the built-in keyboard maps to Linux keys', () {
    expect(DesktopKeySink.codeFor(TerminalKey.enter), LinuxKey.enter);
    expect(DesktopKeySink.codeFor(TerminalKey.f5), 63);
    expect(DesktopKeySink.codeFor(TerminalKey.f12), 88);
    expect(DesktopKeySink.modsFor(const KeyModifiers(ctrl: true, alt: false, shift: true)), [LinuxKey.leftCtrl, LinuxKey.leftShift]);
  });

  test('settings fall back to defaults and keep what they know', () {
    final s = DesktopSettings.fromJson({'touch': 'direct', 'screen': 'nonsense', 'textSize': 9});
    expect(s.touch, DesktopTouchMode.direct);
    expect(s.screen, DesktopScreenMode.mirror, reason: 'like gliff: the real monitor by default');
    expect(s.textSize, 2.0);
    expect(DesktopSettings.fromJson(s.toJson()).touch, DesktopTouchMode.direct);
  });
}
