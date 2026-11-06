import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// The app as it is installed on the phone.
class InstalledApp {
  const InstalledApp({required this.versionName, required this.versionCode});

  final String versionName;
  final int versionCode;
}

/// What the phone found when it looked inside a downloaded APK. Null
/// [problem] means it is a newer build of this very app, signed with the
/// same key as the installed one.
class ApkReport {
  const ApkReport(this.problem);

  final String? problem;

  bool get ok => problem == null;

  /// The words shown for each problem the native check reports.
  String get message => switch (problem) {
        null => '',
        'notAnApp' => 'The downloaded file is not an Android app.',
        'otherApp' => 'The downloaded file is a different app, not Multiplex.',
        'otherSigner' => 'The downloaded app is not signed by the same key as this one, so it may not be genuine.',
        'notNewer' => 'The downloaded app is not newer than the one installed.',
        _ => 'The downloaded app could not be checked.',
      };
}

/// The phone side of updating: reading our own version, checking an APK
/// and opening the system installer. Android only; [AndroidUpdatePlatform]
/// does it through UpdateChannel.kt, tests pass their own.
abstract interface class UpdatePlatform {
  /// Null where in-app updates are not offered (not Android).
  Future<InstalledApp?> installed();

  /// The folder downloads go into (inside the app's cache).
  Future<Directory> downloadDir();

  Future<ApkReport> checkApk(String path);

  /// Whether Android lets Multiplex open the package installer
  /// ("Install unknown apps").
  Future<bool> canInstall();

  /// Opens the system page where the user allows that.
  Future<void> openInstallPermission();

  /// Hands the APK to the system installer, which asks the user.
  Future<void> install(String path);
}

class AndroidUpdatePlatform implements UpdatePlatform {
  const AndroidUpdatePlatform([this._channel = const MethodChannel('multiplex/updater')]);

  final MethodChannel _channel;

  @override
  Future<InstalledApp?> installed() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final info = await _channel.invokeMapMethod<String, Object?>('installed');
      if (info == null) return null;
      return InstalledApp(versionName: info['versionName'] as String? ?? '', versionCode: (info['versionCode'] as num?)?.toInt() ?? 0);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<Directory> downloadDir() async {
    // The FileProvider in AndroidManifest.xml shares only this folder.
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<ApkReport> checkApk(String path) async {
    try {
      return ApkReport(await _channel.invokeMethod<String>('checkApk', {'path': path}));
    } on PlatformException {
      return const ApkReport('failed');
    }
  }

  @override
  Future<bool> canInstall() async => await _channel.invokeMethod<bool>('canInstall') ?? false;

  @override
  Future<void> openInstallPermission() => _channel.invokeMethod<void>('openInstallPermission');

  @override
  Future<void> install(String path) => _channel.invokeMethod<void>('install', {'path': path});
}
