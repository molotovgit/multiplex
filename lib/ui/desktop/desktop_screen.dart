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
import '../common/widgets.dart';
import '../terminal/ended_banner.dart';
import '../terminal/reconnect_banner.dart';
import 'desktop_controls.dart';
import 'desktop_cursor.dart';
import 'desktop_gestures.dart';
import 'desktop_keyboard.dart';
import 'desktop_menu.dart';
import 'desktop_settings.dart';

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
  bool _keysOpen = false;
  bool _toolbarShown = true;
  Timer? _hideToolbar;
  Size _lastView = Size.zero;
  Size _lastRemote = Size.zero;

  DesktopController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    ScreenAwake.hold();
    c.addListener(_changed);
    c.copiedFromDesktop.addListener(_copied);
    _scheduleHide();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideToolbar?.cancel();
    c.removeListener(_changed);
    c.copiedFromDesktop.removeListener(_copied);
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
    setState(() => _keyboardOpen = !_keyboardOpen);
    if (_keyboardOpen) {
      _focus.requestFocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _focus.unfocus();
    }
    _scheduleHide();
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
    return via == null ? 'Direct' : 'via $via';
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
    if (_keyboardOpen && keyboardHeight == 0 && !_focus.hasFocus) _keyboardOpen = false;
    final showKeys = _keysOpen || _keyboardOpen;

    return PrivateScreen(
      child: PopScope(
        child: Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: false,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final view = constraints.biggest;
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
              final bottomInset = keyboardHeight + (showKeys ? 52 : 0);
              final visible = bottomInset > 0 ? view.height - bottomInset : null;
              if (visible != null && c.live) _viewport.follow(c.cursor, view, remote, visibleHeight: visible);

              return DesktopKeyboard(
                controller: c,
                focusNode: _focus,
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
                                  child: DesktopToolbar(
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
                                    onMore: _more,
                                  ),
                                )
                              : _Handle(key: const ValueKey('handle'), onTap: _showToolbar),
                        ),
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
                        _ when showKeys => DesktopKeyBar(controller: c, keepFocus: _keepFocus),
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
    return ClipRect(
      child: Stack(
        children: [
          if (id != null && controller.streamWidth > 0)
            Positioned(
              left: viewport.origin.dx,
              top: viewport.origin.dy,
              width: size.width,
              height: size.height,
              child: Texture(textureId: id, filterQuality: viewport.zoom > 1.05 ? FilterQuality.medium : FilterQuality.low),
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
