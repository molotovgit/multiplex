import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../src/rust/api/terminal_types.dart';
import '../common/widgets.dart';
import '../settings/settings_widgets.dart';
import 'key_sink.dart';
import 'keyboard_settings.dart';
import 'terminal_keyboard_panel.dart';

/// Settings of the built-in terminal keyboard, with a live preview in the
/// current theme. Every change is saved at once.
class KeyboardSettingsScreen extends StatelessWidget {
  const KeyboardSettingsScreen({super.key});

  /// Screens shorter than this show the preview inside the list instead
  /// of pinned to the bottom, so the options stay reachable.
  static const _pinnedPreviewMinHeight = 640.0;

  @override
  Widget build(BuildContext context) {
    final settings = KeyboardSettings.of(AppScope.watch(context));
    final pinned = MediaQuery.sizeOf(context).height >= _pinnedPreviewMinHeight;
    return Scaffold(
      appBar: AppBar(title: const Text('Terminal keyboard')),
      body: Column(
        children: [
          Expanded(
            child: ContentWidth(
              child: ListView(
                padding: const EdgeInsets.only(bottom: SettingsLayout.gutter),
                children: [
                  KeyboardOptionsList(settings: settings),
                  if (!pinned) const KeyboardPreview(),
                ],
              ),
            ),
          ),
          if (pinned) const KeyboardPreview(),
        ],
      ),
    );
  }
}

/// The switches and choices of [KeyboardSettingsScreen].
class KeyboardOptionsList extends StatelessWidget {
  const KeyboardOptionsList({super.key, required this.settings});

  final KeyboardSettings settings;

  void _save(BuildContext context, KeyboardSettings next) => next.saveTo(AppScope.store(context));

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          title: const Text('Use the built-in keyboard'),
          subtitle: const Text('Replaces the phone keyboard in terminals. Turn it off to type with the system keyboard.'),
          value: settings.enabled,
          onChanged: (on) => _save(context, settings.copyWith(enabled: on)),
        ),
        const SectionHeader('Layout'),
        ChoiceTile<KeyboardLayoutKind>(
          icon: Icons.keyboard_outlined,
          title: 'Letter layout',
          value: settings.layout,
          options: [for (final kind in KeyboardLayoutKind.values) ChoiceOption(kind, '${kind.label}, ${kind.description.toLowerCase()}')],
          fallbackLabel: (kind) => kind.label,
          onChanged: (kind) => _save(context, settings.copyWith(layout: kind)),
        ),
        const SectionHeader('Look'),
        _SegmentSetting<KeyHeightOption>(
          label: 'Key height',
          value: settings.keyHeight,
          options: KeyHeightOption.values,
          nameOf: (o) => o.label,
          onChanged: (o) => _save(context, settings.copyWith(keyHeight: o)),
        ),
        _SegmentSetting<KeyShape>(
          label: 'Key shape',
          value: settings.shape,
          options: KeyShape.values,
          nameOf: (o) => o.label,
          onChanged: (o) => _save(context, settings.copyWith(shape: o)),
        ),
        SwitchListTile(
          title: const Text('Bold labels'),
          value: settings.boldLabels,
          onChanged: (on) => _save(context, settings.copyWith(boldLabels: on)),
        ),
        SwitchListTile(
          title: const Text('Show alternate characters'),
          subtitle: const Text('The character you get by swiping up, small in the corner of each key'),
          value: settings.showAlternates,
          onChanged: (on) => _save(context, settings.copyWith(showAlternates: on)),
        ),
        const SectionHeader('Typing'),
        SwitchListTile(
          title: const Text('Show recent commands'),
          subtitle: const Text('A row of the commands you ran on this host, above the keys'),
          value: settings.showRecentCommands,
          onChanged: (on) => _save(context, settings.copyWith(showRecentCommands: on)),
        ),
        SwitchListTile(
          title: const Text('Swipe up for symbols'),
          subtitle: const Text('Swipe up on a key to type its alternate character'),
          value: settings.swipeForSymbols,
          onChanged: (on) => _save(context, settings.copyWith(swipeForSymbols: on)),
        ),
        SwitchListTile(
          title: const Text('Key preview'),
          subtitle: const Text('Shows the character above your finger'),
          value: settings.keyPreview,
          onChanged: (on) => _save(context, settings.copyWith(keyPreview: on)),
        ),
        SwitchListTile(
          title: const Text('Vibrate on key press'),
          value: settings.haptics,
          onChanged: (on) => _save(context, settings.copyWith(haptics: on)),
        ),
        SwitchListTile(
          title: const Text('Click sound'),
          value: settings.sound,
          onChanged: (on) => _save(context, settings.copyWith(sound: on)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 12, SettingsLayout.gutter, 0),
          child: Text(
            'Tap Ctrl, Alt or Shift for the next key, or tap twice to keep it on. '
            'Hold a key for more characters. Hold Backspace, the arrows or Space to repeat. '
            'Drag along the space bar to move the cursor, or up and down for history.',
            style: text.bodyMedium?.copyWith(color: colors.muted),
          ),
        ),
      ],
    );
  }
}

/// A label with a segmented choice under it.
class _SegmentSetting<T> extends StatelessWidget {
  const _SegmentSetting({required this.label, required this.value, required this.options, required this.nameOf, required this.onChanged});

  final String label;
  final T value;
  final List<T> options;
  final String Function(T) nameOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 8, SettingsLayout.gutter, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 8),
            SegmentedButton<T>(
              segments: [for (final o in options) ButtonSegment(value: o, label: Text(nameOf(o)))],
              selected: {value},
              showSelectedIcon: false,
              onSelectionChanged: (picked) => onChanged(picked.first),
            ),
          ],
        ),
      );
}

/// The keyboard as it will look, working: what you type is described in
/// the line above it instead of going to a server.
class KeyboardPreview extends StatefulWidget {
  const KeyboardPreview({super.key});

  @override
  State<KeyboardPreview> createState() => _KeyboardPreviewState();
}

class _KeyboardPreviewState extends State<KeyboardPreview> {
  final _sink = _PreviewSink();
  String _echo = 'Try the keys here';

  void _show(String message) => setState(() => _echo = message);

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(color: colors.outline),
        Padding(
          padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 8, SettingsLayout.gutter, 8),
          child: Row(
            children: [
              Text('Preview', style: text.labelLarge?.copyWith(color: colors.muted, fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: MonoText(_echo, maxLines: 1, style: text.bodyMedium?.copyWith(color: colors.text)),
                ),
              ),
            ],
          ),
        ),
        TerminalKeyboardPanel.withSink(
          sink: _sink,
          onSent: (what) => _show('Sent $what'),
          onSnippets: () => _show('In a terminal this opens your snippets'),
          onHide: () => _show('In a terminal this hides the keyboard'),
          onSwitchToSystem: () => _show('In a terminal this switches to the system keyboard'),
        ),
      ],
    );
  }
}

/// Swallows what the preview types.
class _PreviewSink implements KeySink {
  @override
  void sendText(String text, KeyModifiers mods) {}

  @override
  void sendKey(TerminalKey key, KeyModifiers mods) {}

  @override
  void pasteClipboard() {}
}
