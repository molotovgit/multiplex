import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:multiplex/update/update_errors.dart';
import 'package:multiplex/update/update_http.dart';
import 'package:multiplex/update/update_platform.dart';

final apkUrl = Uri.parse('https://github.com/molotovgit/multiplex/releases/download/v1.2.0/multiplex-1.2.0-arm64.apk');
final sumUrl = Uri.parse('https://github.com/molotovgit/multiplex/releases/download/v1.2.0/multiplex-1.2.0-arm64.apk.sha256');
final apkBytes = utf8.encode('pretend this is an apk');
final apkSum = sha256.convert(apkBytes).toString();

/// A release as the GitHub API returns it, trimmed to the fields we read.
Map<String, Object?> releaseJson({String tag = 'v1.2.0', bool prerelease = false, bool draft = false, String body = 'Faster file copy.', String? apkLink, bool withSum = true}) {
  final v = tag.substring(1);
  return {
    'tag_name': tag,
    'draft': draft,
    'prerelease': prerelease,
    'body': body,
    'assets': [
      {'name': 'multiplex-$v-arm64.apk', 'size': apkBytes.length, 'browser_download_url': apkLink ?? apkUrl.toString()},
      if (withSum) {'name': 'multiplex-$v-arm64.apk.sha256', 'size': 64, 'browser_download_url': sumUrl.toString()},
    ],
  };
}

/// Answers from fixed texts and bytes, and records what was asked.
class FakeUpdateHttp implements UpdateHttp {
  final texts = <Uri, String>{};
  final files = <Uri, List<int>>{};
  final requested = <Uri>[];
  UpdateException? failText;

  /// Called mid-download, so a test can cancel there.
  void Function()? duringDownload;

  @override
  Future<String> getText(Uri uri, {required bool Function(Uri) allow, Map<String, String> headers = const {}}) async {
    requested.add(uri);
    if (!allow(uri)) throw const UpdateException('not allowed');
    if (failText != null) throw failText!;
    final text = texts[uri];
    if (text == null) throw const UpdateException('No release was found on GitHub.', quiet: true);
    return text;
  }

  @override
  Future<void> download(Uri uri, File target, {required bool Function(Uri) allow, required DownloadProgress onProgress, required UpdateCancel cancel}) async {
    requested.add(uri);
    if (!allow(uri)) throw const UpdateException('not allowed');
    final bytes = files[uri]!;
    await target.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));
    onProgress(bytes.length ~/ 2, bytes.length);
    duringDownload?.call();
    if (cancel.isCancelled) throw UpdateException.cancelled;
    await target.writeAsBytes(bytes);
    onProgress(bytes.length, bytes.length);
  }
}

/// The phone, without a phone.
class FakeUpdatePlatform implements UpdatePlatform {
  FakeUpdatePlatform(this.dir, {this.version = '1.1.0'});

  final Directory dir;
  String? version;
  String? apkProblem;
  bool allowed = true;
  int permissionPages = 0;
  final installedPaths = <String>[];
  final checkedPaths = <String>[];

  @override
  Future<InstalledApp?> installed() async => version == null ? null : InstalledApp(versionName: version!, versionCode: 3);

  @override
  Future<Directory> downloadDir() async => dir;

  @override
  Future<ApkReport> checkApk(String path) async {
    checkedPaths.add(path);
    return ApkReport(apkProblem);
  }

  @override
  Future<bool> canInstall() async => allowed;

  @override
  Future<void> openInstallPermission() async => permissionPages++;

  @override
  Future<void> install(String path) async => installedPaths.add(path);
}
