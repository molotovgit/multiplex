import 'package:flutter/material.dart';

import '../../data/models.dart';

/// Keys and known hosts.
class KeychainScreen extends StatelessWidget {
  const KeychainScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Keychain')));
}

/// Creates or imports a key from anywhere in the app (for example the host
/// editor) and returns it, already saved in the vault.
abstract final class KeyCreator {
  static Future<StoredKey?> open(BuildContext context) async => null;
}
