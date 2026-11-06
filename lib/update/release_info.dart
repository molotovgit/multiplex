import 'app_version.dart';
import 'update_hosts.dart';

/// The newest stable release on GitHub, read from the releases API.
class ReleaseInfo {
  const ReleaseInfo({required this.version, required this.notes, required this.apkUrl, required this.apkSize, required this.checksumUrl});

  final AppVersion version;

  /// The release text, shown as plain text.
  final String notes;

  /// The APK file (`multiplex-X.Y.Z-arm64.apk`).
  final Uri apkUrl;

  /// Its size in bytes, as GitHub reports it (0 if not given).
  final int apkSize;

  /// The `.sha256` file next to it, holding the APK's SHA-256 in hex.
  final Uri checksumUrl;

  static String apkName(AppVersion v) => 'multiplex-$v-arm64.apk';
}

/// Why a release could not be used.
class ReleaseFormatException implements Exception {
  const ReleaseFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads the JSON of `GET /repos/{owner}/{repo}/releases/latest`.
abstract final class ReleaseParser {
  /// Longest release text kept; the rest is cut off.
  static const maxNotes = 20000;

  /// Returns null when the release is not a stable one (a draft, a
  /// pre-release, or a tag that is not vX.Y.Z). Throws
  /// [ReleaseFormatException] when it is stable but its files are missing
  /// or not on GitHub.
  static ReleaseInfo? parse(Object? json) {
    if (json is! Map) throw const ReleaseFormatException('GitHub sent something that is not a release.');
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'];
    if (tag is! String || !tag.startsWith('v')) return null;
    final version = AppVersion.tryParse(tag);
    if (version == null) return null;
    final assets = json['assets'] is List ? (json['assets'] as List).whereType<Map>().toList() : const <Map>[];
    final name = ReleaseInfo.apkName(version);
    final apk = _asset(assets, name);
    final checksum = _asset(assets, '$name.sha256');
    if (apk == null || checksum == null) {
      throw ReleaseFormatException('Release $version has no $name with its .sha256 file.');
    }
    final body = json['body'] is String ? json['body'] as String : '';
    return ReleaseInfo(
      version: version,
      notes: body.length > maxNotes ? '${body.substring(0, maxNotes)}...' : body.trim(),
      apkUrl: _link(apk),
      apkSize: apk['size'] is int ? apk['size'] as int : 0,
      checksumUrl: _link(checksum),
    );
  }

  static Map? _asset(List<Map> assets, String name) {
    for (final a in assets) {
      if (a['name'] == name) return a;
    }
    return null;
  }

  static Uri _link(Map asset) {
    final raw = asset['browser_download_url'];
    final uri = raw is String ? Uri.tryParse(raw) : null;
    if (uri == null || !UpdateHosts.isAllowed(uri)) {
      throw const ReleaseFormatException('The download link of the release is not on github.com.');
    }
    return uri;
  }
}
