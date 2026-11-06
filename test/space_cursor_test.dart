import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/src/rust/api/terminal_types.dart';
import 'package:multiplex/ui/keyboard/key_press_tracker.dart';
import 'package:multiplex/ui/keyboard/key_sink.dart';
import 'package:multiplex/ui/keyboard/keyboard_engine.dart';
import 'package:multiplex/ui/keyboard/keyboard_layout.dart';
import 'package:multiplex/ui/keyboard/keyboard_settings.dart';

/// Keeps the keys the engine sent.
class KeysSink implements KeySink {
  final keys = <TerminalKey>[];

  @override
  void sendText(String text, KeyModifiers mods) {}

  @override
  void sendKey(TerminalKey key, KeyModifiers mods) => keys.add(key);

  @override
  void pasteClipboard() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('space bar cursor', () {
    late List<String> sent;
    late List<TerminalKey> moves;
    late KeyPressTracker tracker;
    final space = KeyboardKeys.space(3);

    setUp(() {
      sent = [];
      moves = [];
      tracker = KeyPressTracker(onSend: (key) => sent.add(key.label), onCursor: moves.add);
    });
    tearDown(() => tracker.dispose());

    test('a plain tap types a space', () {
      tracker.down(Offset.zero, space, options: const PressOptions(cursorStep: 8));
      tracker.move(const Offset(4, 1));
      tracker.up();
      expect(sent, ['Space']);
      expect(moves, isEmpty);
    });

    test('a sideways drag moves one cell per cell width and types nothing', () {
      tracker.down(Offset.zero, space, options: const PressOptions(cursorStep: 8));
      tracker.move(const Offset(12, 0));
      expect(moves, [TerminalKey.right]);
      tracker.move(const Offset(40, 0));
      expect(moves.where((k) => k == TerminalKey.right), hasLength(5));
      tracker.move(const Offset(20, 0));
      expect(moves.where((k) => k == TerminalKey.left), hasLength(2));
      tracker.up();
      expect(sent, isEmpty);
    });

    test('a tiny cell width still needs a few pixels per step', () {
      tracker.down(Offset.zero, space, options: const PressOptions(cursorStep: 2));
      tracker.move(const Offset(30, 0));
      expect(moves, hasLength(30 ~/ KeyPressTracker.minStepX));
    });
  });

  group('KeyboardEngine.moveCursor', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
    });
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    bool ticked() => calls.any((c) => c.method == 'HapticFeedback.vibrate' && c.arguments == 'HapticFeedbackType.selectionClick');

    test('sends the arrow with a light tick', () {
      final sink = KeysSink();
      final engine = KeyboardEngine(sink: sink)..settings = const KeyboardSettings(haptics: true);
      engine.moveCursor(TerminalKey.left);
      expect(sink.keys, [TerminalKey.left]);
      expect(ticked(), isTrue);
      engine.dispose();
    });

    test('no tick when haptics are off', () {
      final sink = KeysSink();
      final engine = KeyboardEngine(sink: sink)..settings = const KeyboardSettings(haptics: false);
      engine.moveCursor(TerminalKey.right);
      expect(sink.keys, [TerminalKey.right]);
      expect(ticked(), isFalse);
      engine.dispose();
    });
  });
}
