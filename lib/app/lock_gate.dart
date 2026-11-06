import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'app_scope.dart';
import 'theme.dart';

/// Asks the phone to confirm it is the owner: fingerprint, face or the
/// device PIN. A class so tests can stand in for the phone.
class DeviceUnlock {
  const DeviceUnlock();

  static final _auth = LocalAuthentication();

  /// True when the owner confirmed. Throws [LocalAuthException] when the
  /// prompt was cancelled or could not be shown.
  Future<bool> confirm() => confirmTo('Unlock Multiplex');

  /// The same check, with [reason] shown in the prompt (for example
  /// before connecting to a host marked sensitive).
  Future<bool> confirmTo(String reason) => _auth.authenticate(localizedReason: reason);

  /// Whether the phone has any lock (biometrics or a PIN) to confirm with.
  Future<bool> hasAnyLock() => _auth.isDeviceSupported();
}

/// Covers the app until the user unlocks it with fingerprint, face or the
/// device PIN, when "App lock" is on. It locks again after the app has
/// been in the background for a while.
///
/// Only a confirmed unlock opens the app. Cancelling the prompt, a timeout
/// or a lockout leave it locked, with a button to try again. The one way in
/// without confirming is a phone with no lock at all, where the prompt can
/// never succeed and the user would be shut out of their own data.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child, this.unlock = const DeviceUnlock()});

  final Widget child;
  final DeviceUnlock unlock;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  /// Coming back sooner than this does not ask again.
  static const _grace = Duration(seconds: 60);

  bool _unlocked = false;
  bool _asking = false;
  DateTime? _leftAt;

  /// Why the last try did not unlock, shown under the button.
  String? _message;

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
    var open = false;
    String? message;
    try {
      open = await widget.unlock.confirm();
      if (!open) message = 'Not unlocked. Try again.';
    } on LocalAuthException catch (e) {
      if (e.code == LocalAuthExceptionCode.noCredentialsSet) {
        open = true;
      } else {
        message = _why(e.code);
      }
    } catch (_) {
      // Something unexpected: open only if the phone has no lock to check.
      open = !await _hasAnyLock();
      if (!open) message = 'Could not ask for your fingerprint or PIN. Try again.';
    } finally {
      _asking = false;
    }
    if (mounted) {
      setState(() {
        _unlocked = open;
        _message = message;
      });
    }
  }

  Future<bool> _hasAnyLock() async {
    try {
      return await widget.unlock.hasAnyLock();
    } catch (_) {
      return true;
    }
  }

  static String _why(LocalAuthExceptionCode code) => switch (code) {
        LocalAuthExceptionCode.userCanceled || LocalAuthExceptionCode.systemCanceled => 'Unlock was cancelled.',
        LocalAuthExceptionCode.timeout => 'The unlock prompt timed out.',
        LocalAuthExceptionCode.temporaryLockout => 'Too many tries. Wait a moment, then try again.',
        LocalAuthExceptionCode.biometricLockout => 'Fingerprint is locked. Unlock with your PIN.',
        _ => 'Not unlocked. Try again.',
      };

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
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: TextStyle(color: colors.muted)),
            ],
          ],
        ),
      ),
    );
  }
}
