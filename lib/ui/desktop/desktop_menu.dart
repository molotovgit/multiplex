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

/// Which screen to show: one of the remote's monitors, the monitor in
/// focus, or a phone-sized screen of its own.
abstract final class DesktopScreens {
  static Future<void> show(BuildContext context, {required DesktopController controller}) {
    // Monitors can be plugged in or out while connected.
    controller.refreshMonitors();
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      sheetAnimationStyle: AppMotion.of(context).sheet,
      builder: (context) => _ScreensSheet(controller: controller),
    );
  }
}

class _ScreensSheet extends StatelessWidget {
  const _ScreensSheet({required this.controller});

  final DesktopController controller;

  void _pick(BuildContext context, DesktopSettings next) {
    Navigator.pop(context);
    next.saveTo(AppScope.store(context));
    controller.applySettings(next);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: controller, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final s = controller.settings;
    final mirror = s.screen == DesktopScreenMode.mirror;
    Widget tile({required IconData icon, required String title, String? subtitle, required bool selected, required VoidCallback onTap}) => ListTile(
      leading: Icon(icon, color: selected ? colors.accent : null),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: selected ? Icon(Icons.check, color: colors.accent) : null,
      selected: selected,
      onTap: onTap,
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: SectionHeader('Show')),
            if (controller.monitors.isNotEmpty)
              for (final m in controller.monitors)
                tile(
                  icon: Icons.desktop_windows_outlined,
                  title: m.focused ? '${m.name} · in focus' : m.name,
                  subtitle: '${m.width} × ${m.height}${m.refresh > 0 ? ' · ${m.refresh.round()} Hz' : ''}',
                  selected: mirror && s.output == m.name,
                  onTap: () => _pick(context, s.copyWith(screen: DesktopScreenMode.mirror, output: m.name)),
                )
            else
              for (final o in controller.outputs)
                tile(
                  icon: Icons.desktop_windows_outlined,
                  title: o.name,
                  subtitle: '${o.width} × ${o.height}',
                  selected: mirror && s.output == o.name,
                  onTap: () => _pick(context, s.copyWith(screen: DesktopScreenMode.mirror, output: o.name)),
                ),
            tile(
              icon: Icons.center_focus_strong_outlined,
              title: 'The monitor in focus',
              subtitle: 'Whichever monitor you last worked on',
              selected: mirror && s.output.isEmpty,
              onTap: () => _pick(context, s.copyWith(screen: DesktopScreenMode.mirror, output: '')),
            ),
            tile(
              icon: Icons.smartphone,
              title: 'Phone-sized screen',
              subtitle: DesktopScreenMode.fitted.description,
              selected: !mirror,
              onTap: () => _pick(context, s.copyWith(screen: DesktopScreenMode.fitted)),
            ),
          ],
        ),
      ),
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
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.desktop_windows_outlined),
              title: Text(s.screen == DesktopScreenMode.fitted ? 'Phone-sized screen' : (s.output.isEmpty ? 'The monitor in focus' : s.output)),
              subtitle: Text(c.monitors.length > 1 ? '${c.monitors.length} monitors · tap to switch' : 'Tap to choose'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                DesktopScreens.show(context, controller: c);
              },
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.high_quality_outlined, size: 20),
                const SizedBox(width: 12),
                Text('Resolution', style: text.bodyLarge),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in DesktopResolution.values)
                  ChoiceChip(
                    label: Text(r.label),
                    selected: s.resolution == r,
                    onSelected: (_) => _save(s.copyWith(resolution: r)),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(
                '${s.resolution.description}${c.streamWidth > 0 ? ' · now ${c.streamWidth} × ${c.streamHeight}' : ''}',
                style: text.bodySmall?.copyWith(color: colors.muted),
              ),
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
              subtitle: const Text('Frame rate, network ping, picture delay (server to screen) and data rate'),
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
