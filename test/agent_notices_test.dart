import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/platform/agent_notices.dart';
import 'package:multiplex/platform/incoming_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const place = AgentPlace(hostId: 'c', session: 'default', pane: 'w1:p1', mark: '0123456789abcdef');

  test('where an agent is survives the trip through a notification, and nothing else passes for it', () {
    final back = AgentPlace.decode(place.encode())!;
    expect((back.hostId, back.session, back.pane, back.mark, back.tag), ('c', 'default', 'w1:p1', '0123456789abcdef', 'c/default/w1:p1'));
    expect(AgentPlace.decode(const AgentPlace(hostId: 'c', session: 'default', pane: 'w1:p2').encode())!.mark, '');
    for (final odd in [null, 7, '', 'not json', '[]', '{"host":"c"}', '{"host":"","session":"s","pane":"p"}', '{"host":1,"session":"s","pane":"p"}']) {
      expect(AgentPlace.decode(odd), isNull, reason: '$odd');
    }
  });

  test('a tap on the notification is an action that opens that agent', () {
    final action = IncomingAction.parse({'type': 'agent', 'details': place.encode()});
    expect(action, isA<OpenAgentAction>());
    expect((action! as OpenAgentAction).place.tag, 'c/default/w1:p1');
    expect(IncomingAction.parse({'type': 'agent', 'details': 'nonsense'}), isNull);
    expect(IncomingAction.parse({'type': 'agent'}), isNull);
  });

  test('a long choice is cut to fit its button', () {
    expect(AgentNotice.onButton('Yes'), 'Yes');
    expect(AgentNotice.onButton('No, and tell Claude what to do differently'), 'No, and tell Claude what to…');
    expect(AgentNotice.onButton('x' * 28), 'x' * 28);
    expect(AgentNotice.onButton('x' * 29).length, 28);
  });

  group('on the phone', () {
    const channel = MethodChannel('multiplex/agents');
    final calls = <MethodCall>[];
    var waiting = <Object?>[];

    setUp(() {
      calls.clear();
      waiting = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'take') {
          final all = waiting;
          waiting = [];
          return all;
        }
        return null;
      });
    });

    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    /// Android saying that an answer waits.
    Future<void> changed() async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'multiplex/agents',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('changed')),
        (_) {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    test('a notice goes to Android with its buttons cut to size', () async {
      final notices = PhoneAgentNotices();
      await notices.post(
        const AgentNotice(
          place: place,
          title: 'Claude needs you',
          summary: 'make test',
          body: 'make test\n\nDesk',
          waiting: true,
          choices: [(key: '1', label: 'Yes'), (key: '3', label: 'No, and tell Claude what to do differently')],
        ),
      );
      await notices.withdraw(place.tag);
      final post = calls[0].arguments as Map;
      expect(
        (calls[0].method, post['tag'], post['title'], post['summary'], post['body'], post['reply']),
        ('post', 'c/default/w1:p1', 'Claude needs you', 'make test', 'make test\n\nDesk', false),
      );
      expect(post['waiting'], isTrue, reason: 'shown on top of the screen, where it can be answered');
      expect(post['choices'], [
        {'key': '1', 'label': 'Yes'},
        {'key': '3', 'label': 'No, and tell Claude what to…'},
      ]);
      expect(AgentPlace.decode(post['details'])!.mark, '0123456789abcdef');
      expect(calls[1].method, 'withdraw');
      expect(calls[1].arguments, {'tag': 'c/default/w1:p1'});
    });

    test('an answer given before the app was up is collected, and how it went is told back', () async {
      waiting = [
        {'tag': place.tag, 'details': place.encode(), 'choice': '3'},
      ];
      final answers = <String>[];
      final notices = PhoneAgentNotices()
        ..listen((answer) async {
          answers.add('${answer.place.tag} [${answer.place.mark}] choice ${answer.choice} text ${answer.text}');
          return null;
        });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(answers, ['c/default/w1:p1 [0123456789abcdef] choice 3 text null']);
      final settled = calls.lastWhere((call) => call.method == 'settle').arguments as Map;
      expect((settled['tag'], settled['ok']), ('c/default/w1:p1', true));

      // A typed reply that the computer refuses: its words go back to the notification.
      calls.clear();
      answers.clear();
      notices.listen((answer) async {
        answers.add('text ${answer.text}');
        return 'It is working again. Nothing was sent.';
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      waiting = [
        {'tag': place.tag, 'details': place.encode(), 'text': 'run the linter'},
        {'tag': 'x', 'details': 'nonsense', 'choice': '1'},
      ];
      await changed();
      expect(answers, ['text run the linter']);
      final told = [for (final call in calls.where((call) => call.method == 'settle')) call.arguments as Map];
      expect(told.map((t) => '${t['tag']}: ${t['ok']} ${t['title']} / ${t['message']}'), [
        'c/default/w1:p1: false Not sent / It is working again. Nothing was sent.',
        'x: false Not sent / Open Multiplex to answer.',
      ]);
      notices.stop();
    });
  });
}
