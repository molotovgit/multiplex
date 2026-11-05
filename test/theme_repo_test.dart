import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/theme_backgrounds.dart';
import 'package:multiplex/src/rust/api/theme_types.dart';
import 'package:multiplex/ui/appearance/theme_download.dart';
import 'package:multiplex/ui/appearance/theme_import.dart';
import 'package:multiplex/ui/appearance/theme_repo_install.dart';

/// Answers downloads from a map of links, and remembers what was asked.
class _FakeFetcher implements ThemeFetcher {
  _FakeFetcher(this.files);

  final Map<String, Object> files;
  final asked = <String>[];

  @override
  Future<Uint8List> fetchBytes(Uri uri, {required int maxBytes, required ThemeImportException tooBig, Duration? limit, Map<String, String>? headers}) async {
    asked.add('$uri');
    final file = files['$uri'];
    if (file is int) throw ThemeDownloadStatusException(file);
    if (file == null) throw ThemeDownloadStatusException(404);
    final bytes = file is String ? Uint8List.fromList(utf8.encode(file)) : file as Uint8List;
    if (bytes.length > maxBytes) throw tooBig;
    return bytes;
  }
}

/// Repository listings and files as GitHub serves them.
abstract final class _Repo {
  static const api = 'https://api.github.com/repos/someone/omarchy-ember-night-theme/contents';
  static const raw = 'https://raw.githubusercontent.com/someone/omarchy-ember-night-theme/main';

  static Map<String, Object?> file(String name, {int size = 100, String? url}) =>
      {'name': name, 'type': 'file', 'size': size, 'download_url': url ?? '$raw/$name'};
  static Map<String, Object?> folder(String name) => {'name': name, 'type': 'dir', 'size': 0, 'download_url': null};

  static Uint8List png(int bytes) => Uint8List(bytes)..setAll(0, [0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0, 0, 0, 0, 0]);
  static Uint8List jpg(int bytes) => Uint8List(bytes)..setAll(0, [0xFF, 0xD8, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0]);

  static ImportedTheme parsed(String text) => ImportedTheme(
        foreground: 0xFFD0D0D0,
        background: 0xFF101010,
        ansi: Uint32List.fromList(List.filled(16, 0xFF808080)),
        format: text.startsWith('[colors') ? 'alacritty' : 'kitty',
      );
}

void main() {
  group('repository links', () {
    test('repository and folder links are read', () {
      final plain = GitHubRepoLink.parse('https://github.com/someone/omarchy-ember-night-theme');
      expect(plain.branch, isNull);
      expect(plain.contents().toString(), _Repo.api);
      expect(plain.themeName, 'Ember Night');
      final tree = GitHubRepoLink.parse('https://github.com/someone/themes.git/tree/dev/packs/nord-theme');
      expect((tree.repo, tree.branch, tree.path), ('themes', 'dev', 'packs/nord-theme'));
      expect(tree.contents('backgrounds').toString(), 'https://api.github.com/repos/someone/themes/contents/packs/nord-theme/backgrounds?ref=dev');
      expect(tree.themeName, 'Nord');
    });

    test('other links are refused with a reason', () {
      for (final bad in [
        'http://github.com/someone/theme',
        'https://gitlab.com/someone/theme',
        'https://github.com/someone',
        'https://github.com/someone/theme/blob/main/alacritty.toml',
        'not a link',
        'https://github.com/some one/theme',
      ]) {
        expect(() => GitHubRepoLink.parse(bad), throwsA(isA<ThemeImportException>()), reason: bad);
      }
    });
  });

  group('installing', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('packs');
      ThemeBackgrounds.rootOverride = root;
    });
    tearDown(() {
      ThemeBackgrounds.rootOverride = null;
      root.deleteSync(recursive: true);
    });

    ThemeRepoInstaller installer(_FakeFetcher fetch) => ThemeRepoInstaller(fetcher: fetch, importer: ThemeImporter(parse: _Repo.parsed));

    test('an Omarchy-style repository gives its colours and pictures', () async {
      final pictures = [for (var i = 1; i <= 12; i++) _Repo.file('${'$i'.padLeft(2, '0')}.png')];
      final fetch = _FakeFetcher({
        _Repo.api: jsonEncode([_Repo.file('kitty.conf'), _Repo.file('alacritty.toml'), _Repo.folder('backgrounds'), _Repo.file('README.md')]),
        '${_Repo.api}/backgrounds': jsonEncode([
          ...pictures,
          _Repo.file('00-huge.jpg', size: 9 * 1024 * 1024),
          _Repo.file('00-elsewhere.jpg', url: 'https://example.com/x.jpg'),
          _Repo.file('notes.txt'),
        ]),
        '${_Repo.raw}/alacritty.toml': '[colors.primary]\nbackground = "#101010"',
        '${_Repo.raw}/kitty.conf': 'background #000000',
        for (var i = 1; i <= 12; i++) '${_Repo.raw}/${'$i'.padLeft(2, '0')}.png': i == 2 ? Uint8List.fromList(utf8.encode('not a picture at all')) : _Repo.png(64),
      });
      final steps = <String>[];
      final pack = await installer(fetch).download('https://github.com/someone/omarchy-ember-night-theme', onStep: steps.add);
      expect(pack.colourFile, 'alacritty.toml');
      expect(fetch.asked, isNot(contains('${_Repo.raw}/kitty.conf')));
      expect(fetch.asked, isNot(contains('https://example.com/x.jpg')));
      // At most 10 pictures; the fake one, the huge one and the extra two are left out.
      expect(pack.pictures, hasLength(10));
      expect(pack.pictures.first.name, '01.png');
      expect(pack.pictures.any((p) => p.name == '02.png'), isFalse);
      expect(pack.skipped, 3);
      expect(steps, contains('Reading the repository'));

      final theme = await installer(fetch).build(pack);
      expect(theme.name, 'Ember Night');
      expect(theme.credit, 'From github.com/someone/omarchy-ember-night-theme');
      expect(theme.backgrounds, hasLength(10));
      expect(await ThemeBackgrounds.list(theme.id), [...theme.backgrounds]..sort());
      expect(await ThemeBackgrounds.fileFor(theme.id, theme.backgrounds.first), isNotNull);
    });

    test('the 40 MB total is kept', () async {
      final big = 7 * 1024 * 1024;
      final fetch = _FakeFetcher({
        _Repo.api: jsonEncode([_Repo.file('ghostty.conf'), _Repo.folder('backgrounds')]),
        '${_Repo.api}/backgrounds': jsonEncode([for (var i = 0; i < 8; i++) _Repo.file('$i.jpg', size: big)]),
        '${_Repo.raw}/ghostty.conf': 'background = 101010',
        for (var i = 0; i < 8; i++) '${_Repo.raw}/$i.jpg': _Repo.jpg(big),
      });
      final pack = await installer(fetch).download('https://github.com/someone/omarchy-ember-night-theme');
      expect(pack.pictures.length, 5);
      expect(pack.pictures.fold<int>(0, (sum, p) => sum + p.bytes.length), lessThanOrEqualTo(ThemeRepoInstaller.maxTotalBytes));
    });

    test('a repository without a colour file, a missing one and a rate limit each explain', () async {
      final noColours = _FakeFetcher({_Repo.api: jsonEncode([_Repo.folder('backgrounds')])});
      await expectLater(
        installer(noColours).download('https://github.com/someone/omarchy-ember-night-theme'),
        throwsA(isA<ThemeImportException>().having((e) => e.message, 'message', contains('alacritty.toml, kitty.conf or ghostty.conf'))),
      );
      await expectLater(
        installer(_FakeFetcher({})).download('https://github.com/someone/omarchy-ember-night-theme'),
        throwsA(isA<ThemeImportException>().having((e) => e.message, 'message', contains('no public repository'))),
      );
      await expectLater(
        installer(_FakeFetcher({_Repo.api: 403})).download('https://github.com/someone/omarchy-ember-night-theme'),
        throwsA(isA<ThemeImportException>().having((e) => e.message, 'message', contains('limiting downloads'))),
      );
    });
  });

  group('pictures', () {
    test('only real PNG, JPEG and WebP files count as pictures', () {
      expect(PictureKind.of(_Repo.png(16)), 'png');
      expect(PictureKind.of(_Repo.jpg(16)), 'jpg');
      final webp = Uint8List.fromList([...ascii.encode('RIFF'), 0, 0, 0, 0, ...ascii.encode('WEBP'), 0, 0]);
      expect(PictureKind.of(webp), 'webp');
      expect(PictureKind.of(Uint8List.fromList(utf8.encode('<html>not a picture</html>'))), isNull);
      expect(PictureKind.hasPictureExtension('a.JPEG'), isTrue);
      expect(PictureKind.hasPictureExtension('a.gif'), isFalse);
    });
  });
}
