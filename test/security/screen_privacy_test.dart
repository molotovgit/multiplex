import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/multiplex_app.dart';
import 'package:multiplex/app/screen_privacy.dart';
import 'package:multiplex/data/app_settings.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/ui/settings/settings_screen.dart';

import 'harness.dart';

const _channel = MethodChannel('multiplex/privacy');

/// Every value sent to the native side, in order.
final _sent = <bool>[];

void _fakeNative() {
  _sent.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
    expect(call.method, 'setSecure');
    _sent.add((call.arguments as Map)['on'] as bool);
    return null;
  });
  ScreenPrivacy.instance = ScreenPrivacy();
}

void main() {
  setUp(_fakeNative);
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));

  group('the flag', () {
    test('is on while anything holds it, and only then', () async {
      final privacy = ScreenPrivacy.instance;
      privacy.hold();
      privacy.hold();
      privacy.release();
      expect(privacy.secure, isTrue);
      privacy.release();
      privacy.release(); // one release too many changes nothing
      await pumpEventQueue();
      expect(_sent, [true, false]);
      expect(privacy.secure, isFalse);
    });

    test('follows the setting while held', () async {
      final privacy = ScreenPrivacy.instance;
      privacy.hold();
      privacy.enabled = false;
      privacy.enabled = true;
      privacy.release();
      await pumpEventQueue();
      expect(_sent, [true, false, true, false]);
    });

    test('a missing native side is not an error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
      ScreenPrivacy.instance.hold();
      await pumpEventQueue();
      expect(ScreenPrivacy.instance.secure, isTrue);
    });

    test('is on by default, also for old vaults', () {
      expect(const AppSettings().hideScreens, isTrue);
      expect(AppSettings.fromJson(const {}).hideScreens, isTrue);
      expect(AppSettings.fromJson(const AppSettings().copyWith(hideScreens: false).toJson()).hideScreens, isFalse);
    });
  });

  testWidgets('a private screen holds the flag while shown and follows the setting', (tester) async {
    final app = await SecurityHarness.pump(tester, const PrivateScreen(child: Text('secret')));
    expect(_sent, [true]);
    app.store.updateSettings(app.store.settings.copyWith(hideScreens: false));
    await tester.pump();
    expect(_sent, [true, false]);
    app.store.updateSettings(app.store.settings.copyWith(hideScreens: true));
    await tester.pump();
    expect(_sent, [true, false, true]);
    await tester.pumpWidget(const SizedBox());
    expect(_sent, [true, false, true, false]);
    await app.finish();
  });

  testWidgets('with the setting off, a private screen never sets the flag', (tester) async {
    final app = await SecurityHarness.pump(
      tester,
      const PrivateScreen(child: Text('secret')),
      fill: (s) => s.updateSettings(s.settings.copyWith(hideScreens: false)),
    );
    expect(_sent, isEmpty);
    await app.finish();
  });

  testWidgets('the keychain tab is hidden from screenshots only while it is open', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await VaultStore.open(MemoryBackend());
    final sessions = SessionManager(store);
    await tester.pumpWidget(MultiplexApp(store: store, sessions: sessions));
    await tester.pumpAndSettle();
    expect(ScreenPrivacy.instance.secure, isFalse);

    await tester.tap(find.text('Keychain').last);
    await tester.pumpAndSettle();
    expect(ScreenPrivacy.instance.secure, isTrue);

    await tester.tap(find.text('Hosts').last);
    await tester.pumpAndSettle();
    expect(ScreenPrivacy.instance.secure, isFalse);
    expect(_sent, [true, false]);
    await tester.pump(const Duration(seconds: 2));
    sessions.dispose();
  });

  testWidgets('Settings has the switch, on by default', (tester) async {
    final app = await SecurityHarness.pump(tester, const SettingsScreen());
    final option = find.text('Hide terminals from screenshots');
    await tester.ensureVisible(option);
    expect(tester.widget<SwitchListTile>(find.ancestor(of: option, matching: find.byType(SwitchListTile))).value, isTrue);
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(app.store.settings.hideScreens, isFalse);
    await app.finish();
  });
}
