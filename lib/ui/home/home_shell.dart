import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../hosts/hosts_screen.dart';
import '../keys/keychain_screen.dart';
import '../sessions/sessions_screen.dart';
import '../settings/settings_screen.dart';
import '../snippets/snippets_screen.dart';

/// One top-level place in the app.
class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// The app's main frame: a bottom bar on phones, a side rail on wide
/// screens (tablets, desktop), with the five main places.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Screens at least this wide get the side rail.
  static const _railBreakpoint = 720.0;

  static const _destinations = [
    _Destination('Hosts', Icons.dns_outlined, Icons.dns),
    _Destination('Sessions', Icons.terminal_outlined, Icons.terminal),
    _Destination('Snippets', Icons.bolt_outlined, Icons.bolt),
    _Destination('Keychain', Icons.key_outlined, Icons.key),
    _Destination('Settings', Icons.tune_outlined, Icons.tune),
  ];

  int _index = 0;

  static const _pages = <Widget>[HostsScreen(), SessionsScreen(), SnippetsScreen(), KeychainScreen(), SettingsScreen()];

  void _select(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final sessions = AppScope.sessions(context);
    final wide = MediaQuery.sizeOf(context).width >= _railBreakpoint;
    final body = IndexedStack(index: _index, children: _pages);

    return ListenableBuilder(
      listenable: sessions,
      builder: (context, _) {
        final count = sessions.activeCount;
        Widget icon(_Destination d, {required bool selected}) {
          final glyph = Icon(selected ? d.selectedIcon : d.icon);
          return d.label == 'Sessions' && count > 0 ? Badge(label: Text('$count'), child: glyph) : glyph;
        }

        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(icon: icon(d, selected: false), selectedIcon: icon(d, selected: true), label: Text(d.label)),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            destinations: [
              for (final d in _destinations) NavigationDestination(icon: icon(d, selected: false), selectedIcon: icon(d, selected: true), label: d.label),
            ],
          ),
        );
      },
    );
  }
}
