import 'package:flutter/material.dart';

/// Sizes used by the keychain and snippets screens.
abstract final class PageLayout {
  /// Content never gets wider than this, so lines stay readable on a
  /// desktop monitor.
  static const maxWidth = 840.0;

  /// Space at the end of a list so the last row is not hidden behind the
  /// floating button.
  static const fabClearance = 96.0;
}

/// Centres its child and keeps it at most [PageLayout.maxWidth] wide.
class PageWidth extends StatelessWidget {
  const PageWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
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
