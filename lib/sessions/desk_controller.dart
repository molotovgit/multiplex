import 'dart:async';

import 'package:flutter/foundation.dart';

import '../src/rust/api/desk_types.dart';
import '../src/rust/api/ssh.dart';
import 'error_text.dart';

/// How the panel talks to the computer. The real one runs the computer's
/// `multiplex desk` command over SSH (in the Rust core); tests pass a
/// stand-in.
abstract class DeskLink {
  Future<DeskState> state();

  /// Does [action]; the answer is the state after it.
  Future<DeskState> act(DeskAction action);

  Future<List<DeskBinding>> bindings();

  /// The state whenever it changes, and how to stop listening.
  Future<(Stream<DeskState>, void Function())> watch();

  /// Puts text on the computer's clipboard.
  Future<void> copy(String text);

  /// The text on the computer's clipboard, if it holds text.
  Future<String?> paste();
}

class SshDeskLink implements DeskLink {
  /// [ssh] is asked each time: a session gets a new connection after a
  /// reconnect.
  SshDeskLink(this.ssh);

  final SshSession Function() ssh;

  @override
  Future<DeskState> state() => ssh().deskState();

  @override
  Future<DeskState> act(DeskAction action) => ssh().deskDo(action: action);

  @override
  Future<List<DeskBinding>> bindings() => ssh().deskBindings();

  @override
  Future<(Stream<DeskState>, void Function())> watch() async {
    final watch = await ssh().deskWatch();
    return (watch.states(), watch.stop);
  }

  @override
  Future<void> copy(String text) => ssh().shareCopy(text: text);

  @override
  Future<String?> paste() => ssh().sharePaste();
}

/// The computer's desktop for the panel: what it shows now, the key
/// bindings, and requests to change something. It only passes things
/// along; the commands and their checks are in the Rust core.
class DeskController extends ChangeNotifier {
  DeskController(this._link);

  final DeskLink _link;

  DeskState? state;

  /// Null until loaded.
  List<DeskBinding>? bindings;

  /// Why the computer could not be reached or refused, as a sentence.
  String? problem;

  StreamSubscription<DeskState>? _states;
  void Function()? _stopWatch;
  bool _starting = false;
  bool _disposed = false;

  bool get loading => state == null && problem == null;

  /// Reads the state and keeps it current. Safe to call again after a
  /// failure.
  Future<void> start() async {
    if (_starting || _disposed) return;
    _starting = true;
    try {
      _set(await _link.state());
      await _states?.cancel();
      _stopWatch?.call();
      final (states, stop) = await _link.watch();
      if (_disposed) {
        stop();
        return;
      }
      _stopWatch = stop;
      _states = states.listen(_set);
      unawaited(loadBindings());
    } catch (e) {
      _fail(e);
    } finally {
      _starting = false;
    }
  }

  Future<void> loadBindings({bool again = false}) async {
    if (bindings != null && !again) return;
    try {
      final list = await _link.bindings();
      if (_disposed) return;
      bindings = list;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Asks the computer to do [action]. False when it could not.
  Future<bool> run(DeskAction action) async {
    try {
      _set(await _link.act(action));
      return true;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  /// Puts text on the computer's clipboard. False when it could not.
  Future<bool> copyToComputer(String text) async {
    try {
      await _link.copy(text);
      return true;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  /// The computer's clipboard text; null when it holds none or it could
  /// not be read (then [problem] says why).
  Future<String?> computerClipboard() async {
    try {
      return await _link.paste();
    } catch (e) {
      _fail(e);
      return null;
    }
  }

  void _set(DeskState next) {
    if (_disposed) return;
    state = next;
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
    _states?.cancel();
    _stopWatch?.call();
    super.dispose();
  }
}
