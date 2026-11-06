/// A plain release version such as 1.4.2. Release tags look like v1.4.2;
/// anything else (1.4, v1.4.2-beta, nightly) is not a stable release and
/// is never offered.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final _pattern = RegExp(r'^v?(\d{1,6})\.(\d{1,6})\.(\d{1,6})$');

  /// Reads "1.4.2" or "v1.4.2". A build number after "+" (as in the
  /// app's own "1.4.2+7") is ignored. Returns null for anything else.
  static AppVersion? tryParse(String text) {
    final plain = text.trim().split('+').first;
    final m = _pattern.firstMatch(plain);
    if (m == null) return null;
    return AppVersion(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
