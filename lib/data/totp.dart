import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'otp_account.dart';

/// Base32 (RFC 4648), the way authenticator secrets are written. Spaces,
/// dashes, padding and lower case are accepted.
abstract final class Base32 {
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Upper case, without spaces, dashes or padding.
  static String normalize(String text) => text.toUpperCase().replaceAll(RegExp(r'[\s\-=]'), '');

  /// Throws a [FormatException] for anything that is not Base32.
  static Uint8List decode(String text) {
    final clean = normalize(text);
    if (clean.isEmpty) throw const FormatException('The secret is empty.');
    final out = BytesBuilder();
    var buffer = 0, bits = 0;
    for (final char in clean.split('')) {
      final value = _alphabet.indexOf(char);
      if (value < 0) throw FormatException('"$char" cannot be part of a secret. Use the letters A to Z and the digits 2 to 7.');
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.addByte((buffer >> bits) & 0xff);
        buffer &= (1 << bits) - 1;
      }
    }
    return out.toBytes();
  }

  static bool isValid(String text) {
    try {
      return decode(text).isNotEmpty;
    } on FormatException {
      return false;
    }
  }
}

/// Time-based one-time codes (TOTP, RFC 6238).
abstract final class Totp {
  /// The code for [key] at [unixSeconds].
  static String codeAt(List<int> key, int unixSeconds, {int digits = 6, int period = 30, OtpAlgorithm algorithm = OtpAlgorithm.sha1}) {
    var counter = unixSeconds ~/ period;
    final message = Uint8List(8);
    for (var i = 7; i >= 0; i--) {
      message[i] = counter & 0xff;
      counter >>= 8;
    }
    final hash = Hmac(_hash(algorithm), key).convert(message).bytes;
    final offset = hash.last & 0x0f;
    final binary = ((hash[offset] & 0x7f) << 24) | (hash[offset + 1] << 16) | (hash[offset + 2] << 8) | hash[offset + 3];
    var modulo = 1;
    for (var i = 0; i < digits; i++) {
      modulo *= 10;
    }
    return (binary % modulo).toString().padLeft(digits, '0');
  }

  /// The current code of an account.
  static String now(OtpAccount account, DateTime time) =>
      codeAt(Base32.decode(account.secret), time.millisecondsSinceEpoch ~/ 1000, digits: account.digits, period: account.period, algorithm: account.algorithm);

  /// Whole seconds until the code changes (1 to [period]).
  static int secondsLeft(DateTime time, int period) => period - (time.millisecondsSinceEpoch ~/ 1000) % period;

  /// "123 456" or "1234 5678", easier to read and type.
  static String grouped(String code) {
    final half = code.length ~/ 2;
    return '${code.substring(0, half)} ${code.substring(half)}';
  }

  static Hash _hash(OtpAlgorithm algorithm) => switch (algorithm) {
        OtpAlgorithm.sha1 => sha1,
        OtpAlgorithm.sha256 => sha256,
        OtpAlgorithm.sha512 => sha512,
      };
}

/// The fields of an `otpauth://totp/...` setup link, the text that QR codes
/// for authenticator apps contain.
class OtpLink {
  const OtpLink({required this.issuer, required this.name, required this.secret, required this.algorithm, required this.digits, required this.period});

  final String issuer;
  final String name;
  final String secret;
  final OtpAlgorithm algorithm;
  final int digits;
  final int period;

  static bool looksLikeLink(String text) => text.trim().toLowerCase().startsWith('otpauth://');

  /// Throws a [FormatException] with a plain reason when the link cannot
  /// be used.
  factory OtpLink.parse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'otpauth') throw const FormatException('This is not an otpauth:// setup link.');
    if (uri.host.toLowerCase() == 'hotp') throw const FormatException('Only time-based codes (TOTP) are supported, not counter-based ones (HOTP).');
    if (uri.host.toLowerCase() != 'totp') throw const FormatException('The link does not say it is for time-based codes (totp).');
    final query = uri.queryParameters;

    final secret = Base32.normalize(query['secret'] ?? '');
    if (!Base32.isValid(secret)) throw const FormatException('The link has no valid secret.');

    final label = Uri.decodeComponent(uri.path.startsWith('/') ? uri.path.substring(1) : uri.path).trim();
    final colon = label.indexOf(':');
    final labelIssuer = colon >= 0 ? label.substring(0, colon).trim() : '';
    final name = colon >= 0 ? label.substring(colon + 1).trim() : label;

    final algorithm = query['algorithm'] == null ? OtpAlgorithm.sha1 : OtpAlgorithm.byLabel(query['algorithm']!);
    if (algorithm == null) throw FormatException('The hash "${query['algorithm']}" is not supported. Use SHA1, SHA256 or SHA512.');
    final digits = int.tryParse(query['digits'] ?? '6');
    if (digits != 6 && digits != 8) throw const FormatException('Only 6- and 8-digit codes are supported.');
    final period = int.tryParse(query['period'] ?? '30');
    if (period == null || period <= 0 || period > 3600) throw const FormatException('The code period in the link is not valid.');

    return OtpLink(
      issuer: (query['issuer'] ?? labelIssuer).trim(),
      name: name,
      secret: secret,
      algorithm: algorithm,
      digits: digits!,
      period: period,
    );
  }
}
