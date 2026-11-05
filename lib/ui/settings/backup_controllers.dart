import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/vault_document.dart';
import '../../data/vault_store.dart';
import 'backup_service.dart';

/// Where an export is.
enum ExportStage { idle, encrypting, saving }

/// How an export ended.
enum ExportOutcome { saved, cancelled, failed }

/// A finished export: the file name and what went into it.
class ExportResult {
  const ExportResult(this.fileName, this.summary);

  final String fileName;
  final BackupSummary summary;
}

/// Makes an encrypted backup of the whole vault and saves it to a file.
class ExportController extends ChangeNotifier {
  ExportController({required this.store, required this.cipher, required this.files, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final VaultStore store;
  final BackupCipher cipher;
  final BackupFiles files;
  final DateTime Function() _clock;

  ExportStage _stage = ExportStage.idle;
  String? _error;
  ExportResult? _result;

  ExportStage get stage => _stage;
  bool get busy => _stage != ExportStage.idle;

  /// What went wrong with the last try, in plain words.
  String? get error => _error;

  /// The last backup that was saved.
  ExportResult? get result => _result;

  /// Encrypts with [password] and asks where to save. The password must
  /// already have passed [BackupPassword.check].
  Future<ExportOutcome> export(String password) async {
    if (busy) return ExportOutcome.failed;
    _error = null;
    _result = null;
    _set(ExportStage.encrypting);

    final summary = BackupSummary.ofStore(store);
    final Uint8List sealed;
    try {
      sealed = await cipher.seal(password, store.exportJson());
    } catch (e) {
      debugPrint('VaultTerm: backup encryption failed: $e');
      _error = 'VaultTerm could not encrypt the backup. Try again. If it keeps failing, restart the app.';
      _set(ExportStage.idle);
      return ExportOutcome.failed;
    }

    _set(ExportStage.saving);
    final name = BackupFormat.fileNameFor(_clock());
    try {
      final saved = await files.save(name, sealed);
      if (!saved) {
        _set(ExportStage.idle);
        return ExportOutcome.cancelled;
      }
    } catch (e) {
      debugPrint('VaultTerm: saving the backup failed: $e');
      _error = 'The backup could not be saved there. Choose another folder and try again.';
      _set(ExportStage.idle);
      return ExportOutcome.failed;
    }
    _result = ExportResult(name, summary);
    _set(ExportStage.idle);
    return ExportOutcome.saved;
  }

  void _set(ExportStage stage) {
    _stage = stage;
    notifyListeners();
  }
}

/// Where a restore is.
enum RestoreStage {
  /// Waiting for the user to pick a file.
  chooseFile,

  /// A backup file is picked; waiting for its password.
  enterPassword,

  /// Decrypting (takes about a second).
  opening,

  /// Opened; waiting for "add" or "replace".
  chooseMode,

  /// The backup's contents are in the vault.
  finished,
}

/// A finished restore: whether it replaced everything and what came in.
class RestoreResult {
  const RestoreResult({required this.replaced, required this.summary});

  final bool replaced;
  final BackupSummary summary;
}

/// The words shown for restore problems.
abstract final class RestoreMessages {
  static const notABackup = 'This file is not a VaultTerm backup. Choose a file that ends in .vtbackup.';
  static const tooLarge = 'This file is too large to be a VaultTerm backup. Choose another file.';
  static const cannotRead = 'The file could not be read. Choose it again, or copy it to this device first.';
  static const emptyPassword = 'Type the password the backup was made with.';
  static const wrongPassword = 'This password does not open the backup. Check it and try again.';
  static const unreadable = 'The backup opened, but its contents could not be read. '
      'It may come from a newer version of VaultTerm; update the app and try again.';
}

/// Brings a backup back: pick the file, type its password, then add it to
/// the current data or replace everything with it.
class RestoreController extends ChangeNotifier {
  RestoreController({required this.store, required this.cipher, required this.files});

  final VaultStore store;
  final BackupCipher cipher;
  final BackupFiles files;

  RestoreStage _stage = RestoreStage.chooseFile;
  bool _picking = false;
  String? _fileName;
  Uint8List? _data;
  String? _json;
  BackupSummary? _incoming;
  RestoreResult? _result;
  String? _error;

  RestoreStage get stage => _stage;

  /// True while the file picker is open.
  bool get picking => _picking;
  String? get fileName => _fileName;

  /// What the opened backup holds (from [RestoreStage.chooseMode]).
  BackupSummary? get incoming => _incoming;
  RestoreResult? get result => _result;
  String? get error => _error;

  Future<void> chooseFile() async {
    if (_picking || _stage == RestoreStage.opening) return;
    _picking = true;
    notifyListeners();
    try {
      final picked = await files.pick();
      if (picked == null) return;
      _forgetBackup();
      _result = null;
      if (!BackupFormat.looksLikeBackup(picked.bytes)) {
        _error = RestoreMessages.notABackup;
        _stage = RestoreStage.chooseFile;
        return;
      }
      _fileName = picked.name;
      _data = picked.bytes;
      _error = null;
      _stage = RestoreStage.enterPassword;
    } on BackupTooLarge {
      _error = RestoreMessages.tooLarge;
      _stage = RestoreStage.chooseFile;
    } catch (e) {
      debugPrint('VaultTerm: reading the backup file failed: $e');
      _error = RestoreMessages.cannotRead;
      _stage = RestoreStage.chooseFile;
    } finally {
      _picking = false;
      notifyListeners();
    }
  }

  /// Decrypts the picked file. On a wrong password it goes back to
  /// [RestoreStage.enterPassword] with an error, so the user can retry.
  Future<void> open(String password) async {
    final data = _data;
    if (data == null || _stage == RestoreStage.opening) return;
    if (password.isEmpty) {
      _error = RestoreMessages.emptyPassword;
      notifyListeners();
      return;
    }
    _error = null;
    _stage = RestoreStage.opening;
    notifyListeners();

    final String json;
    try {
      json = await cipher.open(password, data);
    } catch (e) {
      // The core says "not a VaultTerm file" for a damaged header; any
      // other failure means the password did not unlock it.
      if (e.toString().contains('not a VaultTerm file')) {
        _forgetBackup();
        _error = RestoreMessages.notABackup;
        _stage = RestoreStage.chooseFile;
      } else {
        _error = RestoreMessages.wrongPassword;
        _stage = RestoreStage.enterPassword;
      }
      notifyListeners();
      return;
    }

    try {
      final doc = VaultDocument.fromJson(jsonDecode(json) as Map<String, dynamic>);
      _json = json;
      _incoming = BackupSummary.ofDocument(doc);
      _stage = RestoreStage.chooseMode;
    } on FormatException {
      _error = RestoreMessages.unreadable;
      _stage = RestoreStage.enterPassword;
    } on TypeError {
      _error = RestoreMessages.unreadable;
      _stage = RestoreStage.enterPassword;
    }
    notifyListeners();
  }

  /// Puts the opened backup into the vault. With [replace] the current
  /// hosts, keys, snippets, known hosts, themes and settings go first.
  void apply({required bool replace}) {
    final json = _json;
    final incoming = _incoming;
    if (_stage != RestoreStage.chooseMode || json == null || incoming == null) return;
    store.importJson(json, replace: replace);
    _forgetBackup();
    _result = RestoreResult(replaced: replace, summary: incoming);
    _stage = RestoreStage.finished;
    notifyListeners();
  }

  /// Hides the last error, for example once the user retypes the password.
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Drops the picked file and goes back to the start.
  void startOver() {
    _forgetBackup();
    _result = null;
    _error = null;
    _stage = RestoreStage.chooseFile;
    notifyListeners();
  }

  /// Lets go of the file and the decrypted text, so the backup's secrets
  /// do not stay in memory longer than needed.
  void _forgetBackup() {
    _fileName = null;
    _data = null;
    _json = null;
    _incoming = null;
  }

  @override
  void dispose() {
    _forgetBackup();
    super.dispose();
  }
}
