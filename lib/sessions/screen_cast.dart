import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import 'error_text.dart';

/// What came of a piece of the picture, and what the encoder should do.
class ScreenWrote {
  const ScreenWrote({this.ended = false, this.reason = '', this.bitrate, this.keyFrame = false});

  /// The window is gone ([reason] says why; empty when it was closed).
  final bool ended;
  final String reason;

  /// Set the encoder to this many bits per second.
  final int? bitrate;

  /// Ask the encoder for a full picture now.
  final bool keyFrame;
}

/// The window on the computer, as the cast writes to it. The real one is
/// a stream over SSH (in the Rust core, which also decides when to skip
/// ahead on a slow connection); tests pass a stand-in.
abstract class ScreenWindow {
  ScreenWrote write(Uint8List bytes);

  /// Why it ended (empty when it was simply closed).
  Stream<String> get ended;

  /// How the stream is doing, as one line for the log.
  String? status() => null;
  void close();
}

/// What only Android can do: ask the user, capture and encode the screen.
class ScreenCapture {
  const ScreenCapture({this.channel = const MethodChannel('multiplex/screencast'), this.frames = const EventChannel('multiplex/screencast/frames')});

  final MethodChannel channel;
  final EventChannel frames;

  /// Android asks the user; true once they allowed it and capturing began.
  /// The encoder starts at [bitrate] bits per second.
  Future<bool> start({required int bitrate}) async {
    try {
      return await channel.invokeMethod<bool>('start', {'bitrate': bitrate}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
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

  /// Changes the running encoder: a new bitrate, a full picture now, or both.
  Future<void> adjust({int? bitrate, bool keyFrame = false}) async {
    try {
      await channel.invokeMethod<void>('adjust', {'bitrate': bitrate, 'keyFrame': keyFrame});
    } on MissingPluginException {
      // Not on Android.
    } on PlatformException {
      // Already stopped.
    }
  }

  /// The encoded picture in pieces; an empty piece says it has ended.
  Stream<Uint8List> pieces() => frames.receiveBroadcastStream().where((p) => p is Uint8List).cast<Uint8List>();
}

/// What only Android can do for the camera: ask the user, film and encode.
class CameraCapture extends ScreenCapture {
  CameraCapture({super.channel = const MethodChannel('multiplex/camcast'), super.frames = const EventChannel('multiplex/camcast/frames')});

  /// The camera on the screen's side (for filming oneself), not the back one.
  bool front = false;

  @override
  Future<bool> start({required int bitrate}) async {
    try {
      return await channel.invokeMethod<bool>('start', {'bitrate': bitrate, 'facing': front ? 'front' : 'back'}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// How far the picture has to be turned clockwise to stand upright, in
  /// degrees. Known once [start] has returned true.
  Future<int> turn() async {
    try {
      return await channel.invokeMethod<int>('turn') ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }
}

/// What only Android can do for the microphone: ask the user, record and
/// encode. Its pieces are whole AAC frames.
class MicCapture extends ScreenCapture {
  const MicCapture({super.channel = const MethodChannel('multiplex/miccast'), super.frames = const EventChannel('multiplex/miccast/frames')});
}

/// Sends something live from this phone to a paired computer: its screen,
/// for a window there; its camera, as a webcam there; its microphone, as
/// a microphone there. One of each at a time; it carries on while the
/// user leaves Multiplex, which for the screen is the point.
class PhoneCast extends ChangeNotifier {
  PhoneCast({ScreenCapture capture = const ScreenCapture()})
    // ignore: prefer_initializing_formals
    : _capture = capture;

  /// The app's own: this phone's screen, for a window on a computer.
  static final PhoneCast screen = PhoneCast();

  /// The app's own: this phone's camera, as a webcam of a computer.
  static final CameraCapture phoneCamera = CameraCapture();
  static final PhoneCast camera = PhoneCast(capture: phoneCamera);

  /// The app's own: this phone's microphone, as a microphone of a computer.
  static final PhoneCast microphone = PhoneCast(capture: const MicCapture());

  final ScreenCapture _capture;
  ScreenWindow? _window;
  StreamSubscription<Uint8List>? _pieces;
  StreamSubscription<String>? _ended;
  Timer? _log;
  bool _starting = false;

  /// The computer the screen is showing on, while it is.
  Host? showingOn;

  /// Why the last one could not start or stopped, as a sentence.
  String? problem;

  bool get starting => _starting;

  /// Asks Android for the screen, then opens the window on [computer]
  /// with [open] and sends the picture there. False when the user said no
  /// or it could not start ([problem] then says why, unless they said no).
  /// [bitrate] is what the encoder starts at (the stream's pacing says).
  Future<bool> start(Host computer, Future<ScreenWindow> Function() open, {int bitrate = 4000000}) async {
    if (_starting || showingOn != null) return false;
    _starting = true;
    problem = null;
    notifyListeners();
    // Pieces from the very first one are kept until the window is there:
    // the first ones carry what a player needs to begin.
    final early = <Uint8List>[];
    var over = false;
    _pieces = _capture.pieces().listen((piece) {
      if (piece.isEmpty) {
        over = true;
        unawaited(stop());
        return;
      }
      final window = _window;
      if (window == null) {
        early.add(piece);
        return;
      }
      final wrote = window.write(piece);
      if (wrote.ended) {
        unawaited(stop(because: wrote.reason.isEmpty ? null : wrote.reason));
      } else if (wrote.bitrate != null || wrote.keyFrame) {
        unawaited(_capture.adjust(bitrate: wrote.bitrate, keyFrame: wrote.keyFrame));
      }
    });
    try {
      if (!await _capture.start(bitrate: bitrate)) {
        unawaited(_pieces?.cancel());
        _pieces = null;
        return false;
      }
      final window = await open();
      if (over) {
        window.close();
        return false;
      }
      for (final piece in early) {
        window.write(piece);
      }
      early.clear();
      _window = window;
      _ended = window.ended.listen((reason) => unawaited(stop(because: reason.isEmpty ? null : reason)));
      if (kDebugMode) {
        _log = Timer.periodic(const Duration(seconds: 2), (_) {
          final line = window.status();
          if (line != null) debugPrint('mpxcast $line');
        });
      }
      showingOn = computer;
      return true;
    } catch (e) {
      problem = errorSentence(e, fallback: 'The computer could not show the screen.');
      await _capture.stop();
      unawaited(_pieces?.cancel());
      _pieces = null;
      return false;
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  /// Stops capturing and closes the window.
  Future<void> stop({String? because}) async {
    if (because != null) problem = because;
    final window = _window;
    _window = null;
    showingOn = null;
    _log?.cancel();
    _log = null;
    // The window and the capture first. Unhooking the listeners is not
    // waited for: with the real stream that can take until it has ended,
    // and nothing here may hang on it.
    window?.close();
    unawaited(_ended?.cancel());
    _ended = null;
    unawaited(_pieces?.cancel());
    _pieces = null;
    await _capture.stop();
    notifyListeners();
  }
}
