import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../app/theme_look.dart';
import 'terminal_search.dart';

/// The "find in terminal" bar above the text: a box to type in, "3 of 12",
/// match case, older and newer match, and close.
///
/// Enter goes to the next older match (searches usually look back),
/// Shift+Enter to the next newer one, Escape closes the bar.
class TerminalSearchBar extends StatefulWidget {
  const TerminalSearchBar({super.key, required this.search, required this.onClose});

  final TerminalSearch search;

  /// Called after the bar closed, so the terminal can take the focus back.
  final VoidCallback onClose;

  static const height = 52.0;

  @override
  State<TerminalSearchBar> createState() => _TerminalSearchBarState();
}

class _TerminalSearchBarState extends State<TerminalSearchBar> {
  late final _text = TextEditingController(text: widget.search.query);
  final _focus = FocusNode(debugLabel: 'terminal search');

  TerminalSearch get _search => widget.search;

  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = _onKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      HardwareKeyboard.instance.isShiftPressed ? _search.next() : _search.previous();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Four buttons must fit next to the box on a narrow phone, so they
  /// keep only the minimum touch size.
  static final _compact = IconButton.styleFrom(minimumSize: const Size(44, 44), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap);

  void _close() {
    _search.close();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final look = AppStyleTheme.of(context);
    return Material(
      color: look.surfaces.bar,
      shape: Border(bottom: look.surfaces.side == BorderSide.none ? BorderSide.none : BorderSide(color: colors.outline)),
      child: SizedBox(
        height: TerminalSearchBar.height,
        child: ListenableBuilder(
          listenable: _search,
          builder: (context, _) {
            final hasMatches = _search.matches.isNotEmpty;
            return Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    onChanged: _search.setQuery,
                    // Enter is handled in _onKey; keep the keyboard open.
                    onSubmitted: (_) => _focus.requestFocus(),
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration.collapsed(hintText: 'Find in terminal'),
                  ),
                ),
                Semantics(
                  liveRegion: true,
                  child: Text(_search.counter, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.muted)),
                ),
                const SizedBox(width: 4),
                IconButton(
                  style: _compact,
                  tooltip: _search.caseSensitive ? 'Match case: on' : 'Match case: off',
                  isSelected: _search.caseSensitive,
                  onPressed: _search.toggleCaseSensitive,
                  icon: const Icon(Icons.text_fields),
                  selectedIcon: Icon(Icons.text_fields, color: colors.accent),
                ),
                IconButton(style: _compact, tooltip: 'Older match', onPressed: hasMatches ? _search.previous : null, icon: const Icon(Icons.keyboard_arrow_up)),
                IconButton(style: _compact, tooltip: 'Newer match', onPressed: hasMatches ? _search.next : null, icon: const Icon(Icons.keyboard_arrow_down)),
                IconButton(style: _compact, tooltip: 'Close search', onPressed: _close, icon: const Icon(Icons.close)),
              ],
            );
          },
        ),
      ),
    );
  }
}
