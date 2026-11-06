/// One blank in a snippet command: `{name}` or `{name:default}`.
class SnippetBlank {
  const SnippetBlank(this.name, this.defaultValue);

  final String name;

  /// What the field starts with when nothing was typed before. Empty when
  /// the blank has no default.
  final String defaultValue;

  @override
  bool operator ==(Object other) => other is SnippetBlank && other.name == name && other.defaultValue == defaultValue;

  @override
  int get hashCode => Object.hash(name, defaultValue);

  @override
  String toString() => 'SnippetBlank($name, $defaultValue)';
}

/// Reads and fills the blanks of a snippet command.
///
/// A blank is a name in braces, `{file}`, or a name with a default,
/// `{port:8080}`. A name starts with a letter or `_` and holds letters,
/// digits, `_` and `-`. Everything else in braces stays as it is, so shell
/// code keeps working: `${HOME}`, `{}` in `find -exec`, `{a,b}` and
/// `awk '{print $1}'` are not blanks.
class SnippetTemplate {
  SnippetTemplate(this.command) : blanks = _find(command);

  final String command;

  /// Each blank once, in the order it first appears. When a name appears
  /// more than once, the first default given wins.
  final List<SnippetBlank> blanks;

  bool get hasBlanks => blanks.isNotEmpty;

  /// `(?<!\$)` skips shell variables such as `${HOME}`.
  static final _pattern = RegExp(r'(?<!\$)\{([A-Za-z_][A-Za-z0-9_-]*)(?::([^{}\n]*))?\}');

  static List<SnippetBlank> _find(String command) {
    final seen = <String>{};
    final found = <SnippetBlank>[];
    for (final match in _pattern.allMatches(command)) {
      final name = match.group(1)!;
      if (seen.add(name)) found.add(SnippetBlank(name, match.group(2) ?? ''));
    }
    return found;
  }

  /// The command with every blank replaced by its value. A blank without
  /// a value gets its default.
  String fill(Map<String, String> values) => command.replaceAllMapped(_pattern, (match) {
        final name = match.group(1)!;
        return values[name] ?? blanks.firstWhere((b) => b.name == name).defaultValue;
      });

  /// What each field starts with: the value typed last time, otherwise the
  /// default.
  Map<String, String> startValues(Map<String, String> last) => {for (final blank in blanks) blank.name: last[blank.name] ?? blank.defaultValue};
}
