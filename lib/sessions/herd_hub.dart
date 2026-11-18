import 'package:flutter/widgets.dart';

import '../data/models.dart';
import '../src/rust/api/agents.dart';
import '../src/rust/api/herd_types.dart';
import 'herd_controller.dart';
import 'session_manager.dart';

/// One agent on one computer, for a list across computers.
typedef HubAgent = ({Host host, HerdAgent agent});

/// The herds of every connected computer, kept current while the app is
/// in front, so that Home can say at once which agents want the owner,
/// whichever computer they run on. A computer's Agents screen uses the
/// same herd, so nothing is listened to twice.
///
/// With the app out of sight nothing is listened to here: an agent that
/// starts to wait then reaches the owner as a notification, through the
/// link the computer keeps.
class HerdHub extends ChangeNotifier with WidgetsBindingObserver {
  HerdHub(this._sessions, {HerdLink Function(LiveSession session)? link, bool inFront = true})
    : _link = link ?? ((session) => SshHerdLink(() => session.ssh)),
      _front = inFront {
    _sessions.addListener(_sync);
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  /// The app's own, set at start. Null in tests that do not need it.
  static HerdHub? app;

  final SessionManager _sessions;
  final HerdLink Function(LiveSession session) _link;
  bool _front;

  /// By the computer's id: its connection and the herd on it.
  final Map<String, ({LiveSession session, HerdController herd})> _herds = {};

  /// The herd of a connected computer, if it is being kept.
  HerdController? herdOf(String hostId) => _herds[hostId]?.herd;

  /// The agents that want the owner, across computers: those that wait
  /// for an answer first, then those that finished. Within each, in the
  /// order of the computers and of their own inboxes.
  List<HubAgent> get wanting {
    final all = <HubAgent>[
      for (final kept in _herds.values)
        for (final agent in kept.herd.state?.inbox ?? const <HerdAgent>[])
          if (agent.status == AgentStatus.blocked || agent.status == AgentStatus.done) (host: kept.session.host, agent: agent),
    ];
    return [...all.where((one) => one.agent.status == AgentStatus.blocked), ...all.where((one) => one.agent.status == AgentStatus.done)];
  }

  /// Every agent on every connected computer, in the order of the
  /// computers and of their own inboxes. For searching.
  List<HubAgent> get all => [
    for (final kept in _herds.values)
      for (final agent in kept.herd.state?.inbox ?? const <HerdAgent>[]) (host: kept.session.host, agent: agent),
  ];

  /// How many agents wait for an answer on one computer.
  int waitingOn(String hostId) => _herds[hostId]?.herd.state?.waiting ?? 0;

  /// Keeps a herd for every connected computer, and none for the rest.
  void _sync() {
    final live = {
      for (final session in _sessions.sessions)
        if (session.host.computer && session.connected) session.host.id: session,
    };
    var changed = false;
    for (final id in _herds.keys.toList()) {
      // Gone, or connected anew: the old connection's herd is over.
      if (live[id] != _herds[id]!.session) {
        _herds.remove(id)!.herd
          ..removeListener(notifyListeners)
          ..dispose();
        changed = true;
      }
    }
    for (final entry in live.entries) {
      if (_herds.containsKey(entry.key)) continue;
      final herd = HerdController(_link(entry.value))..addListener(notifyListeners);
      _herds[entry.key] = (session: entry.value, herd: herd);
      if (_front) herd.start();
      changed = true;
    }
    if (changed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final front = state == AppLifecycleState.resumed;
    if (front == _front) return;
    _front = front;
    for (final kept in _herds.values) {
      if (front) {
        kept.herd.start();
      } else {
        kept.herd.pause();
      }
    }
  }

  @override
  void dispose() {
    _sessions.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    for (final kept in _herds.values) {
      kept.herd
        ..removeListener(notifyListeners)
        ..dispose();
    }
    _herds.clear();
    super.dispose();
  }
}
