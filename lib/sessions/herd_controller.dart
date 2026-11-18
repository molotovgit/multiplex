import 'dart:async';

import 'package:flutter/foundation.dart';

import '../src/rust/api/herd_types.dart';
import '../src/rust/api/ssh.dart';
import 'error_text.dart';

/// How the Agents screen talks to the computer's herdr. The real one runs
/// the computer's `multiplex herd` command over SSH (in the Rust core);
/// tests pass a stand-in.
abstract class HerdLink {
  Future<HerdState> state();

  /// The herd whenever it changes, and how to stop listening.
  Future<(Stream<HerdState>, void Function())> watch();

  /// A pane's recent output.
  Future<String> read(String session, String pane, int lines);

  /// Text and Enter for a pane's agent, as one piece.
  Future<void> prompt(String session, String pane, String text);

  /// Keys by herdr's names for them: "esc", "enter", "2".
  Future<void> keys(String session, String pane, List<String> keys);
}

class SshHerdLink implements HerdLink {
  /// [ssh] is asked each time: a session gets a new connection after a
  /// reconnect.
  SshHerdLink(this.ssh);

  final SshSession Function() ssh;

  @override
  Future<HerdState> state() => ssh().herdState();

  @override
  Future<(Stream<HerdState>, void Function())> watch() async {
    final watch = await ssh().herdWatch();
    return (watch.states(), watch.stop);
  }

  @override
  Future<String> read(String session, String pane, int lines) => ssh().herdRead(session: session, pane: pane, lines: lines);

  @override
  Future<void> prompt(String session, String pane, String text) => ssh().herdPrompt(session: session, pane: pane, text: text);

  @override
  Future<void> keys(String session, String pane, List<String> keys) => ssh().herdKeys(session: session, pane: pane, keys: keys);
}

/// The herd of one computer for the screens: what it is now, kept current
/// by the computer telling of every change, and requests passed along.
/// Nothing is decided here; the order of the inbox and every check are in
/// the Rust core.
class HerdController extends ChangeNotifier {
  HerdController(this._link, {this.retryAfter = const Duration(seconds: 2)});

  final HerdLink _link;

  /// How long after the computer stopped telling it is asked again.
  final Duration retryAfter;

  HerdState? state;

  /// Why the computer could not be reached or refused, as a sentence.
  String? problem;

  StreamSubscription<HerdState>? _states;
  void Function()? _stopWatch;
  Timer? _retry;
  bool _starting = false;
  bool _disposed = false;

  bool get loading => state == null && problem == null;

  /// Reads the herd and keeps it current. Safe to call again after a
  /// failure.
  Future<void> start() async {
    if (_starting || _disposed) return;
    _starting = true;
    _retry?.cancel();
    try {
      _set(await _link.state());
      // Not waited for: the old stream lets go when it has ended.
      unawaited(_states?.cancel());
      _stopWatch?.call();
      final (states, stop) = await _link.watch();
      if (_disposed) {
        stop();
        return;
      }
      _stopWatch = stop;
      // The computer stopped telling (the connection went, or its command
      // ended): ask again shortly, which also says why if it cannot.
      _states = states.listen(_set, onDone: _again, onError: (Object _) => _again());
    } catch (e) {
      _fail(e);
    } finally {
      _starting = false;
    }
  }

  void _again() {
    if (_disposed) return;
    _retry?.cancel();
    _retry = Timer(retryAfter, start);
  }

  /// The agent in this pane now, if it is still there.
  HerdAgent? agent(String session, String pane) {
    for (final agent in state?.inbox ?? const <HerdAgent>[]) {
      if (agent.session == session && agent.pane == pane) return agent;
    }
    return null;
  }

  /// A pane's recent output; null when it could not be read (then
  /// [problem] says why).
  Future<String?> read(String session, String pane, {int lines = 80}) async {
    try {
      final text = await _link.read(session, pane, lines);
      _clear();
      return text;
    } catch (e) {
      _fail(e);
      return null;
    }
  }

  /// Gives the pane's agent [text] and Enter. False when it could not.
  Future<bool> prompt(String session, String pane, String text) => _ask(() => _link.prompt(session, pane, text));

  /// Presses [keys] in the pane. False when it could not.
  Future<bool> press(String session, String pane, List<String> keys) => _ask(() => _link.keys(session, pane, keys));

  Future<bool> _ask(Future<void> Function() request) async {
    try {
      await request();
      _clear();
      return true;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  void _set(HerdState next) {
    if (_disposed) return;
    // In a debug build each arrival is logged, so the time from a change on
    // the computer to its arrival here can be read off the phone's log.
    assert(() {
      debugPrint('herd: ${next.inbox.length} agents, ${next.waiting} waiting, first ${next.inbox.isEmpty ? '-' : next.inbox.first.status.name}');
      return true;
    }());
    state = next;
    problem = null;
    notifyListeners();
  }

  void _clear() {
    if (_disposed || problem == null) return;
    problem = null;
    notifyListeners();
  }

  void _fail(Object error) {
    if (_disposed) return;
    problem = errorSentence(error, fallback: 'The computer did not answer.');
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    unawaited(_states?.cancel());
    _stopWatch?.call();
    super.dispose();
  }
}
