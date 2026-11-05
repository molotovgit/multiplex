import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../../app/app_scope.dart';
import '../common/widgets.dart';

/// What happened when we asked the device to confirm it is the owner.
enum UnlockResult {
  /// The user unlocked: the device can protect the app.
  passed,

  /// The user closed the prompt.
  cancelled,

  /// The device has no PIN, pattern, password, fingerprint or face set up.
  noScreenLock,

  /// This device or platform cannot check the user at all.
  notSupported,

  /// Too many wrong tries; the device wants the user to wait.
  lockedOut,

  /// Something else went wrong.
  failed,
}

/// Asks the device (fingerprint, face, PIN or password) to confirm the
/// owner. Used before turning on app lock, to prove the device can unlock
/// the app later; otherwise the user could lock themselves out.
class DeviceUnlock {
  const DeviceUnlock();

  Future<UnlockResult> confirm() async {
    final auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) return UnlockResult.noScreenLock;
      final ok = await auth.authenticate(localizedReason: 'Confirm it is you to turn on app lock');
      return ok ? UnlockResult.passed : UnlockResult.cancelled;
    } on LocalAuthException catch (e) {
      return resultFor(e.code);
    } catch (_) {
      // No local_auth support on this platform (for example Linux).
      return UnlockResult.notSupported;
    }
  }

  /// Turns the plugin's error code into one of our results. The plugin may
  /// add codes later, so anything unknown counts as a plain failure.
  static UnlockResult resultFor(LocalAuthExceptionCode code) => switch (code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.userRequestedFallback ||
        LocalAuthExceptionCode.authInProgress =>
          UnlockResult.cancelled,
        LocalAuthExceptionCode.noCredentialsSet || LocalAuthExceptionCode.noBiometricsEnrolled => UnlockResult.noScreenLock,
        LocalAuthExceptionCode.noBiometricHardware || LocalAuthExceptionCode.uiUnavailable => UnlockResult.notSupported,
        LocalAuthExceptionCode.temporaryLockout || LocalAuthExceptionCode.biometricLockout => UnlockResult.lockedOut,
        _ => UnlockResult.failed,
      };
}

/// The words shown for each [UnlockResult].
abstract final class AppLockMessages {
  static const turnedOn = 'App lock is on. Multiplex asks for your fingerprint, face or PIN when it opens.';
  static const turnedOff = 'App lock is off.';
  static const cancelled = 'App lock is still off.';
  static const lockedOut = 'Too many tries. Wait a moment, then try again.';
  static const failed = 'The check did not work, so app lock is still off. Try again.';

  static const noScreenLockTitle = 'Set up a screen lock first';
  static const noScreenLock = 'App lock uses the way you unlock this device: fingerprint, face, PIN, pattern or password. '
      'None is set up yet. Add one in the device settings, then turn on app lock again.';

  static const notSupportedTitle = 'App lock is not available here';
  static const notSupported = 'This device cannot check a fingerprint, face or PIN for Multiplex, so the app cannot lock itself.';
}

/// The "App lock" switch. Turning it on first asks the device to confirm
/// the owner; if that is not possible it explains why and stays off.
class AppLockSwitch extends StatefulWidget {
  const AppLockSwitch({super.key, required this.unlock, required this.on});

  final DeviceUnlock unlock;

  /// Whether app lock is on now.
  final bool on;

  @override
  State<AppLockSwitch> createState() => _AppLockSwitchState();
}

class _AppLockSwitchState extends State<AppLockSwitch> {
  /// True while the device prompt is open, so a second tap does nothing.
  bool _checking = false;

  Future<void> _changed(bool on) async {
    final store = AppScope.store(context);
    if (!on) {
      store.updateSettings(store.settings.copyWith(appLock: false));
      Toast.show(context, AppLockMessages.turnedOff);
      return;
    }
    setState(() => _checking = true);
    final result = await widget.unlock.confirm();
    if (!mounted) return;
    setState(() => _checking = false);
    switch (result) {
      case UnlockResult.passed:
        store.updateSettings(store.settings.copyWith(appLock: true));
        Toast.show(context, AppLockMessages.turnedOn);
      case UnlockResult.cancelled:
        Toast.show(context, AppLockMessages.cancelled);
      case UnlockResult.lockedOut:
        Toast.show(context, AppLockMessages.lockedOut);
      case UnlockResult.failed:
        Toast.show(context, AppLockMessages.failed);
      case UnlockResult.noScreenLock:
        await _explain(AppLockMessages.noScreenLockTitle, AppLockMessages.noScreenLock);
      case UnlockResult.notSupported:
        await _explain(AppLockMessages.notSupportedTitle, AppLockMessages.notSupported);
    }
  }

  Future<void> _explain(String title, String message) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.fingerprint),
      title: const Text('App lock'),
      subtitle: const Text('Ask for fingerprint, face or device PIN when Multiplex opens'),
      value: widget.on,
      onChanged: _checking ? null : _changed,
    );
  }
}
