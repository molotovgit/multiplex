import 'models.dart';

/// Where the owner last was with an agent or a terminal of a computer's
/// session server, so that Home can take them straight back there.
class ResumePlace {
  const ResumePlace({required this.hostId, required this.session, required this.pane, required this.title, this.agent = ''});

  /// The computer, by the id of its host.
  final String hostId;

  /// The session and the terminal in it.
  final String session;
  final String pane;

  /// What it was doing, as its title said when it was last seen.
  final String title;

  /// The agent's name; empty for a plain terminal.
  final String agent;

  Map<String, dynamic> toJson() => {'hostId': hostId, 'session': session, 'pane': pane, 'title': title, 'agent': agent};

  /// Null for anything that does not name a place.
  static ResumePlace? fromJson(Map<String, dynamic> j) {
    final place = ResumePlace(
      hostId: Json.str(j, 'hostId'),
      session: Json.str(j, 'session'),
      pane: Json.str(j, 'pane'),
      title: Json.str(j, 'title'),
      agent: Json.str(j, 'agent'),
    );
    return place.hostId.isEmpty || place.session.isEmpty || place.pane.isEmpty ? null : place;
  }

  /// What to call it in a list: its title, or what it is.
  String get label => title.isNotEmpty ? title : (agent.isNotEmpty ? agent : 'Terminal');
}
