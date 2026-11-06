import 'package:local_auth/local_auth.dart';
import 'package:multiplex/app/lock_gate.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/otp_account.dart';
import 'package:multiplex/sessions/connect_flow.dart';
import 'package:multiplex/src/rust/api/ssh.dart';
import 'package:multiplex/src/rust/api/ssh_types.dart';

/// Answers the fingerprint prompt the way a test says.
class FakeUnlock extends DeviceUnlock {
  FakeUnlock([this.answer = true]);

  /// true, false, or an exception to throw.
  Object answer;
  final reasons = <String>[];

  @override
  Future<bool> confirm() => confirmTo('Unlock Multiplex');

  @override
  Future<bool> confirmTo(String reason) async {
    reasons.add(reason);
    final answer = this.answer;
    if (answer is bool) return answer;
    throw answer;
  }

  @override
  Future<bool> hasAnyLock() async => true;

  static const cancelled = LocalAuthException(code: LocalAuthExceptionCode.userCanceled);
  static const noLock = LocalAuthException(code: LocalAuthExceptionCode.noCredentialsSet);
}

/// Stands in for the SSH connection: fails with the given errors in turn,
/// and records the options of every attempt. When the errors run out it
/// times out, which ends the flow with a [ConnectFailure].
class FakeConnector {
  FakeConnector([List<ConnectError>? errors]) : errors = errors ?? [];

  final List<ConnectError> errors;
  final attempts = <ConnectOptions>[];

  Future<SshSession> call(ConnectOptions options) async {
    attempts.add(options);
    throw errors.isEmpty ? const ConnectError.timeout() : errors.removeAt(0);
  }
}

/// Answers the connection's questions from fixed values and records them.
class FakePrompter implements ConnectPrompter {
  final asked = <String>[];
  bool trust = true;
  SecretAnswer? password = const SecretAnswer('pw');

  @override
  Future<bool> trustNewHost(String host, int port, HostKeyInfo key) async {
    asked.add('trust $host');
    return trust;
  }

  @override
  Future<bool> acceptChangedHost(String host, int port, HostKeyInfo key, KnownHost? previous) async {
    asked.add('changed $host');
    return trust;
  }

  @override
  Future<SecretAnswer?> askPassword(String host, String username, {required bool wasWrong}) async {
    asked.add('password $host${wasWrong ? ' wrong' : ''}');
    return password;
  }

  @override
  Future<SecretAnswer?> askPassphrase(StoredKey key, {required bool wasWrong}) async {
    asked.add('passphrase ${key.name}');
    return null;
  }

  /// Codes to answer with, in turn; null cancels.
  final codes = <String?>[];
  final offered = <List<OtpAccount>>[];

  @override
  Future<String?> askCode(String host, String prompt, List<OtpAccount> linked, {required bool wasWrong}) async {
    asked.add('code $host "$prompt"${wasWrong ? ' wrong' : ''}');
    offered.add(linked);
    return codes.isEmpty ? null : codes.removeAt(0);
  }
}
