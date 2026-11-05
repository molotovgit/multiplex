import 'package:flutter/material.dart';

import 'src/rust/frb_generated.dart';

/// Temporary entry point while the native core is being built.
Future<void> main() async {
  await RustLib.init();
  runApp(const VaultTermApp());
}

class VaultTermApp extends StatelessWidget {
  const VaultTermApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'VaultTerm',
      home: Scaffold(body: Center(child: Text('VaultTerm'))),
    );
  }
}
