import 'package:flutter/widgets.dart';

import 'update_controller.dart';

/// Hands the [UpdateController] to the screens that show updates, and
/// tells it when the app comes back to the screen (after the "Install
/// unknown apps" page). Screens built without one (tests, other
/// platforms) simply show nothing.
class UpdateScope extends StatefulWidget {
  const UpdateScope({super.key, required this.controller, required this.child});

  final UpdateController controller;
  final Widget child;

  /// The controller, redrawing [context] when it changes; null when none.
  static UpdateController? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_UpdateNotifier>()?.notifier;

  @override
  State<UpdateScope> createState() => _UpdateScopeState();
}

class _UpdateScopeState extends State<UpdateScope> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => widget.controller.resumed());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _UpdateNotifier(notifier: widget.controller, child: widget.child);
}

class _UpdateNotifier extends InheritedNotifier<UpdateController> {
  const _UpdateNotifier({required super.notifier, required super.child});
}
