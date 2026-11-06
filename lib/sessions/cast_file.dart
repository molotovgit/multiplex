import 'dart:convert';

/// One step of a recording: output to show, or a new terminal size.
class CastEvent {
  const CastEvent(this.at, this.kind, this.data);

  /// Seconds since the recording started.
  final double at;

  /// "o" for output, "r" for a resize ("80x24").
  final String kind;
  final String data;
}

/// A recording in asciinema v2 format: a JSON header line, then one JSON
/// array per event.
class CastFile {
  const CastFile({required this.width, required this.height, required this.title, required this.events});

  final int width;
  final int height;
  final String title;
  final List<CastEvent> events;

  /// How long the recording runs.
  double get duration => events.isEmpty ? 0 : events.last.at;

  /// Reads a .cast file. Throws [FormatException] for anything else.
  /// Lines that cannot be read are skipped, so a recording cut short
  /// (the app was closed) still plays.
  factory CastFile.parse(String text) {
    final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) throw const FormatException('The recording is empty.');
    final Object? header;
    try {
      header = jsonDecode(lines.first);
    } on FormatException {
      throw const FormatException('This is not a terminal recording.');
    }
    if (header is! Map || header['version'] != 2) throw const FormatException('Only asciinema v2 recordings can be played.');
    final events = <CastEvent>[];
    for (final line in lines.skip(1)) {
      try {
        final e = jsonDecode(line);
        if (e is List && e.length >= 3 && e[0] is num && e[1] is String && e[2] is String) {
          events.add(CastEvent((e[0] as num).toDouble(), e[1] as String, e[2] as String));
        }
      } on FormatException {
        continue;
      }
    }
    return CastFile(
      width: header['width'] is int ? header['width'] as int : 80,
      height: header['height'] is int ? header['height'] as int : 24,
      title: header['title'] is String ? header['title'] as String : '',
      events: events,
    );
  }
}
