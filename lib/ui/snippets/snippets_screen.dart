import 'package:flutter/material.dart';

import '../../app/app_motion.dart';
import '../../app/app_scope.dart';
import '../../data/models.dart';
import '../common/widgets.dart';
import '../keys/page_width.dart';
import 'snippet_blanks_sheet.dart';
import 'snippet_editor_screen.dart';
import 'snippet_list.dart';
import 'snippet_picker_sheet.dart';
import 'snippet_runner.dart';

/// Saved commands, with search. Tap one to edit it; the play button runs
/// it on a saved host.
class SnippetsScreen extends StatefulWidget {
  const SnippetsScreen({super.key});

  @override
  State<SnippetsScreen> createState() => _SnippetsScreenState();
}

class _SnippetsScreenState extends State<SnippetsScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _create() => SnippetEditorScreen.open(context);

  Future<void> _run(Snippet snippet) async {
    final command = await SnippetBlanks.fill(context, snippet);
    if (command != null && mounted) await SnippetRunner.run(context, name: snippet.name, command: command);
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    return ListenableBuilder(
      listenable: Listenable.merge([store, _query]),
      builder: (context, _) {
        final all = store.snippets;
        final shown = SnippetFilter.apply(all, _query.text);
        return Scaffold(
          appBar: AppBar(title: const Text('Snippets')),
          floatingActionButton: all.isEmpty
              ? null
              : FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('New snippet')),
          body: all.isEmpty
              ? EmptyState(
                  icon: Icons.bolt_outlined,
                  title: 'No snippets yet',
                  message: 'Save commands you type often. Insert them into a terminal with one tap, or run them on a host.',
                  actionLabel: 'New snippet',
                  onAction: _create,
                )
              : PageWidth(
                  child: Column(
                    children: [
                      SnippetSearchField(controller: _query),
                      Expanded(
                        child: shown.isEmpty
                            ? Align(
                                alignment: Alignment.topCenter,
                                child: NoSnippetMatches(query: _query.text, onClear: _query.clear),
                              )
                            : SnippetListView(
                                snippets: shown,
                                tileFor: (snippet) => SnippetTile(
                                  snippet: snippet,
                                  onTap: () => SnippetEditorScreen.open(context, snippet: snippet),
                                  trailing: IconButton(
                                    tooltip: 'Run on a host',
                                    icon: const Icon(Icons.play_arrow_outlined),
                                    onPressed: () => _run(snippet),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

/// Bottom sheet to pick a snippet to run in a terminal. Returns the chosen
/// snippet, or null if the sheet was closed.
abstract final class SnippetPicker {
  static Future<Snippet?> show(BuildContext context) {
    return showModalBottomSheet<Snippet>(
      context: context,
      sheetAnimationStyle: AppMotion.of(context).sheet,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const SnippetPickerSheet(),
    );
  }
}
