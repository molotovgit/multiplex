import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../data/sync_pairs.dart';
import '../../../data/vault_store.dart';
import '../../common/widgets.dart';
import '../file_format.dart';
import '../files_widgets.dart';
import '../two_pane/phone_storage.dart';

/// Makes or changes a sync pair: a name, the two folders, the direction
/// and, for one-way pairs only, whether extra files are deleted.
class SyncPairEditor extends StatefulWidget {
  const SyncPairEditor({super.key, required this.hostId, this.pair, this.serverPath = '', this.pickFolder});

  final String hostId;
  final SyncPair? pair;

  /// Where a new pair's server folder starts: the folder open in Files.
  final String serverPath;

  /// Picks a phone folder; tests pass a fake.
  final Future<String?> Function()? pickFolder;

  /// Returns the saved pair, or null when the user backed out.
  static Future<SyncPair?> show(BuildContext context, {required String hostId, SyncPair? pair, String serverPath = '', Future<String?> Function()? pickFolder}) =>
      Navigator.push<SyncPair>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => SyncPairEditor(hostId: hostId, pair: pair, serverPath: serverPath, pickFolder: pickFolder),
        ),
      );

  @override
  State<SyncPairEditor> createState() => _SyncPairEditorState();
}

class _SyncPairEditorState extends State<SyncPairEditor> {
  late final _name = TextEditingController(text: widget.pair?.name ?? '');
  late final _phone = TextEditingController(text: widget.pair?.phonePath ?? '');
  late final _server = TextEditingController(text: widget.pair?.serverPath ?? widget.serverPath);
  late SyncWay _way = widget.pair?.way ?? SyncWay.toServer;
  late bool _mirror = widget.pair?.mirror ?? false;
  bool _tried = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _server.dispose();
    super.dispose();
  }

  String? get _nameProblem => _name.text.trim().isEmpty ? 'Give the pair a name, such as "Photos backup".' : null;
  String? get _phoneProblem => _phone.text.trim().isEmpty ? 'Choose a folder on this phone.' : null;
  String? get _serverProblem => _server.text.trim().startsWith('/') ? null : 'Type a full path on the server, starting with /.';

  Future<void> _pickPhone() async {
    try {
      final picked = await (widget.pickFolder ?? FilePicker.getDirectoryPath)();
      if (picked != null) setState(() => _phone.text = picked);
    } catch (error) {
      if (mounted) Toast.show(context, 'Could not open the folder picker. ${FileErrors.message(error)}');
    }
  }

  Future<void> _setMirror(bool on) async {
    if (on) {
      final sure = await Confirm.ask(
        context,
        title: 'Delete extra files?',
        message: 'With mirror on, each sync deletes files and folders on the ${_way == SyncWay.toServer ? 'server' : 'phone'} '
            'that are not in the source folder. You still see the list before anything is deleted.',
        action: 'Turn on mirror',
      );
      if (!sure) return;
    }
    if (mounted) setState(() => _mirror = on);
  }

  void _save() {
    setState(() => _tried = true);
    if (_nameProblem != null || _phoneProblem != null || _serverProblem != null) return;
    final base = widget.pair ?? SyncPair(id: VaultStore.newId(), hostId: widget.hostId, name: '', phonePath: '', serverPath: '');
    Navigator.pop(
      context,
      base.copyWith(name: _name.text.trim(), phonePath: _phone.text.trim(), serverPath: _server.text.trim(), way: _way, mirror: _mirror && _way != SyncWay.both),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final mono = MonoStyle.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pair == null ? 'New sync pair' : 'Edit sync pair'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: SafeArea(
        top: false,
        child: FilesWidth(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: 'Name', errorText: _tried ? _nameProblem : null),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _phone,
                      style: mono,
                      decoration: InputDecoration(labelText: 'Phone folder', errorText: _tried ? _phoneProblem : null),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(tooltip: 'Choose phone folder', icon: const Icon(Icons.folder_open), onPressed: _pickPhone),
                ],
              ),
              if (PhoneStorage.supportsAccess)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Folders outside the app\'s own files need Android\'s "All files access" for Multiplex.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted),
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _server,
                style: mono,
                decoration: InputDecoration(labelText: 'Server folder', hintText: '/var/www/site', errorText: _tried ? _serverProblem : null),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),
              Text('Direction', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final way in SyncWay.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(way == _way ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: way == _way ? colors.accent : colors.muted),
                  title: Text(way.label),
                  selected: way == _way,
                  onTap: () => setState(() => _way = way),
                ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _mirror && _way != SyncWay.both,
                onChanged: _way == SyncWay.both ? null : (on) => _setMirror(on ?? false),
                title: const Text('Mirror (delete extra files)'),
                subtitle: Text(
                  _way == SyncWay.both ? 'Not for two-way syncs: nothing is ever deleted.' : 'Off: nothing is ever deleted. On: the target ends up an exact copy.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
