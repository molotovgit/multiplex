import 'package:flutter/material.dart';

import '../data/vault_store.dart';
import '../platform/incoming_actions_handler.dart';
import '../sessions/session_manager.dart';
import '../ui/appearance/theme_switcher.dart';
import '../ui/home/home_shell.dart';
import 'app_motion.dart';
import 'app_scope.dart';
import 'lock_gate.dart';
import 'theme.dart';

/// The root widget. Rebuilds the theme whenever the user picks another
/// one, so the whole app changes at once, cross-fading at the speed of
/// the motion setting.
class MultiplexApp extends StatelessWidget {
  const MultiplexApp({super.key, required this.store, required this.sessions});

  final VaultStore store;
  final SessionManager sessions;

  /// Lets app-wide shortcuts open sheets over any screen.
  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return AppScope(
      vault: store,
      manager: sessions,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ThemeSwitcherHotkey(
          navigatorKey: navigatorKey,
          child: MaterialApp(
            title: 'Multiplex',
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(store.activeTheme),
            themeAnimationDuration: AppMotion.resolve(store.settings.motion, reduceMotion: AppMotion.systemReducesMotion).theme,
            home: const LockGate(child: IncomingActionsHandler(child: HomeShell())),
          ),
        ),
      ),
    );
  }
}
