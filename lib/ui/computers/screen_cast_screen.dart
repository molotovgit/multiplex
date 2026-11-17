import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../sessions/screen_cast.dart';
import '../../sessions/session_manager.dart';
import '../../src/rust/api/screen.dart';
import '../hosts/host_connector.dart';
import '../settings/settings_widgets.dart';

/// The real window: a stream to `multiplex screen` on the computer.
class _SshWindow extends ScreenWindow {
  _SshWindow(this._stream);

  final ScreenStream _stream;

  @override
  ScreenWrote write(Uint8List bytes) {
    final wrote = _stream.write(bytes: bytes);
    return ScreenWrote(ended: wrote.ended, reason: wrote.reason, bitrate: wrote.bitrate, keyFrame: wrote.keyFrame);
  }

  @override
  Stream<String> get ended => _stream.ended();

  @override
  String? status() {
    final now = _stream.status();
    return 'kbps=${now.bitrate ~/ 1000} inflight_kb=${now.inFlight ~/ BigInt.from(1024)} skipped=${now.skipped}${now.skipping ? ' skipping' : ''}';
  }

  @override
  void close() => _stream.close();
}

/// Show this phone's screen in a window on a paired computer: start it,
/// see that it is running, stop it.
class ScreenCastScreen extends StatelessWidget {
  const ScreenCastScreen({super.key, required this.host, required this.open, this.startBitrate = 4000000, this.cast});

  final Host host;

  /// Opens the window on the computer. Tests pass a stand-in.
  final Future<ScreenWindow> Function() open;

  /// What the encoder starts at, in bits per second.
  final int startBitrate;
  final ScreenCast? cast;

  /// Connects (if needed) and opens this page.
  static Future<void> show(BuildContext context, Host host) async {
    final LiveSession? session = await HostConnector.connect(context, host);
    if (session == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScreenCastScreen(
          host: host,
          startBitrate: screenStartBitrate(),
          open: () async => _SshWindow(await session.ssh.openScreen(phone: host.pairedAs ?? '')),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cast = this.cast ?? ScreenCast.app;
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Phone screen')),
      body: ContentWidth(
        child: ListenableBuilder(
          listenable: cast,
          builder: (context, _) {
            final showing = cast.showingOn != null;
            final elsewhere = showing && cast.showingOn!.id != host.id;
            return ListView(
              padding: const EdgeInsets.all(SettingsLayout.gutter),
              children: [
                const SizedBox(height: 16),
                Icon(showing ? Icons.cast_connected : Icons.cast, size: 56, color: showing ? colors.live : colors.accent),
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    showing ? 'This phone\'s screen is showing on ${cast.showingOn!.title}' : 'Show this phone\'s screen on ${host.title}',
                    style: text.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  showing
                      ? 'Leave Multiplex and use the phone: the window follows. Close the window on the computer, or stop here.'
                      : 'A window opens on the computer with what is on this screen. Android asks first, and shows that the screen is being shared.',
                  style: text.bodyMedium?.copyWith(color: colors.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (cast.problem != null) ...[NoticeBox(tone: NoticeTone.error, text: cast.problem!), const SizedBox(height: 16)],
                if (showing)
                  FilledButton.tonalIcon(
                    onPressed: () => unawaited(cast.stop()),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop showing'),
                  )
                else
                  FilledButton.icon(
                    onPressed: cast.starting || elsewhere ? null : () => unawaited(cast.start(host, open, bitrate: startBitrate)),
                    icon: const Icon(Icons.cast),
                    label: Text(cast.starting ? 'Starting…' : 'Show the screen'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
