import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../sessions/error_text.dart';
import '../../sessions/herd_controller.dart';
import '../../sessions/session_manager.dart';
import '../../src/rust/api/agents.dart';
import '../../src/rust/api/herd_types.dart';
import '../../src/rust/api/terminal_types.dart';
import '../common/widgets.dart';
import '../hosts/host_connector.dart';
import '../settings/settings_widgets.dart';
import '../terminal/terminal_screen.dart';

/// How an agent's state is shown: its words, colour and icon.
({String label, Color color, IconData icon}) agentLook(AppColors colors, AgentStatus status) => switch (status) {
  AgentStatus.blocked => (label: 'Needs you', color: colors.accent, icon: Icons.front_hand_outlined),
  AgentStatus.done => (label: 'Done', color: colors.live, icon: Icons.check_circle_outline),
  AgentStatus.working => (label: 'Working', color: colors.live, icon: Icons.autorenew),
  AgentStatus.idle => (label: 'Idle', color: colors.muted, icon: Icons.pause_circle_outline),
  AgentStatus.unknown => (label: 'Other', color: colors.muted, icon: Icons.help_outline),
};

/// The coding agents on a paired computer (kept running by herdr), as an
/// inbox: those that need an answer first, then those that finished, the
/// busy, the idle. The computer tells of every change, so the list is
/// always the present. A tap opens an agent to read and answer it.
class AgentsScreen extends StatefulWidget {
  const AgentsScreen({super.key, required this.title, required this.link, required this.onOpenTerminal});

  /// The computer's name.
  final String title;

  /// The computer's herdr. Tests pass a stand-in.
  final HerdLink link;

  /// Opens a terminal attached to an agent's herdr session.
  final Future<void> Function(BuildContext context, HerdAgent agent) onOpenTerminal;

  /// Connects (if needed) and opens the inbox.
  static Future<void> show(BuildContext context, Host host) async {
    final LiveSession? session = await HostConnector.connect(context, host);
    if (session == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AgentsScreen(title: host.title, link: SshHerdLink(() => session.ssh), onOpenTerminal: (context, agent) => _attach(context, session, agent)),
      ),
    );
  }

  static Future<void> _attach(BuildContext context, LiveSession session, HerdAgent agent) async {
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
  late final HerdController _herd = HerdController(widget.link);

  @override
  void initState() {
    super.initState();
    unawaited(_herd.start());
  }

  @override
  void dispose() {
    _herd.dispose();
    super.dispose();
  }

  void _open(HerdAgent agent) {
    unawaited(AgentSheet.show(context, herd: _herd, agent: agent, onOpenTerminal: () => widget.onOpenTerminal(context, agent)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Agents on ${widget.title}')),
      body: ContentWidth(
        child: ListenableBuilder(
          listenable: _herd,
          builder: (context, _) {
            final state = _herd.state;
            final problem = _herd.problem;
            if (state == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: problem == null
                      ? const BusyNote('Asking the computer…')
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            NoticeBox(tone: NoticeTone.error, text: problem),
                            const SizedBox(height: 12),
                            FilledButton.tonal(onPressed: _herd.start, child: const Text('Try again')),
                          ],
                        ),
                ),
              );
            }
            if (!state.available) {
              return const EmptyState(
                icon: Icons.smart_toy_outlined,
                title: 'herdr is not on this computer',
                message: 'herdr keeps coding agents running in terminals that outlive every window. Install it on the computer and start an agent in it; it shows up here.',
              );
            }
            if (state.inbox.isEmpty) {
              final terminals = state.sessions.expand((s) => s.workspaces).expand((w) => w.tabs).fold<int>(0, (sum, tab) => sum + tab.panes.length);
              return EmptyState(
                icon: Icons.smart_toy_outlined,
                title: 'No agents are running',
                message: terminals == 0
                    ? 'Coding agents started under herdr on this computer show up here, with what each is doing.'
                    : 'herdr has ${terminals == 1 ? 'one terminal' : '$terminals terminals'} open, none with an agent in it. An agent started there shows up here.',
              );
            }
            final several = state.sessions.length > 1;
            final rows = <Widget>[
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.all(SettingsLayout.gutter),
                  child: NoticeBox(tone: NoticeTone.error, text: problem),
                ),
            ];
            AgentStatus? group;
            for (final agent in state.inbox) {
              if (agent.status != group) {
                group = agent.status;
                final count = state.inbox.where((a) => a.status == group).length;
                rows.add(SectionHeader('${agentLook(AppColorsTheme.of(context), agent.status).label} · $count'));
              }
              rows.add(_AgentTile(key: ValueKey('${agent.session}/${agent.pane}'), agent: agent, showSession: several, onTap: () => _open(agent)));
            }
            return ListView(children: rows);
          },
        ),
      ),
    );
  }
}

class _AgentTile extends StatelessWidget {
  const _AgentTile({super.key, required this.agent, required this.showSession, required this.onTap});

  final HerdAgent agent;
  final bool showSession;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final look = agentLook(AppColorsTheme.of(context), agent.status);
    final where = [
      agent.name,
      if (agent.workspace.isNotEmpty) agent.workspace,
      if (agent.folder.isNotEmpty && agent.folder != agent.workspace) agent.folder,
      if (showSession) agent.session,
    ].join(' · ');
    return ListTile(
      leading: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Icon(look.icon, key: ValueKey(agent.status), color: look.color),
      ),
      title: Text(agent.title.isEmpty ? agent.name : agent.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(where, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// One agent, to read and to answer without a terminal: what it last
/// wrote, the keys its questions take, and a line to write to it.
class AgentSheet extends StatefulWidget {
  const AgentSheet({super.key, required this.herd, required this.session, required this.pane, required this.onOpenTerminal});

  final HerdController herd;
  final String session;
  final String pane;
  final VoidCallback onOpenTerminal;

  static Future<void> show(BuildContext context, {required HerdController herd, required HerdAgent agent, required VoidCallback onOpenTerminal}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: AgentSheet(herd: herd, session: agent.session, pane: agent.pane, onOpenTerminal: onOpenTerminal),
      ),
    );
  }

  /// The keys an agent's questions take, by herdr's names, with what each
  /// is called on its button and in its tooltip.
  static const quickKeys = [
    ('esc', 'Esc', 'Press Escape'),
    ('1', '1', 'Press 1'),
    ('2', '2', 'Press 2'),
    ('3', '3', 'Press 3'),
    ('up', '↑', 'Press Up'),
    ('down', '↓', 'Press Down'),
    ('tab', 'Tab', 'Press Tab'),
    ('enter', 'Enter', 'Press Enter'),
  ];

  @override
  State<AgentSheet> createState() => _AgentSheetState();
}

class _AgentSheetState extends State<AgentSheet> {
  final _answer = TextEditingController();
  final _scroll = ScrollController();
  String? _output;
  AgentStatus? _status;
  Timer? _follow;
  bool _reading = false;
  bool _sending = false;

  /// While an agent works its output moves: read again this often.
  static const _followEvery = Duration(seconds: 2);

  /// A key or an answer takes a moment to show in the pane.
  static const _afterAsking = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    widget.herd.addListener(_herdChanged);
    _status = widget.herd.agent(widget.session, widget.pane)?.status;
    unawaited(_read());
    _keepFollowing();
  }

  @override
  void dispose() {
    widget.herd.removeListener(_herdChanged);
    _follow?.cancel();
    _answer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _herdChanged() {
    final status = widget.herd.agent(widget.session, widget.pane)?.status;
    if (status != _status) {
      // It began to wait, or finished, or went on: what it wrote is news.
      _status = status;
      unawaited(_read());
      _keepFollowing();
    }
    if (mounted) setState(() {});
  }

  void _keepFollowing() {
    _follow?.cancel();
    _follow = _status == AgentStatus.working ? Timer.periodic(_followEvery, (_) => _read()) : null;
  }

  Future<void> _read() async {
    if (_reading) return;
    _reading = true;
    final text = await widget.herd.read(widget.session, widget.pane);
    _reading = false;
    if (!mounted || text == null) return;
    setState(() => _output = text.trimRight());
  }

  Future<void> _press(String key) async {
    if (await widget.herd.press(widget.session, widget.pane, [key])) {
      await Future<void>.delayed(_afterAsking);
      if (mounted) unawaited(_read());
    }
  }

  Future<void> _send() async {
    final text = _answer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final sent = await widget.herd.prompt(widget.session, widget.pane, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!sent) return;
    _answer.clear();
    await Future<void>.delayed(_afterAsking);
    if (mounted) unawaited(_read());
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final agent = widget.herd.agent(widget.session, widget.pane);
    final problem = widget.herd.problem;
    final output = _output;
    final look = agent == null ? null : agentLook(colors, agent.status);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (look != null) ...[Icon(look.icon, color: look.color), const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agent == null ? 'This agent is no longer running' : (agent.title.isEmpty ? agent.name : agent.title),
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (agent != null && look != null)
                      Text(
                        [look.label, agent.name, if (agent.folder.isNotEmpty) agent.folder].join(' · '),
                        style: textTheme.bodySmall?.copyWith(color: colors.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              IconButton(tooltip: 'Read again', icon: const Icon(Icons.refresh), onPressed: _read),
              IconButton(tooltip: 'Open in a terminal', icon: const Icon(Icons.terminal), onPressed: widget.onOpenTerminal),
            ],
          ),
          const SizedBox(height: 8),
          if (problem != null) ...[NoticeBox(tone: NoticeTone.error, text: problem), const SizedBox(height: 8)],
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: colors.raised, borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.all(12),
              child: output == null
                  ? Center(child: problem == null ? const BusyNote('Reading what it wrote…') : const SizedBox.shrink())
                  : SingleChildScrollView(
                      controller: _scroll,
                      // The newest lines are what matters: start at the end.
                      reverse: true,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: SelectableText(
                          output.isEmpty ? 'Nothing written yet.' : output,
                          style: TextStyle(fontFamily: 'JetBrainsMonoNerd', fontSize: 12, height: 1.35, color: output.isEmpty ? colors.muted : colors.text),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (key, label, tip) in AgentSheet.quickKeys)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Tooltip(
                      message: tip,
                      child: OutlinedButton(
                        onPressed: agent == null ? null : () => _press(key),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 40), padding: const EdgeInsets.symmetric(horizontal: 12)),
                        child: Text(label),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _answer,
                  enabled: agent != null,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(hintText: 'Answer it, or ask for more'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: agent == null || _sending ? null : _send,
                icon: _sending ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
