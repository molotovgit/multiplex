import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/terminal_types.dart';
import 'package:multiplex/ui/keyboard/key_press_tracker.dart';
import 'package:multiplex/ui/keyboard/key_repeater.dart';
import 'package:multiplex/ui/keyboard/key_sink.dart';
import 'package:multiplex/ui/keyboard/key_spec.dart';
import 'package:multiplex/ui/keyboard/keyboard_engine.dart';
import 'package:multiplex/ui/keyboard/keyboard_layout.dart';
import 'package:multiplex/ui/keyboard/keyboard_modifiers.dart';
import 'package:multiplex/ui/keyboard/keyboard_rows.dart';
import 'package:multiplex/ui/keyboard/keyboard_settings.dart';
import 'package:multiplex/ui/keyboard/keyboard_settings_screen.dart';
import 'package:multiplex/ui/keyboard/keyboard_style.dart';
import 'package:multiplex/ui/keyboard/terminal_keyboard_panel.dart';

/// One thing the keyboard sent.
class Sent {
  const Sent(this.what, this.mods);

  /// "text:c", "key:enter" or "paste".
  final String what;
  final KeyModifiers mods;

  @override
  String toString() => '$what ${mods.ctrl ? 'C' : ''}${mods.alt ? 'A' : ''}${mods.shift ? 'S' : ''}';
}

/// Remembers what the keyboard sent instead of sending it.
class RecordingSink implements KeySink {
  final sent = <Sent>[];

  static const _none = KeyModifiers(ctrl: false, alt: false, shift: false);

  List<String> get whats => [for (final s in sent) s.what];

  @override
  void sendText(String text, KeyModifiers mods) => sent.add(Sent('text:$text', mods));

  @override
  void sendKey(TerminalKey key, KeyModifiers mods) => sent.add(Sent('key:${key.name}', mods));

  @override
  void pasteClipboard() => sent.add(const Sent('paste', _none));
}

/// A clock the test moves by hand.
class FakeClock {
  Duration now = Duration.zero;

  Duration read() => now;

  void advance(int ms) => now += Duration(milliseconds: ms);
}

/// Builds stores and keyboards for the widget tests.
abstract final class KeyboardFixture {
  static Future<(VaultStore, SessionManager)> pump(WidgetTester tester, Widget Function() body, {Size size = const Size(400, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await VaultStore.open(MemoryBackend());
    final sessions = SessionManager(store);
    await tester.pumpWidget(AppScope(
      vault: store,
      manager: sessions,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) => MaterialApp(theme: AppTheme.build(store.activeTheme), home: body()),
      ),
    ));
    await tester.pumpAndSettle();
    return (store, sessions);
  }

  static Widget panel(RecordingSink sink, {KeyboardModifiers? modifiers, List<String>? events}) => Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox.expand()),
            TerminalKeyboardPanel.withSink(
              sink: sink,
              modifiers: modifiers,
              onSnippets: () => events?.add('snippets'),
              onHide: () => events?.add('hide'),
              onSwitchToSystem: () => events?.add('system'),
            ),
          ],
        ),
      );

  /// Lets the store's delayed save run, then stops the sessions.
  static Future<void> finish(WidgetTester tester, SessionManager sessions) async {
    await tester.pump(const Duration(seconds: 2));
    sessions.dispose();
  }
}

void main() {
  group('layouts', () {
    List<String> lettersOf(KeyboardLayoutKind kind, int row) => [
          for (final k in KeyboardLayout.of(kind).page(KeyboardPage.letters)[row])
            if (k.isLetter) k.label,
        ];

    test('each layout puts its letters in the right order', () {
      expect(lettersOf(KeyboardLayoutKind.qwerty, 1).join(), 'qwertyuiop');
      expect(lettersOf(KeyboardLayoutKind.qwertz, 1).join(), 'qwertzuiop');
      expect(lettersOf(KeyboardLayoutKind.qwertz, 3).join(), 'yxcvbnm');
      expect(lettersOf(KeyboardLayoutKind.azerty, 1).join(), 'azertyuiop');
      expect(lettersOf(KeyboardLayoutKind.azerty, 2).join(), 'qsdfghjklm');
    });

    test('every page has five rows no wider than ten units', () {
      for (final kind in KeyboardLayoutKind.values) {
        for (final page in KeyboardPage.values) {
          final rows = KeyboardLayout.of(kind).page(page);
          expect(rows, hasLength(5), reason: '$kind $page');
          for (final row in rows) {
            expect(row.fold<double>(0, (s, k) => s + k.width), lessThanOrEqualTo(10.001));
          }
        }
      }
    });

    test('all shell symbols are on the symbols page and F1 to F12 on the function page', () {
      final layout = KeyboardLayout.of(KeyboardLayoutKind.qwerty);
      final typed = {
        for (final row in layout.page(KeyboardPage.symbols))
          for (final k in row)
            if (k.action case TypeText(:final text)) text,
      };
      for (final c in r'|&;<>(){}[]$`' "'" r'"\~^*?!#%=+-_/:@,.'.split('')) {
        expect(typed, contains(c), reason: c);
      }
      final keys = {
        for (final row in layout.page(KeyboardPage.functions))
          for (final k in row)
            if (k.action case SendKey(:final key)) key,
      };
      expect(keys, containsAll([...KeyboardKeys.fKeys, TerminalKey.home, TerminalKey.end, TerminalKey.pageUp, TerminalKey.pageDown, TerminalKey.insert, TerminalKey.delete]));
    });

    test('alternates: symbols on letters, F-keys on digits, accents on European layouts', () {
      final alt = KeyAlternates(KeyboardLayoutKind.qwerty);
      expect(alt.of('a').map((k) => k.label), ['@']);
      expect(alt.of('-').map((k) => k.label), ['_', '~']);
      expect(alt.of('/').map((k) => k.label), [r'\', '|']);
      expect(alt.of('1').map((k) => k.label), ['!', 'F1']);
      expect(KeyAlternates(KeyboardLayoutKind.qwertz).of('u').map((k) => k.label), [']', 'ü']);
      expect(KeyAlternates(KeyboardLayoutKind.azerty).of('e').map((k) => k.label), ['|', 'é', 'è', 'ê', 'ë']);
    });

    test('the top row keeps the key bar order and always has Ctrl and Alt', () {
      final keys = TerminalTopRow.keysFor(['tab', 'esc', 'up']);
      expect(keys.map((k) => k.label), ['Ctrl', 'Alt', 'Tab', 'Esc', '↑']);
      expect(keys.last.repeats, isTrue);
      final full = TerminalTopRow.keysFor(['esc', 'alt', 'ctrl']);
      expect(full.map((k) => k.label), ['Esc', 'Alt', 'Ctrl']);
    });
  });

  group('modifiers', () {
    test('one tap is one shot, a quick second tap locks, a third turns off', () {
      final clock = FakeClock();
      final mods = KeyboardModifiers(clock: clock.read);
      mods.tap(ModifierKind.ctrl);
      expect(mods.modeOf(ModifierKind.ctrl), ModifierMode.oneShot);
      expect(mods.take().ctrl, isTrue);
      expect(mods.modeOf(ModifierKind.ctrl), ModifierMode.off);

      mods.tap(ModifierKind.ctrl);
      clock.advance(200);
      mods.tap(ModifierKind.ctrl);
      expect(mods.modeOf(ModifierKind.ctrl), ModifierMode.locked);
      expect(mods.take().ctrl, isTrue);
      expect(mods.take().ctrl, isTrue, reason: 'locked stays on');
      clock.advance(1000);
      mods.tap(ModifierKind.ctrl);
      expect(mods.modeOf(ModifierKind.ctrl), ModifierMode.off);
    });

    test('a slow second tap turns a one-shot modifier off', () {
      final clock = FakeClock();
      final mods = KeyboardModifiers(clock: clock.read);
      mods.tap(ModifierKind.alt);
      clock.advance(600);
      mods.tap(ModifierKind.alt);
      expect(mods.modeOf(ModifierKind.alt), ModifierMode.off);
    });

    test('the engine applies one-shot Ctrl once and Shift makes capitals', () {
      final sink = RecordingSink();
      final engine = KeyboardEngine(sink: sink, modifiers: KeyboardModifiers(clock: FakeClock().read));
      engine.perform(const ToggleModifier(ModifierKind.ctrl));
      engine.perform(const TypeText('c'));
      engine.perform(const TypeText('d'));
      expect(sink.sent[0].what, 'text:c');
      expect(sink.sent[0].mods.ctrl, isTrue);
      expect(sink.sent[1].mods.ctrl, isFalse);

      engine.perform(const ToggleModifier(ModifierKind.shift));
      engine.perform(const TypeText('a'));
      engine.perform(const TypeText('b'));
      expect(sink.whats.sublist(2), ['text:A', 'text:b']);

      engine.perform(const ToggleModifier(ModifierKind.shift));
      engine.perform(const SendKey(TerminalKey.tab));
      expect(sink.sent.last.mods.shift, isTrue, reason: 'Shift+Tab');
    });

    test('Ctrl and Alt from the controller and the keyboard combine', () {
      final mods = const ActiveModifiers(ctrl: true, alt: true, shift: true);
      expect(mods.forText().shift, isFalse);
      expect(mods.forKey().shift, isTrue);
      expect(mods.prefix, 'Ctrl+Alt+');
    });
  });

  group('press tracking', () {
    final dash = KeySpec.text('-', alternates: [KeySpec.text('_'), KeySpec.text('~')]);
    final geometry = const ChoiceGeometry(left: 0, cell: 40, count: 2);

    test('a tap sends the key on release', () {
      final sent = <KeySpec>[];
      final tracker = KeyPressTracker(onSend: sent.add, onCursor: (_) {});
      tracker.down(Offset.zero, dash);
      tracker.up();
      expect(sent.single.label, '-');
    });

    testWidgets('long press opens the alternates; sliding picks one', (tester) async {
      final sent = <KeySpec>[];
      final tracker = KeyPressTracker(onSend: sent.add, onCursor: (_) {});
      tracker.down(const Offset(10, 20), dash, geometry: geometry);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tracker.phase, PressPhase.pressed);
      await tester.pump(const Duration(milliseconds: 60));
      expect(tracker.phase, PressPhase.choosing);
      tracker.move(const Offset(55, 20));
      expect(tracker.choice, 1);
      tracker.up();
      expect(sent.single.label, '~');
    });

    test('swipe up sends the first alternate', () {
      final sent = <KeySpec>[];
      final tracker = KeyPressTracker(onSend: sent.add, onCursor: (_) {});
      tracker.down(const Offset(10, 40), dash);
      tracker.move(const Offset(12, 5));
      expect(tracker.phase, PressPhase.swiped);
      expect(tracker.previewKey?.label, '_');
      tracker.up();
      expect(sent.single.label, '_');
    });

    test('swipe is ignored when the setting is off', () {
      final sent = <KeySpec>[];
      final tracker = KeyPressTracker(onSend: sent.add, onCursor: (_) {});
      tracker.down(const Offset(10, 40), dash, options: const PressOptions(swipe: false));
      tracker.move(const Offset(12, 5));
      tracker.up();
      expect(sent.single.label, '-');
    });

    test('dragging the space bar moves the cursor and types no space', () {
      final sent = <KeySpec>[];
      final arrows = <TerminalKey>[];
      final tracker = KeyPressTracker(onSend: sent.add, onCursor: arrows.add);
      tracker.down(const Offset(100, 20), KeyboardKeys.space(3));
      tracker.move(const Offset(145, 20));
      expect(arrows, [TerminalKey.right, TerminalKey.right, TerminalKey.right]);
      tracker.move(const Offset(100, 20));
      expect(arrows.skip(3), [TerminalKey.left, TerminalKey.left, TerminalKey.left]);
      tracker.move(const Offset(100, -10));
      expect(arrows.last, TerminalKey.up);
      tracker.up();
      expect(sent, isEmpty);
    });

    test('moving sideways in the scrolling row cancels the press', () {
      final sent = <KeySpec>[];
      final tracker = KeyPressTracker(onSend: sent.add, onCursor: (_) {});
      tracker.down(Offset.zero, KeyboardKeys.arrow(TerminalKey.up), options: const PressOptions(inScrollingRow: true));
      tracker.move(const Offset(30, 0));
      tracker.up();
      expect(sent, isEmpty);
    });

    testWidgets('holding a repeating key repeats after 400 ms, then every 50 ms', (tester) async {
      final sent = <KeySpec>[];
      final tracker = KeyPressTracker(onSend: sent.add, onCursor: (_) {});
      tracker.down(Offset.zero, KeyboardKeys.backspace(1));
      await tester.pump(const Duration(milliseconds: 399));
      expect(sent, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(sent, hasLength(1));
      expect(tracker.phase, PressPhase.repeating);
      await tester.pump(const Duration(milliseconds: 50));
      expect(sent, hasLength(2));
      await tester.pump(const Duration(milliseconds: 500));
      expect(sent, hasLength(12));
      tracker.up();
      await tester.pump(const Duration(seconds: 1));
      expect(sent, hasLength(12), reason: 'release stops it and sends nothing more');
    });

    testWidgets('a short press of a repeating key sends it once', (tester) async {
      final sent = <KeySpec>[];
      final tracker = KeyPressTracker(onSend: sent.add, onCursor: (_) {});
      tracker.down(Offset.zero, KeyboardKeys.backspace(1));
      await tester.pump(const Duration(milliseconds: 100));
      tracker.up();
      await tester.pump(const Duration(seconds: 1));
      expect(sent, hasLength(1));
    });

    testWidgets('the repeater counts its repeats and stops', (tester) async {
      var count = 0;
      final repeater = KeyRepeater()..start(() => count++);
      await tester.pump(KeyRepeater.delay + KeyRepeater.interval * 3);
      expect(count, 4);
      expect(repeater.fired, 4);
      repeater.stop();
      await tester.pump(const Duration(seconds: 1));
      expect(count, 4);
      expect(repeater.running, isFalse);
    });
  });

  group('settings', () {
    test('JSON round trip keeps every option', () {
      const custom = KeyboardSettings(
        enabled: false,
        layout: KeyboardLayoutKind.azerty,
        keyHeight: KeyHeightOption.large,
        shape: KeyShape.square,
        boldLabels: true,
        showAlternates: false,
        swipeForSymbols: false,
        keyPreview: false,
        haptics: false,
        sound: true,
      );
      expect(KeyboardSettings.fromJson(custom.toJson()), custom);
      expect(KeyboardSettings.fromJson(const {}), const KeyboardSettings());
      expect(KeyboardSettings.fromJson(const {'layout': 'dvorak', 'haptics': 'yes'}), const KeyboardSettings());
    });

    test('saved settings are read back from the store', () async {
      final store = await VaultStore.open(MemoryBackend());
      const KeyboardSettings(layout: KeyboardLayoutKind.qwertz, sound: true).saveTo(store);
      expect(store.settings.keyboard['layout'], 'qwertz');
      expect(KeyboardSettings.of(store).sound, isTrue);
    });

    test('key sizes follow the height option and shrink in landscape', () {
      const portrait = Size(400, 800);
      final compact = KeyboardMetrics.resolve(const KeyboardSettings(keyHeight: KeyHeightOption.compact), portrait);
      final large = KeyboardMetrics.resolve(const KeyboardSettings(keyHeight: KeyHeightOption.large), portrait);
      expect(compact.rowHeight, greaterThanOrEqualTo(44));
      expect(large.rowHeight, greaterThan(compact.rowHeight));
      final landscape = KeyboardMetrics.resolve(const KeyboardSettings(), const Size(800, 380));
      expect(landscape.height, lessThanOrEqualTo(380 * KeyboardMetrics.landscapeShare + 0.01));
      final square = KeyboardMetrics.resolve(const KeyboardSettings(shape: KeyShape.square), portrait);
      expect(square.radius, lessThan(compact.radius));
    });
  });

  group('panel', () {
    testWidgets('one-shot and locked Ctrl through the keys', (tester) async {
      final sink = RecordingSink();
      final clock = FakeClock();
      final (_, sessions) = await KeyboardFixture.pump(tester, () => KeyboardFixture.panel(sink, modifiers: KeyboardModifiers(clock: clock.read)));

      await tester.tap(find.text('Ctrl'));
      await tester.pump();
      expect(find.bySemanticsLabel('Control, on for the next key'), findsOneWidget);
      await tester.tap(find.text('c'));
      await tester.pump();
      expect(sink.sent.single.what, 'text:c');
      expect(sink.sent.single.mods.ctrl, isTrue);
      expect(find.bySemanticsLabel('Control'), findsOneWidget);

      await tester.tap(find.text('Ctrl'));
      clock.advance(100);
      await tester.tap(find.text('Ctrl'));
      await tester.pump();
      expect(find.bySemanticsLabel('Control, locked'), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);
      await tester.tap(find.text('x'));
      await tester.tap(find.text('z'));
      await tester.pump();
      expect(sink.sent.skip(1).every((s) => s.mods.ctrl), isTrue);
      await KeyboardFixture.finish(tester, sessions);
    });

    testWidgets('long press shows alternates and release sends the choice', (tester) async {
      final sink = RecordingSink();
      final (_, sessions) = await KeyboardFixture.pump(tester, () => KeyboardFixture.panel(sink));
      final gesture = await tester.startGesture(tester.getCenter(find.text('1')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('F1'), findsOneWidget, reason: 'the popup is open');
      await gesture.moveBy(const Offset(44, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(sink.whats, ['key:f1']);
      expect(find.text('F1'), findsNothing);
      await KeyboardFixture.finish(tester, sessions);
    });

    testWidgets('pages switch, and the command keys call back', (tester) async {
      final sink = RecordingSink();
      final events = <String>[];
      final (_, sessions) = await KeyboardFixture.pump(tester, () => KeyboardFixture.panel(sink, events: events));
      await tester.tap(find.text('?123'));
      await tester.pump();
      expect(find.text('{'), findsOneWidget);
      await tester.tap(find.text('{'));
      await tester.tap(find.text('Fn'));
      await tester.pump();
      expect(find.text('F12'), findsOneWidget);
      await tester.tap(find.text('F12'));
      await tester.tap(find.bySemanticsLabel('Hide the keyboard'));
      await tester.tap(find.bySemanticsLabel('Use the system keyboard'));
      await tester.tap(find.bySemanticsLabel('Snippets').last);
      await tester.pump();
      expect(sink.whats, ['text:{', 'key:f12']);
      expect(events, ['hide', 'system', 'snippets']);
      await KeyboardFixture.finish(tester, sessions);
    });

    testWidgets('dragging the space bar sends arrows', (tester) async {
      final sink = RecordingSink();
      final (_, sessions) = await KeyboardFixture.pump(tester, () => KeyboardFixture.panel(sink));
      final gesture = await tester.startGesture(tester.getCenter(find.text('Space')));
      await gesture.moveBy(const Offset(30, 0));
      await gesture.moveBy(const Offset(30, 0));
      await gesture.up();
      await tester.pump();
      expect(sink.whats, everyElement('key:right'));
      expect(sink.whats.length, 4);
      await KeyboardFixture.finish(tester, sessions);
    });

    testWidgets('keys take their colours from the active theme', (tester) async {
      final sink = RecordingSink();
      final (store, sessions) = await KeyboardFixture.pump(tester, () => KeyboardFixture.panel(sink));
      Color keyColour() {
        final box = tester.widget<DecoratedBox>(find.ancestor(of: find.text('q'), matching: find.byType(DecoratedBox)).first);
        return (box.decoration as BoxDecoration).color!;
      }

      Color panelColour() => tester.widget<Material>(find.ancestor(of: find.byType(TerminalTopRow), matching: find.byType(Material)).first).color!;

      expect(keyColour(), AppColors.derive(BuiltInThemes.ember).raised);
      expect(panelColour(), AppColors.derive(BuiltInThemes.ember).surface);
      store.updateSettings(store.settings.copyWith(themeId: BuiltInThemes.paper.id));
      await tester.pumpAndSettle();
      expect(keyColour(), AppColors.derive(BuiltInThemes.paper).raised);
      expect(panelColour(), AppColors.derive(BuiltInThemes.paper).surface);
      expect(AppColors.derive(BuiltInThemes.paper).raised, isNot(AppColors.derive(BuiltInThemes.ember).raised));
      await KeyboardFixture.finish(tester, sessions);
    });

    testWidgets('the layout setting changes the letters', (tester) async {
      final sink = RecordingSink();
      final (store, sessions) = await KeyboardFixture.pump(tester, () => KeyboardFixture.panel(sink));
      expect(tester.getCenter(find.text('q')).dy, lessThan(tester.getCenter(find.text('a')).dy));
      const KeyboardSettings(layout: KeyboardLayoutKind.azerty).saveTo(store);
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('a')).dy, lessThan(tester.getCenter(find.text('q')).dy));
      await KeyboardFixture.finish(tester, sessions);
    });
  });

  group('settings screen', () {
    testWidgets('switches save at once and the preview echoes keys', (tester) async {
      final (store, sessions) = await KeyboardFixture.pump(tester, () => const KeyboardSettingsScreen(), size: const Size(400, 1600));
      await tester.tap(find.text('Bold labels'));
      await tester.pump();
      expect(KeyboardSettings.of(store).boldLabels, isTrue);
      await tester.tap(find.text('Square'));
      await tester.pump();
      expect(KeyboardSettings.of(store).shape, KeyShape.square);
      await tester.tap(find.text('Ctrl'));
      await tester.tap(find.text('c'));
      await tester.pump();
      expect(find.text('Sent Ctrl+C'), findsOneWidget);
      await KeyboardFixture.finish(tester, sessions);
    });
  });
}
