import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/ui/terminal/terminal_gestures.dart';

void main() {
  TerminalGestureTracker tracker() => TerminalGestureTracker(minSize: 8, maxSize: 28);

  String describe(GestureStep step) => switch (step) {
        ScrollStep(:final pixels) => 'scroll $pixels',
        FontStep(:final size) => 'font $size',
        NoStep() => 'none',
      };

  test('one finger always scrolls, from the first movement', () {
    final t = tracker()..start(pointers: 1, fontSize: 14);
    expect(describe(t.update(scale: 1, dy: 3)), 'scroll 3.0');
    expect(describe(t.update(scale: 1, dy: -5)), 'scroll -5.0');
    expect(t.end(), isNull);
  });

  test('two fingers moving together scroll once they moved far enough', () {
    final t = tracker()..start(pointers: 2, fontSize: 14);
    expect(describe(t.update(scale: 1.01, dy: 5)), 'none');
    // The movement held back so far is not lost.
    expect(describe(t.update(scale: 1.02, dy: 8)), 'scroll 13.0');
    expect(describe(t.update(scale: 1.03, dy: 4)), 'scroll 4.0');
    expect(t.end(), isNull);
  });

  test('a scroll that starts never turns into a pinch', () {
    final t = tracker()..start(pointers: 2, fontSize: 14);
    t.update(scale: 1, dy: 20);
    expect(describe(t.update(scale: 1.5, dy: 2)), 'scroll 2.0');
    expect(t.end(), isNull);
  });

  test('a pinch changes the size live and gives the size to save at the end', () {
    final t = tracker()..start(pointers: 2, fontSize: 14);
    expect(describe(t.update(scale: 1.1, dy: 1)), 'font 15.0');
    expect(t.isPinching, isTrue);
    // Moving the fingers up while pinching does not scroll.
    expect(describe(t.update(scale: 1.1, dy: 30)), 'none');
    expect(describe(t.update(scale: 1.5, dy: 0)), 'font 21.0');
    expect(t.end(), 21);
  });

  test('the size stays within the limits', () {
    final t = tracker()..start(pointers: 2, fontSize: 14);
    expect(describe(t.update(scale: 4, dy: 0)), 'font 28.0');
    expect(describe(t.update(scale: 0.1, dy: 0)), 'font 8.0');
  });

  test('a pinch back to the start size saves nothing', () {
    final t = tracker()..start(pointers: 2, fontSize: 14);
    t.update(scale: 1.2, dy: 0);
    t.update(scale: 1.0, dy: 0);
    expect(t.end(), isNull);
  });
}
