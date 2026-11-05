import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../src/rust/api/sftp_types.dart';
import '../common/widgets.dart';
import 'file_format.dart';
import 'files_widgets.dart';

/// Changes who may read, write and run a file. The tick boxes and the
/// number ("644") stay in step: change one and the other follows.
class PermissionsDialog extends StatefulWidget {
  const PermissionsDialog({super.key, required this.name, required this.mode, required this.kind, this.note});

  final String name;
  final int mode;
  final EntryKind kind;

  /// An extra line, for example that a link's target is what changes.
  final String? note;

  /// Returns the new mode, or null when the user cancels.
  static Future<int?> show(BuildContext context, {required String name, required int mode, required EntryKind kind, String? note}) =>
      showDialog<int>(
        context: context,
        builder: (_) => PermissionsDialog(name: name, mode: mode, kind: kind, note: note),
      );

  @override
  State<PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<PermissionsDialog> {
  static const _who = ['Owner', 'Group', 'Others'];
  static const _what = ['Read', 'Write', 'Execute'];

  /// Each tick box is 48 wide, so 56 leaves 8 between neighbours.
  static const _boxColumn = FixedColumnWidth(56);

  late int _mode = widget.mode & FileModes.mask;
  late final _number = TextEditingController(text: FileModes.octal(_mode));

  /// Null while the number is a valid mode.
  String? _error;

  /// False while the number is half typed ("6", "64").
  bool _complete = true;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  void _toggle(int bit) {
    setState(() {
      _mode ^= bit;
      _number.text = FileModes.octal(_mode);
      _error = null;
      _complete = true;
    });
  }

  void _typed(String text) {
    final parsed = FileModes.parseOctal(text);
    setState(() {
      if (parsed != null) {
        _mode = parsed;
        _error = null;
        _complete = true;
        return;
      }
      _complete = false;
      // Only complain about real mistakes, not about a number still being typed.
      final halfTyped = RegExp(r'^[0-7]{0,2}$').hasMatch(text.trim());
      _error = halfTyped ? null : 'Use three or four digits from 0 to 7, for example 644 or 755.';
    });
  }

  void _submit() {
    if (_complete && _error == null) Navigator.pop(context, _mode);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final note = widget.note;
    return AlertDialog(
      title: Text('Permissions for "${widget.name}"', maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note != null) ...[Text(note, style: text.bodyMedium?.copyWith(color: colors.muted)), const SizedBox(height: 12)],
            Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const {1: _boxColumn, 2: _boxColumn, 3: _boxColumn},
              children: [
                TableRow(
                  children: [
                    const SizedBox.shrink(),
                    for (final what in _what) Center(child: Text(what, style: text.bodySmall?.copyWith(color: colors.muted))),
                  ],
                ),
                for (var row = 0; row < 3; row++)
                  TableRow(
                    children: [
                      Text(_who[row]),
                      for (var col = 0; col < 3; col++)
                        Center(
                          child: Checkbox(
                            semanticLabel: '${_who[row]} can ${_what[col].toLowerCase()}',
                            value: _mode & FileModes.bits[row * 3 + col] != 0,
                            onChanged: (_) => _toggle(FileModes.bits[row * 3 + col]),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _number,
              style: MonoStyle.of(context),
              keyboardType: TextInputType.number,
              maxLength: 4,
              onChanged: _typed,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'As a number',
                helperText: 'Owner, group, others: 4 read + 2 write + 1 execute',
                helperMaxLines: 2,
                errorText: _error,
                errorMaxLines: 3,
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Shown as ', style: text.bodyMedium?.copyWith(color: colors.muted)),
                MonoText(FileModes.describe(_mode, widget.kind)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _complete && _error == null ? _submit : null, child: const Text('Change permissions')),
      ],
    );
  }
}
