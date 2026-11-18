import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/sessions/desktop_controller.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/ssh.dart';
import 'package:multiplex/ui/desktop/desktop_controls.dart';
import 'package:multiplex/ui/desktop/desktop_settings.dart';

/// A connection that is always up and does nothing.
class _Ssh implements SshSession {
  @override
  bool isConnected() => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets('the bar keeps to five controls; the rest lives in More', (tester) async {
    final session = LiveSession(id: 's', host: const Host(id: 'h', label: 'Desk', address: 'desk'), ssh: _Ssh());
    final controller = DesktopController(session: session, settings: const DesktopSettings(haptics: false), onConnectionLost: () {});
    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DesktopToolbar(
              title: 'Desk',
              route: 'Tailscale · direct',
              controller: controller,
              keyboardOpen: false,
              keysOpen: false,
              onBack: () => taps.add('back'),
              onKeyboard: () => taps.add('keyboard'),
              onKeys: () => taps.add('keys'),
              onPanel: () => taps.add('panel'),
              onMore: () => taps.add('more'),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(IconButton), findsNWidgets(5));
    for (final tip in ['Back', 'Keyboard', 'Shortcut keys (Super, Ctrl, Esc…)', 'Panel: workspaces, windows, media', 'More']) {
      await tester.tap(find.byTooltip(tip));
    }
    expect(taps, ['back', 'keyboard', 'keys', 'panel', 'more']);
    // Touch mode and the monitor list moved into More; the chips switch monitors.
    expect(find.byTooltip('Switch screen'), findsNothing);
    expect(find.text('Desk'), findsOneWidget);
    // Narrow phones: the bar still fits.
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
