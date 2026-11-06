import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/otp_account.dart';
import 'package:multiplex/data/totp.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';

/// The secrets of RFC 6238, appendix B: ASCII digits, as long as each
/// hash's own size.
final _sha1Key = utf8.encode('12345678901234567890');
final _sha256Key = utf8.encode('12345678901234567890123456789012');
final _sha512Key = utf8.encode('1234567890123456789012345678901234567890123456789012345678901234');

OtpAccount _account({String? hostId}) =>
    OtpAccount(id: 'o1', issuer: 'Bastion', name: 'alice', secret: 'JBSWY3DPEHPK3PXP', hostId: hostId, createdAt: DateTime(2026, 11, 6));

void main() {
  group('RFC 6238 test vectors (8 digits, 30 seconds)', () {
    const vectors = <(int, String, String, String)>[
      (59, '94287082', '46119246', '90693936'),
      (1111111109, '07081804', '68084774', '25091201'),
      (1111111111, '14050471', '67062674', '99943326'),
      (1234567890, '89005924', '91819424', '93441116'),
      (2000000000, '69279037', '90698825', '38618901'),
      (20000000000, '65353130', '77737706', '47863826'),
    ];
    for (final (time, sha1, sha256, sha512) in vectors) {
      test('at $time', () {
        expect(Totp.codeAt(_sha1Key, time, digits: 8), sha1);
        expect(Totp.codeAt(_sha256Key, time, digits: 8, algorithm: OtpAlgorithm.sha256), sha256);
        expect(Totp.codeAt(_sha512Key, time, digits: 8, algorithm: OtpAlgorithm.sha512), sha512);
      });
    }

    test('six digits are the last six of the same number', () {
      expect(Totp.codeAt(_sha1Key, 59), '287082');
      expect(Totp.codeAt(_sha1Key, 1111111109), '081804');
    });
  });

  group('Base32', () {
    test('decodes the RFC 4648 examples and ignores spaces, case and padding', () {
      expect(utf8.decode(Base32.decode('MZXW6YTBOI======')), 'foobar');
      expect(utf8.decode(Base32.decode('mzxw 6ytb oi')), 'foobar');
      expect(Base32.decode('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'), _sha1Key);
    });

    test('refuses characters that are not Base32', () {
      expect(() => Base32.decode('ABC1'), throwsFormatException);
      expect(() => Base32.decode('   '), throwsFormatException);
      expect(Base32.isValid('JBSWY3DPEHPK3PXP'), isTrue);
      expect(Base32.isValid('hello!'), isFalse);
    });
  });

  group('setup links', () {
    test('reads issuer, account, secret and options', () {
      final link = OtpLink.parse('otpauth://totp/ACME%20Co:john@example.com?secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ&issuer=ACME%20Co&algorithm=SHA256&digits=8&period=60');
      expect(link.issuer, 'ACME Co');
      expect(link.name, 'john@example.com');
      expect(link.secret, 'HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ');
      expect(link.algorithm, OtpAlgorithm.sha256);
      expect(link.digits, 8);
      expect(link.period, 60);
    });

    test('uses the defaults and the label when the link is short', () {
      final link = OtpLink.parse('otpauth://totp/bastion:alice?secret=jbswy3dpehpk3pxp');
      expect(link.issuer, 'bastion');
      expect(link.name, 'alice');
      expect(link.secret, 'JBSWY3DPEHPK3PXP');
      expect((link.algorithm, link.digits, link.period), (OtpAlgorithm.sha1, 6, 30));
    });

    test('explains links it cannot use', () {
      for (final bad in [
        'https://example.com',
        'otpauth://hotp/x?secret=JBSWY3DPEHPK3PXP&counter=1',
        'otpauth://totp/x',
        'otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&digits=7',
        'otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&algorithm=MD5',
      ]) {
        expect(() => OtpLink.parse(bad), throwsFormatException, reason: bad);
      }
      expect(OtpLink.looksLikeLink('  OTPAUTH://totp/x'), isTrue);
    });
  });

  group('accounts in the vault', () {
    test('round-trip through JSON with safe defaults', () {
      final a = _account(hostId: 'h1');
      final back = OtpAccount.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect(back.toJson(), a.toJson());
      final odd = OtpAccount.fromJson(const {'id': 'x', 'secret': 'AA', 'digits': 7, 'period': -1, 'algorithm': 'md5'});
      expect((odd.digits, odd.period, odd.algorithm), (6, 30, OtpAlgorithm.sha1));
    });

    test('are saved, offered for their host, unlinked when the host goes, and kept in backups', () async {
      final store = await VaultStore.open(MemoryBackend());
      store.saveHost(const Host(id: 'h1', label: 'Bastion', address: 'b'));
      store.saveOtp(_account(hostId: 'h1'));
      expect(store.otpFor('h1').single.id, 'o1');
      expect(store.otpFor(null), isEmpty);

      final backup = store.exportJson();
      store.deleteHost('h1');
      expect(store.otpAccounts.single.hostId, isNull);

      store.deleteOtp('o1');
      expect(store.otpAccounts, isEmpty);
      store.importJson(backup, replace: false);
      expect(store.otpAccounts.single.secret, 'JBSWY3DPEHPK3PXP');
      store.dispose();
    });

    test('an old vault without codes still opens', () async {
      final store = await VaultStore.open(MemoryBackend());
      final json = jsonDecode(store.exportJson()) as Map<String, dynamic>..remove('otpAccounts');
      store.importJson(jsonEncode(json), replace: true);
      expect(store.otpAccounts, isEmpty);
      store.dispose();
    });
  });

  test('codes show in two halves and the countdown counts to the next code', () {
    expect(Totp.grouped('123456'), '123 456');
    expect(Totp.grouped('12345678'), '1234 5678');
    expect(Totp.secondsLeft(DateTime.fromMillisecondsSinceEpoch(59 * 1000), 30), 1);
    expect(Totp.secondsLeft(DateTime.fromMillisecondsSinceEpoch(60 * 1000), 30), 30);
  });
}
