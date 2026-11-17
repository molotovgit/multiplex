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

/// The words and pictures of a cast page.
class _Kind {
  const _Kind({
    required this.title,
    required this.icon,
    required this.liveIcon,
    required this.offer,
    required this.live,
    required this.before,
    required this.during,
    required this.start,
    required this.stop,
  });

  final String title;
  final IconData icon;
  final IconData liveIcon;

  /// With the computer's name: what can be started, and what is running.
  final String Function(String computer) offer;
  final String Function(String computer) live;
  final String before;
  final String during;
  final String start;
  final String stop;

  static final screen = _Kind(
    title: 'Phone screen',
    icon: Icons.cast,
    liveIcon: Icons.cast_connected,
    offer: (computer) => 'Show this phone\'s screen on $computer',
    live: (computer) => 'This phone\'s screen is showing on $computer',
    before: 'A window opens on the computer with what is on this screen. Android asks first, and shows that the screen is being shared.',
    during: 'Leave Multiplex and use the phone: the window follows. Close the window on the computer, or stop here.',
    start: 'Show the screen',
    stop: 'Stop showing',
  );

  static final camera = _Kind(
    title: 'Camera',
    icon: Icons.videocam_outlined,
    liveIcon: Icons.videocam,
    offer: (computer) => 'Use this phone as a camera for $computer',
    live: (computer) => '$computer is using this phone\'s camera',
    before: 'The computer gets a camera with this phone\'s name, for calls and recordings there. Hold the phone the way the picture should be: it is set when you start.',
    during: 'Pick the camera named after this phone in the program on the computer. It is there until you stop.',
    start: 'Start the camera',
    stop: 'Stop the camera',
  );
}

/// A picture from this phone on a paired computer: start it, see that it
/// is running, stop it. Either the phone's screen in a window there
/// ([ScreenCastScreen.show]) or its camera as a webcam there
/// ([ScreenCastScreen.showCamera]).
class ScreenCastScreen extends StatelessWidget {
  const ScreenCastScreen({super.key, required this.host, required this.open, this.startBitrate = 4000000, this.cast, this.camera});

  final Host host;

  /// Opens the computer's end. Tests pass a stand-in.
  final Future<ScreenWindow> Function() open;

  /// What the encoder starts at, in bits per second.
  final int startBitrate;
  final PhoneCast? cast;

  /// Set for the camera page: the choice between its cameras lives there.
  final CameraCapture? camera;

  /// Connects (if needed) and opens the page for the phone's screen.
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

  /// Connects (if needed) and opens the page for the phone's camera.
  static Future<void> showCamera(BuildContext context, Host host) async {
    final LiveSession? session = await HostConnector.connect(context, host);
    if (session == null || !context.mounted) return;
    final camera = PhoneCast.phoneCamera;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScreenCastScreen(
          host: host,
          cast: PhoneCast.camera,
          camera: camera,
          startBitrate: screenStartBitrate(),
          open: () async => _SshWindow(await session.ssh.openCamera(phone: host.pairedAs ?? '', turn: await camera.turn())),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cast = this.cast ?? PhoneCast.screen;
    final kind = camera == null ? _Kind.screen : _Kind.camera;
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(kind.title)),
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
                Icon(showing ? kind.liveIcon : kind.icon, size: 56, color: showing ? colors.live : colors.accent),
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(showing ? kind.live(cast.showingOn!.title) : kind.offer(host.title), style: text.titleLarge, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 8),
                Text(
                  showing ? kind.during : kind.before,
                  style: text.bodyMedium?.copyWith(color: colors.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (camera != null) ...[_CameraChoice(camera: camera!, enabled: !showing && !cast.starting), const SizedBox(height: 16)],
                if (cast.problem != null) ...[NoticeBox(tone: NoticeTone.error, text: cast.problem!), const SizedBox(height: 16)],
                if (showing)
                  FilledButton.tonalIcon(onPressed: () => unawaited(cast.stop()), icon: const Icon(Icons.stop_circle_outlined), label: Text(kind.stop))
                else
                  FilledButton.icon(
                    onPressed: cast.starting || elsewhere ? null : () => unawaited(cast.start(host, open, bitrate: startBitrate)),
                    icon: Icon(kind.icon),
                    label: Text(cast.starting ? 'Starting…' : kind.start),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Back camera or the one on the screen's side. Fixed while it runs.
class _CameraChoice extends StatefulWidget {
  const _CameraChoice({required this.camera, required this.enabled});

  final CameraCapture camera;
  final bool enabled;

  @override
  State<_CameraChoice> createState() => _CameraChoiceState();
}

class _CameraChoiceState extends State<_CameraChoice> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, icon: Icon(Icons.camera_rear_outlined), label: Text('Back camera')),
          ButtonSegment(value: true, icon: Icon(Icons.camera_front_outlined), label: Text('Front camera')),
        ],
        selected: {widget.camera.front},
        onSelectionChanged: widget.enabled ? (picked) => setState(() => widget.camera.front = picked.first) : null,
      ),
    );
  }
}
