import 'package:flutter/material.dart';

import '../data/vault_store.dart';
import '../sessions/session_manager.dart';
import '../ui/home/home_shell.dart';
import 'app_scope.dart';
import 'lock_gate.dart';
import 'theme.dart';

/// The root widget. Rebuilds the theme whenever the user picks another
/// one, so the whole app changes at once.
class VaultTermApp extends StatelessWidget {
  const VaultTermApp({super.key, required this.store, required this.sessions});

  final VaultStore store;
  final SessionManager sessions;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      vault: store,
      manager: sessions,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) => MaterialApp(
          title: 'VaultTerm',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(store.activeTheme),
          home: const LockGate(child: HomeShell()),
        ),
      ),
    );
  }
}
