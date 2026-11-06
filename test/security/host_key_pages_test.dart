import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/src/rust/api/ssh_types.dart';
import 'package:multiplex/ui/hosts/host_key_pages.dart';
import 'package:multiplex/ui/hosts/host_key_parts.dart';

import 'harness.dart';

const _offered = HostKeyInfo(algorithm: 'ssh-ed25519', fingerprint: 'SHA256:newNEWnew', publicKey: 'ssh-ed25519 AAAAnew');
final _previous = KnownHost(
  host: 'web.example.com',
  port: 22,
  publicKey: 'ssh-rsa AAAAold',
  fingerprint: 'SHA256:oldOLDold',
  algorithm: 'ssh-rsa',
  addedAt: DateTime(2026, 3, 1),
);

Future<(SecurityHarness, List<bool>)> _openChanged(WidgetTester tester) async {
  final results = <bool>[];
  final app = await SecurityHarness.pump(
    tester,
    Opener((context) => HostKeyPages.acceptChanged(context, 'web.example.com', 22, _offered, _previous), results),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (app, results);
}

void main() {
  group('words', () {
    test('the check command names the file for the key type', () {
      expect(HostKeyWords.checkCommand('ssh-ed25519'), 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub');
      expect(HostKeyWords.serverFile('ecdsa-sha2-nistp256'), '/etc/ssh/ssh_host_ecdsa_key.pub');
      expect(HostKeyWords.serverFile('rsa-sha2-512'), '/etc/ssh/ssh_host_rsa_key.pub');
    });

    test('addresses and ages read naturally', () {
      expect(HostKeyWords.address('a.b', 22), 'a.b');
      expect(HostKeyWords.address('a.b', 2222), 'a.b:2222');
      expect(HostKeyWords.address('::1', 2222), '[::1]:2222');
      final now = DateTime(2026, 11, 6);
      expect(HostKeyWords.age(now, now), 'today');
      expect(HostKeyWords.age(DateTime(2026, 11, 1), now), '5 days ago');
      expect(HostKeyWords.age(DateTime(2026, 3, 1), now), '8 months ago');
      expect(HostKeyWords.age(DateTime(2022, 11, 1), now), '4 years ago');
    });
  });

  testWidgets('a changed key shows both fingerprints, the meaning and the check, and Disconnect refuses', (tester) async {
    final (app, results) = await _openChanged(tester);
    expect(find.text('Server identity changed'), findsOneWidget);
    expect(find.text('SHA256:oldOLDold'), findsOneWidget);
    expect(find.text('SHA256:newNEWnew'), findsOneWidget);
    expect(find.textContaining('Trusted before · RSA'), findsOneWidget);
    expect(find.textContaining('Offered now · Ed25519'), findsOneWidget);
    expect(find.textContaining('Trusted since'), findsOneWidget);
    expect(find.text('The type of key changed too.'), findsOneWidget);
    expect(find.text('Often harmless'), findsOneWidget);
    expect(find.text('Sometimes an attack'), findsOneWidget);
    expect(find.text('ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'), findsOneWidget);

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(results, [false]);
    await app.finish();
  });

  testWidgets('trusting the new key needs the host name typed', (tester) async {
    final (app, results) = await _openChanged(tester);
    final trust = find.text('Trust the new key').last;
    await tester.ensureVisible(trust);
    await tester.tap(trust);
    await tester.pumpAndSettle();
    expect(results, isEmpty, reason: 'a plain tap must not trust the key');
    expect(find.textContaining('Type web.example.com first'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'web.example.co');
    await tester.tap(trust);
    await tester.pumpAndSettle();
    expect(results, isEmpty, reason: 'a near miss must not trust the key');

    await tester.enterText(find.byType(TextField), 'Web.Example.com ');
    await tester.tap(trust);
    await tester.pumpAndSettle();
    expect(results, [true]);
    await app.finish();
  });

  testWidgets('a long press on Trust the new key trusts it without typing', (tester) async {
    final (app, results) = await _openChanged(tester);
    final trust = find.text('Trust the new key').last;
    await tester.ensureVisible(trust);
    await tester.longPress(trust);
    await tester.pumpAndSettle();
    expect(results, [true]);
    await app.finish();
  });

  testWidgets('going back from the warning disconnects', (tester) async {
    final (app, results) = await _openChanged(tester);
    await tester.tap(find.byTooltip('Disconnect'));
    await tester.pumpAndSettle();
    expect(results, [false]);
    await app.finish();
  });

  testWidgets('a new server shows its fingerprint and can be trusted or cancelled', (tester) async {
    final results = <bool>[];
    final app = await SecurityHarness.pump(tester, Opener((context) => HostKeyPages.trustNew(context, 'db', 2222, _offered), results));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('First connection to db:2222'), findsOneWidget);
    expect(find.text('SHA256:newNEWnew'), findsOneWidget);
    await tester.tap(find.text('Trust and connect'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(results, [true, false]);
    await app.finish();
  });
}
