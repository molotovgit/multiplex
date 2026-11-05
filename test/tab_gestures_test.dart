import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/multiplex_app.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/app/theme_style.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/ui/appearance/theme_switcher.dart';

/// Opens the app at phone size in a theme with [style].
Future<(VaultStore, SessionManager)> _open(WidgetTester tester, {ThemeStyle style = const ThemeStyle()}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = await VaultStore.open(MemoryBackend());
  final sessions = SessionManager(store);
  store.saveTheme(BuiltInThemes.matteBlack.copyWith(id: 'styled', name: 'Styled', style: style));
  store.updateSettings(store.settings.copyWith(themeId: 'styled'));
  await tester.pumpWidget(MultiplexApp(store: store, sessions: sessions));
  await tester.pumpAndSettle();
  return (store, sessions);
}

Future<void> _finish(WidgetTester tester, SessionManager sessions) async {
  await tester.pump(const Duration(seconds: 2));
  sessions.dispose();
}

int _selected(WidgetTester tester) => tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

/// The middle of the bar's slot [i] of five.
Offset _slot(WidgetTester tester, int i) {
  final bar = tester.getRect(find.byType(NavigationBar));
  return Offset(bar.left + bar.width * (i + 0.5) / 5, bar.center.dy);
}

void main() {
  testWidgets('swiping the screen sideways moves to the next and back', (tester) async {
    final (_, sessions) = await _open(tester);
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(_selected(tester), 1);
    expect(find.text('Sessions'), findsWidgets);
    await tester.fling(find.byType(PageView), const Offset(300, 0), 1500);
    await tester.pumpAndSettle();
    expect(_selected(tester), 0);
    await _finish(tester, sessions);
  });

  testWidgets('sliding a finger along the bar takes the screens with it', (tester) async {
    final (_, sessions) = await _open(tester);
    final gesture = await tester.startGesture(_slot(tester, 0));
    for (var i = 1; i <= 20; i++) {
      await gesture.moveTo(Offset.lerp(_slot(tester, 0), _slot(tester, 3), i / 20)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_selected(tester), 3);
    await _finish(tester, sessions);
  });

  testWidgets('hold the bar, then slide to a tab', (tester) async {
    final (_, sessions) = await _open(tester);
    final gesture = await tester.startGesture(_slot(tester, 1));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(_slot(tester, 1), _slot(tester, 2), i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_selected(tester), 2);
    expect(find.byType(ThemeSwitcherSheet), findsNothing);
    await _finish(tester, sessions);
  });

  testWidgets('a tap still opens a tab, and screens keep their state', (tester) async {
    final (_, sessions) = await _open(tester);
    await tester.enterText(find.byType(TextField).first, 'web');
    await tester.tapAt(_slot(tester, 2));
    await tester.pumpAndSettle();
    expect(_selected(tester), 2);
    await tester.tapAt(_slot(tester, 0));
    await tester.pumpAndSettle();
    expect(find.text('web'), findsOneWidget);
    await _finish(tester, sessions);
  });

  testWidgets('changing to a theme with another bar keeps the open screen', (tester) async {
    final (store, sessions) = await _open(tester);
    await tester.tapAt(_slot(tester, 4));
    await tester.pumpAndSettle();
    store.updateSettings(store.settings.copyWith(themeId: BuiltInThemes.tokyoNight.id)); // a floating bar
    await tester.pumpAndSettle();
    expect(_selected(tester), 4);
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 4);
    await _finish(tester, sessions);
  });
}
