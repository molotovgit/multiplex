import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app/theme.dart';
import '../data/models.dart';
import '../data/vault_store.dart';
import '../src/rust/api/ssh.dart';
import '../src/rust/api/terminal_types.dart';
import '../src/rust/api/tunnel.dart';
import 'connect_flow.dart';
import 'terminal_controller.dart';

/// A port forward that is running, with the rule it came from.
class RunningTunnel {
  RunningTunnel(this.rule, this.tunnel);

  final ForwardRule rule;
  final ActiveTunnel tunnel;
}

/// One open connection and everything running on it.
class LiveSession {
  LiveSession({required this.id, required this.host, required this.ssh}) : startedAt = DateTime.now();

  final String id;
  final Host host;
  final SshSession ssh;
  final DateTime startedAt;
  final List<TerminalController> terminals = [];
  final List<RunningTunnel> tunnels = [];

  bool get connected => ssh.isConnected();

  RunningTunnel? tunnelFor(String ruleId) => tunnels.where((t) => t.rule.id == ruleId).firstOrNull;
}

/// Keeps track of all open connections, terminals and tunnels, so they
/// survive moving between screens.
class SessionManager extends ChangeNotifier {
  SessionManager(this._store) {
    // Connections can drop at any time; check regularly so the UI shows it
    // and tunnel counters stay fresh.
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) => notifyListeners());
  }

  final VaultStore _store;
  final List<LiveSession> _sessions = [];
  late final Timer _ticker;

  List<LiveSession> get sessions => List.unmodifiable(_sessions);

  Iterable<TerminalController> get terminals => _sessions.expand((s) => s.terminals);

  int get activeCount => _sessions.length;

  LiveSession? sessionFor(String hostId) => _sessions.where((s) => s.host.id == hostId && s.connected).firstOrNull;

  LiveSession? byId(String id) => _sessions.where((s) => s.id == id).firstOrNull;

  /// Reuses an open connection to the host, or opens a new one.
  Future<LiveSession> connect(Host host, ConnectPrompter prompter) async {
    final existing = sessionFor(host.id);
    if (existing != null) return existing;
    final ssh = await ConnectFlow(_store, prompter).connect(host);
    final session = LiveSession(id: VaultStore.newId(), host: host, ssh: ssh);
    _sessions.add(session);
    _store.markConnected(host.id);
    notifyListeners();
    return session;
  }

  /// Opens a new terminal on a session, sized roughly for a phone; the
  /// terminal view sends the real size as soon as it is laid out.
  Future<TerminalController> openTerminal(LiveSession session) async {
    final settings = _store.settings;
    final theme = TerminalThemes.byId(settings.terminalThemeId);
    final shell = await session.ssh.openShell(
      options: ShellOptions(
        cols: 80,
        rows: 24,
        term: 'xterm-256color',
        scrollbackLines: settings.scrollbackLines,
        env: const [EnvVar(name: 'LANG', value: 'en_US.UTF-8')],
        startupCommand: session.host.startupCommand,
        palette: theme.palette(boldIsBright: settings.boldIsBright),
      ),
    );
    final number = session.terminals.length + 1;
    final title = number == 1 ? session.host.title : '${session.host.title} ($number)';
    final controller = TerminalController(shell: shell, title: title, sessionId: session.id);
    session.terminals.add(controller);
    notifyListeners();
    return controller;
  }

  void closeTerminal(TerminalController terminal) {
    for (final session in _sessions) {
      if (session.terminals.remove(terminal)) {
        terminal.dispose();
        break;
      }
    }
    notifyListeners();
  }

  Future<RunningTunnel> startTunnel(LiveSession session, ForwardRule rule) async {
    final running = session.tunnelFor(rule.id);
    if (running != null && running.tunnel.isRunning()) return running;
    final tunnel = await session.ssh.startTunnel(spec: rule.spec);
    final started = RunningTunnel(rule, tunnel);
    session.tunnels
      ..removeWhere((t) => t.rule.id == rule.id)
      ..add(started);
    notifyListeners();
    return started;
  }

  Future<void> stopTunnel(LiveSession session, RunningTunnel tunnel) async {
    await tunnel.tunnel.stop();
    session.tunnels.remove(tunnel);
    notifyListeners();
  }

  /// Applies a new terminal theme to every open terminal.
  void applyTerminalTheme() {
    final settings = _store.settings;
    final palette = TerminalThemes.byId(settings.terminalThemeId).palette(boldIsBright: settings.boldIsBright);
    for (final terminal in terminals) {
      terminal.setPalette(palette);
    }
  }

  /// Closes the connection with all its terminals and tunnels.
  Future<void> disconnect(LiveSession session) async {
    _sessions.remove(session);
    for (final terminal in session.terminals) {
      terminal.dispose();
    }
    session.terminals.clear();
    for (final tunnel in session.tunnels) {
      await tunnel.tunnel.stop();
    }
    session.tunnels.clear();
    notifyListeners();
    await session.ssh.disconnect();
  }

  Future<void> disconnectAll() async {
    for (final session in List.of(_sessions)) {
      await disconnect(session);
    }
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }
}
