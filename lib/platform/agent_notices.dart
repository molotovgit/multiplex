import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Where an agent is, and which question of its was shown: enough to
/// open it, or to answer it so that the answer reaches that question only.
class AgentPlace {
  const AgentPlace({required this.hostId, required this.session, required this.pane, this.mark = ''});

  /// The computer, by the id of its host.
  final String hostId;

  /// The session and the terminal in it.
  final String session;
  final String pane;

  /// The mark of the question that was shown; empty when it was not a
  /// choice.
  final String mark;

  /// One notification per agent: a newer one takes the older one's place.
  String get tag => '$hostId/$session/$pane';

  String encode() => jsonEncode({'host': hostId, 'session': session, 'pane': pane, 'mark': mark});

  /// Null for anything that does not name a place.
  static AgentPlace? decode(Object? details) {
    if (details is! String) return null;
    try {
      final j = jsonDecode(details);
      if (j is! Map) return null;
      final (host, session, pane, mark) = (j['host'], j['session'], j['pane'], j['mark']);
      if (host is! String || session is! String || pane is! String || host.isEmpty || session.isEmpty || pane.isEmpty) return null;
      return AgentPlace(hostId: host, session: session, pane: pane, mark: mark is String ? mark : '');
    } on FormatException {
      return null;
    }
  }
}

/// A notification about an agent: it waits, or it finished.
class AgentNotice {
  const AgentNotice({
    required this.place,
    required this.title,
    required this.summary,
    required this.body,
    required this.waiting,
    this.choices = const [],
    this.reply = false,
  });

  final AgentPlace place;
  final String title;

  /// It waits for the owner (shown on top of the screen, to be answered
  /// there); false: it finished (in the list, without interrupting).
  final bool waiting;

  /// One line, for the notification while it is not opened out.
  final String summary;

  /// All of it: what the agent asks, and where it is.
  final String body;

  /// The agent's choices, each a button: what names it in an answer, and
  /// its words.
  final List<({String key, String label})> choices;

  /// Whether an answer can be typed into the notification.
  final bool reply;

  /// A choice's words as a button carries them.
  static String onButton(String label) => label.length <= buttonChars ? label : '${label.substring(0, buttonChars - 1).trimRight()}…';

  static const buttonChars = 28;
}

/// An answer given in a notification: one of the choices, or words.
class AgentAnswer {
  const AgentAnswer({required this.place, this.choice, this.text});

  final AgentPlace place;
  final String? choice;
  final String? text;
}

/// The phone's notifications about agents. Tests pass a stand-in.
abstract class AgentNotices {
  Future<void> post(AgentNotice notice);

  /// Takes back what was shown about the agent at [tag].
  Future<void> withdraw(String tag);

  /// [onAnswer] gets each answer given in a notification, and returns
  /// null when it was sent, or the words that say why it was not.
  void listen(Future<String?> Function(AgentAnswer answer) onAnswer);

  void stop();
}

/// Android's notifications (see `AgentNotices.kt`). An answer waits on
/// the native side until it is collected here, so one given while the
/// app was not running is not lost.
class PhoneAgentNotices implements AgentNotices {
  PhoneAgentNotices([this._channel = const MethodChannel('multiplex/agents')]);

  final MethodChannel _channel;
  Future<String?> Function(AgentAnswer answer)? _onAnswer;
  bool _taking = false;
  bool _more = false;

  static const notSentTitle = 'Not sent';

  Future<void> _call(String method, Map<String, Object?> arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // No notifications on this platform.
    } on PlatformException {
      // A notification is never worth an error.
    }
  }

  @override
  Future<void> post(AgentNotice notice) => _call('post', {
    'tag': notice.place.tag,
    'details': notice.place.encode(),
    'title': notice.title,
    'summary': notice.summary,
    'body': notice.body,
    'waiting': notice.waiting,
    'choices': [
      for (final choice in notice.choices) {'key': choice.key, 'label': AgentNotice.onButton(choice.label)},
    ],
    'reply': notice.reply,
    'replyLabel': 'Reply',
    'replyHint': 'Answer it, or ask for more',
  });

  @override
  Future<void> withdraw(String tag) => _call('withdraw', {'tag': tag});

  @override
  void listen(Future<String?> Function(AgentAnswer answer) onAnswer) {
    _onAnswer = onAnswer;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') unawaited(_takeAll());
    });
    // One given before the app was up is already waiting.
    unawaited(_takeAll());
  }

  @override
  void stop() {
    _onAnswer = null;
    _channel.setMethodCallHandler(null);
  }

  /// Collects the answers that wait and passes each on, one at a time.
  Future<void> _takeAll() async {
    if (_taking) {
      _more = true;
      return;
    }
    _taking = true;
    try {
      do {
        _more = false;
        List<Object?>? waiting;
        try {
          waiting = await _channel.invokeMethod<List<Object?>>('take');
        } on MissingPluginException {
          return;
        } on PlatformException {
          return;
        }
        for (final item in waiting ?? const <Object?>[]) {
          if (item is! Map) continue;
          final (tag, details) = (item['tag'], item['details']);
          if (tag is! String) continue;
          final place = AgentPlace.decode(details);
          final (choice, text) = (item['choice'], item['text']);
          final onAnswer = _onAnswer;
          final why = place == null || onAnswer == null
              ? 'Open Multiplex to answer.'
              : await onAnswer(AgentAnswer(place: place, choice: choice is String ? choice : null, text: text is String ? text : null));
          await _call('settle', {'tag': tag, 'ok': why == null, 'title': notSentTitle, 'message': why ?? '', 'details': details is String ? details : ''});
        }
      } while (_more);
    } finally {
      _taking = false;
    }
  }
}
