import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/app_icons.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../app/theme_look.dart';
import '../../app/theme_slides.dart';
import '../../app/theme_spec.dart';
import '../../app/theme_style.dart';
import '../appearance/theme_switcher.dart';
import '../common/theme_backdrop.dart';
import '../hosts/hosts_screen.dart';
import '../keys/keychain_screen.dart';
import '../sessions/sessions_screen.dart';
import '../settings/settings_screen.dart';
import '../snippets/snippets_screen.dart';

/// One top-level place in the app.
class _Destination {
  const _Destination(this.label, this.icon);

  final String label;
  final AppIconPair icon;
}

/// The app's main frame with the five main places. The theme's style picks
/// the navigation: a bottom bar with or without labels, a floating bar, or
/// a side rail. Wide screens (tablets, desktop) always get the side rail,
/// unless the floating bar is chosen. A long press on Settings opens the
/// theme switcher.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Finds the floating bar in tests.
  static const floatingBarKey = ValueKey('floating-nav');

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Screens at least this wide get the side rail.
  static const _railBreakpoint = 720.0;

  static const _destinations = [
    _Destination('Hosts', AppIcons.hosts),
    _Destination('Sessions', AppIcons.sessions),
    _Destination('Snippets', AppIcons.snippets),
    _Destination('Keychain', AppIcons.keychain),
    _Destination('Settings', AppIcons.settings),
  ];

  int _index = 0;

  static const _pages = <Widget>[HostsScreen(), SessionsScreen(), SnippetsScreen(), KeychainScreen(), SettingsScreen()];

  /// Where Settings is in [_destinations].
  static const _settingsIndex = 4;

  void _select(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final sessions = AppScope.sessions(context);
    final look = AppStyleTheme.of(context);
    final nav = look.style.nav;
    final wide = MediaQuery.sizeOf(context).width >= _railBreakpoint;
    final store = AppScope.watch(context);
    final theme = store.activeTheme;
    final pages = IndexedStack(index: _index, children: _pages);
    final slide = look.style.backdrop.onScreens ? ActiveSlide.of(theme, store.settings) : null;
    final body = slide != null ? _ScreensBackdrop(theme: theme, slide: slide, child: pages) : pages;

    return ListenableBuilder(
      listenable: sessions,
      builder: (context, _) {
        final bar = _NavModel(
          destinations: _destinations,
          index: _index,
          onSelect: _select,
          sessionCount: sessions.activeCount,
          onLongPressSettings: () => ThemeSwitcherSheet.show(context),
        );
        if (nav == NavStyle.rail || (wide && nav != NavStyle.floating)) {
          return Scaffold(
            body: Row(
              children: [
                _ShellRail(model: bar, labels: nav != NavStyle.iconsOnly),
                if (look.surfaces.style == SurfaceStyle.outlined) const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }
        if (nav == NavStyle.floating) {
          // The pages run on under the bar; Scaffold adds the bar's height
          // to their bottom padding, so lists still scroll clear of it.
          return Scaffold(extendBody: true, body: body, bottomNavigationBar: _FloatingNavBar(model: bar));
        }
        return Scaffold(
          extendBody: look.surfaces.isGlass,
          body: body,
          bottomNavigationBar: _GlassBackdrop(
            enabled: look.surfaces.isGlass,
            child: _ShellNavigationBar(model: bar, labels: nav == NavStyle.labelled),
          ),
        );
      },
    );
  }
}

/// What every navigation style needs to show.
class _NavModel {
  const _NavModel({
    required this.destinations,
    required this.index,
    required this.onSelect,
    required this.sessionCount,
    required this.onLongPressSettings,
  });

  final List<_Destination> destinations;
  final int index;
  final ValueChanged<int> onSelect;

  /// Opens the theme switcher.
  final VoidCallback onLongPressSettings;

  bool isSettings(_Destination d) => d.label == 'Settings';

  /// Open connections, shown as a badge on Sessions.
  final int sessionCount;

  int badgeFor(_Destination d) => d.label == 'Sessions' ? sessionCount : 0;
}

/// A destination's icon in the theme's icon style, with the sessions badge.
class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.destination, required this.selected, required this.badge});

  final _Destination destination;
  final bool selected;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final glyph = AppIcon(destination.icon, selected: selected);
    return badge > 0 ? Badge(label: Text('$badge'), child: glyph) : glyph;
  }
}

/// The bottom bar, with labels or icons only. Icons-only items still have
/// their names as tooltips and for screen readers.
class _ShellNavigationBar extends StatelessWidget {
  const _ShellNavigationBar({required this.model, required this.labels, this.height, this.background});

  final _NavModel model;
  final bool labels;
  final double? height;
  final Color? background;

  @override
  Widget build(BuildContext context) => _BarLongPress(
        count: model.destinations.length,
        target: _HomeShellState._settingsIndex,
        onLongPress: model.onLongPressSettings,
        child: NavigationBar(
          selectedIndex: model.index,
          onDestinationSelected: model.onSelect,
          height: height,
          backgroundColor: background,
          labelBehavior: labels ? NavigationDestinationLabelBehavior.alwaysShow : NavigationDestinationLabelBehavior.alwaysHide,
          destinations: [
            for (final d in model.destinations)
              NavigationDestination(
                icon: _NavIcon(destination: d, selected: false, badge: model.badgeFor(d)),
                selectedIcon: _NavIcon(destination: d, selected: true, badge: model.badgeFor(d)),
                label: d.label,
                // Its long press opens the theme switcher instead of a tooltip.
                tooltip: model.isSettings(d) ? '' : null,
              ),
          ],
        ),
      );
}

/// The side rail, kept clear of a notch or camera cut-out.
class _ShellRail extends StatelessWidget {
  const _ShellRail({required this.model, required this.labels});

  final _NavModel model;
  final bool labels;

  @override
  Widget build(BuildContext context) => SafeArea(
        right: false,
        child: NavigationRail(
          selectedIndex: model.index,
          onDestinationSelected: model.onSelect,
          labelType: labels ? NavigationRailLabelType.all : NavigationRailLabelType.none,
          destinations: [
            for (final d in model.destinations)
              NavigationRailDestination(
                icon: _RailIcon(model: model, destination: d, selected: false),
                selectedIcon: _RailIcon(model: model, destination: d, selected: true),
                label: Text(d.label),
              ),
          ],
        ),
      );
}

/// A rounded bar that floats above the content, inset from the edges and
/// clear of the gesture bar.
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({required this.model});

  final _NavModel model;

  static const _maxWidth = 560.0;
  static const _height = 64.0;

  @override
  Widget build(BuildContext context) {
    final look = AppStyleTheme.of(context);
    final colors = AppColorsTheme.of(context);
    final surfaces = look.surfaces;
    // A floating bar always needs an edge: a shadow, or a border when the
    // style has no shadow.
    final flat = surfaces.style == SurfaceStyle.flat;
    final side = surfaces.style == SurfaceStyle.raised ? BorderSide.none : (flat ? BorderSide(color: colors.outline) : surfaces.side);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Material(
            key: HomeShell.floatingBarKey,
            color: Colors.transparent,
            elevation: flat ? 0 : 4,
            shadowColor: surfaces.shadow,
            shape: look.shapes.border(look.shapes.pill, side),
            clipBehavior: Clip.antiAlias,
            child: _GlassBackdrop(
              enabled: surfaces.isGlass,
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                removeLeft: true,
                removeRight: true,
                child: _ShellNavigationBar(model: model, labels: true, height: _height, background: surfaces.bar),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Blurs what is behind a see-through bar. Blur costs a lot on some
/// phones, so with high contrast on the bar is drawn solid instead.
class _GlassBackdrop extends StatelessWidget {
  const _GlassBackdrop({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    if (MediaQuery.highContrastOf(context)) {
      return ColoredBox(color: AppColorsTheme.of(context).surface, child: child);
    }
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: SurfaceLook.glassBlur, sigmaY: SurfaceLook.glassBlur),
        child: child,
      ),
    );
  }
}

/// A long press on one of a bottom bar's equal slots. The bar's items
/// all have the same width, so the slot follows from where the finger is.
class _BarLongPress extends StatelessWidget {
  const _BarLongPress({required this.count, required this.target, required this.onLongPress, required this.child});

  final int count;
  final int target;
  final VoidCallback onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPressStart: (details) {
            final slot = (details.localPosition.dx / constraints.maxWidth * count).floor().clamp(0, count - 1);
            final rtl = Directionality.of(context) == TextDirection.rtl;
            if ((rtl ? count - 1 - slot : slot) == target) onLongPress();
          },
          child: child,
        ),
      );
}

/// A rail icon; the Settings one also answers a long press.
class _RailIcon extends StatelessWidget {
  const _RailIcon({required this.model, required this.destination, required this.selected});

  final _NavModel model;
  final _Destination destination;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = _NavIcon(destination: destination, selected: selected, badge: model.badgeFor(destination));
    if (!model.isSettings(destination)) return icon;
    return GestureDetector(onLongPress: model.onLongPressSettings, child: icon);
  }
}

/// The theme's picture behind the five main screens. Their own
/// backgrounds turn see-through; cards and bars keep theirs, and the
/// picture is dimmed more than behind the terminal.
class _ScreensBackdrop extends StatelessWidget {
  const _ScreensBackdrop({required this.theme, required this.slide, required this.child});

  final ThemeSpec theme;
  final ThemeSlide slide;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = Theme.of(context);
    final backdrop = theme.style.backdrop;
    return Stack(
      children: [
        Positioned.fill(
          child: ThemeBackdrop(
            theme: theme,
            slide: slide,
            color: AppColorsTheme.of(context).background,
            dim: backdrop.screenDim,
            blur: backdrop.blur,
          ),
        ),
        Theme(
          data: data.copyWith(
            scaffoldBackgroundColor: Colors.transparent,
            appBarTheme: data.appBarTheme.copyWith(backgroundColor: Colors.transparent),
          ),
          child: child,
        ),
      ],
    );
  }
}
