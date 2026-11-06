import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_scope.dart';

/// Keeps terminals and the keychain out of screenshots, screen recordings
/// and the recent-apps preview, using Android's FLAG_SECURE through a small
/// native call. Other platforms ignore it.
///
/// Screens that show secrets [hold] it while they are visible and
/// [release] it when they go; the flag is on while at least one holds it
/// and the "Hide terminals from screenshots" setting is on.
class ScreenPrivacy {
  ScreenPrivacy([this._channel = const MethodChannel('multiplex/privacy')]);

  /// The one the app uses; tests put a fresh one here.
  static ScreenPrivacy instance = ScreenPrivacy();

  final MethodChannel _channel;
  int _holders = 0;
  bool _enabled = true;
  bool _secure = false;

  /// Whether the window is hidden from screenshots now.
  bool get secure => _secure;

  void hold() {
    _holders++;
    _sync();
  }

  void release() {
    if (_holders > 0) _holders--;
    _sync();
  }

  /// The user's setting. Turning it off shows screens in screenshots again
  /// straight away.
  set enabled(bool on) {
    _enabled = on;
    _sync();
  }

  Future<void> _sync() async {
    final want = _enabled && _holders > 0;
    if (want == _secure) return;
    _secure = want;
    try {
      await _channel.invokeMethod<void>('setSecure', {'on': want});
    } on MissingPluginException {
      // Desktop and iOS builds have no handler: nothing to do.
    } on PlatformException {
      // Never let this break the screen that asked for it.
    }
  }
}

/// Hides [child] from screenshots while it is on screen and [active].
/// Follows the setting as it changes.
class PrivateScreen extends StatefulWidget {
  const PrivateScreen({super.key, this.active = true, this.privacy, required this.child});

  /// False while the screen is kept alive but not shown (another tab).
  final bool active;

  /// Defaults to [ScreenPrivacy.instance].
  final ScreenPrivacy? privacy;
  final Widget child;

  @override
  State<PrivateScreen> createState() => _PrivateScreenState();
}

class _PrivateScreenState extends State<PrivateScreen> {
  late final ScreenPrivacy _privacy = widget.privacy ?? ScreenPrivacy.instance;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _privacy.enabled = AppScope.store(context).settings.hideScreens;
    _follow(widget.active);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Redrawn when the setting changes.
    _privacy.enabled = AppScope.watch(context).settings.hideScreens;
  }

  @override
  void didUpdateWidget(PrivateScreen old) {
    super.didUpdateWidget(old);
    _follow(widget.active);
  }

  @override
  void dispose() {
    _follow(false);
    super.dispose();
  }

  void _follow(bool active) {
    if (active == _holding) return;
    _holding = active;
    active ? _privacy.hold() : _privacy.release();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
