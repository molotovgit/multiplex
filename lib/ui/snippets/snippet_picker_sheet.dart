import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../common/widgets.dart';
import 'snippet_editor_screen.dart';
import 'snippet_list.dart';

/// A bottom sheet for choosing a snippet to insert into a terminal.
/// Closes with the chosen snippet.
class SnippetPickerSheet extends StatefulWidget {
  const SnippetPickerSheet({super.key});

  @override
  State<SnippetPickerSheet> createState() => _SnippetPickerSheetState();
}

class _SnippetPickerSheetState extends State<SnippetPickerSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Makes a snippet on the spot and inserts it right away.
  Future<void> _create() async {
    final created = await SnippetEditorScreen.open(context);
    if (created != null && mounted) Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    final media = MediaQuery.of(context);
    return Padding(
      // Stay above the on-screen keyboard while searching.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      // The sheet only keeps clear of the top; this keeps the list clear of
      // the gesture bar at the bottom.
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.75),
          child: ListenableBuilder(
            listenable: Listenable.merge([store, _query]),
            builder: (context, _) {
              final all = store.snippets;
              final shown = SnippetFilter.apply(all, _query.text);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Text('Insert a snippet', style: Theme.of(context).textTheme.titleLarge),
                  ),
                  if (all.isEmpty)
                    EmptyState(
                      icon: Icons.bolt_outlined,
                      title: 'No snippets yet',
                      message: 'Snippets are commands you save once and insert with one tap.',
                      actionLabel: 'New snippet',
                      onAction: _create,
                    )
                  else ...[
                    SnippetSearchField(controller: _query),
                    if (shown.isEmpty)
                      NoSnippetMatches(query: _query.text, onClear: _query.clear)
                    else
                      Flexible(
                        child: SnippetListView(
                          shrinkWrap: true,
                          snippets: shown,
                          tileFor: (snippet) => SnippetTile(
                            snippet: snippet,
                            trailing: snippet.runImmediately ? const RunsImmediatelyIcon() : null,
                            onTap: () => Navigator.pop(context, snippet),
                          ),
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Marks snippets that press Enter by themselves.
class RunsImmediatelyIcon extends StatelessWidget {
  const RunsImmediatelyIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Runs right away',
      child: Icon(Icons.keyboard_return, size: 20, color: AppColorsTheme.of(context).muted, semanticLabel: 'Runs right away'),
    );
  }
}
