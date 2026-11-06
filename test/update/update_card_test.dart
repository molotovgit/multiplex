import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/ui/update/update_card.dart';
import 'package:multiplex/ui/update/update_section.dart';
import 'package:multiplex/update/update_controller.dart';
import 'package:multiplex/update/update_hosts.dart';
import 'package:multiplex/update/update_scope.dart';

import 'fakes.dart';

void main() {
  late Directory dir;
  late VaultStore store;
  late SessionManager sessions;
  late FakeUpdateHttp http;
  late FakeUpdatePlatform platform;
  late UpdateController updates;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mpx-update-ui');
    store = await VaultStore.open(MemoryBackend());
    sessions = SessionManager(store);
    http = FakeUpdateHttp()
      ..texts[UpdateHosts.latestRelease] = jsonEncode(releaseJson(body: 'Line one\n${List.filled(40, 'more notes').join('\n')}'))
      ..texts[sumUrl] = apkSum
      ..files[apkUrl] = apkBytes;
    platform = FakeUpdatePlatform(dir);
    updates = UpdateController(store: store, platform: platform, http: http, clock: () => DateTime.utc(2026, 11, 6));
  });
  tearDown(() async {
    sessions.dispose();
    await dir.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester, Widget body) async {
    await tester.runAsync(updates.start);
    await tester.pumpWidget(AppScope(
      vault: store,
      manager: sessions,
      child: MaterialApp(
        theme: AppTheme.build(store.activeTheme),
        builder: (context, child) => UpdateScope(controller: updates, child: child!),
        home: Scaffold(body: ListView(children: [body])),
      ),
    ));
    await tester.pump();
  }

  /// Lets the vault's delayed save run before the test ends.
  Future<void> settle(WidgetTester tester) => tester.pump(VaultStore.saveDelay * 2);

  testWidgets('the banner offers the new version with its notes and three choices', (tester) async {
    await pump(tester, const UpdateBanner());
    expect(find.text('Version 1.2.0 is available'), findsOneWidget);
    expect(find.text('You have 1.1.0'), findsOneWidget);
    expect(find.textContaining('Line one'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Skip this version'), findsOneWidget);
    // Long notes scroll inside the card instead of growing it.
    expect(tester.getSize(find.byType(SingleChildScrollView)).height, lessThanOrEqualTo(UpdateCard.notesHeight));

    await tester.tap(find.text('Later'));
    await tester.pump();
    expect(find.text('Version 1.2.0 is available'), findsNothing);
    await settle(tester);
  });

  testWidgets('Skip this version hides it and remembers the choice', (tester) async {
    await pump(tester, const UpdateBanner());
    await tester.tap(find.text('Skip this version'));
    await tester.pump();
    expect(find.text('Version 1.2.0 is available'), findsNothing);
    expect(store.settings.skippedUpdateVersion, '1.2.0');
    await settle(tester);
  });

  testWidgets('Update without the install permission explains it and opens the settings page', (tester) async {
    platform.allowed = false;
    await pump(tester, const UpdateBanner());
    await tester.runAsync(() async {
      await tester.tap(find.text('Update'));
      while (updates.busy) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(find.text('Allow Multiplex to install the update'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await tester.pump();
    expect(platform.permissionPages, 1);
  });

  testWidgets('a failed download shows the reason and a way to try again', (tester) async {
    http.files[apkUrl] = [1, 2, 3];
    await pump(tester, const UpdateBanner());
    await tester.runAsync(updates.update);
    await tester.pump();
    expect(find.textContaining('does not match the checksum'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(platform.installedPaths, isEmpty);
  });

  testWidgets('nothing is shown where updates are not offered', (tester) async {
    platform.version = null;
    await pump(tester, const Column(children: [UpdateBanner(), UpdateSection()]));
    expect(find.byType(UpdateCard), findsNothing);
    expect(find.text('Check for updates'), findsNothing);
  });

  testWidgets('About: check by hand says up to date, and the switch turns automatic checks off', (tester) async {
    platform.version = '1.2.0';
    await pump(tester, const UpdateSection());
    expect(find.text('Version 1.2.0 installed'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Check for updates'));
      while (updates.busy) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(find.text('You have the newest version (1.2.0)'), findsOneWidget);

    await tester.tap(find.text('Check for updates automatically'));
    await tester.pump();
    expect(store.settings.autoCheckUpdates, isFalse);
    await settle(tester);
  });

  testWidgets('About shows a skipped version again after a check by hand', (tester) async {
    store.updateSettings(store.settings.copyWith(skippedUpdateVersion: '1.2.0'));
    await pump(tester, const UpdateSection());
    expect(find.byType(UpdateCard), findsNothing);
    await tester.runAsync(() => updates.check(byHand: true));
    await tester.pump();
    expect(find.text('Version 1.2.0 is available'), findsOneWidget);
  });
}
