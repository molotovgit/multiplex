import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../src/rust/api/vault.dart' as native;

/// Where the vault document is loaded from and saved to.
abstract interface class VaultBackend {
  /// The saved JSON, or null on first start.
  Future<String?> load();

  Future<void> save(String json);
}

/// The real storage: a file encrypted by the Rust core, with its key kept
/// in the platform's secure store (Android Keystore, iOS Keychain,
/// Windows Credential Manager).
class EncryptedFileBackend implements VaultBackend {
  EncryptedFileBackend._(this._path, this._key);

  static const _keyName = 'vaultterm.master_key.v1';
  static const _fileName = 'vault.vtv';

  final String _path;
  final List<int> _key;

  /// Finds the data file and the key, creating a key on first start.
  static Future<EncryptedFileBackend> open({FlutterSecureStorage storage = const FlutterSecureStorage()}) async {
    final dir = await getApplicationSupportDirectory();
    final path = '${dir.path}${Platform.pathSeparator}$_fileName';
    var encoded = await storage.read(key: _keyName);
    if (encoded == null) {
      // A key without a file is fine (first start). A file without a key
      // can never be opened again, so never replace a key that exists.
      encoded = base64Encode(native.vaultNewKey());
      await storage.write(key: _keyName, value: encoded);
    }
    return EncryptedFileBackend._(path, base64Decode(encoded));
  }

  @override
  Future<String?> load() => native.vaultLoad(path: _path, key: _key);

  @override
  Future<void> save(String json) => native.vaultSave(path: _path, key: _key, contents: json);
}

/// Keeps the document in memory only. Used by tests.
class MemoryBackend implements VaultBackend {
  MemoryBackend([this.saved]);

  String? saved;
  int saves = 0;

  @override
  Future<String?> load() async => saved;

  @override
  Future<void> save(String json) async {
    saved = json;
    saves++;
  }
}
