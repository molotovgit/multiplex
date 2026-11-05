import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/terminal_fonts.dart';
import '../../app/theme.dart';

/// Shown when a list has nothing in it yet: says what belongs here and
/// offers the action that adds the first item.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.actionLabel, this.onAction});

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: colors.muted),
              const SizedBox(height: 16),
              Text(title, style: text.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(message, style: text.bodyMedium?.copyWith(color: colors.muted), textAlign: TextAlign.center),
              if (actionLabel != null) ...[
                const SizedBox(height: 20),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A small heading above a group of list items.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.muted, fontWeight: FontWeight.w600)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Text in the terminal font: addresses, fingerprints, commands, paths.
class MonoText extends StatelessWidget {
  const MonoText(this.text, {super.key, this.style, this.maxLines, this.selectable = false});

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.store(context).settings;
    final family = TerminalFonts.byId(settings, settings.terminalFontId).family;
    final base = (style ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(fontFamily: family, letterSpacing: 0);
    if (selectable) return SelectableText(text, style: base, maxLines: maxLines);
    return Text(text, style: base, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis);
  }
}

/// A coloured dot: green for live, grey for idle.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.live, this.size = 8});

  final bool live;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: live ? colors.live : colors.outline, shape: BoxShape.circle),
    );
  }
}

/// Short messages at the bottom of the screen.
abstract final class Toast {
  static void show(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Copies text and says so.
  static Future<void> copy(BuildContext context, String text, {String what = 'Copied'}) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) show(context, what);
  }
}

/// "Are you sure?" for actions that cannot be undone.
abstract final class Confirm {
  static Future<bool> ask(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
    bool destructive = true,
  }) async {
    final colors = AppColorsTheme.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: destructive ? FilledButton.styleFrom(backgroundColor: colors.danger, foregroundColor: Colors.white) : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Tag colours a host can be marked with (index 0 = none).
abstract final class TagColors {
  static const values = [
    Colors.transparent,
    Color(0xFFE0605A),
    Color(0xFFE2B65C),
    Color(0xFF8FBF6A),
    Color(0xFF5FB8B2),
    Color(0xFF6B9BD8),
    Color(0xFFB78AD6),
  ];

  static Color of(int index) => values[index.clamp(0, values.length - 1)];
}
