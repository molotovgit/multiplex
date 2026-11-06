import 'package:flutter/material.dart';

import '../../app/app_motion.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../common/widgets.dart';
import '../keys/mono_style.dart';
import 'snippet_template.dart';

/// Fills in the blanks of a snippet before it is used.
abstract final class SnippetBlanks {
  /// The command ready to insert or run. A command without blanks comes
  /// back as it is; otherwise a sheet asks for each value. Null when the
  /// user closed the sheet.
  ///
  /// With [remember], the typed values are saved with the snippet (when it
  /// is a saved one), so the sheet offers them again next time.
  static Future<String?> fill(BuildContext context, Snippet snippet, {bool remember = true}) async {
    final template = SnippetTemplate(snippet.command);
    if (!template.hasBlanks) return snippet.command;
    final store = AppScope.store(context);
    final values = await showModalBottomSheet<Map<String, String>>(
      context: context,
      sheetAnimationStyle: AppMotion.of(context).sheet,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SnippetBlanksSheet(title: snippet.name, template: template, start: template.startValues(snippet.lastValues)),
    );
    if (values == null) return null;
    final saved = store.snippets.where((s) => s.id == snippet.id).firstOrNull;
    if (remember && saved != null) store.saveSnippet(saved.copyWith(lastValues: {...saved.lastValues, ...values}));
    return template.fill(values);
  }
}

/// One field per blank, prefilled, and a live preview of the command.
/// Closes with the values by blank name.
class SnippetBlanksSheet extends StatefulWidget {
  const SnippetBlanksSheet({super.key, required this.title, required this.template, required this.start});

  final String title;
  final SnippetTemplate template;

  /// What each field starts with, by blank name.
  final Map<String, String> start;

  @override
  State<SnippetBlanksSheet> createState() => _SnippetBlanksSheetState();
}

class _SnippetBlanksSheetState extends State<SnippetBlanksSheet> {
  late final _fields = {for (final blank in widget.template.blanks) blank.name: TextEditingController(text: widget.start[blank.name] ?? '')};

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _values => {for (final e in _fields.entries) e.key: e.value.text};

  void _done() => Navigator.pop(context, _values);

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final media = MediaQuery.of(context);
    final blanks = widget.template.blanks;
    return Padding(
      // Stay above the on-screen keyboard while typing.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.8),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.title.trim().isEmpty ? 'Fill in the blanks' : widget.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(blanks.length == 1 ? 'This snippet needs one value.' : 'This snippet needs ${blanks.length} values.', style: TextStyle(color: colors.muted)),
                const SizedBox(height: 12),
                for (final (i, blank) in blanks.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _fields[blank.name],
                      autofocus: i == 0,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: MonoStyle.of(context),
                      textInputAction: i == blanks.length - 1 ? TextInputAction.done : TextInputAction.next,
                      onSubmitted: i == blanks.length - 1 ? (_) => _done() : null,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: blank.name,
                        helperText: blank.defaultValue.isEmpty ? null : 'Default: ${blank.defaultValue}',
                      ),
                    ),
                  ),
                Text('Command', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.muted)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: colors.raised, borderRadius: BorderRadius.circular(8)),
                  child: MonoText(widget.template.fill(_values)),
                ),
                const SizedBox(height: 16),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowAlignment: OverflowBarAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                    FilledButton(onPressed: _done, child: const Text('Use these values')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
