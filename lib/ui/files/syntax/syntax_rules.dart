import 'syntax_language.dart';

/// What [CodeTokenizer] looks for in one language.
class SyntaxRules {
  const SyntaxRules({
    this.lineComments = const [],
    this.hashNeedsSpace = false,
    this.blockComment,
    this.quotes = '"\'',
    this.tripleQuotes = false,
    this.templateQuote = false,
    this.keywords = const {},
    this.constants = const {},
    this.caseInsensitiveConstants = false,
    this.dollarVariables = false,
    this.jsonKeys = false,
    this.assignKeys = false,
    this.colonAssigns = false,
    this.yamlKeys = false,
    this.sections = false,
    this.firstWordKeywords = const {},
    this.statementKeywords = false,
    this.wordDash = false,
  });

  final List<String> lineComments;

  /// "#" starts a comment only at the line start or after a space.
  final bool hashNeedsSpace;

  /// Opening and closing marks, such as ("/*", "*/").
  final (String, String)? blockComment;

  /// Characters that open a one-line string.
  final String quotes;

  /// """ and ''' strings that can span lines (Python, TOML).
  final bool tripleQuotes;

  /// `template` strings that can span lines (JavaScript).
  final bool templateQuote;
  final Set<String> keywords;

  /// true, false, null and the like.
  final Set<String> constants;
  final bool caseInsensitiveConstants;

  /// $NAME and ${NAME} (shell, nginx, Dockerfile).
  final bool dollarVariables;

  /// A string followed by ":" is a key (JSON).
  final bool jsonKeys;

  /// "key = value" at the line start (ini, TOML).
  final bool assignKeys;

  /// "key: value" counts as an assignment too (Java properties, some conf files).
  final bool colonAssigns;

  /// "key: value" and "- item" (YAML).
  final bool yamlKeys;

  /// "[section]" at the line start (ini, TOML).
  final bool sections;

  /// Words that are instructions when they start a line (Dockerfile), upper case.
  final Set<String> firstWordKeywords;

  /// The first word of every statement is a directive (nginx).
  final bool statementKeywords;

  /// Words can contain "-" (nginx: "proxy-buffer", units like "10m").
  final bool wordDash;

  static const _jsonConstants = {'true', 'false', 'null'};

  static const shell = SyntaxRules(
    lineComments: ['#'],
    hashNeedsSpace: true,
    dollarVariables: true,
    keywords: {
      'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'until', 'do', 'done', 'case', 'esac', 'in', 'function', 'return', 'local', //
      'export', 'readonly', 'declare', 'unset', 'shift', 'break', 'continue', 'exit', 'source', 'alias', 'set', 'trap', 'eval', 'exec', 'select',
    },
    constants: {'true', 'false'},
  );

  static const yaml = SyntaxRules(
    lineComments: ['#'],
    hashNeedsSpace: true,
    yamlKeys: true,
    constants: {'true', 'false', 'null', 'yes', 'no', 'on', 'off', '~'},
    caseInsensitiveConstants: true,
  );

  static const json = SyntaxRules(lineComments: ['//'], blockComment: ('/*', '*/'), quotes: '"', jsonKeys: true, constants: _jsonConstants);

  static const toml = SyntaxRules(
    lineComments: ['#'],
    tripleQuotes: true,
    assignKeys: true,
    sections: true,
    constants: {'true', 'false', 'inf', 'nan'},
  );

  static const ini = SyntaxRules(
    lineComments: ['#', ';'],
    hashNeedsSpace: true,
    assignKeys: true,
    colonAssigns: true,
    sections: true,
    constants: {'true', 'false', 'yes', 'no', 'on', 'off', 'none', 'null'},
    caseInsensitiveConstants: true,
  );

  static const nginx = SyntaxRules(
    lineComments: ['#'],
    hashNeedsSpace: true,
    dollarVariables: true,
    statementKeywords: true,
    wordDash: true,
    constants: {'on', 'off', 'default_server', 'ssl', 'http2'},
  );

  static const python = SyntaxRules(
    lineComments: ['#'],
    tripleQuotes: true,
    keywords: {
      'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue', 'def', 'del', 'elif', 'else', 'except', 'finally', 'for', //
      'from', 'global', 'if', 'import', 'in', 'is', 'lambda', 'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'try', 'while', 'with',
      'yield', 'match', 'case',
    },
    constants: {'True', 'False', 'None', 'self', 'cls'},
  );

  static const javascript = SyntaxRules(
    lineComments: ['//'],
    blockComment: ('/*', '*/'),
    templateQuote: true,
    keywords: {
      'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger', 'default', 'delete', 'do', 'else', 'export', 'extends', //
      'finally', 'for', 'from', 'function', 'if', 'import', 'in', 'instanceof', 'let', 'new', 'of', 'return', 'super', 'switch', 'this',
      'throw', 'try', 'typeof', 'var', 'void', 'while', 'with', 'yield', 'async', 'await', 'static', 'interface', 'type', 'enum',
      'implements', 'private', 'public', 'protected', 'readonly', 'declare', 'namespace', 'abstract', 'as', 'keyof',
    },
    constants: {'true', 'false', 'null', 'undefined', 'NaN', 'Infinity'},
  );

  static const dockerfile = SyntaxRules(
    lineComments: ['#'],
    hashNeedsSpace: true,
    dollarVariables: true,
    firstWordKeywords: {
      'FROM', 'RUN', 'CMD', 'LABEL', 'MAINTAINER', 'EXPOSE', 'ENV', 'ADD', 'COPY', 'ENTRYPOINT', 'VOLUME', 'USER', 'WORKDIR', 'ARG', //
      'ONBUILD', 'STOPSIGNAL', 'HEALTHCHECK', 'SHELL',
    },
    keywords: {'AS', 'as'},
  );

  static SyntaxRules of(SyntaxLanguage language) => switch (language) {
    SyntaxLanguage.shell => shell,
    SyntaxLanguage.yaml => yaml,
    SyntaxLanguage.json => json,
    SyntaxLanguage.toml => toml,
    SyntaxLanguage.ini => ini,
    SyntaxLanguage.nginx => nginx,
    SyntaxLanguage.python => python,
    SyntaxLanguage.javascript => javascript,
    SyntaxLanguage.dockerfile => dockerfile,
    _ => const SyntaxRules(),
  };
}
