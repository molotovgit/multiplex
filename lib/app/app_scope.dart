import 'package:flutter/widgets.dart';

import '../data/vault_store.dart';
import '../sessions/session_manager.dart';

/// Hands the app's long-lived objects to every screen.
///
/// - `AppScope.watch(context)` inside `build`: the widget redraws whenever
///   saved data or settings change.
/// - `AppScope.store(context)` in callbacks and `initState`: reads without
///   redrawing.
/// - `AppScope.sessions(context)`: the live connections. They change
///   often (tunnel counters tick), so wrap the parts that show them in a
///   `ListenableBuilder` instead of redrawing whole screens.
class AppScope extends InheritedNotifier<VaultStore> {
  const AppScope({super.key, required VaultStore vault, required this.manager, required super.child}) : super(notifier: vault);

  final SessionManager manager;

  static AppScope _read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!;
  }

  /// The saved data, redrawing this widget when it changes.
  static VaultStore watch(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!.notifier!;
  }

  /// The saved data (hosts, keys, snippets, themes, settings), without
  /// redrawing.
  static VaultStore store(BuildContext context) => _read(context).notifier!;

  /// The open connections, terminals and tunnels.
  static SessionManager sessions(BuildContext context) => _read(context).manager;
}
