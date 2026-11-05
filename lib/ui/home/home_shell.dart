import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../app/app_icons.dart';
import '../../app/app_motion.dart';
import '../../app/gloss.dart';
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
import 'tab_scrub.dart';

/// One top-level place in the app.
class _Destination {
  const _Destination(this.label, this.icon);

  final String label;
  final AppIconPair icon;
}

/// The app's main frame with the five main places. The theme's style picks
/// the navigation: a bottom bar with or without labels, a floating bar, or
/// a side rail. Wide screens (tablets, desktop) always get the side rail,
/// unless the floating bar is chosen. Swiping sideways moves between the
/// places, and so does sliding a finger along the bottom bar. A long press
/// on Settings opens the theme switcher.
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

  final _pager = PageController();

  /// Keeps the screens, and which one is open, when a theme change moves
  /// them to another place in the tree (another navigation style).
  final _pagesKey = GlobalKey();

  /// Set while a tap on the bar animates the screens there, so the tabs
  /// passed on the way do not light up.
  int? _target;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    if (!_pager.hasClients) return;
    final duration = AppMotion.of(context).page;
    if (duration == Duration.zero) {
      _pager.jumpToPage(index);
      return;
    }
    _target = index;
    _pager.animateToPage(index, duration: duration, curve: Curves.easeOutCubic).whenComplete(() => _target = null);
  }

  void _paged(int index) {
    if (_target != null && index != _target) return;
    if (index == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final sessions = AppScope.sessions(context);
    final look = AppStyleTheme.of(context);
    final nav = look.style.nav;
    final wide = MediaQuery.sizeOf(context).width >= _railBreakpoint;
    final store = AppScope.watch(context);
    final theme = store.activeTheme;
    final pages = PageView(
      key: _pagesKey,
      controller: _pager,
      onPageChanged: _paged,
      children: [for (final page in _pages) _KeepAlive(child: page)],
    );
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
          pages: _pager,
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
          return Scaffold(extendBody: true, body: _ClearOfBar(child: body), bottomNavigationBar: _FloatingNavBar(model: bar));
        }
        return Scaffold(
          extendBody: look.surfaces.isGlass,
          body: look.surfaces.isGlass ? _ClearOfBar(child: body) : body,
          bottomNavigationBar: _GlassBackdrop(
            enabled: look.surfaces.isGlass,
            child: _ShellNavigationBar(model: bar, labels: nav == NavStyle.labelled),
          ),
        );
      },
    );
  }
}

/// For pages that run on under the bottom bar. Scaffold adds the bar's
/// height to their padding but not to their view padding, which is what a
/// page's own floating button keeps clear of, so "New host" and the like
/// would sit hidden behind the bar.
class _ClearOfBar extends StatelessWidget {
  const _ClearOfBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottom = math.max(media.viewPadding.bottom, media.padding.bottom);
    return MediaQuery(data: media.copyWith(viewPadding: media.viewPadding.copyWith(bottom: bottom)), child: child);
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
    required this.pages,
  });

  final List<_Destination> destinations;

  /// The screens; the bar's gestures move them.
  final PageController pages;
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
/// their names for screen readers. A finger on the bar can also slide
/// between the screens (see [TabScrub]).
class _ShellNavigationBar extends StatefulWidget {
  const _ShellNavigationBar({required this.model, required this.labels, this.height, this.background});

  final _NavModel model;
  final bool labels;
  final double? height;
  final Color? background;

  @override
  State<_ShellNavigationBar> createState() => _ShellNavigationBarState();
}

class _ShellNavigationBarState extends State<_ShellNavigationBar> {
  /// Material's mark behind a bar icon.
  static const _iconMark = Size(64, 32);

  final _stackKey = GlobalKey();

  /// Where the middle of the icons sits from the top of the bar, measured
  /// after layout: it depends on the label's font and size, and on whether
  /// a label wraps.
  double? _iconY;

  void _measure(Duration _) {
    if (!mounted) return;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final icon = _IconProbe.find(stack);
    if (stack == null || icon == null || !icon.hasSize) return;
    final y = stack.globalToLocal(icon.localToGlobal(icon.size.center(Offset.zero))).dy;
    if (_iconY == null || (y - _iconY!).abs() > 0.5) setState(() => _iconY = y);
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model, labels = widget.labels, height = widget.height, background = widget.background;
    WidgetsBinding.instance.addPostFrameCallback(_measure);
    final theme = NavigationBarTheme.of(context);
    final barHeight = height ?? theme.height ?? 80;
    final count = model.destinations.length;
    final bar = NavigationBar(
          selectedIndex: model.index,
          onDestinationSelected: model.onSelect,
          height: height,
          // The bar's own colour and mark are drawn underneath, so the mark
          // can stretch and flow between the tabs.
          backgroundColor: Colors.transparent,
          elevation: 0,
          indicatorColor: Colors.transparent,
          labelBehavior: labels ? NavigationDestinationLabelBehavior.alwaysShow : NavigationDestinationLabelBehavior.alwaysHide,
          destinations: [
            for (final d in model.destinations)
              NavigationDestination(
                icon: _IconProbe(child: _NavIcon(destination: d, selected: false, badge: model.badgeFor(d))),
                selectedIcon: _IconProbe(child: _NavIcon(destination: d, selected: true, badge: model.badgeFor(d))),
                label: d.label,
                // A long press on the bar moves between the screens (and
                // opens the theme switcher on Settings), so no tooltips.
                tooltip: '',
              ),
          ],
        );
    final glossy = AppStyleTheme.of(context).surfaces.isGlossy;
    final barColor = background ?? theme.backgroundColor;
    return Material(
      color: glossy ? Colors.transparent : barColor,
      elevation: theme.elevation ?? 0,
      shadowColor: theme.shadowColor,
      surfaceTintColor: Colors.transparent,
      // Glossy bars are banded like a taskbar, with a shine on top.
      shape: glossy ? const GlossBorder() : null,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: glossy && barColor != null && barColor.a > 0 ? Gloss.band(barColor) : null),
        child: TabScrub(
        count: count,
        pages: model.pages,
        settingsSlot: _HomeShellState._settingsIndex,
        onHoldSettings: model.onLongPressSettings,
        child: Stack(
          key: _stackKey,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: barHeight,
              child: LayoutBuilder(
                builder: (context, box) {
                  final slot = box.maxWidth / count;
                  return FlowingTabIndicator(
                    count: count,
                    pages: model.pages,
                    index: model.index,
                    color: theme.indicatorColor ?? Theme.of(context).colorScheme.secondaryContainer,
                    // Just behind the icon, the size of Material's own mark.
                    size: Size(math.min(slot - 8, _iconMark.width), _iconMark.height),
                    centerY: _iconY,
                    // A pushed-in taskbar button rather than a pill.
                    shape: glossy ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)) : const StadiumBorder(),
                  );
                },
              ),
            ),
            bar,
          ],
        ),
      ),
      ),
    );
  }
}

/// Marks a bar icon so the bar can find where Material put it.
class _IconProbe extends SingleChildRenderObjectWidget {
  const _IconProbe({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderIconProbe();

  /// The first marked icon under [root], if any.
  static RenderBox? find(RenderObject? root) {
    RenderBox? found;
    void visit(RenderObject node) {
      if (found != null) return;
      if (node is _RenderIconProbe) {
        found = node;
        return;
      }
      node.visitChildren(visit);
    }

    if (root != null) visit(root);
    return found;
  }
}

class _RenderIconProbe extends RenderProxyBox {}

/// The side rail, kept clear of a notch or camera cut-out.
class _ShellRail extends StatelessWidget {
  const _ShellRail({required this.model, required this.labels});

  final _NavModel model;
  final bool labels;

  /// Narrower than this, labels would take a quarter of the screen from
  /// the pages, so the rail shows icons only.
  static const _labelsFrom = 600.0;

  @override
  Widget build(BuildContext context) {
    final roomy = MediaQuery.sizeOf(context).width >= _labelsFrom;
    return SafeArea(
      right: false,
      child: NavigationRail(
        selectedIndex: model.index,
        onDestinationSelected: model.onSelect,
        minWidth: roomy ? 72 : 56,
        labelType: labels && roomy ? NavigationRailLabelType.all : NavigationRailLabelType.none,
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
}

/// A rounded bar that floats above the content, inset from the edges and
/// clear of the gesture bar.
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({required this.model});

  final _NavModel model;

  static const _maxWidth = 560.0;
  static const _height = 64.0;
  static const _endInset = 12.0;

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
                // The end items keep clear of the bar's round ends.
                child: ColoredBox(
                  color: surfaces.bar,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _endInset),
                    child: _ShellNavigationBar(model: model, labels: true, height: _height, background: Colors.transparent),
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

/// Keeps a main screen alive while another one is shown, so its scroll
/// position and anything typed are still there when the user comes back.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
