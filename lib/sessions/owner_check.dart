import 'package:local_auth/local_auth.dart';

import '../app/lock_gate.dart';
import '../data/models.dart';
import 'connect_flow.dart';

/// Hosts marked "Ask for fingerprint before connecting" need the owner's
/// fingerprint, face or PIN for every new connection, even while the app
/// itself is unlocked. A jump host marked that way counts too.
///
/// Only a confirmed check lets the connection go ahead. Cancelling stops
/// it quietly; anything else stops it with a reason.
class OwnerCheck {
  const OwnerCheck(this._unlock);

  final DeviceUnlock _unlock;

  /// Whether connecting to [host] (through [jump]) needs the check.
  static bool needed(Host host, Host? jump) => host.askUnlock || (jump?.askUnlock ?? false);

  /// Returns when the owner confirmed; throws [ConnectCancelled] or
  /// [ConnectFailure] otherwise.
  Future<void> require(Host host) async {
    bool confirmed;
    try {
      confirmed = await _unlock.confirmTo('Confirm it is you to connect to ${host.title}');
    } on LocalAuthException catch (e) {
      throw _failureFor(e.code);
    } catch (_) {
      throw const ConnectFailure(
        'Could not check your fingerprint',
        'This host needs your fingerprint, face or PIN before it connects, and the check could not be shown. Try again.',
      );
    }
    if (!confirmed) throw const ConnectCancelled();
  }

  static Exception _failureFor(LocalAuthExceptionCode code) => switch (code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback ||
        LocalAuthExceptionCode.timeout =>
          const ConnectCancelled(),
        LocalAuthExceptionCode.noCredentialsSet => const ConnectFailure(
            'Set up a screen lock first',
            'This host asks for your fingerprint or PIN before connecting, but this phone has no screen lock. '
                'Add one in the phone settings, or turn the option off in the host settings.',
          ),
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout =>
          const ConnectFailure('Too many tries', 'Wait a moment, then try again. You can also unlock with your PIN.'),
        _ => const ConnectFailure('Not confirmed', 'The fingerprint or PIN check did not succeed, so Multiplex did not connect.'),
      };
}
