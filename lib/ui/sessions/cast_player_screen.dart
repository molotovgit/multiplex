import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../sessions/cast_file.dart';
import '../../sessions/cast_player.dart';
import '../../sessions/recordings.dart';
import '../../sessions/terminal_controller.dart';
import '../../src/rust/api/terminal.dart';
import '../terminal/terminal_view.dart';
import 'recordings_screen.dart';

/// Shows a recording on a terminal with no server behind it.
class _ShellScreen implements CastScreen {
  const _ShellScreen(this.shell);

  final RemoteShell shell;

  @override
  void feed(String text) => shell.feed(text: text);

  @override
  void resize(int cols, int rows) => shell.resize(cols: cols, rows: rows);

  @override
  void reset() => shell.resetScreen();
}

/// Plays a recording back in the terminal view, with play/pause and
/// 1x, 2x or 4x speed.
class CastPlayerScreen extends StatefulWidget {
  const CastPlayerScreen({super.key, required this.recording});

  final Recording recording;

  @override
  State<CastPlayerScreen> createState() => _CastPlayerScreenState();
}

class _CastPlayerScreenState extends State<CastPlayerScreen> {
  final _focus = FocusNode(debugLabel: 'player');
  TerminalController? _terminal;
  CastPlayer? _player;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cast = CastFile.parse(await widget.recording.file.readAsString());
      if (!mounted) return;
      final store = AppScope.store(context);
      final shell = RemoteShell.player(
        cols: cast.width,
        rows: cast.height,
        palette: store.activeTheme.palette(boldIsBright: store.settings.boldIsBright),
      );
      setState(() {
        _terminal = TerminalController(shell: shell, title: cast.title, sessionId: '', fixedSize: true);
        _player = CastPlayer(cast, _ShellScreen(shell))..play();
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    _terminal?.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final terminal = _terminal, player = _player;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recording.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Save as file',
            icon: const Icon(Icons.save_alt),
            onPressed: () => RecordingExport.save(context, widget.recording),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
          : terminal == null || player == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // Watching only: taps must not open a keyboard.
                    Expanded(child: AbsorbPointer(child: TerminalView(controller: terminal, focusNode: _focus))),
                    PlayerControls(player: player),
                  ],
                ),
    );
  }
}

/// Play/pause, speed and how far the playback is.
class PlayerControls extends StatelessWidget {
  const PlayerControls({super.key, required this.player});

  final CastPlayer player;

  static String clock(double secs) {
    final s = secs.round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: player,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: player.playing ? 'Pause' : (player.finished ? 'Play again' : 'Play'),
                  icon: Icon(player.playing ? Icons.pause : (player.finished ? Icons.replay : Icons.play_arrow)),
                  onPressed: player.toggle,
                ),
                Text('${clock(player.position)} / ${clock(player.cast.duration)}', style: TextStyle(color: colors.muted)),
                const Spacer(),
                SegmentedButton<double>(
                  showSelectedIcon: false,
                  segments: [for (final s in CastPlayer.speeds) ButtonSegment(value: s, label: Text('${s.round()}x'))],
                  selected: {player.speed},
                  onSelectionChanged: (picked) => player.setSpeed(picked.first),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
