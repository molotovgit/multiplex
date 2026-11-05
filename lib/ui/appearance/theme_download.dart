import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'theme_import.dart';

/// Theme text fetched from a link, with a name taken from the link.
class ThemeDownload {
  const ThemeDownload({required this.text, required this.sourceName});

  final String text;
  final String? sourceName;
}

/// Fetches a theme file from an https link. Refuses plain http, files
/// over 1 MB and servers that take longer than 15 seconds.
class ThemeDownloader implements ThemeFetcher {
  /// [newClient] makes the HTTP client; tests pass their own.
  ThemeDownloader({HttpClient Function()? newClient}) : _newClient = newClient ?? HttpClient.new;

  final HttpClient Function() _newClient;

  static const timeout = Duration(seconds: 15);
  static const maxRedirects = 5;

  /// Reads the link the user typed. Only https links are accepted, and a
  /// GitHub page link is changed into the link of the file itself.
  static Uri parseLink(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.host.isEmpty) {
      throw const ThemeImportException('This is not a link. Paste a link that starts with https://');
    }
    if (uri.scheme != 'https') {
      throw const ThemeImportException('Only https links are allowed, so the theme cannot be changed on the way. Use a link that starts with https://');
    }
    return rawFileLink(uri);
  }

  /// github.com/owner/repo/blob/branch/path is a web page about the file;
  /// raw.githubusercontent.com/owner/repo/branch/path is the file itself.
  static Uri rawFileLink(Uri uri) {
    final host = uri.host.toLowerCase();
    final parts = uri.pathSegments;
    final isGitHubPage = host == 'github.com' || host == 'www.github.com';
    if (!isGitHubPage || parts.length < 5 || parts[2] != 'blob') return uri;
    return Uri(scheme: 'https', host: 'raw.githubusercontent.com', pathSegments: [parts[0], parts[1], ...parts.skip(3)]);
  }

  /// Downloads the theme at [link]. Throws [ThemeImportException] with a
  /// message for the user when anything goes wrong.
  Future<ThemeDownload> fetch(String link) async {
    final uri = parseLink(link);
    final bytes = await fetchBytes(uri, maxBytes: ThemeImporter.maxBytes, tooBig: ThemeImportException.tooBig);
    return ThemeDownload(text: ThemeImporter.decode(bytes), sourceName: ThemeSourceName.fromUrl(uri));
  }

  /// Downloads up to [maxBytes] from an https [uri]. Redirects must stay
  /// on https; slow servers and big files are refused with a message.
  @override
  Future<Uint8List> fetchBytes(
    Uri uri, {
    required int maxBytes,
    required ThemeImportException tooBig,
    Duration limit = timeout,
    Map<String, String> headers = const {},
  }) async {
    if (uri.scheme != 'https') {
      throw const ThemeImportException('Only https links are allowed, so the theme cannot be changed on the way. Use a link that starts with https://');
    }
    final client = _newClient()
      ..connectionTimeout = timeout
      ..userAgent = 'Multiplex';
    try {
      return await _download(client, uri, maxBytes, tooBig, headers).timeout(limit);
    } on TimeoutException {
      throw ThemeImportException('${uri.host} took longer than ${limit.inSeconds} seconds. Check your connection and try again.');
    } on HandshakeException {
      throw ThemeImportException('The secure connection to ${uri.host} failed. Check the link, or try again on another network.');
    } on SocketException {
      throw ThemeImportException('Could not reach ${uri.host}. Check the link and your internet connection.');
    } on HttpException catch (e) {
      throw ThemeImportException('The download stopped part way: ${e.message}. Try again.');
    } finally {
      // Also stops a download that is still running after a time-out.
      client.close(force: true);
    }
  }

  Future<Uint8List> _download(HttpClient client, Uri start, int maxBytes, ThemeImportException tooBig, Map<String, String> headers) async {
    var uri = start;
    for (var hop = 0;; hop++) {
      final request = await client.getUrl(uri);
      headers.forEach(request.headers.set);
      // Redirects are followed by hand so none of them can leave https.
      request.followRedirects = false;
      final response = await request.close();
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null || hop >= maxRedirects) {
          throw const ThemeImportException('The link keeps sending you elsewhere. Use a direct link to the theme file.');
        }
        uri = uri.resolve(location);
        if (uri.scheme != 'https') {
          throw const ThemeImportException('The link sends you on to a page that is not https. Use a direct https link to the theme file.');
        }
        continue;
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw ThemeDownloadStatusException(response.statusCode);
      }
      if (response.contentLength > maxBytes) throw tooBig;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        bytes.add(chunk);
        if (bytes.length > maxBytes) throw tooBig;
      }
      return bytes.takeBytes();
    }
  }
}

/// The server answered with an error code instead of the file.
class ThemeDownloadStatusException extends ThemeImportException {
  ThemeDownloadStatusException(this.statusCode)
      : super(statusCode == HttpStatus.notFound
            ? 'Nothing was found at this link (error 404). Check that the link is right and the repository is public.'
            : 'The server answered with error $statusCode. Check that the link opens the theme file, or try again later.');

  final int statusCode;
}

/// Downloads bytes from https links. [ThemeDownloader] does it for real;
/// tests pass their own.
abstract interface class ThemeFetcher {
  Future<Uint8List> fetchBytes(
    Uri uri, {
    required int maxBytes,
    required ThemeImportException tooBig,
    Duration limit,
    Map<String, String> headers,
  });
}
