import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import 'error_text.dart';

/// The computer's sound on its way here, as the speaker takes it. The
/// real one is a stream over SSH (in the Rust core, which cuts it into
/// frames); tests pass a stand-in.
abstract class SpeakerLine {
  /// AAC frames, one at a time.
  Stream<Uint8List> get sound;

  /// Why it ended (empty when it was simply closed).
  Stream<String> get ended;
  void close();
}

/// What only Android can do: decode the frames and play them.
class SpeakerOutput {
  const SpeakerOutput({this.channel = const MethodChannel('multiplex/speaker')});

  final MethodChannel channel;

  /// True when the phone can play.
  Future<bool> start() async {
    try {
      return await channel.invokeMethod<bool>('start') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  void feed(Uint8List frame) {
    unawaited(channel.invokeMethod<void>('feed', frame).catchError((Object _) {}));
  }

  Future<void> stop() async {
    try {
      await channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Not on Android.
    } on PlatformException {
      // Already stopped.
    }
  }

  /// How it is going, as one line for the log.
  Future<String?> stats() async {
    try {
      final now = await channel.invokeMapMethod<String, Object?>('stats');
      return now == null ? null : 'played=${now['played']} dropped=${now['dropped']} waiting=${now['waiting']} level=${now['level']}';
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

/// Plays a paired computer's sound on this phone. One computer at a time;
/// it carries on while Multiplex is in the background.
class PhoneSpeaker extends ChangeNotifier {
  PhoneSpeaker({SpeakerOutput output = const SpeakerOutput()})
    // ignore: prefer_initializing_formals
    : _output = output;

  /// The app's own.
  static final PhoneSpeaker app = PhoneSpeaker();

  final SpeakerOutput _output;
  SpeakerLine? _line;
  StreamSubscription<Uint8List>? _sound;
  StreamSubscription<String>? _ended;
  Timer? _log;
  bool _starting = false;

  /// The computer whose sound is playing, while it is.
  Host? playing;

  /// Why the last one could not start or stopped, as a sentence.
  String? problem;

  /// All of the computer's sound (it becomes the computer's output while
  /// this plays), not only what is pointed at the phone there.
  bool everything = true;

  bool get starting => _starting;

  void setEverything(bool value) {
    if (playing != null || _starting || everything == value) return;
    everything = value;
    notifyListeners();
  }

  /// Opens the line to [computer] with [open] and plays what comes. False
  /// when it could not start ([problem] then says why).
  Future<bool> start(Host computer, Future<SpeakerLine> Function(bool everything) open) async {
    if (_starting || playing != null) return false;
    _starting = true;
    problem = null;
    notifyListeners();
    try {
      if (!await _output.start()) {
        problem = 'This phone could not start playing.';
        return false;
      }
      final line = await open(everything);
      _line = line;
      _sound = line.sound.listen(_output.feed);
      _ended = line.ended.listen((reason) => unawaited(stop(because: reason.isEmpty ? null : reason)));
      if (kDebugMode) {
        _log = Timer.periodic(const Duration(seconds: 2), (_) async {
          final now = await _output.stats();
          if (now != null) debugPrint('mpxspk $now');
        });
      }
      playing = computer;
      return true;
    } catch (e) {
      problem = errorSentence(e, fallback: 'The computer could not send its sound.');
      await _output.stop();
      return false;
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  /// Stops playing and gives the computer its sound back.
  Future<void> stop({String? because}) async {
    if (because != null) problem = because;
    final line = _line;
    _line = null;
    playing = null;
    _log?.cancel();
    _log = null;
    // The computer first: its sound goes back to its own output at once.
    line?.close();
    unawaited(_sound?.cancel());
    _sound = null;
    unawaited(_ended?.cancel());
    _ended = null;
    await _output.stop();
    notifyListeners();
  }
}
