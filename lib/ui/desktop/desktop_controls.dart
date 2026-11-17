import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/theme_look.dart';
import '../../sessions/desktop_controller.dart';
import 'desktop_keys.dart';

/// The row of extra keys for the desktop: sticky Super, Ctrl, Alt and
/// Shift (tap: next key; double tap: locked), Esc, Tab, arrows, the
/// navigation keys and F1 to F12. Shown with the phone keyboard, or on its
/// own for shortcuts.
class DesktopKeyBar extends StatelessWidget {
  const DesktopKeyBar({super.key, required this.controller, required this.keepFocus, this.onSwitchKeyboard, this.compact = false});

  /// Above Multiplex's keyboard: only the keys it does not have (Super,
  /// Shift, Del, the page keys and F1 to F12).
  final bool compact;

  /// Shown with the phone's keyboard: back to Multiplex's keyboard.
  final VoidCallback? onSwitchKeyboard;

  /// The desktop, or the touchpad without a picture.
  final KeyTarget controller;

  /// Called after each press so the phone keyboard stays open.
  final VoidCallback keepFocus;

  static const _mods = [(LinuxKey.leftMeta, 'Super'), (LinuxKey.leftCtrl, 'Ctrl'), (LinuxKey.leftAlt, 'Alt'), (LinuxKey.leftShift, 'Shift')];

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Material(
        color: colors.surface,
        child: SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            children: [
              if (onSwitchKeyboard != null) _Key(icon: Icons.keyboard_alt_outlined, name: 'Multiplex keyboard', onTap: onSwitchKeyboard!),
              for (final (code, label) in _mods)
                if (!compact || code == LinuxKey.leftMeta || code == LinuxKey.leftShift)
                  _Key(
                    label: label,
                    name: '$label (tap for the next key, double tap to lock)',
                    state: controller.mods[code] ?? ModState.off,
                    onTap: () {
                      controller.toggleMod(code);
                      keepFocus();
                    },
                  ),
              if (!compact) ...[
                _Key(label: 'Esc', name: 'Escape', onTap: () => _tap(LinuxKey.esc)),
                _Key(label: 'Tab', name: 'Tab', onTap: () => _tap(LinuxKey.tab)),
                _Key(icon: Icons.keyboard_arrow_left, name: 'Left', onTap: () => _tap(LinuxKey.left)),
                _Key(icon: Icons.keyboard_arrow_up, name: 'Up', onTap: () => _tap(LinuxKey.up)),
                _Key(icon: Icons.keyboard_arrow_down, name: 'Down', onTap: () => _tap(LinuxKey.down)),
                _Key(icon: Icons.keyboard_arrow_right, name: 'Right', onTap: () => _tap(LinuxKey.right)),
                _Key(icon: Icons.backspace_outlined, name: 'Backspace', onTap: () => _tap(LinuxKey.backspace)),
              ],
              _Key(label: 'Del', name: 'Delete', onTap: () => _tap(LinuxKey.delete)),
              _Key(label: 'Home', name: 'Home', onTap: () => _tap(LinuxKey.home)),
              _Key(label: 'End', name: 'End', onTap: () => _tap(LinuxKey.end)),
              _Key(label: 'PgUp', name: 'Page up', onTap: () => _tap(LinuxKey.pageUp)),
              _Key(label: 'PgDn', name: 'Page down', onTap: () => _tap(LinuxKey.pageDown)),
              for (var f = 1; f <= 12; f++) _Key(label: 'F$f', name: 'F$f', onTap: () => _tap(LinuxKey.function(f))),
            ],
          ),
        ),
      ),
    );
  }

  void _tap(int code) {
    controller.tap(code);
    keepFocus();
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, required this.name, required this.onTap, this.state = ModState.off});

  final String? label;
  final IconData? icon;
  final String name;
  final VoidCallback onTap;
  final ModState state;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final on = state != ModState.off;
    final fg = on ? colors.onAccent : colors.text;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: name,
        excludeFromSemantics: true,
        child: Material(
          color: on ? colors.accent : colors.raised,
          borderRadius: BorderRadius.circular(8),
          child: Semantics(
            button: true,
            label: name,
            toggled: label != null && ['Super', 'Ctrl', 'Alt', 'Shift'].contains(label) ? on : null,
            value: state == ModState.locked ? 'locked' : (state == ModState.once ? 'on for the next key' : null),
            child: InkWell(
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null)
                          Icon(icon, size: 20, color: fg)
                        else
                          Text(
                            label!,
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w600),
                          ),
                        if (state == ModState.locked) ...[const SizedBox(width: 4), Icon(Icons.lock, size: 12, color: fg)],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The floating bar at the bottom of the desktop, where thumbs reach: back,
/// where you are connected and how, the keyboard, the shortcut keys, the
/// panel (workspaces, windows, media), and More for everything else. It fades away while you work and comes back
/// with a tap on the handle.
class DesktopToolbar extends StatelessWidget {
  const DesktopToolbar({
    super.key,
    required this.title,
    required this.route,
    required this.controller,
    required this.keyboardOpen,
    required this.keysOpen,
    this.panelOpen = false,
    required this.onBack,
    required this.onKeyboard,
    required this.onKeys,
    this.onPanel,
    required this.onMore,
  });

  final String title;

  /// "Direct" or "via" and the jump host.
  final String route;
  final DesktopController controller;
  final bool keyboardOpen;
  final bool keysOpen;
  final bool panelOpen;
  final VoidCallback onBack;
  final VoidCallback onKeyboard;
  final VoidCallback onKeys;

  /// Null when the computer has no panel (a plain SSH server).
  final VoidCallback? onPanel;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final look = AppStyleTheme.of(context);
    final text = Theme.of(context).textTheme;
    final c = controller;
    final status = switch (c.phase) {
      DesktopPhase.connecting => 'Starting…',
      DesktopPhase.reconnecting => 'Reconnecting…',
      DesktopPhase.ended => 'Ended',
      DesktopPhase.live => route,
    };
    return Material(
      color: colors.surface.withValues(alpha: 0.94),
      elevation: 3,
      shadowColor: look.surfaces.shadow,
      shape: look.shapes.border(look.shapes.pill, BorderSide(color: colors.outline.withValues(alpha: 0.5))),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: onBack),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.live ? colors.live : (c.phase == DesktopPhase.ended ? colors.danger : colors.muted),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelSmall?.copyWith(color: colors.muted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: keyboardOpen ? 'Hide keyboard' : 'Keyboard',
              isSelected: keyboardOpen,
              icon: const Icon(Icons.keyboard_outlined),
              selectedIcon: const Icon(Icons.keyboard_hide_outlined),
              onPressed: onKeyboard,
            ),
            IconButton(
              tooltip: keysOpen ? 'Hide shortcut keys' : 'Shortcut keys (Super, Ctrl, Esc…)',
              isSelected: keysOpen,
              icon: const Icon(Icons.keyboard_command_key),
              onPressed: onKeys,
            ),
            if (onPanel != null)
              IconButton(
                tooltip: panelOpen ? 'Hide the panel' : 'Panel: workspaces, windows, media',
                isSelected: panelOpen,
                icon: const Icon(Icons.space_dashboard_outlined),
                selectedIcon: const Icon(Icons.space_dashboard),
                onPressed: onPanel,
              ),
            IconButton(tooltip: 'More', icon: const Icon(Icons.more_vert), onPressed: onMore),
          ],
        ),
      ),
    );
  }
}

/// Frame rate and delay, small in a corner.
class DesktopStatsChip extends StatelessWidget {
  const DesktopStatsChip({super.key, required this.controller});

  final DesktopController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.stats;
    if (s == null) return const SizedBox.shrink();
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.text, fontFeatures: const [FontFeature.tabularFigures()]);
    final encoder = controller.hardwareEncoder ? 'GPU' : 'CPU';
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.surface.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            '${s.fps.toStringAsFixed(0)} fps · ping ${s.rttMs.toStringAsFixed(0)} ms'
            '${controller.netPingMs != null ? ' (net ${controller.netPingMs!.toStringAsFixed(0)})' : ''} · '
            'delay ${s.frameAgeMs > 0 ? s.frameAgeMs.toStringAsFixed(0) : '–'} ms · '
            '${(s.kbps / 1000).toStringAsFixed(1)} Mbit/s · ${controller.streamWidth}×${controller.streamHeight} $encoder',
            style: text,
          ),
        ),
      ),
    );
  }
}

/// One tap per monitor, under the toolbar.
class DesktopScreenChips extends StatelessWidget {
  const DesktopScreenChips({super.key, required this.names, required this.selected, required this.onSelect});

  final List<String> names;
  final int selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final look = AppStyleTheme.of(context);
    return Material(
      color: colors.surface.withValues(alpha: 0.94),
      shape: look.shapes.border(look.shapes.pill, BorderSide(color: colors.outline.withValues(alpha: 0.5))),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < names.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.desktop_windows_outlined, size: 16, color: i == selected ? colors.onAccent : colors.muted),
                  label: Text(names[i]),
                  selected: i == selected,
                  showCheckmark: false,
                  selectedColor: colors.accent,
                  labelStyle: TextStyle(color: i == selected ? colors.onAccent : colors.text),
                  onSelected: (_) => onSelect(names[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shown while zoomed in: out, the zoom level, in, and back to the whole
/// screen.
class DesktopZoomPill extends StatelessWidget {
  const DesktopZoomPill({super.key, required this.zoom, required this.onOut, required this.onIn, required this.onFit});

  final double zoom;
  final VoidCallback onOut;
  final VoidCallback onIn;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final look = AppStyleTheme.of(context);
    return Material(
      color: colors.surface.withValues(alpha: 0.92),
      elevation: 2,
      shadowColor: look.surfaces.shadow,
      shape: look.shapes.border(look.shapes.pill, BorderSide(color: colors.outline.withValues(alpha: 0.5))),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(tooltip: 'Zoom out', icon: const Icon(Icons.remove), onPressed: onOut),
          Text('${zoom.toStringAsFixed(1)}×', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          IconButton(tooltip: 'Zoom in', icon: const Icon(Icons.add), onPressed: onIn),
          IconButton(tooltip: 'Whole screen', icon: const Icon(Icons.fit_screen_outlined), onPressed: onFit),
        ],
      ),
    );
  }
}
