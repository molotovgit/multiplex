import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/resume_place.dart';
import '../computers/computer_screen.dart';
import '../computers/agents_screen.dart';
import '../../sessions/herd_hub.dart';
import '../../sessions/computer_links.dart';
import '../computers/computer_sharing_screen.dart';
import '../settings/settings_widgets.dart';
import '../common/widgets.dart';
import '../update/update_card.dart';
import 'arranged_host_list.dart';
import 'host_connector.dart';
import 'host_editor_screen.dart';
import 'host_tile.dart';
import '../computers/computer_card.dart';
import '../pair/pair_screen.dart';
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
      appBar: AppBar(
        title: const Text('Home'),
        actions: [IconButton(tooltip: 'Pair a computer', icon: const Icon(Icons.qr_code_scanner), onPressed: () => PairScreen.open(context))],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _openEditor(), icon: const Icon(Icons.add), label: const Text('New host')),
      body: ListenableBuilder(
        listenable: Listenable.merge([store, sessions, ?HerdHub.app, ?ComputerLinks.app]),
        builder: (context, _) {
          final hosts = store.hosts;
          if (hosts.isEmpty && _query.isEmpty) {
            return _FirstRun(
              onPair: () => PairScreen.open(context),
              onAdd: () => _openEditor(),
              searchField: _SearchField(controller: _search, onChanged: _onQuery),
            );
          }
          final computers = hosts.where((h) => h.computer).toList();
          final servers = hosts.where((h) => !h.computer).toList();
          final header = [
            const UpdateBanner(),
            _SearchField(controller: _search, onChanged: _onQuery),
            ..._agents(context),
            ..._arrived(context, computers),
            ..._continue(context, store.settings.resume, computers),
            if (computers.isNotEmpty) ...[
              const SectionHeader('Computers'),
              for (final computer in computers) ComputerCard(key: ValueKey('computer-${computer.id}'), host: computer),
            ],
            ..._recent(servers),
          ];
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

  /// Files a computer sent since the app started, the newest few: they
  /// are news until looked at. A tap goes to that computer's sharing
  /// page, where all of them are listed with where they were saved.
  List<Widget> _arrived(BuildContext context, List<Host> computers) {
    final received = ComputerLinks.app?.received ?? const <ReceivedFile>[];
    if (received.isEmpty) return const [];
    const most = 3;
    return [
      const SectionHeader('Arrived'),
      for (final file in received.take(most))
        ListTile(
          key: ValueKey('arrived-${file.path}'),
          leading: const Icon(Icons.download_done_outlined),
          title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('From ${file.from} · saved in Multiplex downloads', maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            final host = computers.where((host) => host.title == file.from).firstOrNull;
            if (host != null) ComputerSharingScreen.open(context, host.id);
          },
        ),
      if (received.length > most)
        Padding(
          padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 0, SettingsLayout.gutter, 8),
          child: Text('and ${received.length - most} more', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColorsTheme.of(context).muted)),
        ),
    ];
  }

  /// The agents that want the owner, on whichever connected computer:
  /// those that wait for an answer first, then those that finished. One
  /// tap goes from Home to the agent itself.
  List<Widget> _agents(BuildContext context) {
    final wanting = HerdHub.app?.wanting ?? const <HubAgent>[];
    if (wanting.isEmpty) return const [];
    final colors = AppColorsTheme.of(context);
    // Home is for what comes first; the rest is one tap further.
    const most = 5;
    return [
      const SectionHeader('Agents'),
      for (final (:host, :agent) in wanting.take(most))
        ListTile(
          key: ValueKey('agent-${host.id}-${agent.session}-${agent.pane}'),
          leading: Icon(agentLook(colors, agent.status).icon, color: agentLook(colors, agent.status).color),
          title: Text(agent.title.isEmpty ? agent.name : agent.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${agentLook(colors, agent.status).label} · ${agent.name} · ${host.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => AgentsScreen.show(
            context,
            host,
            place: ResumePlace(hostId: host.id, session: agent.session, pane: agent.pane, title: agent.title, agent: agent.name),
          ),
        ),
      if (wanting.length > most)
        ListTile(
          key: const ValueKey('agents-more'),
          leading: const SizedBox(width: 24),
          title: Text('${wanting.length - most} more'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => AgentsScreen.show(context, wanting[most].host),
        ),
    ];
  }

  /// Where the owner last was with an agent or a terminal, one tap away:
  /// nothing when there is no such place, or its computer is gone.
  List<Widget> _continue(BuildContext context, Map<String, dynamic> saved, List<Host> computers) {
    final place = ResumePlace.fromJson(saved);
    final host = place == null ? null : computers.where((h) => h.id == place.hostId).firstOrNull;
    if (place == null || host == null) return const [];
    return [
      const SectionHeader('Continue'),
      ListTile(
        key: const ValueKey('continue'),
        leading: Icon(place.agent.isEmpty ? Icons.terminal : Icons.smart_toy_outlined),
        title: Text(place.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${place.agent.isEmpty ? 'Terminal' : place.agent} on ${host.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => AgentsScreen.show(context, host, place: place),
      ),
    ];
  }

  /// Hosts matching the search, plus "connect to user@host" when the text
  /// looks like an address.
  List<Widget> _searchResults(List<Host> hosts) {
    final q = _query.toLowerCase();
    final matches = hosts.where((h) => '${h.label} ${h.address} ${h.username}'.toLowerCase().contains(q)).toList();
    final quick = QuickTarget.parse(_query);
    final colors = AppColorsTheme.of(context);
    // One search for everything one could want to go to: an agent on any
    // connected computer, and anything a paired computer offers ("camera",
    // "files"), each one tap from the thing itself.
    final agents = [
      for (final one in HerdHub.app?.all ?? const <HubAgent>[])
        if ('${one.agent.title} ${one.agent.name} ${one.agent.folder} ${one.agent.workspace}'.toLowerCase().contains(q)) one,
    ];
    final features = [
      for (final host in hosts.where((host) => host.computer))
        for (final (group, list) in ComputerScreen.featuresOf(context, host))
          for (final feature in list)
            if ('${feature.title} ${feature.subtitle} $group'.toLowerCase().contains(q)) (host: host, feature: feature),
    ];
    return [
      if (quick != null) QuickConnectTile(target: quick),
      if (matches.isEmpty && quick == null && agents.isEmpty && features.isEmpty)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('Nothing matches. Try a name, an address, or what you want to do.')),
        ),
      for (final host in matches) HostTile(host: host),
      if (agents.isNotEmpty) const SectionHeader('Agents'),
      for (final (:host, :agent) in agents.take(8))
        ListTile(
          key: ValueKey('found-agent-${host.id}-${agent.session}-${agent.pane}'),
          leading: Icon(agentLook(colors, agent.status).icon, color: agentLook(colors, agent.status).color),
          title: Text(agent.title.isEmpty ? agent.name : agent.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${agentLook(colors, agent.status).label} · ${agent.name} · ${host.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => AgentsScreen.show(
            context,
            host,
            place: ResumePlace(hostId: host.id, session: agent.session, pane: agent.pane, title: agent.title, agent: agent.name),
          ),
        ),
      if (features.isNotEmpty) const SectionHeader('Go to'),
      for (final (:host, :feature) in features.take(12))
        ListTile(
          key: ValueKey('found-${host.id}-${feature.title}'),
          leading: Icon(feature.icon),
          title: Text('${feature.title} · ${host.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(feature.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: feature.onTap,
        ),
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
        hintText: 'Search, go to, or type user@host',
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

/// First run: one thing to do, pairing a computer. Plain SSH servers are
/// still a tap away.
class _FirstRun extends StatelessWidget {
  const _FirstRun({required this.onPair, required this.onAdd, required this.searchField});

  final VoidCallback onPair;
  final VoidCallback onAdd;
  final Widget searchField;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        const UpdateBanner(),
        searchField,
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.qr_code_scanner, size: 48, color: colors.accent),
                    const SizedBox(height: 16),
                    Text('Pair your computer', style: text.titleLarge, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      'Run `multiplex pair` on your Omarchy computer and scan the code it shows. '
                      'Its desktop, terminal and files are then one tap away, at home or anywhere.',
                      style: text.bodyMedium?.copyWith(color: colors.muted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(onPressed: onPair, icon: const Icon(Icons.qr_code_scanner), label: const Text('Pair a computer')),
                    const SizedBox(height: 8),
                    TextButton(onPressed: onAdd, child: const Text('Add an SSH server instead')),
                  ],
                ),
              ),
            ),
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
