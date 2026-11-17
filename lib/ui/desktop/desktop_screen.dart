import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_motion.dart';
import '../../app/app_scope.dart';
import '../../app/screen_awake.dart';
import '../../app/screen_privacy.dart';
import '../../app/theme.dart';
import '../../sessions/desktop_controller.dart';
import '../../sessions/session_manager.dart';
import '../../sessions/tailscale_node.dart';
import '../common/widgets.dart';
import '../terminal/ended_banner.dart';
import '../terminal/reconnect_banner.dart';
import 'desktop_controls.dart';
import 'desktop_cursor.dart';
import 'desktop_gestures.dart';
import 'desktop_key_sink.dart';
import 'desktop_keyboard.dart';
import '../keyboard/terminal_keyboard_panel.dart';
import 'desktop_menu.dart';
import 'desktop_settings.dart';
import 'direct_video_view.dart';

/// The remote desktop, full screen: the live picture of the machine, a
/// pointer you steer with a finger, the phone keyboard with shortcut keys,
/// and a small toolbar that stays out of the way.
class DesktopScreen extends StatefulWidget {
  const DesktopScreen({super.key, required this.session, required this.controller});

  final LiveSession session;
  final DesktopController controller;

  /// Opens a new desktop on [session].
  static Future<void> open(BuildContext context, LiveSession session) {
    final sessions = AppScope.sessions(context);
    final controller = sessions.openDesktop(session, DesktopSettings.of(AppScope.store(context)));
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DesktopScreen(session: session, controller: controller),
      ),
    );
  }

  @override
  State<DesktopScreen> createState() => _DesktopScreenState();
}

class _DesktopScreenState extends State<DesktopScreen> with WidgetsBindingObserver {
  final _viewport = DesktopViewport();
  final _focus = FocusNode(debugLabel: 'desktop keyboard');
  bool _started = false;
  bool _keyboardOpen = false;

  /// The phone keyboard actually appeared since it was asked for; only then
  /// does its disappearing (back gesture) mean the user closed it.
  bool _keyboardSeen = false;
  bool _keysOpen = false;

  /// The phone's own keyboard instead of Multiplex's.
  late bool _systemKeyboard = !c.settings.builtInKeyboard;

  /// The keyboard was opened because a remote text field got the focus
  /// (so it closes again when the field loses it).
  bool _autoOpened = false;
  final _panelKey = GlobalKey();
  double _panelHeight = 0;
  bool _toolbarShown = true;
  Timer? _hideToolbar;
  Size _lastView = Size.zero;
  Size _lastRemote = Size.zero;

  DesktopController get c => widget.controller;

  /// This connection runs over the app's Tailscale (a Tailscale host, or a
  /// paired computer on its Tailscale route).
  late final bool _overTailscale = widget.session.ssh.info().via == 'Tailscale';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    ScreenAwake.hold();
    c.addListener(_changed);
    c.copiedFromDesktop.addListener(_copied);
    c.remoteTextFocus.addListener(_remoteFocusChanged);
    c.remoteTextFocusEvents.addListener(_remoteFocusGained);
    // Over Tailscale, keep the route label current: a connection often
    // starts on a relay and turns direct a few seconds later.
    if (_overTailscale) {
      TailscaleNode.instance.addListener(_changed);
      TailscaleNode.instance.watch();
    }
    _scheduleHide();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideToolbar?.cancel();
    c.removeListener(_changed);
    c.copiedFromDesktop.removeListener(_copied);
    c.remoteTextFocus.removeListener(_remoteFocusChanged);
    c.remoteTextFocusEvents.removeListener(_remoteFocusGained);
    _clickCheck?.cancel();
    if (_overTailscale) {
      TailscaleNode.instance.removeListener(_changed);
      TailscaleNode.instance.unwatch();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    ScreenAwake.release();
    _focus.dispose();
    // Leaving the screen ends the desktop; its fitted screen goes away on
    // the remote. Opening it again takes a moment.
    AppScope.sessions(context).closeDesktop(c);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in front: the video surface may be new; a full picture fixes it.
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _copied() {
    final text = c.copiedFromDesktop.value;
    if (text == null || !mounted) return;
    final short = text.length > 40 ? '${text.substring(0, 40)}…' : text;
    Toast.show(context, 'Copied from the desktop: $short');
  }

  void _scheduleHide() {
    _hideToolbar?.cancel();
    _hideToolbar = Timer(const Duration(seconds: 4), () {
      if (mounted && c.live && !_keyboardOpen) setState(() => _toolbarShown = false);
    });
  }

  void _showToolbar() {
    if (!_toolbarShown) setState(() => _toolbarShown = true);
    _scheduleHide();
  }

  void _toggleKeyboard() {
    _autoOpened = false;
    _keyboardOpen ? _closeKeyboard() : _openKeyboard();
    _scheduleHide();
  }

  void _openKeyboard() {
    setState(() {
      _keyboardOpen = true;
      _keyboardSeen = false;
    });
    _focus.requestFocus();
    SystemChannels.textInput.invokeMethod<void>(_systemKeyboard ? 'TextInput.show' : 'TextInput.hide');
  }

  void _closeKeyboard() {
    setState(() {
      _keyboardOpen = false;
      _keyboardSeen = false;
      _autoOpened = false;
    });
    _focus.unfocus();
  }

  /// The remote's text focus went away: a keyboard that opened by itself
  /// closes again.
  void _remoteFocusChanged() {
    if (!mounted || !c.settings.autoKeyboard) return;
    if (!c.remoteTextFocus.value && _keyboardOpen && _autoOpened) _closeKeyboard();
  }

  /// A text field on the remote newly got the focus (also another field
  /// than before): the keyboard opens.
  void _remoteFocusGained() => _openForText();

  void _openForText() {
    if (!mounted || !c.settings.autoKeyboard || _keyboardOpen || !c.remoteTextFocus.value) return;
    _openKeyboard();
    _autoOpened = true;
  }

  Timer? _clickCheck;

  /// After a tap on the picture: if a text field has the focus by then
  /// (also one that already had it, after the keyboard was hidden), the
  /// keyboard opens, as tapping into a field does on a phone. The wait
  /// covers the remote noticing the click and the watcher reporting it.
  void _afterClick() {
    _clickCheck?.cancel();
    _clickCheck = Timer(const Duration(milliseconds: 450), _openForText);
  }

  /// Between Multiplex's keyboard and the phone's (voice, other languages).
  void _useSystemKeyboard(bool system) {
    setState(() => _systemKeyboard = system);
    if (_keyboardOpen) {
      _focus.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) => _openKeyboard());
    }
  }

  /// The built-in keyboard's height, once laid out, so the picture can move
  /// above it.
  void _measurePanel() {
    final box = _panelKey.currentContext?.findRenderObject() as RenderBox?;
    final h = box?.hasSize == true ? box!.size.height : 0.0;
    if ((h - _panelHeight).abs() > 0.5) setState(() => _panelHeight = h);
  }

  void _keepFocus() {
    if (_keyboardOpen && !_focus.hasFocus) _focus.requestFocus();
  }

  void _toggleTouchMode() {
    final store = AppScope.store(context);
    final next = c.settings.copyWith(touch: c.settings.touch == DesktopTouchMode.trackpad ? DesktopTouchMode.direct : DesktopTouchMode.trackpad);
    next.saveTo(store);
    c.applySettings(next);
    Toast.show(
      context,
      next.touch == DesktopTouchMode.trackpad ? 'Trackpad: drag to move the pointer, tap to click' : 'Direct touch: tap where you want to click',
    );
    _scheduleHide();
  }

  Future<void> _more() async {
    _hideToolbar?.cancel();
    await DesktopMenu.show(context, controller: c, onDisconnect: _disconnect);
    _scheduleHide();
  }

  Future<void> _disconnect() async {
    final ok = await Confirm.ask(
      context,
      title: 'Disconnect from ${widget.session.host.title}?',
      message: 'The desktop and every terminal and tunnel on this connection close.',
      action: 'Disconnect',
    );
    if (!ok || !mounted) return;
    final sessions = AppScope.sessions(context);
    Navigator.of(context).pop();
    await sessions.disconnect(widget.session);
  }

  String get _route {
    final via = widget.session.ssh.info().via;
    if (via == 'Tailscale') {
      final device = TailscaleNode.instance.deviceFor(widget.session.host.tailnetName);
      if (device == null) return 'Tailscale';
      return device.direct ? 'Tailscale · direct' : (device.relay.isEmpty ? 'Tailscale' : 'Tailscale · relay ${device.relay}');
    }
    return via == null ? 'Direct' : 'via $via';
  }

  // Zoom.

  Size _view = Size.zero;

  void _toggleZoom(Offset focal) {
    if (_viewport.zoom > 1.05) {
      _viewport.layout(_view, c.remoteSize, zoom: 1);
    } else {
      _viewport.zoomAround(focal, 2.5, _view, c.remoteSize);
    }
    setState(() {});
  }

  void _zoomBy(double factor) {
    _viewport.zoomAround(Offset(_view.width / 2, _view.height / 2), factor, _view, c.remoteSize);
    setState(() {});
  }

  // Screens.

  /// The monitors to step through, in order, and which one is shown.
  (List<String>, int) get _screens {
    final names = c.monitors.isNotEmpty ? [for (final m in c.monitors) m.name] : [for (final o in c.outputs) o.name];
    final shown = c.settings.output.isNotEmpty ? c.settings.output : (c.monitors.where((m) => m.focused).firstOrNull?.name ?? c.outputName);
    return (names, names.indexOf(shown));
  }

  Future<void> _switchScreen(int step) async {
    if (c.monitors.isEmpty) await c.refreshMonitors();
    final (names, at) = _screens;
    if (names.length < 2) {
      if (mounted) Toast.show(context, 'Only one monitor');
      return;
    }
    final next = names[((at < 0 ? 0 : at) + step) % names.length];
    _showScreen(next);
  }

  void _showScreen(String name) {
    final next = c.settings.copyWith(output: name);
    next.saveTo(AppScope.store(context));
    c.showOutput(name);
    _viewport.layout(_view, c.remoteSize, zoom: 1);
    Toast.show(context, name);
  }

  /// Starts the desktop once the size is known; later sizes are resizes.
  void _layoutChanged(Size view, double dpr) {
    final px = Size(view.width * dpr, view.height * dpr);
    if (!_started) {
      _started = true;
      c.start(viewPx: px, dpr: dpr);
    } else {
      c.viewResized(px, dpr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardHeight = media.viewInsets.bottom;
    // The phone keyboard closed by itself (back gesture): follow it.
    if (_keyboardOpen && _systemKeyboard && keyboardHeight > 0) _keyboardSeen = true;
    if (_keyboardOpen && _systemKeyboard && _keyboardSeen && keyboardHeight == 0) {
      _keyboardOpen = false;
      _keyboardSeen = false;
      _focus.unfocus();
    }
    final showKeys = _keysOpen || _keyboardOpen;

    return PrivateScreen(
      child: PopScope(
        child: Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: false,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final view = constraints.biggest;
              _view = view;
              final dpr = media.devicePixelRatio;
              // The remote screen is sized to the whole phone screen, so
              // opening the keyboard never resizes the remote desktop.
              WidgetsBinding.instance.addPostFrameCallback((_) => _layoutChanged(view, dpr));
              final remote = c.remoteSize;
              if (view != _lastView || remote != _lastRemote) {
                _viewport.layout(view, remote);
                _lastView = view;
                _lastRemote = remote;
              }
              final builtIn = _keyboardOpen && !_systemKeyboard;
              if (builtIn) WidgetsBinding.instance.addPostFrameCallback((_) => _measurePanel());
              final bottomInset = builtIn ? _panelHeight : keyboardHeight + (showKeys ? 52 : 0);
              final visible = bottomInset > 0 ? view.height - bottomInset : null;
              if (visible != null && c.live) {
                _viewport.follow(c.cursor, view, remote, visibleHeight: visible);
              } else {
                // Keyboard gone: the picture settles back (no black band
                // left where it had moved up).
                _viewport.layout(view, remote);
              }

              return DesktopKeyboard(
                controller: c,
                focusNode: _focus,
                systemKeyboard: _systemKeyboard,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DesktopGestures(
                        controller: c,
                        viewport: _viewport,
                        viewSize: view,
                        visibleHeight: visible,
                        onViewChanged: () => setState(() {}),
                        onTapEmpty: () {},
                        onToggleZoom: _toggleZoom,
                        onSwitchScreen: _switchScreen,
                        onClicked: _afterClick,
                        child: _RemoteView(controller: c, viewport: _viewport),
                      ),
                    ),
                    if (c.phase == DesktopPhase.connecting) _Starting(title: widget.session.host.title),
                    // The toolbar, or the handle that brings it back.
                    Positioned(
                      top: media.padding.top + 8,
                      left: 12,
                      right: 12,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: AppMotion.of(context).page ~/ 2,
                          child: _toolbarShown || !c.live
                              ? ConstrainedBox(
                                  key: const ValueKey('bar'),
                                  constraints: const BoxConstraints(maxWidth: 560),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      DesktopToolbar(
                                        title: widget.session.host.title,
                                        route: _route,
                                        controller: c,
                                        keyboardOpen: _keyboardOpen,
                                        keysOpen: _keysOpen,
                                        onBack: () => Navigator.of(context).maybePop(),
                                        onKeyboard: _toggleKeyboard,
                                        onKeys: () {
                                          setState(() => _keysOpen = !_keysOpen);
                                          _scheduleHide();
                                        },
                                        onTouchMode: _toggleTouchMode,
                                        onScreens: () async {
                                          _hideToolbar?.cancel();
                                          await DesktopScreens.show(context, controller: c);
                                          _scheduleHide();
                                        },
                                        onMore: _more,
                                      ),
                                      if (_screens.$1.length > 1) ...[
                                        const SizedBox(height: 6),
                                        DesktopScreenChips(
                                          names: _screens.$1,
                                          selected: _screens.$2,
                                          onSelect: (name) {
                                            _showScreen(name);
                                            _scheduleHide();
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                )
                              : _Handle(key: const ValueKey('handle'), onTap: _showToolbar),
                        ),
                      ),
                    ),
                    // While zoomed in: zoom out, in, or back to the whole screen.
                    if (c.live && _viewport.zoom > 1.05)
                      Positioned(
                        left: 12,
                        bottom: bottomInset + 12 + (showKeys || _keyboardOpen ? 0 : media.padding.bottom),
                        child: DesktopZoomPill(
                          zoom: _viewport.zoom,
                          onOut: () => _zoomBy(1 / 1.5),
                          onIn: () => _zoomBy(1.5),
                          onFit: () => _toggleZoom(Offset.zero),
                        ),
                      ),
                    if (c.settings.showStats && c.live)
                      Positioned(
                        right: 8,
                        bottom: bottomInset + 8 + (showKeys ? 0 : media.padding.bottom),
                        child: DesktopStatsChip(controller: c),
                      ),
                    // Bottom: reconnect / ended banner, or the key bar.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: keyboardHeight,
                      child: switch (c.phase) {
                        DesktopPhase.reconnecting => ReconnectBanner(
                          note: c.note,
                          onTryNow: () => AppScope.sessions(context).networkBack(),
                          onStop: () => AppScope.sessions(context).stopReconnecting(widget.session),
                        ),
                        DesktopPhase.ended => EndedBanner(reason: c.note, onReconnect: c.restart, onClose: () => Navigator.of(context).maybePop()),
                        // Multiplex's keyboard, with the desktop's Super key bar on top.
                        _ when builtIn => Column(
                          key: _panelKey,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DesktopKeyBar(controller: c, keepFocus: _keepFocus, compact: true),
                            TerminalKeyboardPanel.withSink(
                              showCommands: false,
                              sink: DesktopKeySink(c),
                              onSnippets: () {},
                              onHistory: () {},
                              onHide: _closeKeyboard,
                              onSwitchToSystem: () => _useSystemKeyboard(true),
                            ),
                          ],
                        ),
                        _ when showKeys => DesktopKeyBar(
                          controller: c,
                          keepFocus: _keepFocus,
                          onSwitchKeyboard: _keyboardOpen ? () => _useSystemKeyboard(false) : null,
                        ),
                        _ => const SizedBox.shrink(),
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The video with the pointer drawn on top, placed by the viewport.
class _RemoteView extends StatelessWidget {
  const _RemoteView({required this.controller, required this.viewport});

  final DesktopController controller;
  final DesktopViewport viewport;

  @override
  Widget build(BuildContext context) {
    final id = controller.textureId;
    final remote = controller.remoteSize;
    final size = remote * viewport.k;
    final pad = controller.paddingFactor;
    return ClipRect(
      child: Stack(
        children: [
          // Direct video: the decoder's own Android layer, placed where the
          // screen goes (it must exist before the desktop can start).
          if (controller.direct)
            Positioned(
              left: viewport.origin.dx,
              top: viewport.origin.dy,
              width: size.width,
              height: size.height,
              child: DirectVideoView(onSurface: controller.attachDirectSurface),
            )
          else if (id != null && controller.streamWidth > 0)
            Positioned(
              left: viewport.origin.dx,
              top: viewport.origin.dy,
              width: size.width,
              height: size.height,
              // The decoded picture is a little larger than the screen in
              // it (16-pixel padding); draw it so the screen part fills the
              // box and clip the padding away.
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: size.width * pad.width,
                  maxWidth: size.width * pad.width,
                  minHeight: size.height * pad.height,
                  maxHeight: size.height * pad.height,
                  child: Texture(textureId: id, filterQuality: viewport.zoom > 1.05 ? FilterQuality.medium : FilterQuality.low),
                ),
              ),
            ),
          if (controller.live && controller.cursorVisible)
            Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: DesktopCursorPainter(controller, viewport))),
            ),
        ],
      ),
    );
  }
}

/// Shown until the first picture arrives.
class _Starting extends StatelessWidget {
  const _Starting({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: colors.background,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.accent)),
              const SizedBox(height: 16),
              Text('Starting the desktop on $title', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('gliff over SSH', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small pill at the top that brings the toolbar back.
class _Handle extends StatelessWidget {
  const _Handle({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Semantics(
      button: true,
      label: 'Show toolbar',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          // A generous target around a slim handle.
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Container(
            width: 56,
            height: 6,
            decoration: BoxDecoration(color: colors.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(3)),
          ),
        ),
      ),
    );
  }
}
