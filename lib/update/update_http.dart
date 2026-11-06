import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'update_errors.dart';

/// Called while a file downloads. [total] is 0 when the server did not say.
typedef DownloadProgress = void Function(int received, int total);

/// The few web requests the updater makes. [GitHubHttp] does them for
/// real; tests pass their own.
abstract interface class UpdateHttp {
  /// A small text reply (the release JSON or a .sha256 file). Every
  /// address on the way, redirects included, must pass [allow].
  Future<String> getText(Uri uri, {required bool Function(Uri) allow, Map<String, String> headers});

  /// Saves [uri] into [target], reporting progress, until done or [cancel].
  Future<void> download(Uri uri, File target, {required bool Function(Uri) allow, required DownloadProgress onProgress, required UpdateCancel cancel});
}

/// Follows a redirect by hand so each new address can be checked first.
abstract final class UpdateRedirects {
  static const maxHops = 5;

  /// The next address after a redirect from [current] to [location].
  /// Throws when there is none, too many hops were made, or the new
  /// address is not allowed.
  static Uri next(Uri current, String? location, int hop, bool Function(Uri) allow) {
    if (location == null || location.isEmpty || hop >= maxHops) {
      throw const UpdateException('GitHub kept sending the download elsewhere. Try again later.');
    }
    final uri = current.resolve(location);
    if (!allow(uri)) throw UpdateException('The download was sent to ${uri.host}, which is not GitHub. It was stopped.');
    return uri;
  }
}

/// Real requests with dart:io, with a time limit and a size limit.
class GitHubHttp implements UpdateHttp {
  GitHubHttp({HttpClient Function()? newClient}) : _newClient = newClient ?? HttpClient.new;

  final HttpClient Function() _newClient;

  static const userAgent = 'Multiplex-updater';
  static const timeout = Duration(seconds: 20);

  /// Biggest text reply read (the release JSON is a few kB).
  static const maxTextBytes = 1024 * 1024;

  /// The APK is about 30 MB; anything far bigger is not ours.
  static const maxApkBytes = 200 * 1024 * 1024;

  static const _brokenTls = UpdateException('The secure connection to GitHub failed. Try again on another network.');
  static const _tooBig = UpdateException('The update file is far bigger than expected. It was not kept.');

  HttpClient _client() => _newClient()
    ..connectionTimeout = timeout
    ..idleTimeout = timeout
    ..userAgent = userAgent;

  @override
  Future<String> getText(Uri uri, {required bool Function(Uri) allow, Map<String, String> headers = const {}}) async {
    final client = _client();
    try {
      final response = await _open(client, uri, allow, headers).timeout(timeout);
      final bytes = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maxTextBytes) throw const UpdateException('GitHub sent a much bigger reply than expected. Try again later.');
      }
      return utf8.decode(bytes, allowMalformed: true);
    } on HandshakeException {
      throw _brokenTls;
    } on TimeoutException {
      throw UpdateException.offline;
    } on SocketException {
      throw UpdateException.offline;
    } on HttpException {
      throw UpdateException.offline;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> download(Uri uri, File target, {required bool Function(Uri) allow, required DownloadProgress onProgress, required UpdateCancel cancel}) async {
    final client = _client();
    // Closing the client stops the transfer at once.
    cancel.onCancel(() => client.close(force: true));
    IOSink? sink;
    try {
      final response = await _open(client, uri, allow, const {}).timeout(timeout);
      final total = response.contentLength > 0 ? response.contentLength : 0;
      if (total > maxApkBytes) throw _tooBig;
      sink = target.openWrite();
      var received = 0;
      onProgress(0, total);
      // A stalled transfer (no data for [timeout]) ends with an error.
      await for (final chunk in response.timeout(timeout)) {
        if (cancel.isCancelled) throw UpdateException.cancelled;
        received += chunk.length;
        if (received > maxApkBytes) throw _tooBig;
        sink.add(chunk);
        onProgress(received, total);
      }
      await sink.flush();
      if (total > 0 && received != total) throw const UpdateException('The download stopped part way. Try again.');
    } on UpdateException {
      if (cancel.isCancelled) throw UpdateException.cancelled;
      rethrow;
    } catch (e) {
      if (cancel.isCancelled) throw UpdateException.cancelled;
      if (e is HandshakeException) throw _brokenTls;
      if (e is TimeoutException || e is SocketException || e is HttpException) {
        throw const UpdateException('The download stopped. Check your internet connection and try again.');
      }
      rethrow;
    } finally {
      try {
        await sink?.close();
      } catch (_) {
        // The file is deleted by the caller anyway.
      }
      client.close(force: true);
    }
  }

  Future<HttpClientResponse> _open(HttpClient client, Uri start, bool Function(Uri) allow, Map<String, String> headers) async {
    if (!allow(start)) throw UpdateException('${start.host} is not GitHub, so nothing was downloaded.');
    var uri = start;
    for (var hop = 0;; hop++) {
      final request = await client.getUrl(uri);
      // Redirects are followed by hand so each one is checked.
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      final response = await request.close();
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        uri = UpdateRedirects.next(uri, location, hop, allow);
        continue;
      }
      if (response.statusCode == HttpStatus.ok) return response;
      await response.drain<void>();
      throw UpdateStatus.error(response.statusCode, rateLimitLeft: response.headers.value('x-ratelimit-remaining'));
    }
  }
}

/// Turns an HTTP error code into a message.
abstract final class UpdateStatus {
  /// GitHub answers 403 with "x-ratelimit-remaining: 0" (or 429) when the
  /// hourly limit of 60 unsigned requests is used up.
  static UpdateException error(int status, {String? rateLimitLeft}) {
    if (status == HttpStatus.tooManyRequests || (status == HttpStatus.forbidden && rateLimitLeft == '0')) return UpdateException.rateLimited;
    if (status == HttpStatus.notFound) return const UpdateException('No release was found on GitHub.', quiet: true);
    return UpdateException('GitHub answered with error $status. Try again later.', quiet: status >= 500 || status == HttpStatus.forbidden);
  }
}
