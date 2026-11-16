import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../src/rust/api/desktop.dart';
import '../src/rust/api/desktop_types.dart';
import '../ui/desktop/desktop_keys.dart';
import '../ui/desktop/desktop_settings.dart';
import 'session_manager.dart';

/// Where a remote desktop stands.
enum DesktopPhase { connecting, live, reconnecting, ended }

/// A sticky modifier on the key bar: off, on for the next key, or locked.
enum ModState { off, once, locked }

/// One remote desktop: the video texture, the remote pointer and keys,
/// and keeping it running across drops and network changes.
///
/// The video itself never comes through here: the Rust core decodes it
/// straight into [textureId]. This class only tracks what the screen
/// draws on top (cursor, status) and turns gestures into input.
class DesktopController extends ChangeNotifier {
  DesktopController({required this.session, required DesktopSettings settings, required this.onConnectionLost})
    // ignore: prefer_initializing_formals
    : _settings = settings;

  static const _video = MethodChannel('multiplex/desktop_video');

  final LiveSession session;

  /// The connection under the desktop looks dead; the session manager
  /// takes over and calls [reattach] once it is back.
  final VoidCallback onConnectionLost;

  DesktopSettings _settings;
  DesktopSettings get settings => _settings;

  RemoteDesktop? _desktop;
  StreamSubscription<DesktopEvent>? _events;

  /// The texture the video is drawn into, once created.
  int? textureId;

  DesktopPhase phase = DesktopPhase.connecting;

  /// Reconnecting progress, or why it ended.
  String note = '';

  /// True when the screen was made for this phone (not a mirror).
  bool fitted = true;
  String outputName = '';

  /// Video size in pixels and the remote's scale (logical = video / scale).
  int streamWidth = 0;
  int streamHeight = 0;
  double remoteScale = 1;
  bool hardwareEncoder = false;
  DesktopStats? stats;

  /// The remote pointer, in logical remote pixels.
  Offset cursor = const Offset(100, 100);
  bool cursorVisible = true;
  ui.Image? cursorImage;
  Offset cursorHot = Offset.zero;
  final Map<int, (ui.Image, Offset)> _shapes = {};
  int _shapeId = -1;

  /// While a finger steers the pointer, the remote's own reports of it
  /// (which lag behind) are not shown.
  bool steering = false;

  /// Sticky modifiers from the key bar.
  final Map<int, ModState> mods = {
    LinuxKey.leftMeta: ModState.off,
    LinuxKey.leftCtrl: ModState.off,
    LinuxKey.leftAlt: ModState.off,
    LinuxKey.leftShift: ModState.off,
  };
  final Map<int, DateTime> _modTapped = {};

  /// Buttons held down right now (a drag), with the modifiers held for them.
  final Map<DesktopButton, List<int>> _held = {};

  /// Text copied on the desktop, for the screen to show a short note.
  final ValueNotifier<String?> copiedFromDesktop = ValueNotifier(null);

  Size _viewPx = const Size(1280, 720);
  double _dpr = 2;
  Timer? _resizeDebounce;
  int _quickRetries = 0;
  bool _disposed = false;

  /// The remote screen's size in logical pixels.
  Size get remoteSize =>
      streamWidth == 0 ? Size(_viewPx.width / _scaleFor(_dpr), _viewPx.height / _scaleFor(_dpr)) : Size(streamWidth / remoteScale, streamHeight / remoteScale);

  bool get live => phase == DesktopPhase.live;

  /// The scale a fitted screen gets: desktop apps need more room than
  /// phone apps, so things are drawn at about half the phone's size by
  /// default, adjustable with the text size setting.
  double _scaleFor(double dpr) => (dpr * 0.5 * _settings.textSize).clamp(1.0, 4.0);

  /// Starts the desktop on a view of [viewPx] physical pixels.
  Future<void> start({required Size viewPx, required double dpr}) async {
    _viewPx = viewPx;
    _dpr = dpr;
    try {
      textureId ??= await _video.invokeMethod<int>('create', {'width': viewPx.width.round(), 'height': viewPx.height.round()});
    } on MissingPluginException {
      _end('Remote desktop needs the Android app.');
      return;
    }
    _video.setMethodCallHandler(_onVideoCall);
    await _open();
  }

  Future<dynamic> _onVideoCall(MethodCall call) async {
    // The surface was replaced (back from the background): the decoder
    // rebuilds on it and needs a full picture.
    if (call.method == 'surfaceChanged' && call.arguments == textureId) _desktop?.refresh();
  }

  Future<void> _open() async {
    final id = textureId;
    if (id == null || _disposed) return;
    phase = phase == DesktopPhase.reconnecting ? DesktopPhase.reconnecting : DesktopPhase.connecting;
    notifyListeners();
    try {
      final desktop = await session.ssh.openDesktop(
        options: DesktopOptions(
          mode: _settings.screen == DesktopScreenMode.fitted ? const DesktopMode.fitted() : const DesktopMode.mirror(),
          width: _viewPx.width.round(),
          height: _viewPx.height.round(),
          scale: _scaleFor(_dpr),
          lowBandwidth: _settings.quality == DesktopQuality.saver,
          textureId: id,
          serverCommand: '',
        ),
      );
      if (_disposed) {
        desktop.close();
        return;
      }
      _attach(desktop);
    } catch (e) {
      final message = '$e'.replaceFirst(RegExp(r'^(AnyhowException|Exception)\(?'), '').replaceAll(RegExp(r'\)$'), '');
      if (!session.ssh.isConnected()) {
        _lost();
      } else {
        _end(message.isEmpty ? 'The desktop could not start.' : message);
      }
    }
  }

  void _attach(RemoteDesktop desktop) {
    _events?.cancel();
    _desktop = desktop;
    _events = desktop.events().listen(_onEvent);
  }

  void _onEvent(DesktopEvent event) {
    switch (event) {
      case DesktopEvent_Started(:final fitted, :final output):
        this.fitted = fitted;
        outputName = output;
        phase = DesktopPhase.live;
        note = '';
        _quickRetries = 0;
        // Put the pointer where the user will look for it.
        if (streamWidth == 0) cursor = Offset(remoteSize.width / 2, remoteSize.height / 2);
      case DesktopEvent_Stream(:final width, :final height, :final scale, :final hardware):
        streamWidth = width;
        streamHeight = height;
        remoteScale = scale;
        hardwareEncoder = hardware;
        final id = textureId;
        if (id != null) _video.invokeMethod<void>('setSize', {'id': id, 'width': width, 'height': height});
        cursor = Offset(cursor.dx.clamp(0, remoteSize.width - 1), cursor.dy.clamp(0, remoteSize.height - 1));
      case DesktopEvent_CursorShape(:final id, :final width, :final height, :final hotX, :final hotY, :final bgra):
        _decodeCursor(id, width, height, Offset(hotX.toDouble(), hotY.toDouble()), bgra);
        return;
      case DesktopEvent_CursorMoved(:final x, :final y, :final shapeId, :final visible):
        cursorVisible = visible;
        if (!steering) cursor = Offset(x, y);
        _useShape(shapeId);
      case DesktopEvent_Clipboard(:final text):
        if (_settings.syncClipboard) {
          Clipboard.setData(ClipboardData(text: text));
          copiedFromDesktop.value = text;
        }
        return;
      case DesktopEvent_Stats(:final field0):
        stats = field0;
        if (!_settings.showStats) return;
      case DesktopEvent_Ended(:final reason, :final retryable):
        _desktop = null;
        if (phase == DesktopPhase.ended || _disposed) return;
        if (retryable) {
          _retry(reason);
        } else {
          _end(reason);
        }
    }
    notifyListeners();
  }

  /// The desktop stopped but may come back: on a healthy connection just
  /// start it again; otherwise let the session reconnect first.
  Future<void> _retry(String reason) async {
    if (_quickRetries < 3 && session.ssh.isConnected() && await session.ssh.checkAlive(timeoutSecs: 3)) {
      _quickRetries++;
      phase = DesktopPhase.reconnecting;
      note = 'Restarting the desktop…';
      notifyListeners();
      await Future<void>.delayed(Duration(milliseconds: 400 * _quickRetries));
      await _open();
      return;
    }
    _lost();
  }

  void _lost() {
    phase = DesktopPhase.reconnecting;
    note = 'Reconnecting…';
    notifyListeners();
    onConnectionLost();
  }

  void _end(String reason) {
    phase = DesktopPhase.ended;
    note = reason;
    _releaseHeld();
    notifyListeners();
  }

  // Called by the session manager.

  void showReconnecting(String status) {
    if (phase == DesktopPhase.ended || _disposed) return;
    phase = DesktopPhase.reconnecting;
    note = status;
    notifyListeners();
  }

  /// The connection is back (maybe by another route): start again on it.
  Future<void> reattach() async {
    if (_disposed || phase == DesktopPhase.ended) return;
    _desktop?.close();
    _desktop = null;
    _quickRetries = 0;
    await _open();
  }

  void connectionGone(String reason) => _end(reason);

  /// Asks for a fresh full picture.
  void restartPicture() => _desktop?.refresh();

  /// Starts again by hand after it ended.
  Future<void> restart() async {
    _quickRetries = 0;
    phase = DesktopPhase.connecting;
    note = '';
    notifyListeners();
    if (session.ssh.isConnected()) {
      await _open();
    } else {
      _lost();
    }
  }

  // View changes.

  /// The view changed size (rotation, split screen). Debounced so a
  /// rotation sends one resize, not dozens.
  void viewResized(Size px, double dpr) {
    if ((px.width - _viewPx.width).abs() < 2 && (px.height - _viewPx.height).abs() < 2 && dpr == _dpr) return;
    _viewPx = px;
    _dpr = dpr;
    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(const Duration(milliseconds: 250), () {
      _desktop?.resize(width: px.width.round(), height: px.height.round(), scale: _scaleFor(dpr));
    });
  }

  /// New settings; the screen mode and quality need a restart to apply.
  Future<void> applySettings(DesktopSettings next) async {
    final restart = next.screen != _settings.screen || next.quality != _settings.quality;
    final rescale = next.textSize != _settings.textSize;
    _settings = next;
    notifyListeners();
    if (restart && _desktop != null) {
      _desktop?.close();
      _desktop = null;
      phase = DesktopPhase.connecting;
      streamWidth = 0;
      await _open();
    } else if (rescale) {
      _desktop?.resize(width: _viewPx.width.round(), height: _viewPx.height.round(), scale: _scaleFor(_dpr));
    }
  }

  // Pointer.

  /// Moves the pointer to [p] (logical remote pixels), kept on screen.
  void moveTo(Offset p) {
    final size = remoteSize;
    cursor = Offset(p.dx.clamp(0, size.width - 1), p.dy.clamp(0, size.height - 1));
    _desktop?.pointerMove(x: cursor.dx, y: cursor.dy);
    notifyListeners();
  }

  void moveBy(Offset delta) => moveTo(cursor + delta);

  /// Presses a button, holding the sticky modifiers with it (Super+drag
  /// moves windows in Hyprland).
  void press(DesktopButton button) {
    final held = _activeMods();
    for (final m in held) {
      _desktop?.key(code: m, pressed: true);
    }
    _held[button] = held;
    _desktop?.button(button: button, pressed: true);
  }

  void release(DesktopButton button) {
    final held = _held.remove(button);
    if (held == null) return;
    _desktop?.button(button: button, pressed: false);
    for (final m in held.reversed) {
      _desktop?.key(code: m, pressed: false);
    }
    _consumeOnceMods();
  }

  void click(DesktopButton button) {
    press(button);
    release(button);
  }

  void _releaseHeld() {
    for (final b in List.of(_held.keys)) {
      release(b);
    }
  }

  void scroll(double dx, double dy) => _desktop?.scroll(dx: dx, dy: dy, wheel: false);

  void scrollStop() => _desktop?.scrollStop();

  // Keys.

  /// Taps a key with the sticky modifiers (and [extra] ones) held.
  void tap(int code, {List<int> extra = const []}) {
    final mods = [..._activeMods(), ...extra.where((m) => !_activeMods().contains(m))];
    _desktop?.chord(modifiers: mods, code: code);
    _consumeOnceMods();
  }

  /// Raw press/release, for a hardware keyboard (it sends its own
  /// modifiers).
  void keyEvent(int code, bool pressed) => _desktop?.key(code: code, pressed: pressed);

  /// Types text. What the US layout cannot type (accents, other
  /// alphabets, emoji) is pasted through the clipboard instead.
  void type(String text) {
    if (text.isEmpty) return;
    if (!UsLayout.canType(text)) {
      _desktop?.setClipboard(text: text);
      Timer(const Duration(milliseconds: 120), () => _desktop?.chord(modifiers: const [LinuxKey.leftCtrl], code: LinuxKey.v));
      return;
    }
    for (final rune in text.runes) {
      final stroke = UsLayout.stroke(String.fromCharCode(rune))!;
      tap(stroke.code, extra: stroke.shift ? const [LinuxKey.leftShift] : const []);
    }
  }

  /// Sends the phone's clipboard and pastes it on the desktop.
  Future<bool> pastePhoneClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return false;
    _desktop?.setClipboard(text: text);
    Timer(const Duration(milliseconds: 120), () => _desktop?.chord(modifiers: const [LinuxKey.leftCtrl], code: LinuxKey.v));
    return true;
  }

  /// One tap: on for the next key; a quick second tap: locked; a tap
  /// while on or locked: off.
  void toggleMod(int code) {
    final now = DateTime.now();
    final last = _modTapped[code];
    _modTapped[code] = now;
    final state = mods[code] ?? ModState.off;
    final quick = last != null && now.difference(last) < const Duration(milliseconds: 350);
    mods[code] = switch (state) {
      ModState.off => ModState.once,
      ModState.once => quick ? ModState.locked : ModState.off,
      ModState.locked => ModState.off,
    };
    notifyListeners();
  }

  List<int> _activeMods() => [
    for (final e in mods.entries)
      if (e.value != ModState.off) e.key,
  ];

  void _consumeOnceMods() {
    var changed = false;
    for (final e in mods.entries.toList()) {
      if (e.value == ModState.once) {
        mods[e.key] = ModState.off;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // Cursor pictures.

  Future<void> _decodeCursor(int id, int width, int height, Offset hot, Uint8List bgra) async {
    // Hyprland sometimes sends a blank or one-colour picture (a hidden or
    // placeholder pointer). Like gliff's own client, show the plain arrow
    // for those instead of a solid square.
    final usable = width > 0 &&
        height > 0 &&
        width <= 1024 &&
        height <= 1024 &&
        bgra.length >= width * height * 4 &&
        hot.dx >= 0 &&
        hot.dy >= 0 &&
        hot.dx < width &&
        hot.dy < height &&
        _hasVisibleShape(bgra);
    if (!usable) {
      _shapes.remove(id)?.$1.dispose();
      if (_shapeId == id) {
        cursorImage = null;
        notifyListeners();
      }
      return;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(bgra, width, height, ui.PixelFormat.bgra8888, completer.complete);
    final image = await completer.future;
    _shapes[id]?.$1.dispose();
    _shapes[id] = (image, hot);
    if (_shapeId == id || cursorImage == null) {
      _shapeId = -1;
      _useShape(id);
      notifyListeners();
    }
  }

  /// Some pixel is not fully transparent, and not every pixel is the same.
  static bool _hasVisibleShape(Uint8List bgra) {
    var opaque = false;
    var uniform = true;
    for (var i = 0; i + 3 < bgra.length; i += 4) {
      if (bgra[i + 3] != 0) opaque = true;
      if (uniform && (bgra[i] != bgra[0] || bgra[i + 1] != bgra[1] || bgra[i + 2] != bgra[2] || bgra[i + 3] != bgra[3])) uniform = false;
      if (opaque && !uniform) return true;
    }
    return false;
  }

  void _useShape(int id) {
    if (id == _shapeId) return;
    final shape = _shapes[id];
    _shapeId = id;
    if (shape == null) {
      // Unknown or unusable picture: the plain arrow.
      cursorImage = null;
      return;
    }
    cursorImage = shape.$1;
    // The picture is in remote pixels; the hot spot is drawn in logical.
    cursorHot = shape.$2;
  }

  @override
  void dispose() {
    _disposed = true;
    _resizeDebounce?.cancel();
    _releaseHeld();
    _events?.cancel();
    _desktop?.close();
    _desktop = null;
    final id = textureId;
    if (id != null) _video.invokeMethod<void>('release', {'id': id});
    for (final s in _shapes.values) {
      s.$1.dispose();
    }
    copiedFromDesktop.dispose();
    super.dispose();
  }
}
