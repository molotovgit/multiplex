import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'app_scope.dart';
import 'theme.dart';

/// Covers the app until the user unlocks it with fingerprint, face or the
/// device PIN, when "App lock" is on. It locks again after the app has
/// been in the background for a while.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  /// Coming back sooner than this does not ask again.
  static const _grace = Duration(seconds: 60);

  final _auth = LocalAuthentication();
  bool _unlocked = false;
  bool _asking = false;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _leftAt = DateTime.now();
      AppScope.store(context).flush();
    } else if (state == AppLifecycleState.resumed && _leftAt != null) {
      if (DateTime.now().difference(_leftAt!) > _grace && _lockEnabled) {
        setState(() => _unlocked = false);
        _unlock();
      }
    }
  }

  bool get _lockEnabled => AppScope.store(context).settings.appLock;

  Future<void> _unlock() async {
    if (!_lockEnabled) {
      setState(() => _unlocked = true);
      return;
    }
    if (_asking) return;
    _asking = true;
    try {
      final ok = await _auth.authenticate(localizedReason: 'Unlock Multiplex');
      if (mounted) setState(() => _unlocked = ok);
    } catch (_) {
      // No biometrics or PIN set up on this device: do not lock the user out.
      if (mounted) setState(() => _unlocked = true);
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked || !_lockEnabled) return widget.child;
    final colors = AppColorsTheme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: colors.accent),
            const SizedBox(height: 16),
            Text('Multiplex is locked', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: _unlock, icon: const Icon(Icons.fingerprint), label: const Text('Unlock')),
          ],
        ),
      ),
    );
  }
}
