import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/theme_spec.dart';

/// Sizes shared by the settings screens. Spacing follows the 4/8 grid.
abstract final class SettingsLayout {
  /// On wide screens lists stay this wide.
  static const maxContentWidth = 720.0;

  /// Pages that are mostly sentences and fields stay narrower, so lines
  /// stay easy to read.
  static const maxReadingWidth = 600.0;

  /// Space around cards and blocks of text.
  static const gutter = 16.0;

  /// Icon sizes: small marks inside chips, and icons inside boxes.
  static const iconSmall = 16.0;
  static const iconMedium = 20.0;
}

/// How long the small "this part changed" animations take.
abstract final class SettingsMotion {
  static const change = Duration(milliseconds: 200);

  /// No motion when the user asked the system for less of it.
  static Duration of(BuildContext context) => MediaQuery.disableAnimationsOf(context) ? Duration.zero : change;
}

/// Keeps its child at a readable width and centred on wide screens, and
/// clear of the system bars and notches at the bottom and sides. On
/// phones it simply fills the width.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = SettingsLayout.maxContentWidth});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        ),
      );
}

/// Fades between old and new content and lets the space grow or shrink
/// smoothly, so the user sees which part changed. Give each state of the
/// child its own key.
class FadeChange extends StatelessWidget {
  const FadeChange({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = SettingsMotion.of(context);
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        child: child,
      ),
    );
  }
}

/// Formats numbers and counts the way people say them.
abstract final class SettingsFormat {
  /// 50000 becomes "50,000".
  static String thousands(int value) {
    final digits = value.abs().toString();
    final out = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  /// "1 host", "3 hosts".
  static String count(int value, String one, String many) => '${thousands(value)} ${value == 1 ? one : many}';

  /// "a", "a and b", "a, b and c".
  static String list(List<String> parts) {
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.single;
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }
}

/// One choice in a [ChoiceTile].
class ChoiceOption<T> {
  const ChoiceOption(this.value, this.label);

  final T value;
  final String label;
}

/// A setting with a few fixed choices. Shows the current choice and opens
/// a dialog with radio buttons when tapped.
class ChoiceTile<T> extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.fallbackLabel,
    this.icon,
    this.description,
  });

  final String title;
  final T value;
  final List<ChoiceOption<T>> options;
  final ValueChanged<T> onChanged;

  /// Shown when the saved value is not one of the options (for example
  /// after restoring a backup from another version).
  final String Function(T value) fallbackLabel;
  final IconData? icon;

  /// A sentence in the dialog that explains the setting.
  final String? description;

  String get _currentLabel {
    for (final option in options) {
      if (option.value == value) return option.label;
    }
    return fallbackLabel(value);
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showDialog<ChoiceOption<T>>(
      context: context,
      builder: (context) => ChoiceDialog<T>(title: title, value: value, options: options, description: description),
    );
    if (picked != null && picked.value != value) onChanged(picked.value);
  }

  @override
  Widget build(BuildContext context) => ListTile(
        leading: icon == null ? null : Icon(icon),
        title: Text(title),
        subtitle: Text(_currentLabel),
        onTap: () => _pick(context),
      );
}

/// The dialog behind a [ChoiceTile]. Picking an option closes it.
class ChoiceDialog<T> extends StatelessWidget {
  const ChoiceDialog({super.key, required this.title, required this.value, required this.options, this.description});

  final String title;
  final T value;
  final List<ChoiceOption<T>> options;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
      content: SingleChildScrollView(
        child: RadioGroup<T>(
          groupValue: value,
          onChanged: (picked) {
            final option = options.where((o) => o.value == picked).firstOrNull;
            Navigator.pop(context, option);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (description != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(description!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.muted)),
                ),
              for (final option in options) RadioListTile<T>(value: option.value, title: Text(option.label)),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

/// A row of small dots with a theme's main colours: background, text,
/// accent and the six bright-ish ANSI colours.
class ThemeSwatches extends StatelessWidget {
  const ThemeSwatches({super.key, required this.theme, this.size = 16});

  final ThemeSpec theme;
  final double size;

  List<int> get _colours => [theme.background, theme.foreground, theme.accent, ...theme.ansi.sublist(1, 7)];

  @override
  Widget build(BuildContext context) {
    final outline = AppColorsTheme.of(context).outline;
    return ExcludeSemantics(
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final colour in _colours)
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Color(colour),
                shape: BoxShape.circle,
                border: Border.all(color: outline),
              ),
            ),
        ],
      ),
    );
  }
}

/// How a [NoticeBox] is meant: a warning, a problem, good news or a hint.
enum NoticeTone { warning, error, success, info }

/// A short message in a soft box with an icon, used for warnings, errors
/// and results inside a card.
class NoticeBox extends StatelessWidget {
  const NoticeBox({super.key, required this.tone, required this.text, this.title});

  final NoticeTone tone;
  final String text;
  final String? title;

  IconData get _icon => switch (tone) {
        NoticeTone.warning => Icons.warning_amber_rounded,
        NoticeTone.error => Icons.error_outline,
        NoticeTone.success => Icons.check_circle_outline,
        NoticeTone.info => Icons.info_outline,
      };

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final tint = switch (tone) {
      NoticeTone.warning => colors.accent,
      NoticeTone.error => colors.danger,
      NoticeTone.success => colors.live,
      NoticeTone.info => colors.muted,
    };
    return Semantics(
      liveRegion: tone == NoticeTone.error || tone == NoticeTone.success,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.raised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tint.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, color: tint, size: SettingsLayout.iconMedium),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    // Same weight as the section headings, so a screen
                    // uses only two weights.
                    Text(title!, style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                  ],
                  Text(text, style: textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A thin progress bar with a line saying what is happening.
class BusyNote extends StatelessWidget {
  const BusyNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.muted)),
        ],
      ),
    );
  }
}

/// Plain body text in the muted colour, for explanations.
class HelpText extends StatelessWidget {
  const HelpText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColorsTheme.of(context).muted),
      );
}
