import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../src/rust/api/tailscale.dart';
import '../src/rust/api/tailscale_types.dart';
import 'connect_flow.dart';

/// Tailscale built into the app: one node for the whole app, which joins
/// the user's tailnet without the Tailscale VPN app. Hosts marked "Connect
/// through Tailscale" go through it, from home or anywhere else.
///
/// The node starts the first time it is needed (or at launch when a host
/// uses it) and keeps running; signing in is needed once per phone.
class TailscaleNode extends ChangeNotifier {
  TailscaleNode._();

  static final instance = TailscaleNode._();

  /// The name this phone gets on the tailnet.
  static const hostname = 'multiplex-phone';

  TailscaleStatus? status;

  /// An error as one readable line (no wrapper names or backtraces).
  static String clean(Object e) {
    var text = '$e';
    final trace = text.indexOf('Stack backtrace');
    if (trace >= 0) text = text.substring(0, trace);
    text = text.replaceFirst(RegExp(r'^(AnyhowException|Exception)\(?'), '').trim();
    if (text.endsWith(')')) text = text.substring(0, text.length - 1);
    return text.replaceFirst(RegExp(r'^tsnet: '), '').trim();
  }

  /// Why starting or signing in failed, for the screen to show.
  String? problem;
  bool _started = false;
  Future<void>? _starting;
  Timer? _poll;
  int _watchers = 0;

  /// This build carries Tailscale (Android builds with the library).
  bool get available {
    try {
      return tailscaleAvailable();
    } catch (_) {
      return false;
    }
  }

  bool get running => status?.state == 'Running';
  bool get needsLogin => status?.state == 'NeedsLogin' || status?.state == 'NeedsMachineAuth';

  /// Starts the node once; later calls wait for the same start.
  Future<void> ensureStarted() => _starting ??= _start();

  Future<void> _start() async {
    try {
      final base = await getApplicationSupportDirectory();
      await tailscaleStart(dir: '${base.path}/tailscale', hostname: hostname);
      _started = true;
      problem = null;
      await refresh();
    } catch (e) {
      _starting = null;
      problem = clean(e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> refresh() async {
    if (!_started) return;
    try {
      status = await tailscaleStatus();
    } catch (e) {
      problem = clean(e);
    }
    notifyListeners();
  }

  /// For a connection: the node running and signed in, within [limit],
  /// or a [ConnectFailure] that says what to do.
  Future<void> ensureRunning({Duration limit = const Duration(seconds: 12)}) async {
    if (!available) {
      throw const ConnectFailure('Tailscale is not available', 'This build of Multiplex does not include Tailscale.');
    }
    try {
      await ensureStarted();
    } catch (e) {
      throw ConnectFailure('Tailscale could not start', clean(e));
    }
    final until = DateTime.now().add(limit);
    while (true) {
      await refresh();
      if (running) return;
      if (needsLogin) {
        throw const ConnectFailure('Sign in to Tailscale first', 'Open Settings, then Tailscale, and sign in. You only do this once on this phone.');
      }
      if (DateTime.now().isAfter(until)) {
        throw ConnectFailure('Tailscale is not connected', 'It is still starting (${status?.state ?? 'no state'}). Check the network and try again.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  /// Signs in: returns the page to open, once Tailscale has made one.
  Future<Uri?> startSignIn() async {
    await ensureStarted();
    problem = null;
    await tailscaleLogin();
    for (var i = 0; i < 40; i++) {
      await refresh();
      final url = status?.authUrl ?? '';
      if (url.isNotEmpty) return Uri.tryParse(url);
      if (running) return null;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    problem = 'Tailscale did not offer a sign-in page. Check the network and try again.';
    notifyListeners();
    return null;
  }

  Future<void> signOut() async {
    await tailscaleLogout();
    await refresh();
  }

  /// Keeps the status fresh while a screen shows it.
  void watch() {
    _watchers++;
    _poll ??= Timer.periodic(const Duration(seconds: 2), (_) => refresh());
    unawaited(refresh());
  }

  void unwatch() {
    _watchers = (_watchers - 1).clamp(0, 1 << 20);
    if (_watchers == 0) {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// The device a host address points at, if it is on the tailnet.
  TailscaleDevice? deviceFor(String address) {
    final a = address.toLowerCase();
    for (final d in status?.devices ?? const <TailscaleDevice>[]) {
      if (d.name.toLowerCase() == a || d.dnsName.toLowerCase() == a || d.dnsName.toLowerCase().startsWith('$a.') || d.ips.contains(address)) return d;
    }
    return null;
  }
}
