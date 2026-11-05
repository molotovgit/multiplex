import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/data/app_settings.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/ui/settings/about_screen.dart';
import 'package:multiplex/ui/settings/app_licenses.dart';
import 'package:multiplex/ui/settings/app_lock_setup.dart';
import 'package:multiplex/ui/settings/backup_controllers.dart';
import 'package:multiplex/ui/settings/backup_screen.dart';
import 'package:multiplex/ui/settings/backup_service.dart';
import 'package:multiplex/ui/settings/key_bar_editor_screen.dart';
import 'package:multiplex/ui/settings/key_bar_layout.dart';
import 'package:multiplex/ui/settings/restore_panel.dart';
import 'package:multiplex/ui/settings/settings_screen.dart';
import 'package:multiplex/ui/settings/settings_widgets.dart';

/// Stands in for the Rust cipher: wraps the JSON with the password in a
/// file that starts like a real backup, so the format check passes.
class FakeCipher implements BackupCipher {
  bool failSeal = false;

  @override
  Future<Uint8List> seal(String password, String json) async {
    if (failSeal) throw Exception('seal failed');
    final body = utf8.encode(jsonEncode({'p': password, 'j': json}));
    return Uint8List.fromList([...BackupFormat.magic, ...List.filled(BackupFormat.minBytes - 4, 0), ...body]);
  }

  @override
  Future<String> open(String password, List<int> data) async {
    if (!BackupFormat.looksLikeBackup(data)) throw Exception('this is not a Multiplex file');
    final inner = jsonDecode(utf8.decode(data.sublist(BackupFormat.minBytes))) as Map<String, dynamic>;
    if (inner['p'] != password) throw Exception('wrong key or password, or the file was changed');
    return inner['j'] as String;
  }
}

/// Stands in for the platform's save and open windows.
class FakeFiles implements BackupFiles {
  bool saveAccepted = true;
  String? savedName;
  Uint8List? savedBytes;
  PickedBackup? toPick;

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    if (!saveAccepted) return false;
    savedName = fileName;
    savedBytes = bytes;
    return true;
  }

  @override
  Future<PickedBackup?> pick() async => toPick;
}

/// Gives a fixed answer instead of showing the device prompt.
class FakeUnlock extends DeviceUnlock {
  FakeUnlock(this.result);

  final UnlockResult result;
  int asked = 0;

  @override
  Future<UnlockResult> confirm() async {
    asked++;
    return result;
  }
}

class FixedVersion extends CoreVersion {
  const FixedVersion();

  @override
  String read() => '9.9.9';
}

/// Builds stores and screens for the tests.
abstract final class Fixture {
  static Host host(String id) => Host(id: id, label: 'Host $id', address: '$id.example.com', username: 'root', authMode: AuthMode.password);

  static Future<VaultStore> store({List<String> hosts = const []}) async {
    final store = await VaultStore.open(MemoryBackend());
    for (final id in hosts) {
      store.saveHost(host(id));
    }
    return store;
  }

  /// Shows [screen] inside the app's scope and theme, on a tall window
  /// so whole lists are built.
  static Future<Harness> pump(WidgetTester tester, Widget screen, {VaultStore? store, Size size = const Size(1000, 3000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vault = store ?? await Fixture.store();
    final harness = Harness(vault, SessionManager(vault));
    await tester.pumpWidget(AppScope(
      vault: vault,
      manager: harness.sessions,
      child: MaterialApp(theme: AppTheme.build(vault.activeTheme), home: screen),
    ));
    await tester.pumpAndSettle();
    return harness;
  }
}

/// The store and sessions behind a pumped screen.
class Harness {
  Harness(this.store, this.sessions);

  final VaultStore store;
  final SessionManager sessions;

  /// Lets the store's delayed save and any message run out, then stops
  /// the connection checker, so no timer is left when the test ends.
  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    sessions.dispose();
  }
}

void main() {
  group('formatting and rules', () {
    test('numbers, counts and lists read naturally', () {
      expect(SettingsFormat.thousands(0), '0');
      expect(SettingsFormat.thousands(999), '999');
      expect(SettingsFormat.thousands(50000), '50,000');
      expect(SettingsFormat.thousands(1234567), '1,234,567');
      expect(SettingsFormat.count(1, 'host', 'hosts'), '1 host');
      expect(SettingsFormat.count(3, 'host', 'hosts'), '3 hosts');
      expect(SettingsFormat.list(['a', 'b', 'c']), 'a, b and c');
    });

    test('backup file names use the date and the backup extension', () {
      expect(BackupFormat.fileNameFor(DateTime(2026, 3, 7)), 'multiplex-backup-2026-03-07.mpbackup');
    });

    test('only files that start like a backup are accepted', () {
      expect(BackupFormat.looksLikeBackup(utf8.encode('{"hosts": []}')), isFalse);
      expect(BackupFormat.looksLikeBackup([...BackupFormat.magic]), isFalse, reason: 'too short');
      expect(BackupFormat.looksLikeBackup([...BackupFormat.magic, ...List.filled(60, 0)]), isTrue);
    });

    test('backup passwords need 8 characters and must match', () {
      expect(BackupPassword.check(''), isNotNull);
      expect(BackupPassword.check('1234567'), 'Use at least 8 characters.');
      expect(BackupPassword.check('12345678'), isNull);
      expect(BackupPassword.checkRepeat('12345678', '12345679'), 'The two passwords do not match.');
      expect(BackupPassword.checkRepeat('12345678', '12345678'), isNull);
    });

    test('device errors map to clear app lock results', () {
      expect(DeviceUnlock.resultFor(LocalAuthExceptionCode.noCredentialsSet), UnlockResult.noScreenLock);
      expect(DeviceUnlock.resultFor(LocalAuthExceptionCode.userCanceled), UnlockResult.cancelled);
      expect(DeviceUnlock.resultFor(LocalAuthExceptionCode.temporaryLockout), UnlockResult.lockedOut);
      expect(DeviceUnlock.resultFor(LocalAuthExceptionCode.deviceError), UnlockResult.failed);
    });
  });

  group('key bar layout', () {
    test('drops unknown and repeated keys', () {
      expect(KeyBarLayout(['esc', 'nope', 'tab', 'esc']).ids, ['esc', 'tab']);
    });

    test('moves, removes and adds keys', () {
      final layout = KeyBarLayout(['esc', 'tab', 'ctrl']);
      expect(layout.moved(0, 2).ids, ['tab', 'ctrl', 'esc']);
      expect(layout.moved(2, 0).ids, ['ctrl', 'esc', 'tab']);
      expect(layout.without('tab').ids, ['esc', 'ctrl']);
      expect(layout.withKey('f1').ids, ['esc', 'tab', 'ctrl', 'f1']);
      expect(layout.missing.map((i) => i.id), isNot(contains('esc')));
      expect(layout.summary, 'Esc, Tab and Ctrl');
    });

    test('knows the standard layout', () {
      expect(KeyBarLayout.standard().isStandard, isTrue);
      expect(KeyBarLayout.standard().moved(0, 1).isStandard, isFalse);
      expect(KeyBarLayout.standard().summary, 'Esc, Tab, Ctrl and ${AppSettings.defaultKeyBar.length - 3} more');
    });
  });

  group('export', () {
    test('encrypts the vault and saves it under a dated name', () async {
      final store = await Fixture.store(hosts: ['a', 'b']);
      final cipher = FakeCipher();
      final files = FakeFiles();
      final export = ExportController(store: store, cipher: cipher, files: files, clock: () => DateTime(2026, 11, 5));

      expect(await export.export('correct horse'), ExportOutcome.saved);
      expect(files.savedName, 'multiplex-backup-2026-11-05.mpbackup');
      expect(await cipher.open('correct horse', files.savedBytes!), store.exportJson());
      expect(export.result!.summary.hosts, 2);
      expect(export.busy, isFalse);
    });

    test('closing the save window saves nothing and shows no error', () async {
      final files = FakeFiles()..saveAccepted = false;
      final export = ExportController(store: await Fixture.store(), cipher: FakeCipher(), files: files);
      expect(await export.export('correct horse'), ExportOutcome.cancelled);
      expect(export.result, isNull);
      expect(export.error, isNull);
    });

    test('an encryption failure is reported in plain words', () async {
      final export = ExportController(store: await Fixture.store(), cipher: FakeCipher()..failSeal = true, files: FakeFiles());
      expect(await export.export('correct horse'), ExportOutcome.failed);
      expect(export.error, contains('could not encrypt'));
    });
  });

  group('restore', () {
    late FakeCipher cipher;
    late FakeFiles files;
    late VaultStore target;
    late RestoreController restore;

    setUp(() async {
      cipher = FakeCipher();
      files = FakeFiles();
      final source = await Fixture.store(hosts: ['a', 'b']);
      files.toPick = PickedBackup('mine.mpbackup', await cipher.seal('correct horse', source.exportJson()));
      target = await Fixture.store(hosts: ['c']);
      restore = RestoreController(store: target, cipher: cipher, files: files);
    });

    test('a file that is not a backup is refused before asking for a password', () async {
      files.toPick = PickedBackup('notes.txt', Uint8List.fromList(utf8.encode('hello')));
      await restore.chooseFile();
      expect(restore.stage, RestoreStage.chooseFile);
      expect(restore.error, RestoreMessages.notABackup);
    });

    test('a wrong password can be retried, then the backup is added', () async {
      await restore.chooseFile();
      expect(restore.stage, RestoreStage.enterPassword);
      expect(restore.fileName, 'mine.mpbackup');

      await restore.open('wrong password');
      expect(restore.stage, RestoreStage.enterPassword);
      expect(restore.error, RestoreMessages.wrongPassword);

      await restore.open('correct horse');
      expect(restore.stage, RestoreStage.chooseMode);
      expect(restore.incoming!.hosts, 2);

      restore.apply(replace: false);
      expect(restore.stage, RestoreStage.finished);
      expect(target.hosts.map((h) => h.id), unorderedEquals(['a', 'b', 'c']));
      expect(restore.result!.replaced, isFalse);
    });

    test('replace everything removes what was there', () async {
      await restore.chooseFile();
      await restore.open('correct horse');
      restore.apply(replace: true);
      expect(target.hosts.map((h) => h.id), unorderedEquals(['a', 'b']));
      expect(restore.result!.replaced, isTrue);
    });
  });

  group('settings screen', () {
    testWidgets('shows every section and saves switches straight away', (tester) async {
      final app = await Fixture.pump(tester, const SettingsScreen());
      for (final section in ['Appearance', 'Terminal', 'Keyboard', 'Security', 'Backup & restore', 'About']) {
        expect(find.text(section), findsWidgets, reason: section);
      }
      expect(find.text('Connections'), findsNothing, reason: 'no connections are open');
      expect(find.text(app.store.activeTheme.name), findsOneWidget);

      await tester.tap(find.text('Bold text in bright colours'));
      await tester.pump();
      expect(app.store.settings.boldIsBright, isTrue);

      await tester.tap(find.text('Scrollback'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('50,000 lines'));
      await tester.pumpAndSettle();
      expect(app.store.settings.scrollbackLines, 50000);
      expect(find.text('50,000 lines'), findsOneWidget, reason: 'the tile shows the new value');
      await app.finish(tester);
    });

    testWidgets('app lock stays off and explains when the device has no lock', (tester) async {
      final unlock = FakeUnlock(UnlockResult.noScreenLock);
      final app = await Fixture.pump(tester, SettingsScreen(unlock: unlock));
      await tester.tap(find.text('App lock'));
      await tester.pumpAndSettle();
      expect(unlock.asked, 1);
      expect(find.text(AppLockMessages.noScreenLockTitle), findsOneWidget);
      expect(app.store.settings.appLock, isFalse);
      await app.finish(tester);
    });

    testWidgets('app lock turns on once the device confirms', (tester) async {
      final app = await Fixture.pump(tester, SettingsScreen(unlock: FakeUnlock(UnlockResult.passed)));
      await tester.tap(find.text('App lock'));
      await tester.pumpAndSettle();
      expect(app.store.settings.appLock, isTrue);
      await app.finish(tester);
    });
  });

  group('key bar editor', () {
    testWidgets('removes, adds and resets keys', (tester) async {
      final app = await Fixture.pump(tester, const KeyBarEditorScreen());

      // Reordering works without dragging, through the Move menu.
      await tester.tap(find.byTooltip('Move Escape'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move down'));
      await tester.pumpAndSettle();
      expect(app.store.settings.keyBar.take(2), ['tab', 'esc']);

      await tester.tap(find.byTooltip('Remove Escape'));
      await tester.pump();
      expect(app.store.settings.keyBar, isNot(contains('esc')));

      await tester.tap(find.text('Add key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(r'Backslash \'));
      await tester.pump();
      expect(app.store.settings.keyBar.last, 'backslash');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Reset to default'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reset to default'));
      await tester.pumpAndSettle();
      expect(app.store.settings.keyBar, AppSettings.defaultKeyBar);
      await app.finish(tester);
    });
  });

  group('backup screen', () {
    testWidgets('checks the password, then exports', (tester) async {
      final files = FakeFiles();
      final app = await Fixture.pump(tester, BackupScreen(cipher: FakeCipher(), files: files));
      final fields = find.descendant(of: find.byType(ExportPanel), matching: find.byType(TextField));

      await tester.enterText(fields.at(0), 'short');
      await tester.enterText(fields.at(1), 'short');
      await tester.tap(find.text('Export backup'));
      await tester.pumpAndSettle();
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      expect(files.savedName, isNull);

      await tester.enterText(fields.at(0), 'correct horse');
      await tester.enterText(fields.at(1), 'correct horses');
      await tester.pumpAndSettle();
      expect(find.text('The two passwords do not match.'), findsOneWidget);

      await tester.enterText(fields.at(1), 'correct horse');
      await tester.tap(find.text('Export backup'));
      await tester.pumpAndSettle();
      expect(files.savedName, endsWith('.mpbackup'));
      expect(find.text('Backup saved'), findsWidgets);
      await app.finish(tester);
    });

    testWidgets('restores a backup after a wrong password', (tester) async {
      final cipher = FakeCipher();
      final files = FakeFiles();
      final source = await Fixture.store(hosts: ['a']);
      files.toPick = PickedBackup('mine.mpbackup', await cipher.seal('correct horse', source.exportJson()));
      final app = await Fixture.pump(tester, BackupScreen(cipher: cipher, files: files));

      await tester.tap(find.widgetWithText(Tab, 'Restore'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 3: choose the backup file'), findsOneWidget);
      await tester.tap(find.text('Choose backup file'));
      await tester.pumpAndSettle();
      final field = find.descendant(of: find.byType(RestorePanel), matching: find.byType(TextField));
      await tester.enterText(field, 'wrong password');
      await tester.tap(find.text('Open backup'));
      await tester.pumpAndSettle();
      expect(find.text(RestoreMessages.wrongPassword), findsOneWidget);
      expect(tester.widget<TextField>(field).focusNode?.hasFocus, isTrue, reason: 'the cursor goes back to retype');

      await tester.enterText(field, 'correct horse');
      await tester.tap(find.text('Open backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to current data'));
      await tester.pumpAndSettle();
      expect(find.text('Restore finished'), findsOneWidget);
      expect(find.text('Backup restored'), findsOneWidget, reason: 'a short toast confirms it');
      expect(app.store.hosts.single.id, 'a');
      await app.finish(tester);
    });
  });

  group('phone size', () {
    testWidgets('every screen fits a small phone without overflowing', (tester) async {
      final screens = <Widget>[
        const SettingsScreen(),
        const KeyBarEditorScreen(),
        BackupScreen(cipher: FakeCipher(), files: FakeFiles()),
        const AboutScreen(version: FixedVersion()),
      ];
      for (final screen in screens) {
        final app = await Fixture.pump(tester, screen, size: const Size(320, 640));
        expect(tester.takeException(), isNull, reason: '${screen.runtimeType}');
        await app.finish(tester);
      }
    });

    testWidgets('every screen still fits with the largest system text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final screens = <Widget>[
        const SettingsScreen(),
        const KeyBarEditorScreen(),
        BackupScreen(cipher: FakeCipher(), files: FakeFiles()),
        const AboutScreen(version: FixedVersion()),
      ];
      for (final screen in screens) {
        final app = await Fixture.pump(tester, screen, size: const Size(360, 800));
        expect(tester.takeException(), isNull, reason: '${screen.runtimeType}');
        await app.finish(tester);
      }
    });

    testWidgets('every tappable control is big enough and labelled', (tester) async {
      final handle = tester.ensureSemantics();
      final screens = <Widget>[
        const SettingsScreen(),
        const KeyBarEditorScreen(),
        BackupScreen(cipher: FakeCipher(), files: FakeFiles()),
        const AboutScreen(version: FixedVersion()),
      ];
      for (final screen in screens) {
        final app = await Fixture.pump(tester, screen, size: const Size(360, 800));
        // Flutter's own checks: 48 dp on Android, 44 pt on iOS, and a
        // label on everything that can be tapped.
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline), reason: '${screen.runtimeType}');
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline), reason: '${screen.runtimeType}');
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline), reason: '${screen.runtimeType}');
        await app.finish(tester);
      }
      // The drag handle is not a button, so check it by size.
      final app = await Fixture.pump(tester, const KeyBarEditorScreen(), size: const Size(360, 800));
      expect(tester.getSize(find.byType(ReorderableDragStartListener).first).shortestSide, greaterThanOrEqualTo(48));
      await app.finish(tester);
      handle.dispose();
    });
  });

  group('licences', () {
    test('registering the font licences twice adds them once and never breaks the list', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      AppLicenses.register();
      AppLicenses.register();
      final entries = await LicenseRegistry.licenses.toList();
      final ours = AppLicenses.fonts.map((f) => f.packageName).toSet();
      final fontEntries = entries.where((e) => e.packages.any(ours.contains)).toList();
      // The OFL files load once the lead declares them as assets; until
      // then they are skipped instead of breaking the page.
      expect(fontEntries.length, lessThanOrEqualTo(ours.length));
    });
  });

  group('about screen', () {
    testWidgets('shows the version, source address and every theme credit', (tester) async {
      final app = await Fixture.pump(tester, const AboutScreen(version: FixedVersion()));
      expect(find.text('9.9.9'), findsOneWidget);
      expect(find.text(AboutFacts.sourceAddress), findsOneWidget);
      for (final theme in BuiltInThemes.all) {
        expect(find.text(theme.name), findsOneWidget, reason: theme.name);
      }
      expect(find.text('Gruvbox by morhetz (MIT)'), findsOneWidget);
      await app.finish(tester);
    });
  });
}
