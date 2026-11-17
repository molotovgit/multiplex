import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../sessions/error_text.dart';
import '../../sessions/session_manager.dart';
import '../../src/rust/api/agents.dart';
import '../../src/rust/api/terminal_types.dart';
import '../common/widgets.dart';
import '../hosts/host_connector.dart';
import '../settings/settings_widgets.dart';
import '../terminal/terminal_screen.dart';

/// The coding agents running on a paired computer (under herdr): which
/// are working, which wait for an answer, which are done. A tap opens a
/// terminal sitting in front of them.
class AgentsScreen extends StatefulWidget {
  const AgentsScreen({super.key, required this.title, required this.load, required this.onOpen});

  /// The computer's name.
  final String title;

  /// Asks the computer. Tests pass a stand-in.
  final Future<List<Agent>> Function() load;

  /// Opens a terminal attached to an agent's herdr session.
  final Future<void> Function(BuildContext context, Agent agent) onOpen;

  /// Connects (if needed) and opens the list.
  static Future<void> show(BuildContext context, Host host) async {
    final LiveSession? session = await HostConnector.connect(context, host);
    if (session == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgentsScreen(title: host.title, load: () => session.ssh.agents(), onOpen: (context, agent) => _attach(context, session, agent)),
      ),
    );
  }

  static Future<void> _attach(BuildContext context, LiveSession session, Agent agent) async {
    final command = agentAttachCommand(session: agent.session);
    if (command == null) {
      Toast.show(context, 'That session cannot be opened from here.');
      return;
    }
    final sessions = AppScope.sessions(context);
    try {
      final terminal = await sessions.openTerminal(session);
      terminal
        ..type(command)
        ..key(TerminalKey.enter);
      if (context.mounted) await TerminalScreen.open(context, session, terminal);
    } catch (e) {
      if (context.mounted) Toast.show(context, errorSentence(e, fallback: 'Could not open a terminal.'));
    }
  }

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  List<Agent>? _agents;
  String? _problem;
  Timer? _refresh;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Agents change state by themselves: keep the list current.
    _refresh = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final agents = await widget.load();
      // Those that need an answer first, then the busy ones.
      agents.sort((a, b) => _rank(a.status).compareTo(_rank(b.status)));
      if (mounted) {
        setState(() {
          _agents = agents;
          _problem = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _problem = errorSentence(e, fallback: 'The computer did not answer.'));
    } finally {
      _loading = false;
    }
  }

  static int _rank(AgentStatus status) => switch (status) {
    AgentStatus.blocked => 0,
    AgentStatus.working => 1,
    AgentStatus.done => 2,
    AgentStatus.idle => 3,
    AgentStatus.unknown => 4,
  };

  @override
  Widget build(BuildContext context) {
    final agents = _agents;
    final problem = _problem;
    return Scaffold(
      appBar: AppBar(title: Text('Agents on ${widget.title}')),
      body: ContentWidth(
        child: agents == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: problem == null ? const BusyNote('Asking the computer…') : NoticeBox(tone: NoticeTone.error, text: problem),
                ),
              )
            : agents.isEmpty
            ? const EmptyState(
                icon: Icons.smart_toy_outlined,
                title: 'No agents are running',
                message: 'Coding agents started under herdr on this computer show up here, with what each is doing.',
              )
            : ListView(
                children: [
                  if (problem != null)
                    Padding(
                      padding: const EdgeInsets.all(SettingsLayout.gutter),
                      child: NoticeBox(tone: NoticeTone.error, text: problem),
                    ),
                  for (final agent in agents) _AgentTile(agent: agent, onTap: () => widget.onOpen(context, agent)),
                ],
              ),
      ),
    );
  }
}

class _AgentTile extends StatelessWidget {
  const _AgentTile({required this.agent, required this.onTap});

  final Agent agent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final (label, color, icon) = switch (agent.status) {
      AgentStatus.blocked => ('Needs you', colors.accent, Icons.front_hand_outlined),
      AgentStatus.working => ('Working', colors.live, Icons.autorenew),
      AgentStatus.done => ('Done', colors.muted, Icons.check_circle_outline),
      AgentStatus.idle => ('Idle', colors.muted, Icons.pause_circle_outline),
      AgentStatus.unknown => ('Unknown', colors.muted, Icons.help_outline),
    };
    final where = [if (agent.workspace.isNotEmpty) agent.workspace, if (agent.folder.isNotEmpty && agent.folder != agent.workspace) agent.folder].join(' · ');
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(agent.title.isEmpty ? agent.name : agent.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([agent.name, if (where.isNotEmpty) where].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
    );
  }
}
