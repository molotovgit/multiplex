import '../app/lock_gate.dart';
import '../data/models.dart';
import '../data/otp_account.dart';
import '../data/vault_store.dart';
import '../src/rust/api/ssh.dart';
import '../src/rust/api/ssh_types.dart';
import 'owner_check.dart';

/// A secret the user typed, and whether to keep it in the vault.
class SecretAnswer {
  const SecretAnswer(this.value, {this.remember = false});

  final String value;
  final bool remember;
}

/// The questions a connection may need to ask the user. The UI answers
/// them with dialogs; tests answer them directly.
abstract interface class ConnectPrompter {
  /// First visit to a server: show the fingerprint, ask to trust it.
  Future<bool> trustNewHost(String host, int port, HostKeyInfo key);

  /// The server's key is different from before. Must be a strong warning.
  Future<bool> acceptChangedHost(String host, int port, HostKeyInfo key, KnownHost? previous);

  /// The server refused the login or no password is saved.
  Future<SecretAnswer?> askPassword(String host, String username, {required bool wasWrong});

  Future<SecretAnswer?> askPassphrase(StoredKey key, {required bool wasWrong});

  /// The server asks for a one-time code ([prompt] is its own question).
  /// [linked] are the code accounts linked to this host, to offer in one
  /// tap. Returns the code, or null to cancel.
  Future<String?> askCode(String host, String prompt, List<OtpAccount> linked, {required bool wasWrong});
}

/// Opens the SSH connection; tests pass a stand-in.
typedef SshConnector = Future<SshSession> Function(ConnectOptions options);

/// The user chose not to continue.
class ConnectCancelled implements Exception {
  const ConnectCancelled();
}

/// A connection problem explained for people.
class ConnectFailure implements Exception {
  const ConnectFailure(this.title, this.detail);

  final String title;
  final String detail;

  @override
  String toString() => '$title: $detail';
}

/// Turns a saved [Host] into a logged-in [SshSession], asking the user
/// whatever is needed on the way (trust this server? password?).
class ConnectFlow {
  ConnectFlow(this._store, this._prompter, {DeviceUnlock unlock = const DeviceUnlock(), SshConnector? connector, this.ownerConfirmed = false})
      : _ownerCheck = OwnerCheck(unlock),
        _connector = connector ?? ((options) => SshSession.connect(options: options));

  final VaultStore _store;
  final ConnectPrompter _prompter;
  final OwnerCheck _ownerCheck;
  final SshConnector _connector;

  /// The owner already confirmed this session (a reconnect of a session
  /// that was approved when it opened), so the fingerprint is not asked
  /// again.
  final bool ownerConfirmed;

  /// Each question can lead to one more attempt; this stops endless loops.
  static const _maxAttempts = 8;
  static const _timeoutSecs = 20;

  Future<SshSession> connect(Host host) async {
    final jump = _store.host(host.jumpHostId);
    if (!ownerConfirmed && OwnerCheck.needed(host, jump)) await _ownerCheck.require(host);
    final secrets = _Secrets(
      password: host.password,
      passphrase: _store.key(host.keyId)?.passphrase,
      jumpPassword: jump?.password,
      jumpPassphrase: _store.key(jump?.keyId)?.passphrase,
    );

    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        return await _connector(_options(host, jump, secrets));
      } on ConnectError catch (error) {
        await _handle(error, host, jump, secrets);
      }
    }
    throw const ConnectFailure('Could not log in', 'Too many attempts. Check the user name and password or key.');
  }

  /// Answers one failure: either fixes what is missing (and returns, so the
  /// loop tries again) or throws a [ConnectFailure] / [ConnectCancelled].
  Future<void> _handle(ConnectError error, Host host, Host? jump, _Secrets secrets) async {
    switch (error) {
      case ConnectError_HostKeyUnknown(:final host, :final port, :final key):
        if (!await _prompter.trustNewHost(host, port, key)) throw const ConnectCancelled();
        _store.trustHostKey(host, port, key);
      case ConnectError_HostKeyChanged(:final host, :final port, :final key):
        final previous = _store.knownHosts.where((k) => k.host == host && k.port == port).firstOrNull;
        if (!await _prompter.acceptChangedHost(host, port, key, previous)) throw const ConnectCancelled();
        _store.trustHostKey(host, port, key);
      case ConnectError_CodeNeeded(host: final askingHost, :final prompt):
        final isJump = _isJump(askingHost, host, jump);
        final target = isJump ? jump! : host;
        final code = await _prompter.askCode(target.address, prompt, _store.otpFor(target.id), wasWrong: secrets.codeRefused);
        if (code == null || code.trim().isEmpty) throw const ConnectCancelled();
        secrets.setCode(isJump: isJump, code.trim());
      case ConnectError_AuthFailed(host: final failedHost):
        final isJump = _isJump(failedHost, host, jump);
        final target = isJump ? jump! : host;
        // Refused right after a code: most often the code was late or
        // mistyped, so the first time only a new code is asked for; after
        // that the password is asked again too.
        if (secrets.codeFor(isJump: isJump) != null) {
          secrets.setCode(isJump: isJump, null);
          secrets.codeRefused = true;
          if (++secrets.codeRefusals == 1) return;
        }
        final hadOne = (isJump ? secrets.jumpPassword : secrets.password) != null;
        final answer = await _prompter.askPassword(target.address, target.username, wasWrong: hadOne);
        if (answer == null) throw const ConnectCancelled();
        if (isJump) {
          secrets.jumpPassword = answer.value;
        } else {
          secrets.password = answer.value;
        }
        if (answer.remember) _store.saveHost(target.copyWith(password: () => answer.value));
      case ConnectError_KeyNeedsPassphrase():
      case ConnectError_KeyWrongPassphrase():
        await _askPassphrase(host, jump, secrets, wasWrong: error is ConnectError_KeyWrongPassphrase);
      case ConnectError_KeyUnreadable(:final reason):
        throw ConnectFailure('This key cannot be used', reason);
      case ConnectError_Network(:final host, :final port, :final message):
        throw ConnectFailure('Cannot reach $host:$port', message);
      case ConnectError_Timeout():
        throw const ConnectFailure('No answer from the server', 'Check the address, the port and your network, then try again.');
      case ConnectError_Protocol(:final message):
        throw ConnectFailure('The connection failed', message);
    }
  }

  static bool _isJump(String reported, Host host, Host? jump) => jump != null && reported == jump.address && reported != host.address;

  /// Asks for the passphrase of whichever key still lacks one: the
  /// target's key first, then the jump host's.
  Future<void> _askPassphrase(Host host, Host? jump, _Secrets secrets, {required bool wasWrong}) async {
    final ownKey = host.usesKey ? _store.key(host.keyId) : null;
    final jumpKey = (jump?.usesKey ?? false) ? _store.key(jump!.keyId) : null;
    final forJump = ownKey == null || (!ownKey.encrypted && jumpKey != null);
    final key = forJump ? jumpKey : ownKey;
    if (key == null) throw const ConnectFailure('Key problem', 'A key needs a passphrase but could not be found.');
    final answer = await _prompter.askPassphrase(key, wasWrong: wasWrong);
    if (answer == null) throw const ConnectCancelled();
    if (forJump) {
      secrets.jumpPassphrase = answer.value;
    } else {
      secrets.passphrase = answer.value;
    }
    if (answer.remember) _store.saveKey(key.copyWith(passphrase: () => answer.value));
  }

  ConnectOptions _options(Host host, Host? jump, _Secrets secrets) => ConnectOptions(
        host: host.address,
        port: host.port,
        username: host.username,
        credentials: _credentials(host, secrets.password, secrets.passphrase, secrets.code),
        trustedHostKeys: _store.trustedKeysFor(host.address, host.port),
        keepaliveSecs: _store.settings.keepAliveSecs,
        connectTimeoutSecs: _timeoutSecs,
        // Only a key can be forwarded; a password login has none.
        forwardAgent: host.forwardAgent && host.usesKey,
        jump: jump == null
            ? null
            : JumpHost(
                host: jump.address,
                port: jump.port,
                username: jump.username,
                credentials: _credentials(jump, secrets.jumpPassword, secrets.jumpPassphrase, secrets.jumpCode),
                trustedHostKeys: _store.trustedKeysFor(jump.address, jump.port),
              ),
      );

  Credentials _credentials(Host host, String? password, String? passphrase, String? code) {
    final key = host.usesKey ? _store.key(host.keyId) : null;
    return Credentials(
      password: host.usesPassword || key == null ? password : null,
      privateKey: key?.privatePem,
      keyPassphrase: passphrase,
      oneTimeCode: code,
    );
  }
}

/// Passwords and passphrases gathered during one connection attempt.
class _Secrets {
  _Secrets({this.password, this.passphrase, this.jumpPassword, this.jumpPassphrase});

  String? password;
  String? passphrase;
  String? jumpPassword;
  String? jumpPassphrase;

  /// One-time codes, kept until the server refuses the login.
  String? code;
  String? jumpCode;

  /// Logins refused right after a code was sent.
  int codeRefusals = 0;
  bool codeRefused = false;

  String? codeFor({required bool isJump}) => isJump ? jumpCode : code;

  void setCode(String? value, {required bool isJump}) => isJump ? jumpCode = value : code = value;
}
