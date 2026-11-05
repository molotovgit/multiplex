import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';

import '../../src/rust/api/keys.dart' as native;
import '../../src/rust/api/keys.dart' show KeyKind, KeyPairInfo;

/// What went wrong with a key, sorted into the cases the screens explain
/// differently.
enum KeyProblemKind {
  /// The key is protected and no passphrase was given.
  passphraseNeeded,

  /// A passphrase was given but it does not unlock the key.
  wrongPassphrase,

  /// The text is not a private key the app can read.
  unreadable,

  /// Anything else (for example, creating the key failed).
  failed,
}

/// A key operation failed. [detail] is the technical reason, for the
/// rare cases where it helps.
class KeyProblem implements Exception {
  const KeyProblem(this.kind, this.detail);

  final KeyProblemKind kind;
  final String detail;

  @override
  String toString() => 'KeyProblem(${kind.name}): $detail';
}

/// The key operations the screens need. The real one calls the Rust core;
/// tests pass in a stand-in so they run without the native library.
abstract interface class KeyTools {
  /// Creates a new key pair. Throws [KeyProblem].
  Future<KeyPairInfo> generate(KeyKind kind, {required String comment, String? passphrase});

  /// Reads a pasted or imported private key. Throws [KeyProblem] when the
  /// passphrase is missing or wrong, or the text is not a key.
  Future<KeyPairInfo> inspect(String pem, {String? passphrase});

  /// True when the key text needs a passphrase.
  bool isEncrypted(String pem);
}

/// [KeyTools] backed by the Rust core.
class NativeKeyTools implements KeyTools {
  const NativeKeyTools();

  @override
  Future<KeyPairInfo> generate(KeyKind kind, {required String comment, String? passphrase}) async {
    try {
      return await native.generateKey(kind: kind, comment: comment, passphrase: passphrase);
    } catch (error) {
      throw _problem(error);
    }
  }

  @override
  Future<KeyPairInfo> inspect(String pem, {String? passphrase}) async {
    try {
      return await native.inspectPrivateKey(pem: pem, passphrase: passphrase);
    } catch (error) {
      throw _problem(error);
    }
  }

  @override
  bool isEncrypted(String pem) {
    try {
      return native.privateKeyIsEncrypted(pem: pem);
    } catch (_) {
      // Text that cannot be read at all is not "encrypted"; the check
      // that follows reports it as unreadable.
      return false;
    }
  }

  /// The core reports its errors as plain sentences; sort them by the
  /// wording it uses (see rust/src/engine/keys.rs, KeyError).
  static KeyProblem _problem(Object error) {
    final text = error is AnyhowException ? error.message : error.toString();
    final lower = text.toLowerCase();
    final kind = lower.contains('protected with a passphrase')
        ? KeyProblemKind.passphraseNeeded
        : lower.contains('passphrase is wrong')
            ? KeyProblemKind.wrongPassphrase
            : lower.contains('not a private key')
                ? KeyProblemKind.unreadable
                : KeyProblemKind.failed;
    return KeyProblem(kind, text);
  }
}
