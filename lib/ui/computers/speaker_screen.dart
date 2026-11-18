import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../sessions/phone_speaker.dart';
import '../../sessions/session_manager.dart';
import '../../src/rust/api/speaker.dart';
import '../hosts/host_connector.dart';
import '../settings/settings_widgets.dart';

/// The real line: the computer's sound from `multiplex speaker`.
class _SshLine implements SpeakerLine {
  _SshLine(this._stream);

  final SpeakerStream _stream;

  @override
  Stream<Uint8List> get sound => _stream.sound();

  @override
  Stream<String> get ended => _stream.ended();

  @override
  void close() => _stream.close();
}

/// Play a paired computer's sound on this phone: start it, see that it is
/// playing, stop it.
class SpeakerScreen extends StatelessWidget {
  const SpeakerScreen({super.key, required this.host, required this.open, this.speaker});

  final Host host;

  /// Opens the line to the computer. Tests pass a stand-in.
  final Future<SpeakerLine> Function(bool everything) open;
  final PhoneSpeaker? speaker;

  /// Connects (if needed) and opens this page.
  static Future<void> show(BuildContext context, Host host) async {
    final LiveSession? session = await HostConnector.connect(context, host);
    if (session == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SpeakerScreen(
          host: host,
          open: (everything) async => _SshLine(await session.ssh.openSpeaker(phone: host.pairedAs ?? '', everything: everything)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final speaker = this.speaker ?? PhoneSpeaker.app;
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Speaker')),
      body: ContentWidth(
        child: ListenableBuilder(
          listenable: speaker,
          builder: (context, _) {
            final playing = speaker.playing != null;
            final elsewhere = playing && speaker.playing!.id != host.id;
            return ListView(
              padding: const EdgeInsets.all(SettingsLayout.gutter),
              children: [
                const SizedBox(height: 16),
                Icon(playing ? Icons.volume_up : Icons.speaker_phone, size: 56, color: playing ? colors.live : colors.accent),
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    playing ? '${speaker.playing!.title}\'s sound is playing on this phone' : 'Play ${host.title}\'s sound on this phone',
                    style: text.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  playing
                      ? 'It comes out where this phone\'s media sound does, also through its headphones. The phone\'s volume keys set how loud.'
                      : 'The computer gets a sound output with this phone\'s name. What is played into it is heard here, about a quarter of a second later.',
                  style: text.bodyMedium?.copyWith(color: colors.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  value: speaker.everything,
                  onChanged: playing || speaker.starting ? null : speaker.setEverything,
                  title: Text('All of ${host.title}\'s sound'),
                  subtitle: const Text(
                    'The computer plays everything here while this is on, and goes back to its own output when you stop. Off: only what you point at this phone\'s output there.',
                  ),
                ),
                const SizedBox(height: 16),
                if (speaker.problem != null) ...[NoticeBox(tone: NoticeTone.error, text: speaker.problem!), const SizedBox(height: 16)],
                if (playing)
                  FilledButton.tonalIcon(
                    onPressed: () => unawaited(speaker.stop()),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop playing'),
                  )
                else
                  FilledButton.icon(
                    onPressed: speaker.starting || elsewhere ? null : () => unawaited(speaker.start(host, open)),
                    icon: const Icon(Icons.volume_up),
                    label: Text(speaker.starting ? 'Starting…' : 'Play the sound'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
