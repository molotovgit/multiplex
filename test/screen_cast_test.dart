import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/sessions/screen_cast.dart';

/// Android's part: says yes or no, then gives pieces of the picture.
class _Capture extends ScreenCapture {
  _Capture({this.allow = true});

  final bool allow;
  final pieces_ = StreamController<Uint8List>.broadcast();
  int stopped = 0;
  final adjusted = <String>[];

  @override
  Future<void> adjust({int? bitrate, bool keyFrame = false}) async => adjusted.add('$bitrate $keyFrame');

  int? startedAt;

  @override
  Future<bool> start({required int bitrate}) async {
    startedAt = bitrate;
    return allow;
  }

  @override
  Future<void> stop() async => stopped++;

  @override
  Stream<Uint8List> pieces() => pieces_.stream;
}

/// The window on the computer.
class _Window extends ScreenWindow {
  final got = <int>[];
  final ended_ = StreamController<String>.broadcast();

  /// What the next write answers, when it is not a plain "sent".
  ScreenWrote? answer;
  bool closed = false;

  @override
  ScreenWrote write(Uint8List bytes) {
    if (answer?.ended != true) got.addAll(bytes);
    return answer ?? const ScreenWrote();
  }

  @override
  Stream<String> get ended => ended_.stream;

  @override
  void close() => closed = true;
}

/// A window whose "ended" stream never finishes cancelling.
class _SlowToLetGo extends _Window {
  final _never = StreamController<String>(onCancel: () => Completer<void>().future);

  @override
  Stream<String> get ended => _never.stream;
}

Uint8List piece(int n) => Uint8List.fromList([n]);

void main() {
  const desk = Host(id: 'c', label: 'Desk', address: 'desk', computer: true);

  test('the picture reaches the window from its very first piece, in order', () async {
    final capture = _Capture();
    final window = _Window();
    final cast = ScreenCast(capture: capture);
    // The window takes a moment to open; the encoder does not wait.
    final opening = Completer<ScreenWindow>();
    final started = cast.start(desk, () => opening.future);
    await Future<void>.delayed(Duration.zero);
    capture.pieces_.add(piece(1));
    capture.pieces_.add(piece(2));
    await Future<void>.delayed(Duration.zero);
    opening.complete(window);
    expect(await started, isTrue);
    capture.pieces_.add(piece(3));
    await Future<void>.delayed(Duration.zero);
    expect(window.got, [1, 2, 3]);
    expect(cast.showingOn?.title, 'Desk');
  });

  test('a no to Android\'s question opens no window', () async {
    final capture = _Capture(allow: false);
    final cast = ScreenCast(capture: capture);
    var opened = false;
    expect(
      await cast.start(desk, () async {
        opened = true;
        return _Window();
      }),
      isFalse,
    );
    expect(opened, isFalse);
    expect(cast.showingOn, isNull);
    expect(cast.problem, isNull, reason: 'saying no is not a problem to report');
  });

  test('closing the window on the computer stops the capture', () async {
    final capture = _Capture();
    final window = _Window();
    final cast = ScreenCast(capture: capture);
    await cast.start(desk, () async => window);
    window.ended_.add('');
    await Future<void>.delayed(Duration.zero);
    expect(capture.stopped, 1);
    expect(cast.showingOn, isNull);
    expect(cast.problem, isNull);
  });

  test('stopping from the phone (or Android\'s own stop) closes the window', () async {
    final capture = _Capture();
    final window = _Window();
    final cast = ScreenCast(capture: capture);
    await cast.start(desk, () async => window);
    // Android says the capture is over with an empty piece.
    capture.pieces_.add(Uint8List(0));
    await Future<void>.delayed(Duration.zero);
    expect(window.closed, isTrue);
    expect(cast.showingOn, isNull);
  });

  test('stopping does not wait for the stream to let go of its listener', () async {
    final capture = _Capture();
    // Like the real stream: unhooking only completes once it has ended.
    final window = _SlowToLetGo();
    final cast = ScreenCast(capture: capture);
    await cast.start(desk, () async => window);
    await cast.stop().timeout(const Duration(seconds: 1));
    expect(window.closed, isTrue);
    expect(capture.stopped, 1);
    expect(cast.showingOn, isNull);
  });

  test('a stream that has ended stops the capture, with the reason when there is one', () async {
    final capture = _Capture();
    final window = _Window()..answer = const ScreenWrote(ended: true, reason: 'The connection is too slow.');
    final cast = ScreenCast(capture: capture);
    await cast.start(desk, () async => window);
    capture.pieces_.add(piece(9));
    await Future<void>.delayed(Duration.zero);
    expect(cast.showingOn, isNull);
    expect(cast.problem, 'The connection is too slow.');
    expect(capture.stopped, 1);
  });

  test('what the connection can carry is passed on to the encoder', () async {
    final capture = _Capture();
    final window = _Window();
    final cast = ScreenCast(capture: capture);
    await cast.start(desk, () async => window);
    expect(capture.startedAt, 4000000);
    // Going well: the encoder is left alone.
    capture.pieces_.add(piece(1));
    await Future<void>.delayed(Duration.zero);
    expect(capture.adjusted, isEmpty);
    // Behind: a lower bitrate; then caught up: a full picture, please.
    window.answer = const ScreenWrote(bitrate: 2400000);
    capture.pieces_.add(piece(2));
    await Future<void>.delayed(Duration.zero);
    window.answer = const ScreenWrote(keyFrame: true);
    capture.pieces_.add(piece(3));
    await Future<void>.delayed(Duration.zero);
    expect(capture.adjusted, ['2400000 false', 'null true']);
    expect(cast.showingOn, isNotNull);
  });

  test('a computer that cannot open the window says why, and nothing keeps capturing', () async {
    final capture = _Capture();
    final cast = ScreenCast(capture: capture);
    expect(await cast.start(desk, () async => throw Exception('Mpv is needed to show the phone\'s screen: sudo pacman -S mpv')), isFalse);
    expect(cast.problem, contains('Mpv is needed'));
    expect(capture.stopped, 1);
    expect(cast.showingOn, isNull);
  });
}
