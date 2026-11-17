import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/phone_speaker.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/ui/computers/speaker_screen.dart';

/// Android's part, standing in.
class _Output extends SpeakerOutput {
  _Output({this.works = true});

  final bool works;
  final fed = <int>[];
  int started = 0;
  int stopped = 0;

  @override
  Future<bool> start() async {
    started++;
    return works;
  }

  @override
  void feed(Uint8List frame) => fed.addAll(frame);

  @override
  Future<void> stop() async => stopped++;

  @override
  Future<String?> stats() async => null;
}

/// The line from the computer.
class _Line implements SpeakerLine {
  final sound_ = StreamController<Uint8List>.broadcast();
  final ended_ = StreamController<String>.broadcast();
  bool closed = false;

  @override
  Stream<Uint8List> get sound => sound_.stream;

  @override
  Stream<String> get ended => ended_.stream;

  @override
  void close() => closed = true;
}

void main() {
  const desk = Host(id: 'c', label: 'Desk', address: 'desk', computer: true);

  test('what comes down the line is played, in order', () async {
    final output = _Output();
    final line = _Line();
    final speaker = PhoneSpeaker(output: output);
    bool? asked;
    expect(
      await speaker.start(desk, (everything) async {
        asked = everything;
        return line;
      }),
      isTrue,
    );
    expect(asked, isTrue, reason: 'all of the computer\'s sound unless switched off');
    line.sound_.add(Uint8List.fromList([1, 2]));
    line.sound_.add(Uint8List.fromList([3]));
    await Future<void>.delayed(Duration.zero);
    expect(output.fed, [1, 2, 3]);
    expect(speaker.playing?.title, 'Desk');
    await speaker.stop();
  });

  test('stopping gives the computer its sound back first, and never hangs', () async {
    final output = _Output();
    final line = _Line();
    final speaker = PhoneSpeaker(output: output);
    await speaker.start(desk, (_) async => line);
    await speaker.stop().timeout(const Duration(seconds: 1));
    expect(line.closed, isTrue);
    expect(output.stopped, 1);
    expect(speaker.playing, isNull);
    expect(speaker.problem, isNull);
  });

  test('the computer ending it stops the phone, with the reason', () async {
    final output = _Output();
    final line = _Line();
    final speaker = PhoneSpeaker(output: output);
    await speaker.start(desk, (_) async => line);
    line.ended_.add('The connection to the computer was lost.');
    await Future<void>.delayed(Duration.zero);
    expect(speaker.playing, isNull);
    expect(speaker.problem, 'The connection to the computer was lost.');
    expect(output.stopped, 1);
  });

  test('a computer that cannot do it says why, and the phone stops waiting to play', () async {
    final output = _Output();
    final speaker = PhoneSpeaker(output: output);
    expect(await speaker.start(desk, (_) async => throw Exception('The phone as a speaker needs ffmpeg and pactl')), isFalse);
    expect(speaker.problem, contains('needs ffmpeg and pactl'));
    expect(output.stopped, 1);
    expect(speaker.playing, isNull);
  });

  test('a phone that cannot play never asks the computer', () async {
    final speaker = PhoneSpeaker(output: _Output(works: false));
    var asked = false;
    expect(
      await speaker.start(desk, (_) async {
        asked = true;
        return _Line();
      }),
      isFalse,
    );
    expect(asked, isFalse);
    expect(speaker.problem, isNotNull);
  });

  test('only-what-is-pointed-here is a choice made before it starts', () async {
    final speaker = PhoneSpeaker(output: _Output());
    speaker.setEverything(false);
    bool? asked;
    await speaker.start(desk, (everything) async {
      asked = everything;
      return _Line();
    });
    expect(asked, isFalse);
    // Not while it plays.
    speaker.setEverything(true);
    expect(speaker.everything, isFalse);
    await speaker.stop();
  });

  testWidgets('the speaker page starts and stops, and says which is the case', (tester) async {
    final store = await VaultStore.open(MemoryBackend());
    final sessions = SessionManager(store);
    addTearDown(sessions.dispose);
    final speaker = PhoneSpeaker(output: _Output());
    final line = _Line();
    await tester.pumpWidget(
      AppScope(
        vault: store,
        manager: sessions,
        child: MaterialApp(
          home: SpeakerScreen(host: desk, speaker: speaker, open: (_) async => line),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Play Desk\'s sound on this phone'), findsOneWidget);
    expect(find.text('All of Desk\'s sound'), findsOneWidget);
    await tester.tap(find.text('Play the sound'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Desk\'s sound is playing on this phone'), findsOneWidget);
    await tester.tap(find.text('Stop playing'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(line.closed, isTrue);
    expect(find.text('Play the sound'), findsOneWidget);
  });
}
