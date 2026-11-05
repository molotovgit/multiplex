import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../common/widgets.dart';
import '../keys/page_width.dart';

/// Search for snippets by name or command.
abstract final class SnippetFilter {
  /// True when every word of [query] appears in the name or the command,
  /// ignoring case. An empty query matches everything.
  static bool matches(Snippet snippet, String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final haystack = '${snippet.name}\n${snippet.command}'.toLowerCase();
    return words.every(haystack.contains);
  }

  static List<Snippet> apply(List<Snippet> snippets, String query) => snippets.where((s) => matches(s, query)).toList();
}

/// How a command looks in a one-line list row.
abstract final class SnippetText {
  /// The first line, with a "…" when there are more lines.
  static String preview(String command) {
    final lines = command.trim().split('\n');
    return lines.length > 1 ? '${lines.first.trimRight()} …' : lines.first;
  }
}

/// The search box above a snippet list.
class SnippetSearchField extends StatelessWidget {
  const SnippetSearchField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => TextField(
          controller: controller,
          autocorrect: false,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search by name or command',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(tooltip: 'Clear search', icon: const Icon(Icons.close), onPressed: controller.clear),
          ),
        ),
      ),
    );
  }
}

/// One snippet: its name and the start of its command.
class SnippetTile extends StatelessWidget {
  const SnippetTile({super.key, required this.snippet, required this.onTap, this.trailing});

  final Snippet snippet;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return ListTile(
      leading: const Icon(Icons.bolt_outlined),
      title: Text(snippet.name.isEmpty ? 'Untitled snippet' : snippet.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: MonoText(
        SnippetText.preview(snippet.command),
        maxLines: 1,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// Shown when a search finds nothing.
class NoSnippetMatches extends StatelessWidget {
  const NoSnippetMatches({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'No snippets match "$query". Try another word, or clear the search.',
        textAlign: TextAlign.center,
        style: TextStyle(color: colors.muted),
      ),
    );
  }
}

/// A list of snippet rows that keeps clear of the floating button.
class SnippetListView extends StatelessWidget {
  const SnippetListView({super.key, required this.children, this.shrinkWrap = false});

  final List<Widget> children;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: shrinkWrap,
      padding: EdgeInsets.only(bottom: shrinkWrap ? 16 : PageLayout.fabClearance),
      children: children,
    );
  }
}
