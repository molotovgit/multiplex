import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_motion.dart';
import '../../app/app_scope.dart';
import '../../app/app_shortcuts.dart';
import '../../app/theme.dart';
import '../../app/theme_look.dart';
import '../../app/theme_spec.dart';
import '../common/widgets.dart';
import 'theme_actions.dart';
import 'theme_preview.dart';

/// A sheet listing every theme with a small preview. Tapping one applies
/// it at once and the sheet stays open, so themes can be tried one after
/// another. Opens from a long press on Settings, the terminal's menu and
/// Ctrl+Shift+T.
class ThemeSwitcherSheet extends StatelessWidget {
  const ThemeSwitcherSheet({super.key});

  static bool _open = false;

  /// Shows the sheet, unless it is already open.
  static Future<void> show(BuildContext context) async {
    if (_open) return;
    _open = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        sheetAnimationStyle: AppMotion.of(context).sheet,
        builder: (_) => const ThemeSwitcherSheet(),
      );
    } finally {
      _open = false;
    }
  }

  /// The sheet stops at this share of the screen height.
  static const _heightShare = 0.75;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.watch(context);
    final activeId = store.activeTheme.id;
    final custom = store.customThemes;
    final text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * _heightShare),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 8, 0),
            child: Row(
              children: [
                Expanded(child: Semantics(header: true, child: Text('Switch theme', style: text.titleLarge))),
                IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.only(bottom: 16 + MediaQuery.paddingOf(context).bottom),
              children: [
                const SectionHeader('Built-in'),
                for (final theme in BuiltInThemes.all) _SwitcherRow(theme: theme, active: theme.id == activeId),
                if (custom.isNotEmpty) ...[
                  const SectionHeader('Your themes'),
                  for (final theme in custom) _SwitcherRow(theme: theme, active: theme.id == activeId),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One theme: a small preview, its name and a check mark when in use.
class _SwitcherRow extends StatelessWidget {
  const _SwitcherRow({required this.theme, required this.active});

  final ThemeSpec theme;
  final bool active;

  static const _preview = Size(88, 52);

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(StyleShapes.of(theme.style.shape).field);
    final pictures = theme.backgrounds.length;
    final detail = [theme.credit ?? (theme.isDark ? 'Dark' : 'Light'), if (pictures > 0) '$pictures ${pictures == 1 ? 'picture' : 'pictures'}'].join(', ');
    return Semantics(
      button: true,
      selected: active,
      label: '${theme.name}${active ? ', in use' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => ThemeActions(context).useQuietly(theme),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: active ? colors.accent : colors.outline, width: active ? 2 : 1),
                ),
                child: SizedBox.fromSize(size: _preview, child: ThemePreview(theme: theme, showPalette: false, borderRadius: radius)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(theme.name, style: text.titleSmall),
                    Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: colors.muted)),
                  ],
                ),
              ),
              if (active) Icon(Icons.check_circle, color: colors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Listens for Ctrl+Shift+T anywhere in the app and opens the theme
/// switcher over whatever is on screen.
class ThemeSwitcherHotkey extends StatefulWidget {
  const ThemeSwitcherHotkey({super.key, required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<ThemeSwitcherHotkey> createState() => _ThemeSwitcherHotkeyState();
}

class _ThemeSwitcherHotkeyState extends State<ThemeSwitcherHotkey> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (!AppShortcuts.isThemeSwitcher(event)) return false;
    final navigator = widget.navigatorKey.currentContext;
    if (navigator == null) return false;
    ThemeSwitcherSheet.show(navigator);
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
