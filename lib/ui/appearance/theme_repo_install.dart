import 'dart:convert';
import 'dart:typed_data';

import '../../app/theme_backgrounds.dart';
import '../../app/theme_spec.dart';
import 'theme_download.dart';
import 'theme_import.dart';

/// A link to a theme on GitHub: github.com/owner/repo, optionally with
/// /tree/branch/folder.
class GitHubRepoLink {
  const GitHubRepoLink({required this.owner, required this.repo, this.branch, this.path = ''});

  final String owner;
  final String repo;

  /// Null means the repository's default branch.
  final String? branch;

  /// A folder inside the repository, or empty for its top.
  final String path;

  static final _name = RegExp(r'^[A-Za-z0-9._-]+$');

  /// Reads the link the user pasted. Only https GitHub repository links
  /// are accepted.
  static GitHubRepoLink parse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.host.isEmpty) {
      throw const ThemeImportException('This is not a link. Paste a GitHub link such as https://github.com/owner/theme');
    }
    if (uri.scheme != 'https') {
      throw const ThemeImportException('Only https links are allowed. Use a link that starts with https://github.com/');
    }
    final host = uri.host.toLowerCase();
    final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if ((host != 'github.com' && host != 'www.github.com') || parts.length < 2) {
      throw const ThemeImportException('This is not a GitHub repository link. Use a link such as https://github.com/owner/theme');
    }
    final repo = parts[1].endsWith('.git') ? parts[1].substring(0, parts[1].length - 4) : parts[1];
    String? branch;
    var path = '';
    if (parts.length >= 4 && parts[2] == 'tree') {
      branch = parts[3];
      path = parts.skip(4).join('/');
    } else if (parts.length > 2) {
      throw const ThemeImportException('Use the link of the repository itself, or of a folder in it (with /tree/).');
    }
    if (![parts[0], repo, ?branch].every(_name.hasMatch) || path.split('/').any((p) => p == '..')) {
      throw const ThemeImportException('This GitHub link has characters Multiplex does not expect. Copy the link from the address bar.');
    }
    return GitHubRepoLink(owner: parts[0], repo: repo, branch: branch, path: path);
  }

  /// The GitHub API address that lists a folder of the repository.
  Uri contents([String sub = '']) {
    final folder = [path, sub].where((p) => p.isNotEmpty).join('/');
    return Uri(
      scheme: 'https',
      host: 'api.github.com',
      path: '/repos/$owner/$repo/contents${folder.isEmpty ? '' : '/$folder'}',
      queryParameters: branch == null ? null : {'ref': branch},
    );
  }

  /// "github.com/owner/repo", for the theme's credit.
  String get label => 'github.com/$owner/$repo${path.isEmpty ? '' : '/$path'}';

  /// "omarchy-tokyo-night-theme" -> "Tokyo Night".
  String? get themeName {
    var base = path.isEmpty ? repo : path.split('/').last;
    base = base.replaceFirst(RegExp(r'^omarchy[-_]', caseSensitive: false), '').replaceFirst(RegExp(r'[-_]theme$', caseSensitive: false), '');
    return ThemeSourceName.fromFileName(base);
  }
}

/// One file or folder in a GitHub folder listing.
class _RepoEntry {
  const _RepoEntry({required this.name, required this.isFolder, required this.size, required this.download});

  final String name;
  final bool isFolder;
  final int size;
  final Uri? download;

  /// Only files served from GitHub's own raw host, over https, are fetched.
  static _RepoEntry? from(Object? json) {
    if (json is! Map) return null;
    final name = json['name'], type = json['type'], size = json['size'], url = json['download_url'];
    if (name is! String) return null;
    final uri = url is String ? Uri.tryParse(url) : null;
    final safe = uri != null && uri.scheme == 'https' && uri.host == 'raw.githubusercontent.com';
    return _RepoEntry(name: name, isFolder: type == 'dir', size: size is int ? size : 0, download: safe ? uri : null);
  }
}

/// What a theme repository holds: its colour file and its pictures.
class RepoThemePack {
  const RepoThemePack({required this.link, required this.colours, required this.colourFile, required this.pictures, required this.skipped});

  final GitHubRepoLink link;
  final String colours;
  final String colourFile;
  final List<({String name, Uint8List bytes})> pictures;

  /// Pictures left out for being too big, too many or not pictures.
  final int skipped;
}

/// Installs a theme from a GitHub repository laid out like an Omarchy
/// theme: a colour file at the top (alacritty.toml, kitty.conf or
/// ghostty.conf, in that order) and pictures in a backgrounds folder.
class ThemeRepoInstaller {
  ThemeRepoInstaller({ThemeFetcher? fetcher, ThemeImporter? importer})
      : _fetch = fetcher ?? ThemeDownloader(),
        _importer = importer ?? ThemeImporter();

  final ThemeFetcher _fetch;
  final ThemeImporter _importer;

  static const colourFiles = ['alacritty.toml', 'kitty.conf', 'ghostty.conf'];
  static const picturesFolder = 'backgrounds';
  static const maxPictures = 10;
  static const maxPictureBytes = 8 * 1024 * 1024;
  static const maxTotalBytes = 40 * 1024 * 1024;

  /// A folder listing is small; 512 kB leaves plenty of room.
  static const _maxListing = 512 * 1024;
  static const _pictureTime = Duration(seconds: 60);
  static const _api = {'Accept': 'application/vnd.github+json'};

  /// Downloads the theme behind [linkText]. [onStep] hears what is going on,
  /// in words for the user.
  Future<RepoThemePack> download(String linkText, {void Function(String step)? onStep}) async {
    final link = GitHubRepoLink.parse(linkText);
    onStep?.call('Reading the repository');
    final top = await _list(link.contents(), top: true);
    final colour = colourFiles.map((n) => top.where((e) => !e.isFolder && e.name.toLowerCase() == n).firstOrNull).nonNulls.firstOrNull;
    if (colour == null || colour.download == null) {
      throw const ThemeImportException('This repository has no alacritty.toml, kitty.conf or ghostty.conf at its top, so it has no colours to install.');
    }
    onStep?.call('Downloading ${colour.name}');
    final text = ThemeImporter.decode(
      await _fetch.fetchBytes(colour.download!, maxBytes: ThemeImporter.maxBytes, tooBig: ThemeImportException.tooBig),
    );
    final hasPictures = top.any((e) => e.isFolder && e.name == picturesFolder);
    final listed = hasPictures ? await _list(link.contents(picturesFolder)) : const <_RepoEntry>[];
    final candidates = listed.where((e) => !e.isFolder && e.download != null && PictureKind.hasPictureExtension(e.name)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final pictures = <({String name, Uint8List bytes})>[];
    var total = 0, skipped = 0;
    for (final entry in candidates) {
      if (pictures.length >= maxPictures || entry.size > maxPictureBytes || total + entry.size > maxTotalBytes) {
        skipped++;
        continue;
      }
      onStep?.call('Downloading picture ${pictures.length + 1} of ${candidates.length.clamp(0, maxPictures)}');
      final Uint8List bytes;
      try {
        bytes = await _fetch.fetchBytes(entry.download!, maxBytes: maxPictureBytes, tooBig: _pictureTooBig, limit: _pictureTime);
      } on ThemeImportException catch (e) {
        if (identical(e, _pictureTooBig)) {
          skipped++;
          continue;
        }
        rethrow;
      }
      if (PictureKind.of(bytes) == null || total + bytes.length > maxTotalBytes) {
        skipped++;
        continue;
      }
      total += bytes.length;
      pictures.add((name: entry.name, bytes: bytes));
    }
    return RepoThemePack(link: link, colours: text, colourFile: colour.name, pictures: pictures, skipped: skipped);
  }

  /// Reads the pack into a new theme and keeps its pictures in the new
  /// theme's folder. The theme is not saved yet.
  Future<ThemeSpec> build(RepoThemePack pack) async {
    final spec = _importer.read(pack.colours, sourceName: pack.link.themeName);
    final names = <String>[];
    for (final picture in pack.pictures) {
      names.add(await ThemeBackgrounds.addBytes(spec.id, picture.bytes, sourceName: picture.name));
    }
    return spec.copyWith(backgrounds: names, credit: 'From ${pack.link.label}');
  }

  static const _pictureTooBig = ThemeImportException('A picture is larger than 8 MB.');

  Future<List<_RepoEntry>> _list(Uri uri, {bool top = false}) async {
    final Uint8List bytes;
    try {
      bytes = await _fetch.fetchBytes(uri, maxBytes: _maxListing, tooBig: ThemeImportException.tooBig, headers: _api);
    } on ThemeDownloadStatusException catch (e) {
      if (e.statusCode == 403 || e.statusCode == 429) {
        throw const ThemeImportException('GitHub is limiting downloads from this network right now. Wait a while, then try again.');
      }
      if (e.statusCode == 404 && top) {
        throw const ThemeImportException('GitHub has no public repository or folder at this link. Check the link and the branch name.');
      }
      rethrow;
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const ThemeImportException('GitHub sent an answer Multiplex could not read. Try again later.');
    }
    if (json is! List) {
      throw const ThemeImportException('This link points to a file. Use the link of the repository or of the folder that holds the theme.');
    }
    return json.map(_RepoEntry.from).nonNulls.toList();
  }
}
