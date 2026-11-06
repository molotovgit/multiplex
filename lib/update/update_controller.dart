import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/vault_store.dart';
import 'apk_checksum.dart';
import 'app_version.dart';
import 'release_info.dart';
import 'update_errors.dart';
import 'update_hosts.dart';
import 'update_http.dart';
import 'update_platform.dart';
import 'update_schedule.dart';

/// Where the updater is.
enum UpdatePhase {
  /// Nothing to show (not checked yet, or a quiet check failed).
  idle,
  checking,
  upToDate,

  /// [UpdateController.release] is newer than this app.
  available,
  downloading,
  verifying,

  /// Android must first allow Multiplex to install apps.
  needsPermission,

  /// The system installer was opened.
  installing,
  failed,
}

/// Checks GitHub for a newer release, downloads it, checks it and hands it
/// to the system installer. One lives as long as the app.
class UpdateController extends ChangeNotifier {
  UpdateController({required this._store, required this._platform, UpdateHttp? http, DateTime Function()? clock})
      : _http = http ?? GitHubHttp(),
        _clock = clock ?? DateTime.now;

  final VaultStore _store;
  final UpdatePlatform _platform;
  final UpdateHttp _http;
  final DateTime Function() _clock;

  static const _apiHeaders = {'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'};

  InstalledApp? _installed;
  bool _started = false;
  UpdatePhase _phase = UpdatePhase.idle;
  ReleaseInfo? _release;
  String? _error;
  int _received = 0;
  int _total = 0;
  bool _later = false;
  bool _asked = false;
  UpdateCancel? _cancel;
  File? _apk;

  /// False where updates are not offered (not Android); the UI hides
  /// everything then.
  bool get supported => _installed != null;
  String? get currentVersion => _installed?.versionName;
  UpdatePhase get phase => _phase;
  ReleaseInfo? get release => _release;
  String? get error => _error;

  /// Download progress from 0 to 1, or null while the size is unknown.
  double? get progress => _total > 0 ? (_received / _total).clamp(0.0, 1.0) : null;
  int get received => _received;

  bool get busy => _phase == UpdatePhase.checking || _phase == UpdatePhase.downloading || _phase == UpdatePhase.verifying;

  /// Whether the update card is shown. "Later" hides it until the app
  /// starts again and "Skip" hides that version for good, unless the user
  /// checks by hand.
  bool get showCard {
    if (_release == null || _phase == UpdatePhase.idle || _phase == UpdatePhase.upToDate || _phase == UpdatePhase.checking) return false;
    if (_asked) return true;
    return !_later && _store.settings.skippedUpdateVersion != _release!.version.toString();
  }

  /// At app start: reads our version, clears old downloads and checks if
  /// a day has passed since the last check.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _installed = await _platform.installed();
    if (!supported) return;
    await _clearDownloads();
    notifyListeners();
    final s = _store.settings;
    if (UpdateSchedule.isDue(enabled: s.autoCheckUpdates, lastCheckMs: s.lastUpdateCheckMs, now: _clock())) await check();
  }

  /// Asks GitHub for the newest release. [byHand] (from Settings) shows
  /// errors and also versions the user skipped.
  Future<void> check({bool byHand = false}) async {
    if (!supported || busy) return;
    if (byHand) {
      _asked = true;
      _later = false;
    }
    _set(UpdatePhase.checking);
    try {
      final text = await _http.getText(UpdateHosts.latestRelease, allow: (u) => u == UpdateHosts.latestRelease, headers: _apiHeaders);
      _store.updateSettings(_store.settings.copyWith(lastUpdateCheckMs: _clock().millisecondsSinceEpoch));
      final release = ReleaseParser.parse(_decode(text));
      final current = AppVersion.tryParse(_installed!.versionName);
      if (release == null || current == null || !release.version.isNewerThan(current)) {
        _release = null;
        _set(byHand ? UpdatePhase.upToDate : UpdatePhase.idle);
      } else {
        _release = release;
        _set(UpdatePhase.available);
      }
    } on UpdateException catch (e) {
      _fail(e.message, show: byHand);
    } on ReleaseFormatException catch (e) {
      _fail(e.message, show: byHand);
    }
  }

  /// Hides the card until the app starts again.
  void later() {
    _later = true;
    _asked = false;
    notifyListeners();
  }

  /// Never offer this version again (a newer one is still offered).
  void skip() {
    final release = _release;
    if (release == null) return;
    _store.updateSettings(_store.settings.copyWith(skippedUpdateVersion: release.version.toString()));
    _asked = false;
    notifyListeners();
  }

  /// Downloads the release, checks it and installs it.
  Future<void> update() async {
    final release = _release;
    if (release == null || busy) return;
    final cancel = _cancel = UpdateCancel();
    _received = 0;
    _total = release.apkSize;
    _set(UpdatePhase.downloading);
    final file = File('${(await _platform.downloadDir()).path}/${ReleaseInfo.apkName(release.version)}');
    try {
      final expected = ApkChecksum.parse(await _http.getText(release.checksumUrl, allow: UpdateHosts.isAllowed));
      if (await file.exists()) await file.delete();
      await _http.download(release.apkUrl, file, allow: UpdateHosts.isAllowed, cancel: cancel, onProgress: _onProgress);
      if (cancel.isCancelled) throw UpdateException.cancelled;
      _set(UpdatePhase.verifying);
      if (!await ApkChecksum.matches(file, expected)) {
        throw const UpdateException('The downloaded file does not match the checksum of the release. It was deleted, nothing was installed.');
      }
      final report = await _platform.checkApk(file.path);
      if (!report.ok) throw UpdateException('${report.message} It was deleted, nothing was installed.');
      _apk = file;
      await install();
    } on UpdateException catch (e) {
      await _delete(file);
      if (cancel.isCancelled) {
        _set(UpdatePhase.available);
      } else {
        _fail(e.message, show: true);
      }
    } on FileSystemException {
      await _delete(file);
      _fail('The update could not be saved on the phone. Free some space and try again.', show: true);
    } finally {
      _cancel = null;
    }
  }

  void cancelDownload() => _cancel?.cancel();

  /// Opens the system installer for the checked download, or asks for the
  /// "Install unknown apps" permission first.
  Future<void> install() async {
    final apk = _apk;
    if (apk == null) return;
    if (!await _platform.canInstall()) {
      _set(UpdatePhase.needsPermission);
      return;
    }
    // Checked again right before, in case the file changed meanwhile.
    final report = await _platform.checkApk(apk.path);
    if (!report.ok) {
      await _delete(apk);
      _apk = null;
      _fail('${report.message} It was deleted, nothing was installed.', show: true);
      return;
    }
    _set(UpdatePhase.installing);
    await _platform.install(apk.path);
  }

  Future<void> openInstallPermission() => _platform.openInstallPermission();

  /// The app came back to the screen: after the permission page, carry on.
  Future<void> resumed() async {
    if (_phase == UpdatePhase.needsPermission && await _platform.canInstall()) await install();
  }

  Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      throw const UpdateException('GitHub sent a reply that could not be read. Try again later.');
    }
  }

  void _onProgress(int received, int total) {
    _received = received;
    if (total > 0) _total = total;
    notifyListeners();
  }

  void _fail(String message, {required bool show}) {
    _error = message;
    _set(show ? UpdatePhase.failed : (_release == null ? UpdatePhase.idle : UpdatePhase.available));
  }

  void _set(UpdatePhase phase) {
    _phase = phase;
    if (phase != UpdatePhase.failed) _error = null;
    notifyListeners();
  }

  Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Left in the cache; cleared at the next start.
    }
  }

  /// Downloads from an earlier run (installed or not) are not needed.
  Future<void> _clearDownloads() async {
    try {
      final dir = await _platform.downloadDir();
      await for (final entry in dir.list()) {
        if (entry is File) await _delete(entry);
      }
    } on FileSystemException {
      // Not important.
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }
}
