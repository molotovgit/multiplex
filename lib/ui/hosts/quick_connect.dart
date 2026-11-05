import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/models.dart';
import '../../data/vault_store.dart';
import '../common/widgets.dart';
import 'host_connector.dart';

/// An address typed into the search: `[user@]host[:port]`.
class QuickTarget {
  const QuickTarget({required this.user, required this.host, required this.port});

  final String user;
  final String host;
  final int port;

  static final _pattern = RegExp(r'^(?:([A-Za-z0-9._-]+)@)?([A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\])(?::(\d{1,5}))?$');

  /// Reads the text, or returns null when it is not an address. A plain
  /// word without a dot or "@" is treated as a search, not an address.
  static QuickTarget? parse(String text) {
    final match = _pattern.firstMatch(text.trim());
    if (match == null) return null;
    final user = match.group(1) ?? '';
    final host = match.group(2)!.replaceAll('[', '').replaceAll(']', '');
    if (user.isEmpty && !host.contains('.') && !host.contains(':') && host != 'localhost') return null;
    final port = int.tryParse(match.group(3) ?? '') ?? 22;
    if (port < 1 || port > 65535) return null;
    return QuickTarget(user: user, host: host, port: port);
  }

  String get display => '${user.isEmpty ? '' : '$user@'}$host${port == 22 ? '' : ':$port'}';

  /// A host that is not saved yet. If the user chooses to remember a
  /// password while connecting, it gets saved.
  Host toHost() => Host(id: VaultStore.newId(), label: '', address: host, port: port, username: user);
}

/// "Connect to user@host" at the top of the search results.
class QuickConnectTile extends StatelessWidget {
  const QuickConnectTile({super.key, required this.target});

  final QuickTarget target;

  Future<void> _connect(BuildContext context) async {
    var host = target.toHost();
    if (host.username.isEmpty) {
      final user = await _UserNameDialog.ask(context);
      if (user == null || !context.mounted) return;
      host = host.copyWith(username: user);
    }
    await HostConnector.openTerminal(context, host);
  }

  void _save(BuildContext context) {
    AppScope.store(context).saveHost(target.toHost());
    Toast.show(context, 'Saved ${target.display}');
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const SizedBox(width: 44, height: 44, child: Icon(Icons.bolt)),
      title: Text('Connect to ${target.display}'),
      subtitle: const Text('Without saving it first'),
      onTap: () => _connect(context),
      trailing: TextButton(onPressed: () => _save(context), child: const Text('Save host')),
    );
  }
}

class _UserNameDialog extends StatefulWidget {
  const _UserNameDialog();

  static Future<String?> ask(BuildContext context) => showDialog<String>(context: context, builder: (_) => const _UserNameDialog());

  @override
  State<_UserNameDialog> createState() => _UserNameDialogState();
}

class _UserNameDialogState extends State<_UserNameDialog> {
  final _name = TextEditingController(text: 'root');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('User name'),
      content: TextField(
        controller: _name,
        autofocus: true,
        autocorrect: false,
        decoration: const InputDecoration(labelText: 'Log in as'),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _name.text.trim()), child: const Text('Connect')),
      ],
    );
  }
}
