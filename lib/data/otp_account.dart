import 'models.dart';

/// The hash an authenticator account uses. Almost every service uses SHA-1.
enum OtpAlgorithm {
  sha1('SHA1'),
  sha256('SHA256'),
  sha512('SHA512');

  const OtpAlgorithm(this.label);

  /// The name used in setup links.
  final String label;

  static OtpAlgorithm? byLabel(String label) => values.where((a) => a.label == label.toUpperCase()).firstOrNull;
}

/// One account in the "Codes" tab: a secret shared with a service, from
/// which a new code is made every [period] seconds (TOTP, RFC 6238). Kept
/// only inside the encrypted vault.
class OtpAccount {
  const OtpAccount({
    required this.id,
    this.issuer = '',
    this.name = '',
    required this.secret,
    this.algorithm = OtpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    this.hostId,
    required this.createdAt,
  });

  final String id;

  /// The service, such as "GitHub" or "bastion".
  final String issuer;

  /// The account at that service, such as "alice@example.com".
  final String name;

  /// The shared secret in Base32, upper case, without spaces.
  final String secret;
  final OtpAlgorithm algorithm;

  /// 6 or 8.
  final int digits;

  /// Seconds each code lasts.
  final int period;

  /// A saved host whose login asks for this code; the code is then offered
  /// in one tap.
  final String? hostId;
  final DateTime createdAt;

  String get title => issuer.isNotEmpty ? issuer : (name.isNotEmpty ? name : 'Code');

  /// The account name, when the title is the issuer.
  String? get subtitle => issuer.isNotEmpty && name.isNotEmpty ? name : null;

  OtpAccount copyWith({
    String? issuer,
    String? name,
    String? secret,
    OtpAlgorithm? algorithm,
    int? digits,
    int? period,
    String? Function()? hostId,
  }) =>
      OtpAccount(
        id: id,
        issuer: issuer ?? this.issuer,
        name: name ?? this.name,
        secret: secret ?? this.secret,
        algorithm: algorithm ?? this.algorithm,
        digits: digits ?? this.digits,
        period: period ?? this.period,
        hostId: hostId != null ? hostId() : this.hostId,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'issuer': issuer,
        'name': name,
        'secret': secret,
        'algorithm': algorithm.name,
        'digits': digits,
        'period': period,
        'hostId': hostId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory OtpAccount.fromJson(Map<String, dynamic> j) {
    final digits = Json.integer(j, 'digits', 6);
    final period = Json.integer(j, 'period', 30);
    return OtpAccount(
      id: Json.str(j, 'id'),
      issuer: Json.str(j, 'issuer'),
      name: Json.str(j, 'name'),
      secret: Json.str(j, 'secret'),
      algorithm: OtpAlgorithm.values.asNameMap()[j['algorithm']] ?? OtpAlgorithm.sha1,
      digits: digits == 8 ? 8 : 6,
      period: period > 0 ? period : 30,
      hostId: Json.strOrNull(j, 'hostId'),
      createdAt: Json.time(j, 'createdAt') ?? DateTime.now(),
    );
  }
}
