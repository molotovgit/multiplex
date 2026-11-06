import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/app_settings.dart';
import 'package:multiplex/update/apk_checksum.dart';
import 'package:multiplex/update/app_version.dart';
import 'package:multiplex/update/release_info.dart';
import 'package:multiplex/update/update_errors.dart';
import 'package:multiplex/update/update_hosts.dart';
import 'package:multiplex/update/update_http.dart';
import 'package:multiplex/update/update_schedule.dart';

import 'fakes.dart';

void main() {
  group('version', () {
    test('reads tags and the app version, ignoring the build number', () {
      expect(AppVersion.tryParse('v1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.tryParse('1.2.3+7'), const AppVersion(1, 2, 3));
      for (final bad in ['1.2', 'v1.2.3-beta', 'nightly', '', 'v1.2.3.4', 'x1.2.3']) {
        expect(AppVersion.tryParse(bad), isNull, reason: bad);
      }
    });

    test('compares number by number, not as text', () {
      expect(AppVersion.tryParse('1.10.0')!.isNewerThan(AppVersion.tryParse('1.9.9')!), isTrue);
      expect(AppVersion.tryParse('2.0.0')!.isNewerThan(AppVersion.tryParse('1.99.99')!), isTrue);
      expect(AppVersion.tryParse('1.0.1')!.isNewerThan(AppVersion.tryParse('1.0.1')!), isFalse);
      expect(AppVersion.tryParse('1.0.0')!.isNewerThan(AppVersion.tryParse('1.0.1')!), isFalse);
    });
  });

  group('release JSON', () {
    test('reads the version, notes and both file links', () {
      final r = ReleaseParser.parse(releaseJson())!;
      expect(r.version.toString(), '1.2.0');
      expect(r.notes, 'Faster file copy.');
      expect(r.apkUrl, apkUrl);
      expect(r.checksumUrl, sumUrl);
      expect(r.apkSize, apkBytes.length);
    });

    test('pre-releases, drafts and odd tags are not offered', () {
      expect(ReleaseParser.parse(releaseJson(prerelease: true)), isNull);
      expect(ReleaseParser.parse(releaseJson(draft: true)), isNull);
      expect(ReleaseParser.parse({...releaseJson(), 'tag_name': 'v1.2.0-rc1'}), isNull);
      expect(ReleaseParser.parse({...releaseJson(), 'tag_name': '1.2.0'}), isNull);
    });

    test('a release without the checksum file or with a foreign link is refused', () {
      expect(() => ReleaseParser.parse(releaseJson(withSum: false)), throwsA(isA<ReleaseFormatException>()));
      expect(() => ReleaseParser.parse(releaseJson(apkLink: 'https://evil.example/multiplex.apk')), throwsA(isA<ReleaseFormatException>()));
      expect(() => ReleaseParser.parse('not a map'), throwsA(isA<ReleaseFormatException>()));
    });

    test('very long notes are cut', () {
      final r = ReleaseParser.parse(releaseJson(body: 'a' * 30000))!;
      expect(r.notes.length, ReleaseParser.maxNotes + 3);
    });
  });

  group('download hosts', () {
    test('only https on GitHub file hosts is allowed', () {
      for (final ok in [
        'https://github.com/molotovgit/multiplex/releases/download/v1/a.apk',
        'https://objects.githubusercontent.com/x',
        'https://release-assets.githubusercontent.com/x',
        'https://GitHub.com/x',
      ]) {
        expect(UpdateHosts.isAllowed(Uri.parse(ok)), isTrue, reason: ok);
      }
      for (final bad in [
        'http://github.com/x',
        'https://github.com.evil.example/x',
        'https://evilgithub.com/x',
        'https://raw.githubusercontent.com/x',
        'https://github.com:8443/x',
        'https://user@github.com/x',
        'https://api.github.com/x',
      ]) {
        expect(UpdateHosts.isAllowed(Uri.parse(bad)), isFalse, reason: bad);
      }
    });

    test('a redirect off GitHub stops the download', () {
      final from = Uri.parse('https://github.com/a.apk');
      expect(UpdateRedirects.next(from, 'https://objects.githubusercontent.com/b', 0, UpdateHosts.isAllowed).host, 'objects.githubusercontent.com');
      expect(UpdateRedirects.next(from, '/c.apk', 0, UpdateHosts.isAllowed), Uri.parse('https://github.com/c.apk'));
      expect(() => UpdateRedirects.next(from, 'https://evil.example/b', 0, UpdateHosts.isAllowed), throwsA(isA<UpdateException>()));
      expect(() => UpdateRedirects.next(from, 'http://objects.githubusercontent.com/b', 0, UpdateHosts.isAllowed), throwsA(isA<UpdateException>()));
      expect(() => UpdateRedirects.next(from, null, 0, UpdateHosts.isAllowed), throwsA(isA<UpdateException>()));
      expect(() => UpdateRedirects.next(from, '/c', UpdateRedirects.maxHops, UpdateHosts.isAllowed), throwsA(isA<UpdateException>()));
    });

    test('a 403 with the hourly limit used up reads as "wait", quietly', () {
      expect(UpdateStatus.error(403, rateLimitLeft: '0'), same(UpdateException.rateLimited));
      expect(UpdateStatus.error(429), same(UpdateException.rateLimited));
      expect(UpdateStatus.error(500).quiet, isTrue);
      expect(UpdateStatus.error(404).quiet, isTrue);
    });
  });

  group('checksum', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('mpx-sum'));
    tearDown(() => dir.delete(recursive: true));

    test('reads a bare digest or sha256sum output', () {
      expect(ApkChecksum.parse('${apkSum.toUpperCase()}\n'), apkSum);
      expect(ApkChecksum.parse('$apkSum  multiplex-1.2.0-arm64.apk\n'), apkSum);
      expect(() => ApkChecksum.parse('abc'), throwsA(isA<UpdateException>()));
      expect(() => ApkChecksum.parse('<html>not found</html>'), throwsA(isA<UpdateException>()));
    });

    test('matches only the exact bytes', () async {
      final file = File('${dir.path}/a.apk')..writeAsBytesSync(apkBytes);
      expect(await ApkChecksum.matches(file, apkSum), isTrue);
      file.writeAsBytesSync([...apkBytes, 0]);
      expect(await ApkChecksum.matches(file, apkSum), isFalse);
    });
  });

  group('once a day', () {
    final now = DateTime.utc(2026, 11, 6, 12);
    int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;

    test('due when never checked or a day has passed', () {
      expect(UpdateSchedule.isDue(enabled: true, lastCheckMs: 0, now: now), isTrue);
      expect(UpdateSchedule.isDue(enabled: true, lastCheckMs: ago(const Duration(hours: 25)), now: now), isTrue);
      expect(UpdateSchedule.isDue(enabled: true, lastCheckMs: ago(const Duration(hours: 23)), now: now), isFalse);
    });

    test('never when turned off; a clock moved back does not block checks', () {
      expect(UpdateSchedule.isDue(enabled: false, lastCheckMs: 0, now: now), isFalse);
      expect(UpdateSchedule.isDue(enabled: true, lastCheckMs: now.add(const Duration(days: 3)).millisecondsSinceEpoch, now: now), isTrue);
    });
  });

  test('update settings survive a save and default for old vaults', () {
    const s = AppSettings(autoCheckUpdates: false, lastUpdateCheckMs: 42, skippedUpdateVersion: '1.2.0');
    final back = AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect([back.autoCheckUpdates, back.lastUpdateCheckMs, back.skippedUpdateVersion], [false, 42, '1.2.0']);
    final old = AppSettings.fromJson(const {});
    expect([old.autoCheckUpdates, old.lastUpdateCheckMs, old.skippedUpdateVersion], [true, 0, '']);
  });
}
