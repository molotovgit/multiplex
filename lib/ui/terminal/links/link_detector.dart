import 'package:flutter/foundation.dart';

/// What kind of thing a detected link is; decides what a tap offers.
enum LinkKind {
  /// A web (or ftp, ssh, file) address: open in the browser, copy.
  url,

  /// An IPv4 or IPv6 address, maybe with a port: copy.
  address,

  /// An absolute or home (~/) file path: open in Files, copy.
  path,
}

/// A link found in a line of text. [start] and [end] are indexes into
/// that text (end not included).
@immutable
class DetectedLink {
  const DetectedLink(this.kind, this.start, this.end, this.text);

  final LinkKind kind;
  final int start;
  final int end;
  final String text;

  @override
  bool operator ==(Object other) => other is DetectedLink && other.kind == kind && other.start == start && other.end == end && other.text == text;

  @override
  int get hashCode => Object.hash(kind, start, end, text);

  @override
  String toString() => 'DetectedLink(${kind.name}, $start, $end, "$text")';
}

/// Finds URLs, IP addresses and file paths in a line of terminal output.
///
/// Where two finds overlap the more specific one wins: a URL over the
/// path inside it, an IPv6 address over the IPv4 address at its end.
abstract final class LinkDetector {
  static final _url = RegExp(r'''(?:https?|ftp|sftps?|ssh|file)://[^\s<>"'`{}|\\^]+''', caseSensitive: false);

  static const _octet = r'(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)';

  /// Four numbers 0-255, not part of a longer dotted number (a version
  /// such as 1.2.3.4.5) or a word.
  static final _ipv4 = RegExp('(?<![\\w.])(?:$_octet\\.){3}$_octet(?::\\d{1,5})?(?!\\w|\\.\\d)');

  /// "[v6]:port". The part in brackets is checked by [Uri.parseIPv6Address].
  static final _ipv6Bracketed = RegExp(r'\[([0-9A-Fa-f:.]+)\](?::\d{1,5})?');

  /// Hex digits, colons and dots; checked by [Uri.parseIPv6Address] so a
  /// time ("12:30:45") or a MAC address does not count.
  static final _ipv6Plain = RegExp(r'(?<![\w:.])[0-9A-Fa-f:.]{3,}(?!\w)');

  /// Starts with "/" or "~/" after a space, a quote, a bracket or "=",
  /// ":" (PATH=/usr/bin:/bin, user@host:~/src). Never ends in a dot,
  /// comma or colon, so "see /etc/hosts." and "/src/main.rs:12" work.
  static final _path = RegExp(r'''(?<=^|[\s"'`(\[{=:,;|<>])(?:~/|/)(?=[\w.\-+@%~])[\w.\-+@%~,/]*[\w\-+@%~/]''');

  /// Characters a URL rarely ends with; they belong to the sentence.
  static const _urlTrailing = '.,;:!?\'"*';

  static List<DetectedLink> find(String text) {
    if (text.trim().isEmpty) return const [];
    // Most specific first: later finds that overlap an earlier one go.
    final candidates = <DetectedLink>[
      for (final m in _url.allMatches(text)) ?_trimUrl(text, m.start, m.end),
      for (final m in _ipv6Bracketed.allMatches(text))
        if (_isIpv6(m.group(1)!)) DetectedLink(LinkKind.address, m.start, m.end, m.group(0)!),
      for (final m in _ipv6Plain.allMatches(text)) ?_plainIpv6(text, m.start, m.end),
      for (final m in _ipv4.allMatches(text)) DetectedLink(LinkKind.address, m.start, m.end, m.group(0)!),
      for (final m in _path.allMatches(text)) DetectedLink(LinkKind.path, m.start, m.end, m.group(0)!),
    ];
    final kept = <DetectedLink>[];
    for (final c in candidates) {
      if (kept.every((k) => c.end <= k.start || c.start >= k.end)) kept.add(c);
    }
    kept.sort((a, b) => a.start.compareTo(b.start));
    return kept;
  }

  /// Drops sentence punctuation and a closing bracket the URL never
  /// opened: "(see https://x.org/a)." gives "https://x.org/a".
  static DetectedLink? _trimUrl(String text, int start, int end) {
    while (end > start) {
      final last = text[end - 1];
      final url = text.substring(start, end);
      final unbalanced = (last == ')' && _count(url, ')') > _count(url, '(')) || (last == ']' && _count(url, ']') > _count(url, '['));
      if (_urlTrailing.contains(last) || unbalanced) {
        end--;
      } else {
        break;
      }
    }
    final url = text.substring(start, end);
    // "https://" alone is not a link.
    if (!RegExp(r'://[^/]').hasMatch(url)) return null;
    return DetectedLink(LinkKind.url, start, end, url);
  }

  static int _count(String text, String char) => char.allMatches(text).length;

  static DetectedLink? _plainIpv6(String text, int start, int end) {
    // A full stop after the address belongs to the sentence.
    while (end > start && text[end - 1] == '.') {
      end--;
    }
    final candidate = text.substring(start, end);
    if (':'.allMatches(candidate).length < 2 || !RegExp('[0-9A-Fa-f]').hasMatch(candidate)) return null;
    return _isIpv6(candidate) ? DetectedLink(LinkKind.address, start, end, candidate) : null;
  }

  static bool _isIpv6(String text) {
    try {
      Uri.parseIPv6Address(text);
      return true;
    } on FormatException {
      return false;
    }
  }
}
