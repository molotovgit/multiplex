import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultterm/app/app_scope.dart';
import 'package:vaultterm/app/theme.dart';
import 'package:vaultterm/app/theme_spec.dart';
import 'package:vaultterm/data/models.dart';
import 'package:vaultterm/data/vault_backend.dart';
import 'package:vaultterm/data/vault_store.dart';
import 'package:vaultterm/sessions/session_manager.dart';
import 'package:vaultterm/src/rust/api/keys.dart' show KeyKind, KeyPairInfo;
import 'package:vaultterm/src/rust/api/ssh_types.dart';
import 'package:vaultterm/ui/keys/authorized_keys.dart';
import 'package:vaultterm/ui/keys/key_detail_screen.dart';
import 'package:vaultterm/ui/keys/key_labels.dart';
import 'package:vaultterm/ui/keys/key_tools.dart';
import 'package:vaultterm/ui/keys/keychain_screen.dart';

/// Stands in for the Rust key functions. Key text containing "LOCKED"
/// needs the passphrase "secret"; text without "BEGIN" is not a key.
class FakeKeyTools implements KeyTools {
  KeyKind? kind;
  String? comment;
  String? passphrase;

  @override
  Future<KeyPairInfo> generate(KeyKind kind, {required String comment, String? passphrase}) async {
    this.kind = kind;
    this.comment = comment;
    this.passphrase = passphrase;
    return KeyPairInfo(
      privatePem: 'NEW PRIVATE KEY',
      publicOpenssh: 'ssh-ed25519 AAAAnew $comment',
      fingerprint: 'SHA256:new',
      algorithm: 'ssh-ed25519',
      comment: comment,
      encrypted: passphrase != null,
    );
  }

  @override
  Future<KeyPairInfo> inspect(String pem, {String? passphrase}) async {
    if (isEncrypted(pem) && passphrase == null) throw const KeyProblem(KeyProblemKind.passphraseNeeded, 'protected');
    if (isEncrypted(pem) && passphrase != 'secret') throw const KeyProblem(KeyProblemKind.wrongPassphrase, 'wrong');
    if (!pem.contains('BEGIN')) throw const KeyProblem(KeyProblemKind.unreadable, 'not a key');
    return KeyPairInfo(
      privatePem: '$pem\n',
      publicOpenssh: 'ssh-ed25519 AAAAold laptop',
      fingerprint: 'SHA256:imported',
      algorithm: 'ssh-ed25519',
      comment: 'laptop',
      encrypted: isEncrypted(pem),
    );
  }

  @override
  bool isEncrypted(String pem) => pem.contains('LOCKED');
}

/// A phone-sized app with a fresh vault around the widget under test.
class Harness {
  Harness(this.store, this.sessions);

  final VaultStore store;
  final SessionManager sessions;

  static Future<Harness> pump(WidgetTester tester, Widget Function() home, {void Function(VaultStore)? fill}) async {
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await VaultStore.open(MemoryBackend());
    fill?.call(store);
    final sessions = SessionManager(store);
    await tester.pumpWidget(AppScope(
      vault: store,
      manager: sessions,
      child: MaterialApp(theme: AppTheme.build(BuiltInThemes.ember), home: home()),
    ));
    await tester.pumpAndSettle();
    return Harness(store, sessions);
  }

  /// Writes pending saves and stops the session ticker, so no timers are
  /// left when the test ends.
  Future<void> finish() async {
    await store.flush();
    sessions.dispose();
  }
}

/// Test data.
abstract final class Sample {
  static StoredKey key({bool encrypted = false, String? passphrase}) => StoredKey(
        id: 'k1',
        name: 'Laptop',
        privatePem: 'LOCKED BEGIN',
        publicOpenssh: 'ssh-ed25519 AAAAkey laptop@vaultterm',
        fingerprint: 'SHA256:abcdef',
        algorithm: 'ssh-ed25519',
        encrypted: encrypted,
        passphrase: passphrase,
        createdAt: DateTime(2026, 11, 5),
      );

  static const host = Host(id: 'h1', label: 'Web', address: 'web.example.com', username: 'root', keyId: 'k1', authMode: AuthMode.key);
}

void main() {
  group('shell quoting', () {
    test('single quotes are written so the shell reads them literally', () {
      expect(ShellQuote.single('abc'), "'abc'");
      expect(ShellQuote.single(''), "''");
      expect(ShellQuote.single("it's"), r"'it'\''s'");
    });

    test('the key line and its body ignore extra lines and the comment', () {
      expect(AuthorizedKeys.keyLine('  ssh-ed25519 AAAA me@x\n\n'), 'ssh-ed25519 AAAA me@x');
      expect(AuthorizedKeys.keyBody('ssh-ed25519 AAAA me at home'), 'ssh-ed25519 AAAA');
    });

    test('the install command works in a real shell and adds the key only once', () async {
      try {
        await Process.run('sh', ['-c', 'true']);
      } on ProcessException {
        markTestSkipped('needs a POSIX sh on the PATH');
        return;
      }
      final home = await Directory.systemTemp.createTemp('vaultterm_keys_');
      addTearDown(() => home.delete(recursive: true));
      await Directory('${home.path}/.ssh').create();
      // An existing file without a final line break must not get glued.
      final file = File('${home.path}/.ssh/authorized_keys')..writeAsStringSync('ssh-rsa AAAAold old');
      const line = r"ssh-ed25519 AAAAC3Nz+/= it's $HOME `id` me@x";
      final command = AuthorizedKeys.installCommand(line);

      Future<ProcessResult> run() => Process.run('sh', ['-c', command], environment: {'HOME': home.path});
      final first = await run();
      expect(first.exitCode, 0, reason: '${first.stderr}');
      expect(first.stdout, contains(AuthorizedKeys.addedMarker));
      final second = await run();
      expect(second.stdout, contains(AuthorizedKeys.presentMarker));
      expect(file.readAsStringSync(), 'ssh-rsa AAAAold old\n$line\n');
    });
  });

  group('install verdict', () {
    test('says whether the key was added, already there, or refused', () {
      ExecOutput out(String stdout, int code, [String stderr = '']) => ExecOutput(stdout: stdout, stderr: stderr, exitCode: code, truncated: false);
      expect(AuthorizedKeys.verdict(out(AuthorizedKeys.addedMarker, 0), 'web').message, startsWith('Key installed on web'));
      expect(AuthorizedKeys.verdict(out(AuthorizedKeys.presentMarker, 0), 'web').message, 'This key was already installed on web.');
      final refused = AuthorizedKeys.verdict(out('', 1, 'Permission denied'), 'web');
      expect(refused.ok, isFalse);
      expect(refused.showOutput, isTrue);
      expect(refused.message, contains('exit code 1'));
    });
  });

  test('algorithm names are shown the way people know them', () {
    expect(KeyAlgorithms.label('ssh-ed25519'), 'Ed25519');
    expect(KeyAlgorithms.label('ecdsa-sha2-nistp256'), 'ECDSA P-256');
    expect(KeyAlgorithms.label('rsa-sha2-512'), 'RSA');
    expect(KeyAlgorithms.label('something-new'), 'something-new');
    expect(KeyComments.forName(' Work laptop '), 'Work laptop@vaultterm');
  });

  testWidgets('an empty keychain explains keys and offers to make one', (tester) async {
    final app = await Harness.pump(tester, () => KeychainScreen(tools: FakeKeyTools()));
    expect(find.text('No keys yet'), findsOneWidget);
    await tester.tap(find.text('New key'));
    await tester.pumpAndSettle();
    expect(find.text('Generate new'), findsOneWidget);
    await app.finish();
  });

  testWidgets('generating a key saves it and returns it to the caller', (tester) async {
    final tools = FakeKeyTools();
    StoredKey? returned;
    final app = await Harness.pump(
      tester,
      () => Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () async => returned = await KeyCreator.open(context, tools: tools), child: const Text('Open')),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Laptop');
    final comment = tester.widget<TextField>(find.widgetWithText(TextField, 'Comment'));
    expect(comment.controller!.text, 'Laptop@vaultterm', reason: 'the comment follows the name');

    // A passphrase that does not match its repeat stops the form.
    await tester.enterText(find.widgetWithText(TextFormField, 'Passphrase (optional)'), 'pw');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'Repeat passphrase'), 'other');
    await tester.tap(find.text('Generate key'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not the same'), findsOneWidget);
    expect(app.store.keys, isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'Repeat passphrase'), 'pw');
    await tester.tap(find.text('RSA 4096'));
    await tester.tap(find.text('Save passphrase in the vault'));
    await tester.tap(find.text('Generate key'));
    await tester.pumpAndSettle();

    final saved = app.store.keys.single;
    expect(returned?.id, saved.id);
    expect(saved.name, 'Laptop');
    expect(saved.encrypted, isTrue);
    expect(saved.passphrase, isNull, reason: 'the switch was turned off');
    expect(tools.kind, KeyKind.rsa4096);
    expect(tools.comment, 'Laptop@vaultterm');
    expect(tools.passphrase, 'pw');
    await app.finish();
  });

  testWidgets('importing a protected key asks for its passphrase and shows the fingerprint first', (tester) async {
    final app = await Harness.pump(tester, () => KeychainScreen(tools: FakeKeyTools()));
    await tester.tap(find.text('New key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import existing'));
    await tester.pumpAndSettle();

    final keyField = find.widgetWithText(TextField, 'Private key');
    await tester.enterText(keyField, 'ssh-ed25519 AAAA me@x');
    await tester.tap(find.text('Check key'));
    await tester.pump();
    expect(find.textContaining('This is a public key'), findsOneWidget);

    await tester.enterText(keyField, '-----BEGIN LOCKED KEY-----');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'Passphrase'), 'nope');
    await tester.tap(find.text('Check key'));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not unlock the key'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Passphrase'), 'secret');
    await tester.tap(find.text('Check key'));
    await tester.pumpAndSettle();
    expect(find.text('SHA256:imported'), findsOneWidget);
    expect(app.store.keys, isEmpty, reason: 'nothing is saved before the user says so');

    await tester.tap(find.text('Save key'));
    await tester.pumpAndSettle();
    final saved = app.store.keys.single;
    expect(saved.name, 'laptop', reason: 'an empty name takes the key comment');
    expect(saved.passphrase, 'secret');
    expect(saved.fingerprint, 'SHA256:imported');
    expect(find.text('Keychain'), findsOneWidget, reason: 'back on the list');
    await app.finish();
  });

  testWidgets('the list shows a lock for protected keys and opens the details', (tester) async {
    final app = await Harness.pump(tester, () => KeychainScreen(tools: FakeKeyTools()), fill: (s) => s.saveKey(Sample.key(encrypted: true)));
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('SHA256:abcdef'), findsOneWidget);
    expect(find.byTooltip('Protected by a passphrase'), findsOneWidget);
    await tester.tap(find.text('Laptop'));
    await tester.pumpAndSettle();
    expect(find.text('Copy public key'), findsOneWidget);
    await tester.tap(find.byTooltip('Rename key'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Work laptop');
    await tester.tap(find.text('Save name'));
    await tester.pumpAndSettle();
    expect(app.store.key('k1')!.name, 'Work laptop');
    expect(find.textContaining('Renamed the key'), findsOneWidget);
    expect(find.textContaining('~/.ssh/authorized_keys'), findsOneWidget);
    expect(find.text('Save passphrase'), findsOneWidget);
    await app.finish();
  });

  testWidgets('saving a passphrase checks it first', (tester) async {
    final app = await Harness.pump(
      tester,
      () => KeyDetailScreen(keyId: 'k1', tools: FakeKeyTools()),
      fill: (s) => s.saveKey(Sample.key(encrypted: true)),
    );
    await tester.tap(find.text('Save passphrase'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Passphrase'), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Save passphrase'));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not unlock the key'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Passphrase'), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Save passphrase'));
    await tester.pumpAndSettle();
    expect(app.store.key('k1')!.passphrase, 'secret');
    expect(find.text('Forget passphrase'), findsOneWidget);

    await tester.tap(find.text('Forget passphrase'));
    await tester.pumpAndSettle();
    expect(app.store.key('k1')!.passphrase, isNull);
    await app.finish();
  });

  testWidgets('deleting a key says which hosts switch to password login', (tester) async {
    final app = await Harness.pump(
      tester,
      () => KeychainScreen(tools: FakeKeyTools()),
      fill: (s) => s
        ..saveKey(Sample.key())
        ..saveHost(Sample.host),
    );
    await tester.tap(find.text('Laptop'));
    await tester.pumpAndSettle();
    expect(find.text('Web'), findsOneWidget, reason: 'the host using the key is listed');
    await tester.tap(find.text('Delete key'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 host uses it and will switch to password login'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete key'));
    await tester.pumpAndSettle();
    expect(app.store.keys, isEmpty);
    expect(app.store.host('h1')!.authMode, AuthMode.password);
    expect(find.text('No keys yet'), findsOneWidget);
    await app.finish();
  });

  testWidgets('known hosts can be forgotten after a warning', (tester) async {
    final app = await Harness.pump(
      tester,
      () => const KeychainScreen(),
      fill: (s) => s.trustHostKey('web.example.com', 2222, const HostKeyInfo(algorithm: 'ssh-ed25519', fingerprint: 'SHA256:srv', publicKey: 'ssh-ed25519 AAAAsrv')),
    );
    await tester.tap(find.text('Known hosts'));
    await tester.pumpAndSettle();
    expect(find.text('web.example.com:2222'), findsOneWidget);
    expect(find.text('SHA256:srv'), findsOneWidget);
    await tester.tap(find.byTooltip('Forget server'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ask you to trust it'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Forget server'));
    await tester.pumpAndSettle();
    expect(app.store.knownHosts, isEmpty);
    expect(find.text('No trusted servers yet'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(app.store.knownHosts.single.fingerprint, 'SHA256:srv', reason: 'Undo trusts the same key again');
    await app.finish();
  });
}
