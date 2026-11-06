import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/update/update_controller.dart';
import 'package:multiplex/update/update_errors.dart';
import 'package:multiplex/update/update_hosts.dart';

import 'fakes.dart';

void main() {
  late Directory dir;
  late VaultStore store;
  late FakeUpdateHttp http;
  late FakeUpdatePlatform platform;
  var now = DateTime.utc(2026, 11, 6, 12);

  UpdateController controller() => UpdateController(store: store, platform: platform, http: http, clock: () => now);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mpx-update');
    store = await VaultStore.open(MemoryBackend());
    http = FakeUpdateHttp()
      ..texts[UpdateHosts.latestRelease] = jsonEncode(releaseJson())
      ..texts[sumUrl] = '$apkSum  multiplex-1.2.0-arm64.apk\n'
      ..files[apkUrl] = apkBytes;
    platform = FakeUpdatePlatform(dir);
    now = DateTime.utc(2026, 11, 6, 12);
  });
  tearDown(() => dir.delete(recursive: true));

  group('checking', () {
    test('at start it checks once and offers the newer version', () async {
      final c = controller();
      await c.start();
      expect(c.phase, UpdatePhase.available);
      expect(c.release!.version.toString(), '1.2.0');
      expect(c.showCard, isTrue);
      expect(store.settings.lastUpdateCheckMs, now.millisecondsSinceEpoch);
    });

    test('a second start on the same day does not ask GitHub again', () async {
      await controller().start();
      now = now.add(const Duration(hours: 5));
      final again = controller();
      await again.start();
      expect(http.requested.where((u) => u == UpdateHosts.latestRelease), hasLength(1));
      expect(again.phase, UpdatePhase.idle);
    });

    test('turned off: no check at start, but checking by hand works', () async {
      store.updateSettings(store.settings.copyWith(autoCheckUpdates: false));
      final c = controller();
      await c.start();
      expect(http.requested, isEmpty);
      await c.check(byHand: true);
      expect(c.phase, UpdatePhase.available);
    });

    test('not on Android: nothing is checked or shown', () async {
      platform.version = null;
      final c = controller();
      await c.start();
      expect(c.supported, isFalse);
      expect(http.requested, isEmpty);
    });

    test('the same version is up to date', () async {
      platform.version = '1.2.0';
      final c = controller();
      await c.start();
      expect(c.phase, UpdatePhase.idle);
      await c.check(byHand: true);
      expect(c.phase, UpdatePhase.upToDate);
      expect(c.showCard, isFalse);
    });

    test('offline at start stays quiet and is tried again next start', () async {
      http.failText = UpdateException.offline;
      final c = controller();
      await c.start();
      expect(c.phase, UpdatePhase.idle);
      expect(store.settings.lastUpdateCheckMs, 0, reason: 'a failed check is not remembered');
      await c.check(byHand: true);
      expect(c.phase, UpdatePhase.failed);
      expect(c.error, contains('internet'));
    });

    test('Later hides the card for now; Skip hides that version until a check by hand', () async {
      final c = controller();
      await c.start();
      c.later();
      expect(c.showCard, isFalse);
      await c.check(byHand: true);
      expect(c.showCard, isTrue);
      c.skip();
      expect(c.showCard, isFalse);
      expect(store.settings.skippedUpdateVersion, '1.2.0');
      now = now.add(const Duration(days: 2));
      final next = controller();
      await next.start();
      expect(next.showCard, isFalse, reason: 'a skipped version stays hidden after a restart');
    });
  });

  group('updating', () {
    test('downloads, checks the hash and the signature, then opens the installer', () async {
      final c = controller();
      await c.start();
      await c.update();
      expect(c.phase, UpdatePhase.installing);
      expect(platform.installedPaths.single, endsWith('multiplex-1.2.0-arm64.apk'));
      expect(platform.checkedPaths, hasLength(2), reason: 'checked after download and again right before installing');
    });

    test('a file that does not match the checksum is deleted and never installed', () async {
      http.files[apkUrl] = [...apkBytes, 1];
      final c = controller();
      await c.start();
      await c.update();
      expect(c.phase, UpdatePhase.failed);
      expect(c.error, contains('checksum'));
      expect(platform.installedPaths, isEmpty);
      expect(dir.listSync(), isEmpty);
    });

    test('an APK signed by another key is deleted and never installed', () async {
      platform.apkProblem = 'otherSigner';
      final c = controller();
      await c.start();
      await c.update();
      expect(c.phase, UpdatePhase.failed);
      expect(c.error, contains('same key'));
      expect(platform.installedPaths, isEmpty);
      expect(dir.listSync(), isEmpty);
    });

    test('a broken checksum file stops before downloading', () async {
      http.texts[sumUrl] = '<html>';
      final c = controller();
      await c.start();
      await c.update();
      expect(c.phase, UpdatePhase.failed);
      expect(http.requested, isNot(contains(apkUrl)));
    });

    test('cancel stops the download and keeps the offer', () async {
      final c = controller();
      await c.start();
      http.duringDownload = c.cancelDownload;
      await c.update();
      expect(c.phase, UpdatePhase.available);
      expect(platform.installedPaths, isEmpty);
      expect(dir.listSync(), isEmpty);
    });

    test('without the install permission it asks first, then goes on when the user comes back', () async {
      platform.allowed = false;
      final c = controller();
      await c.start();
      await c.update();
      expect(c.phase, UpdatePhase.needsPermission);
      await c.openInstallPermission();
      expect(platform.permissionPages, 1);
      await c.resumed();
      expect(platform.installedPaths, isEmpty, reason: 'still not allowed');
      platform.allowed = true;
      await c.resumed();
      expect(c.phase, UpdatePhase.installing);
      expect(platform.installedPaths, hasLength(1));
    });

    test('old downloads are cleared at start', () async {
      File('${dir.path}/multiplex-1.0.0-arm64.apk').writeAsStringSync('old');
      await controller().start();
      expect(dir.listSync(), isEmpty);
    });
  });
}
