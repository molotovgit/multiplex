import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../data/vault_document.dart';
import '../../data/vault_store.dart';
import '../../src/rust/api/vault.dart' as core;
import 'settings_widgets.dart';

/// Encrypts and decrypts backups with the user's password.
abstract interface class BackupCipher {
  /// Takes about a second: the password is stretched on purpose so that
  /// guessing it is slow.
  Future<Uint8List> seal(String password, String json);

  /// Returns the JSON inside, or throws when the password is wrong or the
  /// data is not a backup.
  Future<String> open(String password, List<int> data);
}

/// The real cipher, in the Rust core.
class CoreBackupCipher implements BackupCipher {
  const CoreBackupCipher();

  @override
  Future<Uint8List> seal(String password, String json) => core.backupSeal(password: password, contents: json);

  @override
  Future<String> open(String password, List<int> data) => core.backupOpen(password: password, data: data);
}

/// A file the user picked: its name and contents.
class PickedBackup {
  const PickedBackup(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

/// Thrown when a picked file is far too big to be a backup.
class BackupTooLarge implements Exception {
  const BackupTooLarge();
}

/// Where backups are saved to and read from.
abstract interface class BackupFiles {
  /// Asks where to save [bytes] under the suggested [fileName]. Returns
  /// false when the user closed the save window.
  Future<bool> save(String fileName, Uint8List bytes);

  /// Asks for a file and reads it. Returns null when the user closed the
  /// picker.
  Future<PickedBackup?> pick();
}

/// The real files, through the platform's own save and open windows.
class PickerBackupFiles implements BackupFiles {
  const PickerBackupFiles();

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    final saved = await FilePicker.saveFile(fileName: fileName, bytes: bytes, dialogTitle: 'Save the backup');
    return saved != null;
  }

  @override
  Future<PickedBackup?> pick() async {
    final file = await FilePicker.pickFile(dialogTitle: 'Choose a VaultTerm backup');
    if (file == null) return null;
    final size = file.lengthSync() ?? await file.length();
    if (size != null && size > BackupFormat.maxBytes) throw const BackupTooLarge();
    final bytes = await file.readAsBytes();
    // Phones copy the picked file into the app's cache; tidy it away. The
    // copy is encrypted, so a failure here is harmless.
    await FilePicker.clearTemporaryFiles().catchError((Object _) {});
    return PickedBackup(file.name, bytes);
  }
}

/// What a backup file looks like on the outside. The Rust core checks
/// this too; checking here as well lets us say "not a backup" before
/// asking for a password.
abstract final class BackupFormat {
  /// Backups start with the letters "VTB1".
  static const magic = [0x56, 0x54, 0x42, 0x31];

  /// Magic, three numbers for the key settings, salt, then the nonce.
  static const minBytes = 4 + 12 + 16 + 24;

  /// Real backups are small (text); anything bigger is the wrong file.
  static const maxBytes = 64 * 1024 * 1024;

  static const extension = 'vtbackup';

  static bool looksLikeBackup(List<int> bytes) {
    if (bytes.length < minBytes) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  /// "vaultterm-backup-2026-11-05.vtbackup", using the local date.
  static String fileNameFor(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'vaultterm-backup-${date.year}-${two(date.month)}-${two(date.day)}.$extension';
  }
}

/// Rules for the backup password.
abstract final class BackupPassword {
  static const minLength = 8;

  /// An error to show under the password field, or null when it is fine.
  static String? check(String password) {
    if (password.isEmpty) return 'Choose a password for the backup.';
    if (password.length < minLength) return 'Use at least $minLength characters.';
    return null;
  }

  /// An error to show under the second field, or null when both match.
  static String? checkRepeat(String password, String repeat) {
    if (repeat.isEmpty) return 'Type the password again.';
    if (repeat != password) return 'The two passwords do not match.';
    return null;
  }
}

/// How many of each thing a backup holds.
class BackupSummary {
  const BackupSummary({
    required this.hosts,
    required this.keys,
    required this.snippets,
    required this.knownHosts,
    required this.themes,
  });

  /// What a backup made now would hold.
  factory BackupSummary.ofStore(VaultStore store) => BackupSummary(
        hosts: store.hosts.length,
        keys: store.keys.length,
        snippets: store.snippets.length,
        knownHosts: store.knownHosts.length,
        themes: store.customThemes.length,
      );

  /// What an opened backup holds.
  factory BackupSummary.ofDocument(VaultDocument doc) => BackupSummary(
        hosts: doc.hosts.length,
        keys: doc.keys.length,
        snippets: doc.snippets.length,
        knownHosts: doc.knownHosts.length,
        themes: doc.customThemes.length,
      );

  final int hosts;
  final int keys;
  final int snippets;
  final int knownHosts;

  /// Themes the user made or imported; the built-in ones are not saved.
  final int themes;

  /// Each count with its name, in a fixed order.
  List<(int, String)> get parts => [
        (hosts, SettingsFormat.count(hosts, 'host', 'hosts')),
        (keys, SettingsFormat.count(keys, 'key', 'keys')),
        (snippets, SettingsFormat.count(snippets, 'snippet', 'snippets')),
        (knownHosts, SettingsFormat.count(knownHosts, 'known host', 'known hosts')),
        (themes, SettingsFormat.count(themes, 'theme', 'themes')),
      ];

  /// "3 hosts, 2 keys, 5 snippets, 4 known hosts and 1 theme".
  String describe() => SettingsFormat.list([for (final (_, text) in parts) text]);
}
