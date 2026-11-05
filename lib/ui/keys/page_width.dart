import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Sizes used by the keychain and snippets screens. All spacing in these
/// screens sits on the 4/8 grid.
abstract final class PageLayout {
  /// Content never gets wider than this, so lines stay readable on a
  /// desktop monitor.
  static const maxWidth = 840.0;

  /// Space at the end of a list so the last row is not hidden behind the
  /// floating button.
  static const fabClearance = 96.0;

  /// How long a small change (progress turning into a result) takes to
  /// fade in, so it is clear what changed.
  static const fade = Duration(milliseconds: 200);
}

/// Centres its child and keeps it at most [PageLayout.maxWidth] wide.
class PageWidth extends StatelessWidget {
  const PageWidth({super.key, required this.child, this.fillHeight = true});

  final Widget child;

  /// True for page bodies (lists fill the screen); false for a row that
  /// should only be as tall as its content.
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: fillHeight ? null : 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PageLayout.maxWidth),
        child: child,
      ),
    );
  }
}

/// Standard side padding for one field or button row in a form, lined up
/// with list tiles and section headers.
class FormRow extends StatelessWidget {
  const FormRow({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: child);
  }
}

/// The screen's main action, pinned to the bottom where the thumb reaches
/// it, clear of the gesture bar. An optional [note] (an error, or a hint
/// while waiting) shows right above the button, so it is never scrolled
/// out of sight.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.action, this.note, this.noteIsError = false});

  final Widget action;
  final String? note;
  final bool noteIsError;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.background, border: Border(top: BorderSide(color: colors.outline))),
      child: SafeArea(
        top: false,
        child: PageWidth(
          fillHeight: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (note != null) ...[
                  Text(note!, style: text.bodyMedium?.copyWith(color: noteIsError ? colors.danger : colors.muted)),
                  const SizedBox(height: 12),
                ],
                action,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
