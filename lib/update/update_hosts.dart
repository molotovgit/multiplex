/// Where an update may be downloaded from. The release asset's link
/// points at github.com, which sends the download on to GitHub's file
/// servers; every step of the way must be on this list and on https, so
/// a changed release page cannot make the app fetch a file from anywhere
/// else.
abstract final class UpdateHosts {
  /// The release API itself.
  static final latestRelease = Uri.parse('https://api.github.com/repos/molotovgit/multiplex/releases/latest');

  /// github.com serves the asset link; the others hold the file it
  /// redirects to (GitHub moved release files to
  /// release-assets.githubusercontent.com in 2025).
  static const allowed = {'github.com', 'objects.githubusercontent.com', 'release-assets.githubusercontent.com'};

  static bool isAllowed(Uri uri) => uri.scheme == 'https' && !uri.hasPort && allowed.contains(uri.host.toLowerCase()) && uri.userInfo.isEmpty;
}
