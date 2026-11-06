/// Everything Multiplex saves. All of it lives in one encrypted file (see
/// [VaultStore]); these classes only describe the data and how it turns
/// into JSON and back.
library;

import '../src/rust/api/tunnel_types.dart';

/// Reads JSON values without crashing on missing or odd fields, so an older
/// or newer data file still opens.
abstract final class Json {
  static String str(Map<String, dynamic> j, String key, [String fallback = '']) => j[key] is String ? j[key] as String : fallback;
  static String? strOrNull(Map<String, dynamic> j, String key) => j[key] is String && (j[key] as String).isNotEmpty ? j[key] as String : null;
  static int integer(Map<String, dynamic> j, String key, int fallback) => j[key] is num ? (j[key] as num).toInt() : fallback;
  static bool boolean(Map<String, dynamic> j, String key, bool fallback) => j[key] is bool ? j[key] as bool : fallback;
  static DateTime? time(Map<String, dynamic> j, String key) => j[key] is String ? DateTime.tryParse(j[key] as String) : null;
  static List<Map<String, dynamic>> list(Map<String, dynamic> j, String key) =>
      j[key] is List ? (j[key] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : const [];
}

/// How a host logs in.
enum AuthMode {
  /// Saved or asked-for password.
  password,

  /// A key from the keychain.
  key,

  /// Key first, then password (for servers that want both).
  keyAndPassword,
}

/// A saved server.
class Host {
  const Host({
    required this.id,
    required this.label,
    required this.address,
    this.port = 22,
    this.username = '',
    this.groupId,
    this.authMode = AuthMode.password,
    this.password,
    this.keyId,
    this.jumpHostId,
    this.startupCommand,
    this.colorTag = 0,
    this.lastConnectedAt,
    this.askUnlock = false,
  });

  final String id;
  final String label;
  final String address;
  final int port;
  final String username;
  final String? groupId;
  final AuthMode authMode;

  /// Saved password, or null to ask every time.
  final String? password;
  final String? keyId;

  /// Another saved host to hop through first.
  final String? jumpHostId;

  /// Typed automatically after the shell opens.
  final String? startupCommand;

  /// Index into the tag colours, 0 = none.
  final int colorTag;
  final DateTime? lastConnectedAt;

  /// Ask for fingerprint, face or PIN before every new connection, even
  /// when the app itself is unlocked.
  final bool askUnlock;

  /// "user@address:port", leaving out the default port.
  String get target => '${username.isEmpty ? '' : '$username@'}$address${port == 22 ? '' : ':$port'}';

  String get title => label.isEmpty ? address : label;

  bool get usesKey => authMode != AuthMode.password;
  bool get usesPassword => authMode != AuthMode.key;

  Host copyWith({
    String? label,
    String? address,
    int? port,
    String? username,
    String? Function()? groupId,
    AuthMode? authMode,
    String? Function()? password,
    String? Function()? keyId,
    String? Function()? jumpHostId,
    String? Function()? startupCommand,
    int? colorTag,
    DateTime? lastConnectedAt,
    bool? askUnlock,
  }) =>
      Host(
        id: id,
        label: label ?? this.label,
        address: address ?? this.address,
        port: port ?? this.port,
        username: username ?? this.username,
        groupId: groupId != null ? groupId() : this.groupId,
        authMode: authMode ?? this.authMode,
        password: password != null ? password() : this.password,
        keyId: keyId != null ? keyId() : this.keyId,
        jumpHostId: jumpHostId != null ? jumpHostId() : this.jumpHostId,
        startupCommand: startupCommand != null ? startupCommand() : this.startupCommand,
        colorTag: colorTag ?? this.colorTag,
        lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
        askUnlock: askUnlock ?? this.askUnlock,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'address': address,
        'port': port,
        'username': username,
        'groupId': groupId,
        'authMode': authMode.name,
        'password': password,
        'keyId': keyId,
        'jumpHostId': jumpHostId,
        'startupCommand': startupCommand,
        'colorTag': colorTag,
        'lastConnectedAt': lastConnectedAt?.toIso8601String(),
        'askUnlock': askUnlock,
      };

  factory Host.fromJson(Map<String, dynamic> j) => Host(
        id: Json.str(j, 'id'),
        label: Json.str(j, 'label'),
        address: Json.str(j, 'address'),
        port: Json.integer(j, 'port', 22),
        username: Json.str(j, 'username'),
        groupId: Json.strOrNull(j, 'groupId'),
        authMode: AuthMode.values.asNameMap()[j['authMode']] ?? AuthMode.password,
        password: Json.strOrNull(j, 'password'),
        keyId: Json.strOrNull(j, 'keyId'),
        jumpHostId: Json.strOrNull(j, 'jumpHostId'),
        startupCommand: Json.strOrNull(j, 'startupCommand'),
        colorTag: Json.integer(j, 'colorTag', 0),
        lastConnectedAt: Json.time(j, 'lastConnectedAt'),
        askUnlock: Json.boolean(j, 'askUnlock', false),
      );
}

/// A folder for hosts.
class HostGroup {
  const HostGroup({required this.id, required this.name});

  final String id;
  final String name;

  HostGroup copyWith({String? name}) => HostGroup(id: id, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory HostGroup.fromJson(Map<String, dynamic> j) => HostGroup(id: Json.str(j, 'id'), name: Json.str(j, 'name'));
}

/// A key pair in the keychain.
class StoredKey {
  const StoredKey({
    required this.id,
    required this.name,
    required this.privatePem,
    required this.publicOpenssh,
    required this.fingerprint,
    required this.algorithm,
    this.passphrase,
    this.encrypted = false,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String privatePem;
  final String publicOpenssh;
  final String fingerprint;
  final String algorithm;

  /// Saved passphrase for an encrypted key, or null to ask when needed.
  final String? passphrase;
  final bool encrypted;
  final DateTime createdAt;

  StoredKey copyWith({String? name, String? Function()? passphrase}) => StoredKey(
        id: id,
        name: name ?? this.name,
        privatePem: privatePem,
        publicOpenssh: publicOpenssh,
        fingerprint: fingerprint,
        algorithm: algorithm,
        passphrase: passphrase != null ? passphrase() : this.passphrase,
        encrypted: encrypted,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'privatePem': privatePem,
        'publicOpenssh': publicOpenssh,
        'fingerprint': fingerprint,
        'algorithm': algorithm,
        'passphrase': passphrase,
        'encrypted': encrypted,
        'createdAt': createdAt.toIso8601String(),
      };

  factory StoredKey.fromJson(Map<String, dynamic> j) => StoredKey(
        id: Json.str(j, 'id'),
        name: Json.str(j, 'name'),
        privatePem: Json.str(j, 'privatePem'),
        publicOpenssh: Json.str(j, 'publicOpenssh'),
        fingerprint: Json.str(j, 'fingerprint'),
        algorithm: Json.str(j, 'algorithm'),
        passphrase: Json.strOrNull(j, 'passphrase'),
        encrypted: Json.boolean(j, 'encrypted', false),
        createdAt: Json.time(j, 'createdAt') ?? DateTime.now(),
      );
}

/// A saved command.
class Snippet {
  const Snippet({required this.id, required this.name, required this.command, this.runImmediately = true});

  final String id;
  final String name;
  final String command;

  /// Press Enter after typing it.
  final bool runImmediately;

  Snippet copyWith({String? name, String? command, bool? runImmediately}) =>
      Snippet(id: id, name: name ?? this.name, command: command ?? this.command, runImmediately: runImmediately ?? this.runImmediately);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'command': command, 'runImmediately': runImmediately};

  factory Snippet.fromJson(Map<String, dynamic> j) => Snippet(
        id: Json.str(j, 'id'),
        name: Json.str(j, 'name'),
        command: Json.str(j, 'command'),
        runImmediately: Json.boolean(j, 'runImmediately', true),
      );
}

/// A server identity the user accepted.
class KnownHost {
  const KnownHost({required this.host, required this.port, required this.publicKey, required this.fingerprint, required this.algorithm, required this.addedAt});

  final String host;
  final int port;
  final String publicKey;
  final String fingerprint;
  final String algorithm;
  final DateTime addedAt;

  /// The key used to look it up: "host:port".
  String get endpoint => '$host:$port';

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'publicKey': publicKey,
        'fingerprint': fingerprint,
        'algorithm': algorithm,
        'addedAt': addedAt.toIso8601String(),
      };

  factory KnownHost.fromJson(Map<String, dynamic> j) => KnownHost(
        host: Json.str(j, 'host'),
        port: Json.integer(j, 'port', 22),
        publicKey: Json.str(j, 'publicKey'),
        fingerprint: Json.str(j, 'fingerprint'),
        algorithm: Json.str(j, 'algorithm'),
        addedAt: Json.time(j, 'addedAt') ?? DateTime.now(),
      );
}

/// A saved port forward, tied to a host.
class ForwardRule {
  const ForwardRule({
    required this.id,
    required this.hostId,
    required this.kind,
    this.label = '',
    this.bindHost = '127.0.0.1',
    required this.bindPort,
    this.targetHost = '127.0.0.1',
    this.targetPort = 0,
  });

  final String id;
  final String hostId;
  final TunnelKind kind;
  final String label;
  final String bindHost;
  final int bindPort;
  final String targetHost;
  final int targetPort;

  TunnelSpec get spec => TunnelSpec(kind: kind, bindHost: bindHost, bindPort: bindPort, targetHost: targetHost, targetPort: targetPort);

  /// Short description such as "L 8080 → db:5432".
  String get summary => switch (kind) {
        TunnelKind.local => 'Local $bindPort → $targetHost:$targetPort',
        TunnelKind.remote => 'Remote $bindPort → $targetHost:$targetPort',
        TunnelKind.dynamic_ => 'SOCKS5 on $bindHost:$bindPort',
      };

  ForwardRule copyWith({TunnelKind? kind, String? label, String? bindHost, int? bindPort, String? targetHost, int? targetPort}) => ForwardRule(
        id: id,
        hostId: hostId,
        kind: kind ?? this.kind,
        label: label ?? this.label,
        bindHost: bindHost ?? this.bindHost,
        bindPort: bindPort ?? this.bindPort,
        targetHost: targetHost ?? this.targetHost,
        targetPort: targetPort ?? this.targetPort,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'hostId': hostId,
        'kind': kind.name,
        'label': label,
        'bindHost': bindHost,
        'bindPort': bindPort,
        'targetHost': targetHost,
        'targetPort': targetPort,
      };

  factory ForwardRule.fromJson(Map<String, dynamic> j) => ForwardRule(
        id: Json.str(j, 'id'),
        hostId: Json.str(j, 'hostId'),
        kind: TunnelKind.values.asNameMap()[j['kind']] ?? TunnelKind.local,
        label: Json.str(j, 'label'),
        bindHost: Json.str(j, 'bindHost', '127.0.0.1'),
        bindPort: Json.integer(j, 'bindPort', 0),
        targetHost: Json.str(j, 'targetHost', '127.0.0.1'),
        targetPort: Json.integer(j, 'targetPort', 0),
      );
}
