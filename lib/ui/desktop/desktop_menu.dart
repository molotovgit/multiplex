import 'package:flutter/material.dart';

import '../../app/app_motion.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../sessions/desktop_controller.dart';
import '../common/widgets.dart';
import 'desktop_keys.dart';
import 'desktop_settings.dart';

/// Everything that does not fit the toolbar: shortcuts, paste, the screen
/// mode, quality and text size, and disconnecting.
abstract final class DesktopMenu {
  static Future<void> show(BuildContext context, {required DesktopController controller, required Future<void> Function() onDisconnect}) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      sheetAnimationStyle: AppMotion.of(context).sheet,
      builder: (_) => _DesktopMenuSheet(controller: controller, onDisconnect: onDisconnect),
    );
  }
}

class _DesktopMenuSheet extends StatefulWidget {
  const _DesktopMenuSheet({required this.controller, required this.onDisconnect});

  final DesktopController controller;
  final Future<void> Function() onDisconnect;

  @override
  State<_DesktopMenuSheet> createState() => _DesktopMenuSheetState();
}

class _DesktopMenuSheetState extends State<_DesktopMenuSheet> {
  DesktopController get c => widget.controller;

  void _save(DesktopSettings next) {
    next.saveTo(AppScope.store(context));
    c.applySettings(next);
    setState(() {});
  }

  void _shortcut(List<int> mods, int key) {
    Navigator.pop(context);
    c.tap(key, extra: mods);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final s = c.settings;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader('Quick actions'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.content_paste, size: 18),
                  label: const Text('Paste from phone'),
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await c.pastePhoneClipboard();
                    nav.pop();
                    if (!ok) messenger.showSnackBar(const SnackBar(content: Text('The phone clipboard has no text')));
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.apps, size: 18),
                  label: const Text('Launcher'),
                  tooltip: 'Super + Space',
                  onPressed: () => _shortcut(const [LinuxKey.leftMeta], LinuxKey.space),
                ),
                ActionChip(
                  avatar: const Icon(Icons.terminal, size: 18),
                  label: const Text('Terminal'),
                  tooltip: 'Super + Enter',
                  onPressed: () => _shortcut(const [LinuxKey.leftMeta], LinuxKey.enter),
                ),
                ActionChip(
                  avatar: const Icon(Icons.close, size: 18),
                  label: const Text('Close window'),
                  tooltip: 'Super + W',
                  onPressed: () => _shortcut(const [LinuxKey.leftMeta], 17),
                ),
                ActionChip(
                  avatar: const Icon(Icons.fullscreen, size: 18),
                  label: const Text('Full screen'),
                  tooltip: 'Super + F',
                  onPressed: () => _shortcut(const [LinuxKey.leftMeta], 33),
                ),
                ActionChip(
                  avatar: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh picture'),
                  onPressed: () {
                    Navigator.pop(context);
                    c.restartPicture();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SectionHeader('Screen'),
            SegmentedButton<DesktopScreenMode>(
              segments: [
                for (final m in DesktopScreenMode.values)
                  ButtonSegment(
                    value: m,
                    label: Text(m == DesktopScreenMode.fitted ? 'Phone-sized' : 'Your monitor'),
                    icon: Icon(m == DesktopScreenMode.fitted ? Icons.smartphone : Icons.desktop_windows_outlined),
                  ),
              ],
              selected: {s.screen},
              onSelectionChanged: (v) => _save(s.copyWith(screen: v.first)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(s.screen.description, style: text.bodySmall?.copyWith(color: colors.muted)),
            ),
            if (s.screen == DesktopScreenMode.fitted) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.format_size, size: 20),
                  const SizedBox(width: 12),
                  Text('Text size', style: text.bodyLarge),
                  Expanded(
                    child: Slider(
                      value: DesktopSettings.textSizes.indexOf(s.textSize).clamp(0, DesktopSettings.textSizes.length - 1).toDouble(),
                      max: DesktopSettings.textSizes.length - 1.0,
                      divisions: DesktopSettings.textSizes.length - 1,
                      label: '${(s.textSize * 100).round()} %',
                      onChanged: (i) => _save(s.copyWith(textSize: DesktopSettings.textSizes[i.round()])),
                    ),
                  ),
                ],
              ),
            ],
            const SectionHeader('Touch'),
            SegmentedButton<DesktopTouchMode>(
              segments: [
                for (final m in DesktopTouchMode.values)
                  ButtonSegment(value: m, label: Text(m.label), icon: Icon(m == DesktopTouchMode.trackpad ? Icons.touch_app_outlined : Icons.ads_click)),
              ],
              selected: {s.touch},
              onSelectionChanged: (v) => _save(s.copyWith(touch: v.first)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                s.touch == DesktopTouchMode.trackpad
                    ? 'Drag to move · tap to click · two-finger tap: right-click · two fingers: scroll · hold, then drag: select · pinch: zoom'
                    : 'Tap: click · hold: right-click · drag: drag · two fingers: scroll · pinch: zoom',
                style: text.bodySmall?.copyWith(color: colors.muted),
              ),
            ),
            const SectionHeader('Connection'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.data_saver_on_outlined),
              title: const Text('Data saver'),
              subtitle: const Text('A smaller stream for slow or metered networks'),
              value: s.quality == DesktopQuality.saver,
              onChanged: (on) => _save(s.copyWith(quality: on ? DesktopQuality.saver : DesktopQuality.auto)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.speed),
              title: const Text('Show speed'),
              subtitle: const Text('Frame rate, delay and data rate in a corner'),
              value: s.showStats,
              onChanged: (on) => _save(s.copyWith(showStats: on)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.content_copy_outlined),
              title: const Text('Copy to the phone'),
              subtitle: const Text('Text copied on the desktop lands on the phone\'s clipboard'),
              value: s.syncClipboard,
              onChanged: (on) => _save(s.copyWith(syncClipboard: on)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: colors.danger),
              icon: const Icon(Icons.power_settings_new),
              label: const Text('Disconnect'),
              onPressed: () {
                Navigator.pop(context);
                widget.onDisconnect();
              },
            ),
          ],
        ),
      ),
    );
  }
}
