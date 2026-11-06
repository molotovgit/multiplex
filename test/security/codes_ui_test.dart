import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/otp_account.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/ui/common/code_prompt_dialog.dart';
import 'package:multiplex/ui/keys/keychain_screen.dart';

import 'harness.dart';

/// Base32 of the RFC 6238 SHA-1 secret; at 59 seconds its 6-digit code is
/// 287082, with 1 second left.
const _rfcSecret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
DateTime _at59() => DateTime.fromMillisecondsSinceEpoch(59 * 1000);

const _bastion = Host(id: 'h1', label: 'Bastion', address: 'bastion');
final _account = OtpAccount(id: 'o1', issuer: 'Bastion', name: 'alice', secret: _rfcSecret, hostId: 'h1', createdAt: DateTime(2026));

/// Records what the app copies to the clipboard.
List<String> _watchClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

Future<SecurityHarness> _openCodes(WidgetTester tester, {void Function(VaultStore)? fill}) async {
  final app = await SecurityHarness.pump(tester, KeychainScreen(clock: _at59), fill: (s) {
    s.saveHost(_bastion);
    fill?.call(s);
  });
  await tester.tap(find.text('Codes'));
  await tester.pumpAndSettle();
  return app;
}

void main() {
  testWidgets('a code shows with its countdown and its host, and a tap copies it', (tester) async {
    final copied = _watchClipboard(tester);
    final app = await _openCodes(tester, fill: (s) => s.saveOtp(_account));
    expect(find.text('287 082'), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: 'one second left');
    expect(find.text('alice · For Bastion'), findsOneWidget);
    await tester.tap(find.text('287 082'));
    await tester.pump();
    expect(copied, ['287082']);
    expect(find.text('Add code'), findsOneWidget, reason: 'the button to add another');
    await tester.pump(const Duration(seconds: 4));
    await app.finish();
  });

  testWidgets('pasting a setup link fills the form, and saving adds the code', (tester) async {
    final app = await _openCodes(tester);
    expect(find.text('No codes yet'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add code'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'otpauth:// link'), 'otpauth://totp/Work:bob?secret=$_rfcSecret&issuer=Work');
    await tester.pump();
    expect(find.textContaining('Filled in from the link'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Work'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final saved = app.store.otpAccounts.single;
    expect((saved.issuer, saved.name, saved.secret), ('Work', 'bob', _rfcSecret));
    expect(find.text('287 082'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await app.finish();
  });

  testWidgets('a bad link is explained, and a secret typed by hand is checked', (tester) async {
    final app = await _openCodes(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'otpauth:// link'), 'otpauth://hotp/x?secret=$_rfcSecret');
    await tester.pump();
    expect(find.textContaining('Only time-based codes'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Secret key'), 'not a secret!');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('letters A to Z and digits 2 to 7'), findsOneWidget);
    expect(app.store.otpAccounts, isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'Secret key'), 'gezd gnbv gy3t qojq gezd gnbv gy3t qojq');
    await tester.enterText(find.widgetWithText(TextFormField, 'Service'), 'Typed');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(app.store.otpAccounts.single.secret, _rfcSecret);
    await tester.pump(const Duration(seconds: 4));
    await app.finish();
  });

  testWidgets('the login question offers the linked code in one tap', (tester) async {
    final results = <String?>[];
    final app = await SecurityHarness.pump(
      tester,
      Opener(
        (context) => showDialog<String>(
          context: context,
          builder: (_) => CodePromptDialog(host: 'bastion', prompt: 'Verification code:', linked: [_account], wasWrong: false, clock: _at59),
        ),
        results,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('bastion asks: "Verification code:"'), findsOneWidget);
    await tester.tap(find.text('Use Bastion'));
    await tester.pumpAndSettle();
    expect(results, ['287082']);

    // A typed code works too.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '99 11 22');
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(results, ['287082', '991122']);
    await app.finish();
  });
}
