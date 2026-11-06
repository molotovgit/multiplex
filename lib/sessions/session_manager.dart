import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/vault_store.dart';
import '../src/rust/api/ssh.dart';
import '../src/rust/api/terminal_types.dart';
import '../src/rust/api/tunnel.dart';
import 'broadcast.dart';
import 'connect_flow.dart';
import 'done_notifier.dart';
import 'reconnector.dart';
import 'session_restore.dart';
import 'shell_launch.dart';
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

  /// The connection. Replaced by a new one after a reconnect.
  SshSession ssh;
  final DateTime startedAt;
  final List<TerminalController> terminals = [];
  final List<RunningTunnel> tunnels = [];

  /// Set while the dropped connection is being restored.
  Reconnector? reconnector;
  int _nextTerminal = 1;

  bool get connected => !reconnecting && ssh.isConnected();

  bool get reconnecting => reconnector != null && !reconnector!.finished;

  /// A number for a new terminal, never reused on this connection.
  int takeTerminalNumber() => _nextTerminal++;

  RunningTunnel? tunnelFor(String ruleId) => tunnels.where((t) => t.rule.id == ruleId).firstOrNull;
}

/// Keeps track of all open connections, terminals and tunnels, so they
/// survive moving between screens.
class SessionManager extends ChangeNotifier {
  SessionManager(this._store, {DoneNotifier? done}) : _done = done ?? DoneNotifier(_store) {
    // Connections can drop at any time; check regularly so the UI shows it
    // and tunnel counters stay fresh.
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) => notifyListeners());
    broadcast.addListener(notifyListeners);
  }

  final VaultStore _store;
  final DoneNotifier _done;
  final List<LiveSession> _sessions = [];

  /// Terminals that all get what is typed in one of them.
  final broadcast = Broadcast();
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
    final number = session.takeTerminalNumber();
    final shell = await session.ssh.openShell(options: shellOptions(session.host, number));
    final title = number == 1 ? session.host.title : '${session.host.title} ($number)';
    final hostId = session.host.id;
    // Only saved hosts keep a history; a quick connection leaves none.
    final saved = _store.host(hostId) != null;
    late final TerminalController controller;
    controller = TerminalController(
      shell: shell,
      title: title,
      sessionId: session.id,
      number: number,
      hostId: saved ? hostId : null,
      onCommand: saved ? (command) => _store.recordCommand(hostId, command) : null,
      onConnectionLost: () => connectionLost(session),
      onInput: broadcast.forward,
      onCommandDone: (done) => _done.finished(session.host.title, done, terminalOnScreen: controller.onScreen),
    );
    session.terminals.add(controller);
    notifyListeners();
    return controller;
  }

  /// How a terminal starts: size (until the view sends its own), theme,
  /// and the shell, tmux or startup command of the host.
  ShellOptions shellOptions(Host host, int number) {
    final settings = _store.settings;
    return ShellOptions(
      cols: 80,
      rows: 24,
      term: 'xterm-256color',
      scrollbackLines: settings.scrollbackLines,
      env: const [EnvVar(name: 'LANG', value: 'en_US.UTF-8')],
      startupCommand: ShellLaunch.startupCommand(host),
      command: ShellLaunch.command(host, number),
      palette: _store.activeTheme.palette(boldIsBright: settings.boldIsBright),
    );
  }

  // Reconnecting.

  /// The connection of [session] dropped: keep its terminals on screen
  /// and log in again in the background, with what is saved only.
  void connectionLost(LiveSession session) {
    if (!_sessions.contains(session) || session.reconnecting) return;
    final restore = SessionRestore(store: _store, session: session, shellOptions: shellOptions, stillOpen: () => _sessions.contains(session));
    final reconnector = Reconnector(
      tryOnce: restore.tryOnce,
      onStatus: (status) {
        for (final terminal in session.terminals) {
          terminal.showReconnecting(SessionRestore.note(status));
        }
        notifyListeners();
      },
      onDone: (back) {
        if (!back) {
          for (final terminal in session.terminals) {
            terminal.connectionGone(restore.failure ?? 'The connection was lost and could not be restored.');
          }
        }
        notifyListeners();
      },
    );
    session.reconnector = reconnector;
    for (final terminal in session.terminals) {
      terminal.showReconnecting('Reconnecting…');
    }
    reconnector.start();
    notifyListeners();
  }

  /// The user stopped the reconnect: the terminals end and can be
  /// reconnected by hand.
  void stopReconnecting(LiveSession session) {
    final reconnector = session.reconnector;
    if (reconnector == null || reconnector.finished) return;
    reconnector.cancel();
    for (final terminal in session.terminals) {
      terminal.connectionGone('Reconnecting was stopped.');
    }
    notifyListeners();
  }

  /// The phone has a network again: reconnect at once instead of waiting,
  /// and check that the other connections still get through.
  Future<void> networkBack() async {
    for (final session in List.of(_sessions)) {
      if (session.reconnecting) session.reconnector!.retryNow();
    }
    await checkConnections();
  }

  /// Asks each open connection for an answer; one that gives none (the
  /// network changed under it) is dropped and reconnected.
  Future<void> checkConnections() async {
    for (final session in List.of(_sessions)) {
      if (session.reconnecting || !session.ssh.isConnected()) continue;
      if (await session.ssh.checkAlive(timeoutSecs: 5)) continue;
      if (!_sessions.contains(session) || session.reconnecting) continue;
      unawaited(session.ssh.disconnect());
      connectionLost(session);
    }
  }

  void closeTerminal(TerminalController terminal) {
    for (final session in _sessions) {
      if (session.terminals.remove(terminal)) {
        broadcast.remove(terminal);
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
    final palette = _store.activeTheme.palette(boldIsBright: settings.boldIsBright);
    for (final terminal in terminals) {
      terminal.setPalette(palette);
    }
  }

  /// Closes the connection with all its terminals and tunnels.
  Future<void> disconnect(LiveSession session) async {
    _sessions.remove(session);
    session.reconnector?.cancel();
    for (final terminal in session.terminals) {
      broadcast.remove(terminal);
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
    broadcast.dispose();
    super.dispose();
  }
}
