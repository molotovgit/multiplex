import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../common/widgets.dart';
import 'authorized_keys.dart';
import 'key_dialogs.dart';
import 'key_labels.dart';
import 'key_tools.dart';
import 'page_width.dart';

/// Everything about one key: its public half to copy or install, its
/// passphrase, which hosts use it, rename and delete.
class KeyDetailScreen extends StatefulWidget {
  const KeyDetailScreen({super.key, required this.keyId, this.tools = const NativeKeyTools()});

  final String keyId;
  final KeyTools tools;

  @override
  State<KeyDetailScreen> createState() => _KeyDetailScreenState();
}

class _KeyDetailScreenState extends State<KeyDetailScreen> {
  /// The key as last seen, so the page still shows it while it slides
  /// away after a delete.
  StoredKey? _last;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    final tools = widget.tools;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final key = store.key(widget.keyId) ?? _last;
        if (key == null) return Scaffold(appBar: AppBar());
        _last = key;
        final users = store.hosts.where((h) => h.keyId == key.id).toList();
        return Scaffold(
          appBar: AppBar(title: Text(key.name)),
          bottomNavigationBar: BottomActionBar(
            action: FilledButton.icon(
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy public key'),
              onPressed: () => Toast.copy(context, key.publicOpenssh.trim(), what: 'Copied the public key'),
            ),
          ),
          body: PageWidth(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                KeySummaryTile(storedKey: key),
                const SectionHeader('Fingerprint'),
                FormRow(child: MonoText(key.fingerprint, selectable: true)),
                const SectionHeader('Public key'),
                PublicKeySection(storedKey: key),
                if (key.encrypted) ...[const SectionHeader('Passphrase'), PassphraseTile(storedKey: key, tools: tools)],
                const SectionHeader('Used by'),
                KeyUsersTile(users: users),
                const SizedBox(height: 16),
                FormRow(
                  child: DeleteKeyButton(storedKey: key, users: users.length),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Name, type and date, with a button to rename.
class KeySummaryTile extends StatelessWidget {
  const KeySummaryTile({super.key, required this.storedKey});

  final StoredKey storedKey;

  Future<void> _rename(BuildContext context) async {
    final store = AppScope.store(context);
    final name = await RenameDialog.ask(context, title: 'Rename key', initial: storedKey.name, action: 'Save name');
    if (name == null || name == storedKey.name) return;
    store.saveKey(storedKey.copyWith(name: name));
    if (context.mounted) Toast.show(context, 'Renamed the key to "$name"');
  }

  @override
  Widget build(BuildContext context) {
    final created = MaterialLocalizations.of(context).formatShortDate(storedKey.createdAt);
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      leading: const Icon(Icons.vpn_key_outlined),
      title: Text(storedKey.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text('${KeyAlgorithms.label(storedKey.algorithm)} · Created $created'),
      trailing: IconButton(tooltip: 'Rename key', icon: const Icon(Icons.edit_outlined), onPressed: () => _rename(context)),
    );
  }
}

/// The public key line, what it is for, and installing it on a server.
/// Copying it is the screen's main action, in the bar at the bottom.
class PublicKeySection extends StatelessWidget {
  const PublicKeySection({super.key, required this.storedKey});

  final StoredKey storedKey;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return FormRow(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: colors.raised, borderRadius: BorderRadius.circular(10)),
            child: MonoText(storedKey.publicOpenssh.trim(), selectable: true, style: text.bodySmall),
          ),
          const SizedBox(height: 8),
          Text(
            'Add this line to ~/.ssh/authorized_keys on a server to log in there with this key.',
            style: text.bodySmall?.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.upload_outlined),
              label: const Text('Install on a server'),
              onPressed: () => KeyInstaller.install(context, storedKey),
            ),
          ),
        ],
      ),
    );
  }
}

/// Whether the passphrase is kept in the vault, with the button to change
/// that.
class PassphraseTile extends StatelessWidget {
  const PassphraseTile({super.key, required this.storedKey, required this.tools});

  final StoredKey storedKey;
  final KeyTools tools;

  Future<void> _save(BuildContext context) async {
    final store = AppScope.store(context);
    final passphrase = await PassphraseDialog.ask(
      context,
      keyName: storedKey.name,
      check: (passphrase) async {
        try {
          await tools.inspect(storedKey.privatePem, passphrase: passphrase);
          return null;
        } on KeyProblem catch (problem) {
          return problem.kind == KeyProblemKind.wrongPassphrase
              ? 'That passphrase does not unlock the key. Try again.'
              : 'Could not check the passphrase. Details: ${problem.detail}';
        }
      },
    );
    if (passphrase == null) return;
    store.saveKey(storedKey.copyWith(passphrase: () => passphrase));
    if (context.mounted) Toast.show(context, 'Passphrase saved');
  }

  void _forget(BuildContext context) {
    AppScope.store(context).saveKey(storedKey.copyWith(passphrase: () => null));
    Toast.show(context, 'Passphrase forgotten. You will be asked for it when you connect.');
  }

  @override
  Widget build(BuildContext context) {
    final saved = storedKey.passphrase != null;
    return ListTile(
      leading: Icon(saved ? Icons.lock_open_outlined : Icons.lock_outline),
      title: Text(saved ? 'Saved in the vault' : 'Not saved'),
      subtitle: Text(saved ? 'VaultTerm unlocks the key for you when you connect.' : 'VaultTerm asks for it each time you connect.'),
      trailing: saved
          ? TextButton(onPressed: () => _forget(context), child: const Text('Forget passphrase'))
          : TextButton(onPressed: () => _save(context), child: const Text('Save passphrase')),
    );
  }
}

/// Which saved hosts log in with this key.
class KeyUsersTile extends StatelessWidget {
  const KeyUsersTile({super.key, required this.users});

  final List<Host> users;

  @override
  Widget build(BuildContext context) {
    final names = users.map((h) => h.title).join(', ');
    return ListTile(
      leading: const Icon(Icons.dns_outlined),
      title: Text(switch (users.length) {
        0 => 'No hosts use this key yet',
        1 => '1 host',
        final n => '$n hosts',
      }),
      subtitle: users.isEmpty ? const Text('Choose it in a host\'s settings to log in with it.') : Text(names),
    );
  }
}

/// Deletes the key after asking. Hosts that used it go back to password
/// login, and the message says so.
class DeleteKeyButton extends StatelessWidget {
  const DeleteKeyButton({super.key, required this.storedKey, required this.users});

  final StoredKey storedKey;
  final int users;

  Future<void> _delete(BuildContext context) async {
    final store = AppScope.store(context);
    final hosts = switch (users) {
      0 => 'No hosts use it.',
      1 => '1 host uses it and will switch to password login.',
      final n => '$n hosts use it and will switch to password login.',
    };
    final sure = await Confirm.ask(
      context,
      title: 'Delete "${storedKey.name}"?',
      message:
          '$hosts The key is removed from this device and cannot be brought back. '
          'Servers keep the public key until you remove it there.',
      action: 'Delete key',
    );
    if (!sure || !context.mounted) return;
    Toast.show(context, 'Deleted the key "${storedKey.name}"');
    Navigator.pop(context);
    store.deleteKey(storedKey.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: colors.danger),
        icon: const Icon(Icons.delete_outline),
        label: const Text('Delete key'),
        onPressed: () => _delete(context),
      ),
    );
  }
}
