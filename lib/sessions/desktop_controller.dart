import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../src/rust/api/desktop.dart';
import '../src/rust/api/desktop_types.dart';
import '../src/rust/api/tailscale.dart';
import '../src/rust/api/watch.dart';
import '../ui/desktop/desktop_keys.dart';
import '../ui/desktop/desktop_settings.dart';
import 'session_manager.dart';
import 'tailscale_node.dart';

/// One monitor of the remote machine, as Hyprland reports it.
class RemoteMonitor {
  const RemoteMonitor({required this.name, required this.width, required this.height, required this.focused, this.description = '', this.refresh = 0});

  final String name;
  final int width;
  final int height;
  final bool focused;
  final String description;
  final double refresh;
}

/// Starts `~/.local/bin/gliff-server-fast` when the machine has one (gliff
/// built for up to 120 frames a second; see docs/remote-desktop), and the
/// normal gliff-server otherwise.
const fastServerCommand = r'"$( [ -x "$HOME/.local/bin/gliff-server-fast" ] && echo "$HOME/.local/bin/gliff-server-fast" || echo gliff-server )"';

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

  /// Video in its own Android layer (see [DesktopSettings.directVideo]);
  /// fixed for the life of this desktop.
  late final bool direct = _settings.directVideo;
  final Completer<int> _directSurface = Completer<int>();

  /// The direct video layer exists; [surfaceId] is its decoder id.
  void attachDirectSurface(int surfaceId) {
    if (!_directSurface.isCompleted) _directSurface.complete(surfaceId);
  }

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

  /// The remote's monitors (from the server's welcome).
  List<DesktopOutput> outputs = const [];

  /// All monitors of the remote, from Hyprland (the server's welcome only
  /// names the one being shown).
  List<RemoteMonitor> monitors = const [];

  /// Asks Hyprland for its monitors over the same SSH connection.
  Future<void> refreshMonitors() async {
    const command =
        r'sig=$(ls -t "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" 2>/dev/null | head -1); '
        r'HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl monitors -j';
    try {
      final out = await session.ssh.exec(command: command, maxBytes: 256 * 1024);
      final list = jsonDecode(out.stdout) as List<dynamic>;
      monitors = [
        for (final m in list.cast<Map<String, dynamic>>())
          RemoteMonitor(
            name: m['name'] as String? ?? '',
            width: (m['width'] as num?)?.toInt() ?? 0,
            height: (m['height'] as num?)?.toInt() ?? 0,
            focused: m['focused'] == true,
            description: m['description'] as String? ?? '',
            refresh: (m['refreshRate'] as num?)?.toDouble() ?? 0,
          ),
      ]..sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
    } catch (_) {
      // Not Hyprland, or hyprctl missing: the picker falls back to what
      // the server named.
    }
  }

  /// The decoder's picture size and the part of it that is the screen.
  /// H.264 codes in 16-pixel blocks, so a 1072 x 602 stream decodes to
  /// 1072 x 608: those extra rows must not be drawn (they show as a green
  /// line). Until the decoder says, assume 16-pixel padding.
  int pictureWidth = 0;
  int pictureHeight = 0;
  int visibleWidth = 0;
  int visibleHeight = 0;

  /// How much wider and taller the decoded picture is than the screen in it.
  Size get paddingFactor {
    // Android's compositor applies the decoder's crop to a direct layer.
    if (direct) return const Size(1, 1);
    final vw = visibleWidth > 0 ? visibleWidth : streamWidth;
    final vh = visibleHeight > 0 ? visibleHeight : streamHeight;
    final pw = pictureWidth > 0 ? pictureWidth : (streamWidth + 15) ~/ 16 * 16;
    final ph = pictureHeight > 0 ? pictureHeight : (streamHeight + 15) ~/ 16 * 16;
    if (vw == 0 || vh == 0) return const Size(1, 1);
    // Smooth scaling blends the last row and column with the padding next
    // to them; leaving out two more pixels there keeps the edge clean.
    final ew = pw > vw ? vw - 2 : vw;
    final eh = ph > vh ? vh - 2 : vh;
    return Size(pw / ew, ph / eh);
  }

  DesktopStats? stats;

  /// A text field has the keyboard focus on the remote: the screen shows
  /// the keyboard while this is true (see [_watchTextFocus]).
  final ValueNotifier<bool> remoteTextFocus = ValueNotifier(false);
  RemoteWatch? _textWatch;
  StreamSubscription<String>? _textLines;

  /// Asks the remote's input method (fcitx5) about 7 times a second
  /// whether a text field has focus, and reports only changes. Apps that
  /// type through the input method (browsers, terminals, chat, editors)
  /// all show up; without fcitx5 nothing is reported and the keyboard
  /// stays manual.
  static const _textFocusScript = r'''
command -v busctl >/dev/null || exit 0
prev=unset
while :; do
  d=$(busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 DebugInfo 2>/dev/null)
  f=$(printf %s "$d" | grep -o 'IC \[[0-9a-f]*\][^\\]*focus:1' | head -1 | sed 's/IC \[\([0-9a-f]*\)\].*/\1/')
  [ "$f" != "$prev" ] && echo "text ${f:-0}" && prev=$f
  sleep 0.15
done
''';

  /// The script travels base64-encoded, so it runs the same whatever the
  /// login shell is. It prints "text" and the id of the focused field, or
  /// "text 0", and only when that changes.
  static String get _textFocusWatcher => 'echo ${base64.encode(utf8.encode(_textFocusScript))} | base64 -d | sh';

  /// Counts up whenever a text field on the remote newly gets the focus
  /// (also when it moves from one field to another), so the screen can
  /// tell a new focus from an unchanged one.
  final ValueNotifier<int> remoteTextFocusEvents = ValueNotifier(0);

  Future<void> _watchTextFocus() async {
    if (_textWatch != null || !_settings.autoKeyboard) return;
    try {
      final watch = await session.ssh.watch(command: _textFocusWatcher);
      if (_disposed) {
        watch.stop();
        return;
      }
      _textWatch = watch;
      _textLines = watch.lines().listen((line) {
        if (!line.startsWith('text ')) return;
        final focused = line != 'text 0';
        remoteTextFocus.value = focused;
        if (focused) remoteTextFocusEvents.value++;
      });
    } catch (_) {
      // No watcher: the keyboard stays manual.
    }
  }

  void _stopTextWatch() {
    _textLines?.cancel();
    _textLines = null;
    _textWatch?.stop();
    _textWatch = null;
    remoteTextFocus.value = false;
  }

  /// Over Tailscale: the network's own round trip (disco ping) and one
  /// through WireGuard and the IP stacks (TSMP), measured every 2 s, to
  /// compare with the stream's ping. Null until measured.
  double? netPingMs;
  double? tsmpPingMs;
  Timer? _netProbe;

  void _startNetProbe() {
    if (_netProbe != null || !session.host.viaTailscale) return;
    _netProbe = Timer.periodic(const Duration(seconds: 2), (_) => _probeNet());
  }

  bool _probing = false;

  Future<void> _probeNet() async {
    if (_probing || !live) return;
    final ip = TailscaleNode.instance.deviceFor(session.host.address)?.ips.where((i) => !i.contains(':')).firstOrNull;
    if (ip == null) return;
    _probing = true;
    try {
      final disco = await tailscalePing(ip: ip, kind: 'disco');
      final tsmp = await tailscalePing(ip: ip, kind: 'TSMP');
      netPingMs = disco >= 0 ? disco : null;
      tsmpPingMs = tsmp >= 0 ? tsmp : null;
      // One line per sample in the device log, for diagnosis.
      debugPrint(
        'MPXLAT disco=${disco.toStringAsFixed(1)} tsmp=${tsmp.toStringAsFixed(1)} '
        'stream=${stats?.rttMs.toStringAsFixed(0)} delay=${stats?.frameAgeMs.toStringAsFixed(0)} fps=${stats?.fps.toStringAsFixed(0)}',
      );
    } catch (_) {
    } finally {
      _probing = false;
    }
  }

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
      if (direct) {
        // The video layer is a platform view; its Surface id comes from
        // [attachDirectSurface] once Android has made it.
        textureId ??= await _directSurface.future.timeout(const Duration(seconds: 8));
      } else {
        textureId ??= await _video.invokeMethod<int>('create', {'width': viewPx.width.round(), 'height': viewPx.height.round()});
      }
    } on MissingPluginException {
      _end('Remote desktop needs the Android app.');
      return;
    } on TimeoutException {
      _end('The video layer did not start. Turn off "Direct video" in the menu and try again.');
      return;
    }
    _video.setMethodCallHandler(_onVideoCall);
    unawaited(_video.invokeMethod<void>('lowLatency', {'on': true}).catchError((_) {}));
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
          mode: _settings.screen == DesktopScreenMode.fitted
              ? const DesktopMode.fitted()
              : (_settings.output.isEmpty ? const DesktopMode.mirror() : DesktopMode.output(name: _settings.output)),
          width: _target.width.round(),
          height: _target.height.round(),
          scale: _scaleFor(_dpr),
          lowBandwidth: _settings.quality == DesktopQuality.saver,
          textureId: id,
          serverCommand: fastServerCommand,
          warmRadio: _settings.warmRadio,
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
      case DesktopEvent_Started(:final fitted, :final output, :final outputs):
        this.fitted = fitted;
        outputName = output;
        this.outputs = outputs;
        unawaited(refreshMonitors());
        phase = DesktopPhase.live;
        note = '';
        _startNetProbe();
        // A reconnect makes a new connection: the watcher starts again on it.
        _stopTextWatch();
        unawaited(_watchTextFocus());
        _quickRetries = 0;
        // Put the pointer where the user will look for it.
        if (streamWidth == 0) cursor = Offset(remoteSize.width / 2, remoteSize.height / 2);
      case DesktopEvent_Stream(:final width, :final height, :final scale, :final hardware):
        streamWidth = width;
        streamHeight = height;
        remoteScale = scale;
        hardwareEncoder = hardware;
        visibleWidth = width;
        visibleHeight = height;
        pictureWidth = 0;
        pictureHeight = 0;
        _sizeTexture((width + 15) ~/ 16 * 16, (height + 15) ~/ 16 * 16);
        cursor = Offset(cursor.dx.clamp(0, remoteSize.width - 1), cursor.dy.clamp(0, remoteSize.height - 1));
      case DesktopEvent_Picture(:final width, :final height, :final visibleWidth, :final visibleHeight):
        pictureWidth = width;
        pictureHeight = height;
        // Some decoders (Qualcomm) report the padded size with no crop:
        // the screen is never larger than the stream the server sent.
        this.visibleWidth = streamWidth > 0 ? visibleWidth.clamp(1, streamWidth) : visibleWidth;
        this.visibleHeight = streamHeight > 0 ? visibleHeight.clamp(1, streamHeight) : visibleHeight;
        _sizeTexture(width, height);
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

  int _textureW = 0, _textureH = 0;

  /// The texture's buffer matches the decoder's pictures, so they are not
  /// stretched on the way. Only resized when the size really changes
  /// (a resize makes the decoder start over on a new surface).
  void _sizeTexture(int width, int height) {
    // A direct video layer takes the decoder's size by itself.
    if (direct) return;
    final id = textureId;
    if (id == null || (width == _textureW && height == _textureH)) return;
    _textureW = width;
    _textureH = height;
    _video.invokeMethod<void>('setSize', {'id': id, 'width': width, 'height': height});
  }

  /// The stream size to ask for, from the resolution setting. A mirrored
  /// monitor is scaled down by the server to fit this box (never up); a
  /// phone-sized screen is created at it.
  Size get _target {
    final view = _viewPx;
    final landscape = view.width >= view.height;
    Size box(double w, double h) => landscape ? Size(w, h) : Size(h, w);
    final fitted = _settings.screen == DesktopScreenMode.fitted;
    final Size limit = switch (_settings.resolution) {
      DesktopResolution.phone => view,
      DesktopResolution.p720 => fitted ? box(1280, 720) : const Size(1280, 720),
      DesktopResolution.p1080 => fitted ? box(1920, 1080) : const Size(1920, 1080),
      DesktopResolution.auto => fitted ? view : const Size(3840, 2160),
    };
    if (!fitted || _settings.resolution == DesktopResolution.auto || _settings.resolution == DesktopResolution.phone) return limit;
    // A phone-sized screen keeps the phone's shape inside the box.
    final f = (limit.width / view.width) < (limit.height / view.height) ? limit.width / view.width : limit.height / view.height;
    return f >= 1 ? view : Size((view.width * f).roundToDouble(), (view.height * f).roundToDouble());
  }

  /// Shows another monitor ('' = the one in focus).
  Future<void> showOutput(String name) => applySettings(_settings.copyWith(screen: DesktopScreenMode.mirror, output: name));

  // View changes.

  /// The view changed size (rotation, split screen). Debounced so a
  /// rotation sends one resize, not dozens.
  void viewResized(Size px, double dpr) {
    if ((px.width - _viewPx.width).abs() < 2 && (px.height - _viewPx.height).abs() < 2 && dpr == _dpr) return;
    _viewPx = px;
    _dpr = dpr;
    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(const Duration(milliseconds: 250), () {
      final t = _target;
      _desktop?.resize(width: t.width.round(), height: t.height.round(), scale: _scaleFor(dpr));
    });
  }

  /// New settings; the screen mode and quality need a restart to apply.
  Future<void> applySettings(DesktopSettings next) async {
    final restart =
        next.screen != _settings.screen || next.quality != _settings.quality || next.output != _settings.output || next.warmRadio != _settings.warmRadio;
    final resized = next.resolution != _settings.resolution;
    final rescale = next.textSize != _settings.textSize;
    _settings = next;
    notifyListeners();
    if (restart && _desktop != null) {
      _desktop?.close();
      _desktop = null;
      phase = DesktopPhase.connecting;
      streamWidth = 0;
      _textureW = 0;
      _textureH = 0;
      await _open();
    } else if (rescale || resized) {
      final t = _target;
      _desktop?.resize(width: t.width.round(), height: t.height.round(), scale: _scaleFor(_dpr));
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
    final usable =
        width > 0 &&
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
    _netProbe?.cancel();
    _stopTextWatch();
    remoteTextFocus.dispose();
    remoteTextFocusEvents.dispose();
    _releaseHeld();
    _events?.cancel();
    _desktop?.close();
    _desktop = null;
    final id = textureId;
    if (id != null && !direct) _video.invokeMethod<void>('release', {'id': id});
    _video.invokeMethod<void>('lowLatency', {'on': false}).catchError((_) {});
    for (final s in _shapes.values) {
      s.$1.dispose();
    }
    copiedFromDesktop.dispose();
    super.dispose();
  }
}
