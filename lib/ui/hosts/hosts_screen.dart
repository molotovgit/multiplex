import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/models.dart';
import '../common/widgets.dart';
import '../update/update_card.dart';
import 'arranged_host_list.dart';
import 'host_connector.dart';
import 'host_editor_screen.dart';
import 'host_tile.dart';
import 'quick_connect.dart';

/// The saved servers: search, recent ones first, then by group. Tap a host
/// to connect. Typing "user@host" in the search offers to connect right
/// away without saving it first.
class HostsScreen extends StatefulWidget {
  const HostsScreen({super.key});

  @override
  State<HostsScreen> createState() => _HostsScreenState();
}

class _HostsScreenState extends State<HostsScreen> {
  /// How many recently used hosts to list at the top.
  static const _recentCount = 3;

  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openEditor({Host? host, String? groupId}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HostEditorScreen(host: host, initialGroupId: groupId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    final sessions = AppScope.sessions(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Hosts')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _openEditor(), icon: const Icon(Icons.add), label: const Text('New host')),
      body: ListenableBuilder(
        listenable: Listenable.merge([store, sessions]),
        builder: (context, _) {
          final hosts = store.hosts;
          if (hosts.isEmpty && _query.isEmpty) {
            return _EmptyHosts(
              onAdd: () => _openEditor(),
              searchField: _SearchField(controller: _search, onChanged: _onQuery),
            );
          }
          final header = [const UpdateBanner(), _SearchField(controller: _search, onChanged: _onQuery), ..._recent(hosts)];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: _query.isNotEmpty
                  ? ListView(padding: const EdgeInsets.only(bottom: 96), children: [...header.take(2), ..._searchResults(hosts)])
                  : ArrangedHostList(
                      header: header,
                      groupMenu: (group) => _GroupMenu(
                        group: group,
                        onAddHost: () => _openEditor(groupId: group.id),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }

  void _onQuery(String value) => setState(() => _query = value.trim());

  /// Hosts matching the search, plus "connect to user@host" when the text
  /// looks like an address.
  List<Widget> _searchResults(List<Host> hosts) {
    final q = _query.toLowerCase();
    final matches = hosts.where((h) => '${h.label} ${h.address} ${h.username}'.toLowerCase().contains(q)).toList();
    final quick = QuickTarget.parse(_query);
    return [
      if (quick != null) QuickConnectTile(target: quick),
      if (matches.isEmpty && quick == null)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No hosts match. Try a name or an address.')),
        ),
      for (final host in matches) HostTile(host: host),
    ];
  }

  /// The last few hosts used, above the arranged list (not draggable: they
  /// are shortcuts, the real place of each host is below).
  List<Widget> _recent(List<Host> hosts) {
    final recent = hosts.where((h) => h.lastConnectedAt != null).toList()..sort((a, b) => b.lastConnectedAt!.compareTo(a.lastConnectedAt!));
    if (recent.length < 2 || hosts.length <= _recentCount) return const [];
    return [const SectionHeader('Recent'), for (final host in recent.take(_recentCount)) HostTile(host: host, compactMenu: true)];
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: SearchBar(
        controller: controller,
        onChanged: onChanged,
        hintText: 'Search, or type user@host to connect',
        leading: const Icon(Icons.search),
        elevation: const WidgetStatePropertyAll(0),
        keyboardType: TextInputType.url,
        trailing: [
          if (controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              icon: const Icon(Icons.close),
              onPressed: () {
                controller.clear();
                onChanged('');
              },
            ),
        ],
      ),
    );
  }
}

class _EmptyHosts extends StatelessWidget {
  const _EmptyHosts({required this.onAdd, required this.searchField});

  final VoidCallback onAdd;
  final Widget searchField;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const UpdateBanner(),
        searchField,
        Expanded(
          child: EmptyState(
            icon: Icons.dns_outlined,
            title: 'Add your first server',
            message:
                'Save a server once with its address and login, then connect with one tap. '
                'Or type user@host above to connect right away.',
            actionLabel: 'Add a host',
            onAction: onAdd,
          ),
        ),
      ],
    );
  }
}

/// Rename or delete a group, or add a host to it.
class _GroupMenu extends StatelessWidget {
  const _GroupMenu({required this.group, required this.onAddHost});

  final HostGroup group;
  final VoidCallback onAddHost;

  Future<void> _rename(BuildContext context) async {
    final name = await GroupNameDialog.ask(context, initial: group.name, title: 'Rename group');
    if (name != null && context.mounted) AppScope.store(context).saveGroup(group.copyWith(name: name));
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await Confirm.ask(
      context,
      title: 'Delete the group "${group.name}"?',
      message: 'The hosts in it are kept and move to "Other hosts".',
      action: 'Delete group',
    );
    if (ok && context.mounted) AppScope.store(context).deleteGroup(group.id);
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Group actions',
      icon: const Icon(Icons.more_horiz),
      onSelected: (choice) => switch (choice) {
        0 => onAddHost(),
        1 => _rename(context),
        _ => _delete(context),
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 0,
          child: ListTile(leading: Icon(Icons.add), title: Text('Add host here')),
        ),
        PopupMenuItem(
          value: 1,
          child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Rename group')),
        ),
        PopupMenuItem(
          value: 2,
          child: ListTile(leading: Icon(Icons.folder_delete_outlined), title: Text('Delete group')),
        ),
      ],
    );
  }
}

/// Asks for a group name.
class GroupNameDialog extends StatefulWidget {
  const GroupNameDialog({super.key, required this.initial, required this.title});

  final String initial;
  final String title;

  static Future<String?> ask(BuildContext context, {String initial = '', String title = 'New group'}) => showDialog<String>(
    context: context,
    builder: (_) => GroupNameDialog(initial: initial, title: title),
  );

  @override
  State<GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<GroupNameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _name,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Group name', hintText: 'Production'),
        onSubmitted: (_) => _done(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _done, child: const Text('Save group')),
      ],
    );
  }
}

/// Opens a terminal on a host, for use by other screens.
abstract final class HostActions {
  static Future<void> connect(BuildContext context, Host host) => HostConnector.openTerminal(context, host);
}
