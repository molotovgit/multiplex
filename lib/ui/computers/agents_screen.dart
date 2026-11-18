import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/resume_place.dart';
import '../../sessions/error_text.dart';
import '../../sessions/herd_controller.dart';
import '../../sessions/session_manager.dart';
import '../../src/rust/api/agents.dart';
import '../../src/rust/api/herd.dart';
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
  const AgentsScreen({
    super.key,
    required this.title,
    required this.link,
    required this.onOpenTerminal,
    required this.onOpenHerdr,
    this.openAt,
    this.onVisited,
  });

  /// The computer's name.
  final String title;

  /// The computer's herdr. Tests pass a stand-in.
  final HerdLink link;

  /// Opens a terminal in front of one pane alone, drawn at the phone's
  /// size: an agent's, or a plain terminal's.
  final Future<void> Function(BuildContext context, String session, String pane) onOpenTerminal;

  /// Opens a terminal with a herdr session's whole screen.
  final Future<void> Function(BuildContext context, String session) onOpenHerdr;

  /// A pane to go straight to once the herd is known: where the owner
  /// was last (Home's "Continue").
  final ({String session, String pane})? openAt;

  /// Told each time an agent or a terminal is opened, so it can be
  /// remembered as the place to continue from. [agent] is empty for a
  /// plain terminal.
  final void Function(String session, String pane, String title, String agent)? onVisited;

  /// Connects (if needed) and opens the inbox, or with [place] goes
  /// straight to where the owner was.
  static Future<void> show(BuildContext context, Host host, {ResumePlace? place}) async {
    final LiveSession? session = await HostConnector.connect(context, host);
    if (session == null || !context.mounted) return;
    final store = AppScope.store(context);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgentsScreen(
          title: host.title,
          link: SshHerdLink(() => session.ssh),
          onOpenTerminal: (context, name, pane) => _run(context, session, herdPaneCommand(session: name, pane: pane), aView: true),
          onOpenHerdr: (context, name) => _run(context, session, agentAttachCommand(session: name)),
          openAt: place == null ? null : (session: place.session, pane: place.pane),
          onVisited: (name, pane, title, agent) => store.updateSettings(
            store.settings.copyWith(
              resume: ResumePlace(hostId: host.id, session: name, pane: pane, title: title, agent: agent).toJson(),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens a terminal on the computer and types [command] there; the
  /// core gives none for a session or pane that is not one. [aView] is a
  /// terminal that only shows a pane: it is closed when it is left, so no
  /// view of a pane stays running on the computer with nobody looking
  /// (seen on the phone: each visit left one behind).
  static Future<void> _run(BuildContext context, LiveSession session, String? command, {bool aView = false}) async {
    if (command == null) {
      Toast.show(context, 'That cannot be opened from here.');
      return;
    }
    final sessions = AppScope.sessions(context);
    try {
      final terminal = await sessions.openTerminal(session);
      terminal
        ..type(command)
        ..key(TerminalKey.enter);
      if (!context.mounted) {
        if (aView) sessions.closeTerminal(terminal);
        return;
      }
      if (!aView) {
        await TerminalScreen.open(context, session, terminal);
        return;
      }
      // A view is closed once its screen is gone for good, exit animation
      // and all: closing it the moment the screen starts to leave broke
      // that animation (seen on the phone as Flutter's error screen).
      final route = MaterialPageRoute<void>(
        builder: (_) => TerminalScreen(session: session, controller: terminal),
      );
      unawaited(Navigator.of(context).push(route));
      try {
        await route.completed;
      } finally {
        sessions.closeTerminal(terminal);
      }
    } catch (e) {
      if (context.mounted) Toast.show(context, errorSentence(e, fallback: 'Could not open a terminal.'));
    }
  }

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  late final HerdController _herd = HerdController(widget.link);

  /// Still to go to: the place asked for, until the herd is known.
  late ({String session, String pane})? _goTo = widget.openAt;

  @override
  void initState() {
    super.initState();
    _herd.addListener(_arrive);
    unawaited(_herd.start());
  }

  /// Once the herd is known, goes where the owner was: its agent, its
  /// terminal, or, when it is gone, says so and stays on the list.
  void _arrive() {
    final place = _goTo;
    final state = _herd.state;
    if (place == null || state == null) return;
    _goTo = null;
    _herd.removeListener(_arrive);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pane = _pane(state, place.session, place.pane);
      if (pane == null) {
        Toast.show(context, 'That one is no longer running. Here is what is.');
      } else {
        _openPane(place.session, pane);
      }
    });
  }

  static HerdPane? _pane(HerdState state, String session, String id) {
    for (final one in state.sessions) {
      if (one.name != session) continue;
      for (final pane in one.workspaces.expand((w) => w.tabs).expand((t) => t.panes)) {
        if (pane.id == id) return pane;
      }
    }
    return null;
  }

  /// An agent's pane opens the agent; a plain terminal opens as itself.
  /// Either way it is the place to continue from next time.
  void _openPane(String session, HerdPane pane) {
    final agent = _herd.agent(session, pane.id);
    widget.onVisited?.call(session, pane.id, pane.title, pane.agent ?? '');
    if (agent != null) {
      _show(agent);
    } else {
      unawaited(widget.onOpenTerminal(context, session, pane.id));
    }
  }

  @override
  void dispose() {
    _herd.dispose();
    super.dispose();
  }

  void _open(HerdAgent agent) {
    widget.onVisited?.call(agent.session, agent.pane, agent.title, agent.name);
    _show(agent);
  }

  void _show(HerdAgent agent) {
    unawaited(AgentSheet.show(context, herd: _herd, agent: agent, onOpenTerminal: () => widget.onOpenTerminal(context, agent.session, agent.pane)));
  }

  @override
  Widget build(BuildContext context) {
    // The tabs are there once there is a herd to show under them.
    return DefaultTabController(
      length: 2,
      child: ListenableBuilder(
        listenable: _herd,
        builder: (context, _) => _page(context, tabs: _herd.state?.available ?? false),
      ),
    );
  }

  Widget _page(BuildContext context, {required bool tabs}) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Agents on ${widget.title}'),
        bottom: tabs
            ? const TabBar(
                tabs: [
                  Tab(text: 'Inbox'),
                  Tab(text: 'Everything'),
                ],
              )
            : null,
        actions: [
          ListenableBuilder(
            listenable: _herd,
            builder: (context, _) {
              final sessions = [for (final session in _herd.state?.sessions ?? const <HerdSession>[]) session.name];
              if (sessions.isEmpty) return const SizedBox.shrink();
              const tip = "Open herdr's own screen";
              if (sessions.length == 1) {
                return IconButton(tooltip: tip, icon: const Icon(Icons.dashboard_outlined), onPressed: () => widget.onOpenHerdr(context, sessions.single));
              }
              return PopupMenuButton<String>(
                tooltip: tip,
                icon: const Icon(Icons.dashboard_outlined),
                onSelected: (name) => widget.onOpenHerdr(context, name),
                itemBuilder: (_) => [for (final name in sessions) PopupMenuItem(value: name, child: Text(name))],
              );
            },
          ),
        ],
      ),
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
            return TabBarView(
              children: [
                _inbox(context, state, problem),
                _Everything(
                  state: state,
                  onPane: (session, id) {
                    final pane = _pane(state, session, id);
                    if (pane != null) _openPane(session, pane);
                  },
                  onStart: (session) => widget.onOpenHerdr(context, session),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _inbox(BuildContext context, HerdState state, String? problem) {
    if (state.inbox.isEmpty) {
      final terminals = state.sessions.expand((s) => s.workspaces).expand((w) => w.tabs).fold<int>(0, (sum, tab) => sum + tab.panes.length);
      return EmptyState(
        icon: Icons.smart_toy_outlined,
        title: 'No agents are running',
        message: terminals == 0
            ? 'Coding agents started under herdr on this computer show up here, with what each is doing.'
            : 'herdr has ${terminals == 1 ? 'one terminal' : '$terminals terminals'} open, none with an agent in it. They are under Everything; an agent started in one shows up here.',
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
  }
}

/// All that herdr holds on the computer, in its own order: sessions,
/// their workspaces, each workspace's tabs, each tab's panes. An agent's
/// pane opens the agent; a plain terminal opens as a terminal.
class _Everything extends StatelessWidget {
  const _Everything({required this.state, required this.onPane, required this.onStart});

  final HerdState state;
  final void Function(String session, String pane) onPane;
  final void Function(String session) onStart;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    if (state.sessions.isEmpty) {
      return const EmptyState(
        icon: Icons.dashboard_outlined,
        title: 'herdr holds nothing yet',
        message: 'Open herdr on the computer, or from here once it has a session, and what runs in it shows up.',
      );
    }
    // One running session needs no heading of its own.
    final named = state.sessions.length > 1 || state.sessions.any((session) => !session.running);
    final rows = <Widget>[];
    for (final session in state.sessions) {
      if (named) {
        // A session's name stands above its workspaces' headings, so it is
        // set apart from them: larger, in the text's own colour.
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    session.running ? session.name : '${session.name} · not running',
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: session.running ? colors.text : colors.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!session.running) TextButton(onPressed: () => onStart(session.name), child: const Text('Start')),
              ],
            ),
          ),
        );
      }
      if (session.running && session.workspaces.isEmpty) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text('Nothing is open in it.', style: textTheme.bodyMedium?.copyWith(color: colors.muted)),
          ),
        );
      }
      for (final workspace in session.workspaces) {
        final label = workspace.label.isEmpty ? workspace.id : workspace.label;
        for (final tab in workspace.tabs) {
          // A workspace with one tab is headed by its own name alone.
          rows.add(SectionHeader(workspace.tabs.length == 1 ? label : '$label · ${tab.label.isEmpty ? tab.id : tab.label}'));
          for (final pane in tab.panes) {
            final agent = pane.agent;
            final look = agent == null ? null : agentLook(colors, pane.status);
            final title = pane.title.isNotEmpty ? pane.title : (agent ?? 'Terminal');
            rows.add(
              ListTile(
                key: ValueKey('everything/${session.name}/${pane.id}'),
                leading: Icon(look?.icon ?? Icons.terminal, color: look?.color ?? colors.muted),
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [if (agent != null) '$agent · ${look!.label}' else 'Terminal', if (pane.folderName.isNotEmpty) pane.folderName].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onPane(session.name, pane.id),
              ),
            );
          }
        }
      }
    }
    return ListView(children: rows);
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
/// wrote, the keys its questions take, and a line to write to it. Its own
/// terminal, at the phone's size, is one tap further.
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
  ///
  /// Enter comes second: on a phone six keys fit before the row scrolls,
  /// and it is pressed more than any but Escape.
  static const quickKeys = [
    ('esc', 'Esc', 'Press Escape'),
    ('enter', 'Enter', 'Press Enter'),
    ('1', '1', 'Press 1'),
    ('2', '2', 'Press 2'),
    ('3', '3', 'Press 3'),
    ('up', '↑', 'Press Up'),
    ('down', '↓', 'Press Down'),
    ('tab', 'Tab', 'Press Tab'),
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
              IconButton(tooltip: 'Open its terminal', icon: const Icon(Icons.terminal), onPressed: widget.onOpenTerminal),
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
