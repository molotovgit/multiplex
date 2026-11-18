import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/resume_place.dart';
import '../../sessions/error_text.dart';
import '../../sessions/herd_controller.dart';
import '../../sessions/herd_hub.dart';
import '../../sessions/session_manager.dart';
import '../../src/rust/api/agents.dart';
import '../../src/rust/api/herd.dart';
import '../../src/rust/api/herd_types.dart';
import '../../src/rust/api/terminal_types.dart';
import '../common/widgets.dart';
import '../files/transfer_queue.dart';
import '../files/transfer_tasks.dart';
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

/// The coding agents on a paired computer (in the terminals its session server keeps running), as an
/// inbox: those that need an answer first, then those that finished, the
/// busy, the idle. The computer tells of every change, so the list is
/// always the present. A tap opens an agent to read and answer it.
class AgentsScreen extends StatefulWidget {
  const AgentsScreen({
    super.key,
    required this.title,
    required this.link,
    required this.onOpenTerminal,
    this.onStartSession,
    this.attachPictures,
    this.openAt,
    this.onVisited,
    this.herd,
  });

  /// The computer's name.
  final String title;

  /// The computer's session server. Tests pass a stand-in.
  final HerdLink link;

  /// The computer's herd when it is already being kept (Home keeps one
  /// per connected computer): used as it is and left running. Without
  /// one the screen keeps its own over [link] while it is open.
  final HerdController? herd;

  /// Opens a terminal in front of one pane alone, drawn at the phone's
  /// size: an agent's, or a plain terminal's.
  final Future<void> Function(BuildContext context, String session, String pane) onOpenTerminal;

  /// Starts a session that is not running (none is, with one server).
  final Future<void> Function(BuildContext context, String session)? onStartSession;

  /// Lets the owner pick pictures on the phone, puts them on the
  /// computer, and says where they are there, for an agent to be shown
  /// them. None: the sheet has no button for it.
  final Future<List<String>> Function(BuildContext context)? attachPictures;

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
          herd: HerdHub.app?.herdOf(host.id),
          attachPictures: (context) => _pictures(context, session),
          onOpenTerminal: (context, name, pane) => _run(context, session, herdPaneCommand(session: name, pane: pane), aView: true),
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

  /// Pictures picked on the phone, put into the computer's folder for
  /// what phones send, each under a name of its own: where they are there.
  static Future<List<String>> _pictures(BuildContext context, LiveSession session) async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(dialogTitle: 'Pictures for the agent', type: FileType.image);
    } catch (error) {
      if (context.mounted) Toast.show(context, 'The pictures could not be picked.');
      return const [];
    }
    final files = [
      for (final file in picked)
        if (file.path != null) file,
    ];
    if (files.isEmpty) return const [];
    try {
      final remote = await session.ssh.openFiles();
      final inbox = await session.ssh.shareInbox();
      final queue = TransferQueue.of(session);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final jobs = <String, TransferJob>{};
      for (final (n, file) in files.indexed) {
        final name = pictureName(file.name, stamp, n);
        jobs['$inbox/$name'] = queue.add(
          UploadTask(
            files: remote,
            source: UploadSource(name: name, path: file.path!),
            remoteFolder: inbox,
          ),
        );
      }
      while (jobs.values.any((job) => job.isActive)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final arrived = [
        for (final entry in jobs.entries)
          if (entry.value.state == TransferState.done) entry.key,
      ];
      if (arrived.length < jobs.length && context.mounted) {
        Toast.show(context, arrived.isEmpty ? 'The pictures did not reach the computer.' : 'Not every picture reached the computer.');
      }
      return arrived;
    } catch (error) {
      if (context.mounted) Toast.show(context, errorSentence(error, fallback: 'The pictures did not reach the computer.'));
      return const [];
    }
  }

  /// A picture's name on the computer: told apart from every other by
  /// when it was sent, and with nothing in it that a path or a prompt
  /// would trip over.
  static String pictureName(String name, int stamp, int n) {
    final dot = name.lastIndexOf('.');
    final ending = dot > 0 ? name.substring(dot).toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]'), '') : '';
    final words = (dot > 0 ? name.substring(0, dot) : name).replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    final short = words.length > 40 ? words.substring(0, 40) : words;
    return 'from-phone-$stamp-${n + 1}${short.isEmpty ? '' : '-$short'}${ending.length > 1 && ending.length <= 6 ? ending : '.png'}';
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
  late final HerdController _herd = widget.herd ?? HerdController(widget.link);

  /// Still to go to: the place asked for, until the herd is known.
  late ({String session, String pane})? _goTo = widget.openAt;

  @override
  void initState() {
    super.initState();
    _herd.addListener(_arrive);
    unawaited(_lookOutside());
    if (widget.herd == null) {
      unawaited(_herd.start());
    } else {
      // Already known: go where asked without waiting for news.
      WidgetsBinding.instance.addPostFrameCallback((_) => _arrive());
    }
  }

  /// The agents that run in terminals the computer does not keep.
  List<HerdOutside> _outside = const [];

  Future<void> _lookOutside() async {
    final found = await _herd.outside();
    if (mounted) setState(() => _outside = found);
  }

  /// An agent outside cannot be sat in front of. Its latest conversation
  /// in that folder can be carried on in a terminal that can: asked
  /// about first, because two at once on one conversation get in each
  /// other's way.
  Future<void> _carryOn(String session, HerdOutside one) async {
    final agent = agentKindName(one.agent);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(one.canContinue ? 'Continue $agent here?' : '$agent runs outside'),
        content: Text(
          '$agent in ${one.folder} was started in a terminal Multiplex does not keep, so it cannot be opened from the phone.'
          '${one.canContinue ? '\n\nIts latest conversation in that folder can be continued in a new terminal that can. If the other one is still in use, close it first: two at once on one conversation get in each other\'s way.' : '\n\nStart it in a new terminal on the computer and it shows up here.'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(one.canContinue ? 'Not now' : 'Close')),
          if (one.canContinue) FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Continue here')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final made = await _herd.carryOn(session, one.folder, one.agent);
    if (!mounted) return;
    if (made == null) {
      Toast.show(context, _herd.problem ?? 'It could not be continued.');
      return;
    }
    widget.onVisited?.call(session, made.pane, one.folderName, one.agent);
    await widget.onOpenTerminal(context, session, made.pane);
    unawaited(_lookOutside());
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
    if (widget.herd == null) {
      _herd.dispose();
    } else {
      _herd.removeListener(_arrive);
    }
    super.dispose();
  }

  void _open(HerdAgent agent) {
    widget.onVisited?.call(agent.session, agent.pane, agent.title, agent.name);
    _show(agent);
  }

  /// A new tab in a workspace: a plain terminal, or an agent of a kind
  /// the computer has, started in it. Either way the phone then sits in
  /// front of it.
  Future<void> _new(String session, HerdWorkspace workspace) async {
    final name = workspace.label.isEmpty ? workspace.id : workspace.label;
    final choice = await NewInWorkspaceSheet.show(context, herd: _herd, workspace: name);
    if (choice == null || !mounted) return;
    final kind = choice.kind;
    final made = await _herd.newTab(session, workspace.id, label: kind ?? '');
    if (!mounted) return;
    if (made == null) {
      Toast.show(context, _herd.problem ?? 'The tab could not be made.');
      return;
    }
    if (kind != null) {
      Toast.show(context, 'Starting ${agentKindName(kind)}…');
      final started = await _herd.startAgent(session, made.pane, kind);
      if (!mounted) return;
      // The tab is there either way; without its agent it is a terminal
      // in which to see why.
      if (!started) Toast.show(context, _herd.problem ?? '${agentKindName(kind)} did not start.');
    }
    widget.onVisited?.call(session, made.pane, kind == null ? '' : agentKindName(kind), kind ?? '');
    await widget.onOpenTerminal(context, session, made.pane);
  }

  /// A folder of the computer opened as a new workspace, and then what
  /// to have in it: the terminal it comes with, or an agent started there.
  Future<void> _openFolder(String session) async {
    final place = await OpenFolderSheet.show(context, herd: _herd);
    if (place == null || !mounted) return;
    final made = await _herd.newWorkspace(session, place.path, label: place.name);
    if (!mounted) return;
    if (made == null) {
      Toast.show(context, _herd.problem ?? 'The folder could not be opened.');
      return;
    }
    final name = place.name.isEmpty ? place.shown : place.name;
    final choice = await NewInWorkspaceSheet.show(context, herd: _herd, workspace: name, fresh: true);
    // Left without choosing: the workspace is there, with its terminal.
    if (choice == null || !mounted) return;
    final kind = choice.kind;
    if (kind != null) {
      Toast.show(context, 'Starting ${agentKindName(kind)}…');
      final started = await _herd.startAgent(session, made.pane, kind);
      if (!mounted) return;
      if (!started) Toast.show(context, _herd.problem ?? '${agentKindName(kind)} did not start.');
    }
    widget.onVisited?.call(session, made.pane, kind == null ? name : agentKindName(kind), kind ?? '');
    await widget.onOpenTerminal(context, session, made.pane);
  }

  /// Closes a pane, asked about first: what runs in it ends with it.
  /// Another name for a workspace, asked for in a small dialog.
  Future<void> _rename(String session, HerdWorkspace workspace) async {
    final name = TextEditingController(text: workspace.label);
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename this workspace'),
        content: TextField(
          controller: name,
          autofocus: true,
          maxLength: 48,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'A name'),
          onSubmitted: (text) => Navigator.of(context).pop(text),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(name.text), child: const Text('Rename')),
        ],
      ),
    );
    final label = next?.trim() ?? '';
    if (label.isEmpty || label == workspace.label || !mounted) return;
    if (!await _herd.rename(session, workspace.id, label) && mounted) Toast.show(context, _herd.problem ?? 'It could not be renamed.');
  }

  Future<void> _close(String session, HerdPane pane) async {
    final what = pane.title.isNotEmpty ? pane.title : (pane.agent ?? 'this terminal');
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(pane.agent == null ? 'Close this terminal?' : 'Close this agent?'),
        content: Text('$what\n\nWhat runs in it on the computer ends with it.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Close')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    if (!await _herd.closePane(session, pane.id) && mounted) Toast.show(context, _herd.problem ?? 'It could not be closed.');
  }

  void _show(HerdAgent agent) {
    final attach = widget.attachPictures;
    unawaited(
      AgentSheet.show(
        context,
        herd: _herd,
        agent: agent,
        onOpenTerminal: () => widget.onOpenTerminal(context, agent.session, agent.pane),
        attachPictures: attach == null ? null : () => attach(context),
      ),
    );
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
                title: 'This computer does not keep sessions yet',
                message: 'Its Multiplex package is older than this app. Update it on the computer, and the terminals and agents it keeps running show up here.',
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
                  onStart: (session) => widget.onStartSession?.call(context, session),
                  onNew: _new,
                  onRename: _rename,
                  onClose: _close,
                  onOpenFolder: _openFolder,
                  outside: _outside,
                  onOutside: _carryOn,
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
            ? 'Coding agents started in a terminal on this computer show up here, with what each is doing.'
            : '${terminals == 1 ? 'One terminal is' : '$terminals terminals are'} open, none with an agent in it. ${terminals == 1 ? 'It is' : 'They are'} under Everything; an agent started in one shows up here.',
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
      rows.add(
        _AgentTile(
          key: ValueKey('${agent.session}/${agent.pane}'),
          agent: agent,
          showSession: several,
          onTap: () => _open(agent),
          onSwipe: () => widget.onOpenTerminal(context, agent.session, agent.pane),
        ),
      );
    }
    return ListView(children: rows);
  }
}

/// All that the computer keeps running, in its own order: sessions,
/// their workspaces, each workspace's tabs, each tab's panes. An agent's
/// pane opens the agent; a plain terminal opens as a terminal.
class _Everything extends StatelessWidget {
  const _Everything({
    required this.state,
    required this.onPane,
    required this.onStart,
    required this.onNew,
    required this.onRename,
    required this.onClose,
    required this.onOpenFolder,
    this.outside = const [],
    this.onOutside,
  });

  final HerdState state;
  final void Function(String session, String pane) onPane;
  final void Function(String session) onStart;

  /// Something new in a workspace: a terminal, or an agent.
  final void Function(String session, HerdWorkspace workspace) onNew;
  final void Function(String session, HerdWorkspace workspace) onRename;

  /// Close a pane (asked about by the caller).
  final void Function(String session, HerdPane pane) onClose;

  /// Open a folder of the computer as a new workspace of a session.
  final void Function(String session) onOpenFolder;

  /// Agents that run in terminals the computer does not keep, and what
  /// to do when one is tapped.
  final List<HerdOutside> outside;
  final void Function(String session, HerdOutside one)? onOutside;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    if (state.sessions.isEmpty) {
      return const EmptyState(icon: Icons.dashboard_outlined, title: 'Nothing is open yet', message: 'Open a terminal on the computer and it shows up here.');
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
          rows.add(
            SectionHeader(
              workspace.tabs.length == 1 ? label : '$label · ${tab.label.isEmpty ? tab.id : tab.label}',
              // Once per workspace, on its first heading.
              trailing: tab == workspace.tabs.first
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Rename $label',
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onRename(session.name, workspace),
                        ),
                        IconButton(
                          tooltip: 'New in $label',
                          icon: const Icon(Icons.add),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onNew(session.name, workspace),
                        ),
                      ],
                    )
                  : null,
            ),
          );
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
                onLongPress: () => onClose(session.name, pane),
              ),
            );
          }
        }
      }
      // Each running session ends with the way to add to it.
      if (session.running) {
        rows.add(
          ListTile(
            key: ValueKey('open-folder/${session.name}'),
            leading: Icon(Icons.create_new_folder_outlined, color: colors.accent),
            title: const Text('Open a folder'),
            subtitle: Text(named ? 'As a new workspace in ${session.name}' : 'As a new workspace'),
            onTap: () => onOpenFolder(session.name),
          ),
        );
      }
    }
    final running = state.sessions.where((session) => session.running).firstOrNull;
    if (outside.isNotEmpty && running != null) {
      rows.add(const SectionHeader('Running outside Multiplex'));
      for (final one in outside) {
        rows.add(
          ListTile(
            key: ValueKey('outside/${one.agent}/${one.folder}'),
            leading: Icon(Icons.link_off, color: colors.muted),
            title: Text('${agentKindName(one.agent)} in ${one.folderName.isEmpty ? one.folder : one.folderName}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              one.canContinue ? 'Not reachable from here. Tap to continue it in a terminal that is.' : 'Not reachable from here.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: onOutside == null ? null : () => onOutside!(running.name, one),
          ),
        );
      }
    }
    return ListView(children: rows);
  }
}

class _AgentTile extends StatelessWidget {
  const _AgentTile({super.key, required this.agent, required this.showSession, required this.onTap, this.onSwipe});

  final HerdAgent agent;
  final bool showSession;
  final VoidCallback onTap;

  /// A swipe across it goes straight to its terminal, past its sheet.
  final VoidCallback? onSwipe;

  @override
  Widget build(BuildContext context) {
    final look = agentLook(AppColorsTheme.of(context), agent.status);
    final where = [
      agent.name,
      if (agent.workspace.isNotEmpty) agent.workspace,
      if (agent.folder.isNotEmpty && agent.folder != agent.workspace) agent.folder,
      if (showSession) agent.session,
    ].join(' · ');
    final tile = ListTile(
      leading: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Icon(look.icon, key: ValueKey(agent.status), color: look.color),
      ),
      title: Text(agent.title.isEmpty ? agent.name : agent.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(where, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
    final swipe = onSwipe;
    if (swipe == null) return tile;
    final colors = AppColorsTheme.of(context);
    // It slides aside to show where the swipe leads, and comes back: the
    // agent stays in the list.
    return Dismissible(
      key: ValueKey('swipe/${agent.session}/${agent.pane}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        swipe();
        return false;
      },
      background: Container(
        color: colors.raised,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Its terminal', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.muted)),
            const SizedBox(width: 8),
            Icon(Icons.terminal, color: colors.muted),
          ],
        ),
      ),
      child: tile,
    );
  }
}

/// A kind of agent as a name to show: its program's name, capitalised
/// ("claude" is Claude).
String agentKindName(String kind) => kind.isEmpty ? kind : kind[0].toUpperCase() + kind.substring(1);

/// What to make in a workspace: a terminal ([kind] null) or an agent.
class NewChoice {
  const NewChoice([this.kind]);

  final String? kind;
}

/// Asks what to make in a workspace: a plain terminal, or one of the
/// agents installed on the computer. Each opens in a new tab.
class NewInWorkspaceSheet extends StatefulWidget {
  const NewInWorkspaceSheet({super.key, required this.herd, required this.workspace, this.fresh = false});

  final HerdController herd;

  /// The workspace's name, for the heading.
  final String workspace;

  /// The workspace was only just made: it has its terminal already, and
  /// what is chosen goes into that one instead of a new tab.
  final bool fresh;

  static Future<NewChoice?> show(BuildContext context, {required HerdController herd, required String workspace, bool fresh = false}) {
    return showModalBottomSheet<NewChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => NewInWorkspaceSheet(herd: herd, workspace: workspace, fresh: fresh),
    );
  }

  @override
  State<NewInWorkspaceSheet> createState() => _NewInWorkspaceSheetState();
}

class _NewInWorkspaceSheetState extends State<NewInWorkspaceSheet> {
  List<HerdKind>? _kinds;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    widget.herd.kinds().then((kinds) {
      if (mounted) {
        setState(() {
          _kinds = kinds;
          _asked = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final kinds = _kinds;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              widget.fresh ? '${widget.workspace} is open. What in it?' : 'New in ${widget.workspace}',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.terminal),
            title: const Text('Terminal'),
            subtitle: Text(widget.fresh ? 'The shell it came with' : 'A new tab with a shell in it'),
            onTap: () => Navigator.of(context).pop(const NewChoice()),
          ),
          if (!_asked)
            const Padding(padding: EdgeInsets.all(16), child: BusyNote('Asking which agents this computer has…'))
          else if (kinds == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: NoticeBox(tone: NoticeTone.error, text: widget.herd.problem ?? 'The computer did not say which agents it has.'),
            )
          else if (kinds.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('None of the agents Multiplex knows is installed on this computer.', style: textTheme.bodyMedium?.copyWith(color: colors.muted)),
            )
          else
            for (final kind in kinds)
              ListTile(
                leading: Icon(Icons.smart_toy_outlined, color: kind.installed ? null : colors.muted),
                title: Text(agentKindName(kind.name)),
                // One that is not installed downloads itself when it is
                // first started: said before, not found out after.
                subtitle: Text(
                  kind.installed ? (widget.fresh ? 'Starts in its terminal' : 'Starts in a new tab') : 'Not installed yet: the first start downloads it',
                ),
                onTap: () => Navigator.of(context).pop(NewChoice(kind.name)),
              ),
        ],
      ),
    );
  }
}

/// Picks a folder of the computer to open as a workspace. It starts with
/// the folders worth offering (those the owner goes to, those open in
/// already, projects in the home folder); any folder can be looked into,
/// so every folder can be reached. A tap on a folder picks it.
class OpenFolderSheet extends StatefulWidget {
  const OpenFolderSheet({super.key, required this.herd});

  final HerdController herd;

  static Future<HerdPlace?> show(BuildContext context, {required HerdController herd}) {
    return showModalBottomSheet<HerdPlace>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.85, child: OpenFolderSheet(herd: herd)),
    );
  }

  @override
  State<OpenFolderSheet> createState() => _OpenFolderSheetState();
}

class _OpenFolderSheetState extends State<OpenFolderSheet> {
  /// The folders looked into, outermost first; empty at the offers.
  final List<HerdPlace> _inside = [];
  List<HerdPlace>? _places;
  bool _asking = true;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mine = ++_asked;
    setState(() => _asking = true);
    final places = await widget.herd.places(inside: _inside.isEmpty ? null : _inside.last.path);
    // An answer to an earlier question is not this folder's.
    if (!mounted || mine != _asked) return;
    setState(() {
      _places = places;
      _asking = false;
    });
  }

  void _lookInto(HerdPlace place) {
    _inside.add(place);
    _load();
  }

  void _back() {
    _inside.removeLast();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final places = _places;
    final here = _inside.isEmpty ? null : _inside.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 16, 4),
          child: Row(
            children: [
              if (here == null) const SizedBox(width: 12) else IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: _back),
              Expanded(
                // Inside a folder: its name, which is what matters, and
                // under it the whole path, which may be too long to show
                // (seen on the phone: only its beginning fitted).
                child: here == null
                    ? Text('Open a folder', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            here.name.isEmpty ? here.shown : here.name,
                            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (here.name.isNotEmpty)
                            Text(
                              here.shown,
                              style: textTheme.bodySmall?.copyWith(color: colors.muted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
              ),
              if (here != null) FilledButton.tonal(onPressed: () => Navigator.of(context).pop(here), child: const Text('Open this one')),
            ],
          ),
        ),
        Expanded(
          child: _asking
              ? const Center(child: BusyNote('Asking the computer…'))
              : places == null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: NoticeBox(tone: NoticeTone.error, text: widget.herd.problem ?? 'The computer did not answer.'),
                )
              : places.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(here == null ? 'No folder to offer yet.' : 'No folders in here.', style: textTheme.bodyMedium?.copyWith(color: colors.muted)),
                  ),
                )
              : ListView(
                  children: [
                    for (final place in places)
                      ListTile(
                        key: ValueKey('folder/${place.path}'),
                        leading: Icon(place.project ? Icons.source_outlined : Icons.folder_outlined, color: place.project ? colors.accent : null),
                        title: Text(place.name.isEmpty ? place.shown : place.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        // Among the offers a folder says where it is; inside
                        // a folder that is the heading's to say.
                        subtitle: here == null ? Text(place.shown, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                        trailing: IconButton(tooltip: 'Look inside ${place.name}', icon: const Icon(Icons.chevron_right), onPressed: () => _lookInto(place)),
                        onTap: () => Navigator.of(context).pop(place),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// One agent, to read and to answer without a terminal: what it last
/// wrote, the keys its questions take, and a line to write to it. Its own
/// terminal, at the phone's size, is one tap further.
class AgentSheet extends StatefulWidget {
  const AgentSheet({super.key, required this.herd, required this.session, required this.pane, required this.onOpenTerminal, this.attachPictures});

  final HerdController herd;
  final String session;
  final String pane;
  final VoidCallback onOpenTerminal;

  /// Pictures picked on the phone and put on the computer: where they
  /// are there.
  final Future<List<String>> Function()? attachPictures;

  static Future<void> show(
    BuildContext context, {
    required HerdController herd,
    required HerdAgent agent,
    required VoidCallback onOpenTerminal,
    Future<List<String>> Function()? attachPictures,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: AgentSheet(herd: herd, session: agent.session, pane: agent.pane, onOpenTerminal: onOpenTerminal, attachPictures: attachPictures),
      ),
    );
  }

  /// The keys an agent's questions take, by their names, with what each
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

  /// What it asks by choice, as last read off its screen.
  HerdAsked? _asked;

  /// Why the last answer was not sent. It stays in sight until the next
  /// thing is tried: reading the screen again must not wipe it away.
  String? _refused;
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
    final read = await widget.herd.read(widget.session, widget.pane);
    _reading = false;
    if (!mounted || read == null) return;
    setState(() {
      _output = read.text.trimRight();
      _asked = read.asked;
    });
  }

  /// Takes one of the agent's choices. The computer sends it on only if
  /// the agent still asks that question; if not, it says so, and what the
  /// agent shows now is read again.
  Future<void> _choose(HerdAsked asked, HerdChoice choice) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _refused = null;
    });
    final sent = await widget.herd.answer(widget.session, widget.pane, asked.mark, choice.key);
    if (!mounted) return;
    setState(() {
      _sending = false;
      // Either way these buttons are over: answered, or no longer asked.
      _asked = null;
      if (!sent) _refused = widget.herd.problem;
    });
    await Future<void>.delayed(_afterAsking);
    if (mounted) unawaited(_read());
  }

  bool _attaching = false;

  /// Pictures for the agent: picked on the phone, put on the computer,
  /// and named in the answer by where they are there (agents read a
  /// picture from its path). The owner adds their words and sends.
  Future<void> _attach() async {
    final attach = widget.attachPictures;
    if (attach == null || _attaching) return;
    setState(() => _attaching = true);
    final paths = await attach();
    if (!mounted) return;
    setState(() => _attaching = false);
    if (paths.isEmpty) return;
    final before = _answer.text;
    final joined = paths.map((path) => path.contains(' ') ? '"$path"' : path).join(' ');
    _answer.text = before.trim().isEmpty ? '$joined ' : '${before.trimRight()} $joined ';
    _answer.selection = TextSelection.collapsed(offset: _answer.text.length);
  }

  Future<void> _press(String key) async {
    if (_refused != null) setState(() => _refused = null);
    if (await widget.herd.press(widget.session, widget.pane, [key])) {
      await Future<void>.delayed(_afterAsking);
      if (mounted) unawaited(_read());
    }
  }

  Future<void> _send() async {
    final text = _answer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _refused = null;
    });
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
    final problem = widget.herd.problem ?? _refused;
    final output = _output;
    final asked = agent == null ? null : _asked;
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
          // What it offers, in its own words: one tap answers it.
          if (asked != null) ...[
            for (final choice in asked.choices)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: FilledButton.tonal(
                  key: ValueKey('choice-${choice.key}'),
                  onPressed: _sending ? null : () => _choose(asked, choice),
                  style: FilledButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: Text(choice.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ),
            const SizedBox(height: 2),
          ],
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
              if (widget.attachPictures != null)
                IconButton(
                  tooltip: 'Show it pictures',
                  onPressed: agent == null || _attaching ? null : _attach,
                  icon: _attaching ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.image_outlined),
                ),
              Expanded(
                child: TextField(
                  controller: _answer,
                  enabled: agent != null,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  // It can be told more at any time, also in the middle of its work.
                  decoration: InputDecoration(hintText: agent?.status == AgentStatus.working ? 'It is working. Tell it more…' : 'Answer it, or ask for more'),
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
