import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/vault_store.dart';
import '../src/rust/api/keys.dart';
import '../src/rust/api/pairing.dart';
import '../src/rust/api/ssh_types.dart';
import 'tailscale_node.dart';

/// Pairs the phone with a computer from the QR code `multiplex pair` shows
/// there, and saves what the pairing gives: the phone's own key, the
/// computer's host key (so the first connection already trusts it) and the
/// computer itself, with its home-network address and its Tailscale name.
///
/// The exchange is in the Rust core; this class gathers what it needs and
/// stores the result.
class PairingFlow {
  PairingFlow(this._store, {MethodChannel channel = const MethodChannel('multiplex/pair')})
    // ignore: prefer_initializing_formals
    : _channel = channel;

  final VaultStore _store;
  final MethodChannel _channel;

  /// The name of the key that is this phone's identity on paired computers.
  static const phoneKeyName = 'This phone';

  /// Opens the camera scanner. Null when the user closed it.
  Future<String?> scan() => _channel.invokeMethod<String>('scan');

  /// Reads a code without pairing yet; throws with a sentence for the user.
  PairingInfo read(String code) => pairingRead(code: code);

  Future<String> _phoneName() async {
    try {
      return await _channel.invokeMethod<String>('deviceName') ?? 'Phone';
    } catch (_) {
      return 'Phone';
    }
  }

  /// Pairs and saves. Returns the saved computer.
  Future<Host> pair(String code) async {
    // One key is this phone's identity everywhere; made on first pairing.
    var key = _store.keys.where((k) => k.name == phoneKeyName && !k.encrypted).firstOrNull;
    final isNewKey = key == null;
    if (key == null) {
      final made = await generateKey(kind: KeyKind.ed25519, comment: 'multiplex-phone', passphrase: null);
      key = StoredKey(
        id: VaultStore.newId(),
        name: phoneKeyName,
        privatePem: made.privatePem,
        publicOpenssh: made.publicOpenssh,
        fingerprint: made.fingerprint,
        algorithm: made.algorithm,
        passphrase: null,
        encrypted: false,
        createdAt: DateTime.now(),
      );
    }
    final outcome = await pairingRegister(
      code: code,
      phoneKey: key.publicOpenssh,
      phoneName: await _phoneName(),
      tailscaleReady: await TailscaleNode.instance.usableSoon(),
    );
    final info = outcome.info;
    if (isNewKey) _store.saveKey(key);

    // The host key from the code is trusted for every name the computer
    // answers to, so no "trust this server?" question ever comes.
    final hostKey = HostKeyInfo(
      algorithm: 'ssh-ed25519',
      fingerprint: publicKeyFingerprint(publicOpenssh: info.hostKey),
      publicKey: info.hostKey,
    );
    for (final name in {...info.addresses, ?info.tailscale}) {
      _store.trustHostKey(name, info.port, hostKey);
    }

    final home = info.addresses.firstOrNull;
    final known = _store.hosts.where((h) => h.computer && h.label == info.name).firstOrNull;
    final host = (known ?? Host(id: VaultStore.newId(), label: info.name, address: '')).copyWith(
      // Without a home-network address the computer is reached over Tailscale only.
      address: home ?? info.tailscale!,
      viaTailscale: home == null,
      port: info.port,
      username: info.user,
      authMode: AuthMode.key,
      keyId: () => key!.id,
      password: () => null,
      jumpHostId: () => null,
      computer: true,
      tailscaleName: () => home == null ? null : info.tailscale,
      mac: () => info.mac,
      pairedAs: () => outcome.phoneName,
      favourite: true,
    );
    _store.saveHost(host);
    return host;
  }
}
