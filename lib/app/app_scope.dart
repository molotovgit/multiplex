import 'package:flutter/widgets.dart';

import '../data/vault_store.dart';
import '../sessions/session_manager.dart';

/// Hands the app's long-lived objects to every screen:
/// `AppScope.store(context)`, `AppScope.sessions(context)`.
///
/// Screens that must redraw on changes wrap the part that depends on them
/// in a `ListenableBuilder`.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.vault, required this.manager, required super.child});

  final VaultStore vault;
  final SessionManager manager;

  static AppScope _of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!;
  }

  /// The saved data (hosts, keys, snippets, themes, settings).
  static VaultStore store(BuildContext context) => _of(context).vault;

  /// The open connections, terminals and tunnels.
  static SessionManager sessions(BuildContext context) => _of(context).manager;

  @override
  bool updateShouldNotify(AppScope oldWidget) => vault != oldWidget.vault || manager != oldWidget.manager;
}
