import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../sessions/recordings.dart';
import '../common/widgets.dart';
import 'cast_player_screen.dart';

/// Saved terminal recordings: play them back, save a copy elsewhere, or
/// delete them.
class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key, this.library});

  final RecordingLibrary? library;

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  late final _library = widget.library ?? RecordingLibrary();
  late Future<List<Recording>> _list = _library.list();

  void _reload() => setState(() => _list = _library.list());

  Future<void> _play(Recording recording) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CastPlayerScreen(recording: recording)));
  }

  Future<void> _delete(Recording recording) async {
    final ok = await Confirm.ask(context, title: 'Delete this recording?', message: recording.label, action: 'Delete');
    if (!ok) return;
    await _library.delete(recording);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Recordings')),
      body: FutureBuilder<List<Recording>>(
        future: _list,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Could not read the recordings: ${snapshot.error}'));
          final list = snapshot.data;
          if (list == null) return const Center(child: CircularProgressIndicator());
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.fiber_manual_record_outlined,
              title: 'No recordings yet',
              message: 'In a terminal, open the ⋮ menu and choose Record. What the terminal shows is saved with its timing, and you can play it back here.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final r = list[i];
              return ListTile(
                leading: Icon(Icons.play_circle_outline, color: colors.accent),
                title: Text(r.label),
                subtitle: Text(RecordingText.size(r.bytes), style: text.bodySmall?.copyWith(color: colors.muted)),
                onTap: () => _play(r),
                trailing: PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (action) => switch (action) {
                    'export' => RecordingExport.save(context, r),
                    _ => _delete(r),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'export', child: ListTile(leading: Icon(Icons.save_alt), title: Text('Save as file'))),
                    PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete'))),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

abstract final class RecordingText {
  /// "812 bytes", "14 KB", "2.3 MB".
  static String size(int bytes) {
    if (bytes < 1024) return '$bytes bytes';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Saves a copy of a recording where the user picks (Downloads, a cloud
/// folder), to share it or play it with asciinema on a computer.
abstract final class RecordingExport {
  static Future<void> save(BuildContext context, Recording recording) async {
    try {
      final saved = await FilePicker.saveFile(
        fileName: recording.name,
        bytes: await recording.file.readAsBytes(),
        mimeType: 'application/x-asciicast',
        dialogTitle: 'Save recording',
      );
      if (saved != null && context.mounted) Toast.show(context, 'Saved ${recording.name}');
    } catch (e) {
      if (context.mounted) Toast.show(context, 'Could not save the file ($e). Try another folder.');
    }
  }
}
