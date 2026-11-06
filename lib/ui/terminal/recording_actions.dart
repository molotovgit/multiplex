import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../sessions/recordings.dart';
import '../../sessions/terminal_controller.dart';
import '../common/widgets.dart';

/// Starting and stopping a terminal recording from the terminal screen.
abstract final class RecordingActions {
  static Future<void> toggle(BuildContext context, TerminalController terminal, {RecordingLibrary? library}) async {
    if (terminal.recording) {
      terminal.stopRecording();
      Toast.show(context, 'Recording saved. Find it in Sessions > Recordings.');
      return;
    }
    try {
      final path = await (library ?? RecordingLibrary()).newPath(terminal.title);
      terminal.startRecording(path);
      if (context.mounted) Toast.show(context, 'Recording. Password prompts are left out.');
    } catch (e) {
      if (context.mounted) Toast.show(context, 'Could not start recording: $e');
    }
  }
}

/// A red dot in the app bar while recording; a tap stops it.
class RecordingButton extends StatelessWidget {
  const RecordingButton({super.key, required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return IconButton(
      tooltip: 'Stop recording',
      icon: Icon(Icons.fiber_manual_record, color: colors.danger),
      onPressed: onStop,
    );
  }
}
