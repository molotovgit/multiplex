import '../../src/rust/api/keys.dart';

/// One choice in the "type of key" list.
class KeyKindOption {
  const KeyKindOption(this.kind, this.label, this.hint);

  final KeyKind kind;
  final String label;
  final String hint;
}

/// The key types people can create, in the order they are offered.
abstract final class KeyKinds {
  static const recommended = KeyKind.ed25519;

  static const options = [
    KeyKindOption(KeyKind.ed25519, 'Ed25519', 'Recommended. Short, fast and secure.'),
    KeyKindOption(KeyKind.ecdsaP256, 'ECDSA P-256', 'For servers that do not accept Ed25519.'),
    KeyKindOption(KeyKind.rsa3072, 'RSA 3072', 'For older servers.'),
    KeyKindOption(KeyKind.rsa4096, 'RSA 4096', 'For older servers. Takes a few seconds to create.'),
  ];

  /// RSA keys take long enough to create that we warn about the wait.
  static bool isSlow(KeyKind kind) => kind == KeyKind.rsa3072 || kind == KeyKind.rsa4096;
}

/// The comment at the end of a new public key, which helps tell keys
/// apart in a server's authorized_keys file.
abstract final class KeyComments {
  static String forName(String name) => name.trim().isEmpty ? 'vaultterm' : '${name.trim()}@vaultterm';
}

/// Turns the algorithm names SSH uses into names people recognise.
abstract final class KeyAlgorithms {
  static String label(String algorithm) => switch (algorithm) {
        'ssh-ed25519' => 'Ed25519',
        'ecdsa-sha2-nistp256' => 'ECDSA P-256',
        'ecdsa-sha2-nistp384' => 'ECDSA P-384',
        'ecdsa-sha2-nistp521' => 'ECDSA P-521',
        'ssh-rsa' || 'rsa-sha2-256' || 'rsa-sha2-512' => 'RSA',
        'ssh-dss' => 'DSA',
        _ when algorithm.startsWith('sk-') => 'Security key',
        '' => 'Unknown type',
        _ => algorithm,
      };
}
