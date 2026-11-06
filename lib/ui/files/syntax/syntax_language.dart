/// The kinds of files the editor colours. Anything else shows as plain text.
enum SyntaxLanguage {
  plain('Plain text'),
  shell('Shell'),
  yaml('YAML'),
  json('JSON'),
  toml('TOML'),
  ini('Settings (ini, conf)'),
  nginx('nginx'),
  python('Python'),
  javascript('JavaScript / TypeScript'),
  dockerfile('Dockerfile'),
  markdown('Markdown'),
  log('Log');

  const SyntaxLanguage(this.label);

  /// The name shown in the editor's language menu.
  final String label;
}

/// Guesses a file's language from its path and, failing that, from a
/// "#!" line at the top.
abstract final class SyntaxDetect {
  static const _byExtension = {
    'sh': SyntaxLanguage.shell,
    'bash': SyntaxLanguage.shell,
    'zsh': SyntaxLanguage.shell,
    'ksh': SyntaxLanguage.shell,
    'yml': SyntaxLanguage.yaml,
    'yaml': SyntaxLanguage.yaml,
    'json': SyntaxLanguage.json,
    'jsonc': SyntaxLanguage.json,
    'json5': SyntaxLanguage.json,
    'toml': SyntaxLanguage.toml,
    'ini': SyntaxLanguage.ini,
    'conf': SyntaxLanguage.ini,
    'cfg': SyntaxLanguage.ini,
    'cnf': SyntaxLanguage.ini,
    'properties': SyntaxLanguage.ini,
    'service': SyntaxLanguage.ini,
    'timer': SyntaxLanguage.ini,
    'socket': SyntaxLanguage.ini,
    'mount': SyntaxLanguage.ini,
    'desktop': SyntaxLanguage.ini,
    'env': SyntaxLanguage.shell,
    'nginx': SyntaxLanguage.nginx,
    'py': SyntaxLanguage.python,
    'pyw': SyntaxLanguage.python,
    'js': SyntaxLanguage.javascript,
    'mjs': SyntaxLanguage.javascript,
    'cjs': SyntaxLanguage.javascript,
    'jsx': SyntaxLanguage.javascript,
    'ts': SyntaxLanguage.javascript,
    'tsx': SyntaxLanguage.javascript,
    'mts': SyntaxLanguage.javascript,
    'dockerfile': SyntaxLanguage.dockerfile,
    'md': SyntaxLanguage.markdown,
    'markdown': SyntaxLanguage.markdown,
    'log': SyntaxLanguage.log,
    'out': SyntaxLanguage.log,
    'err': SyntaxLanguage.log,
  };

  static const _byName = {
    '.bashrc': SyntaxLanguage.shell,
    '.bash_profile': SyntaxLanguage.shell,
    '.bash_aliases': SyntaxLanguage.shell,
    '.bash_logout': SyntaxLanguage.shell,
    '.profile': SyntaxLanguage.shell,
    '.zshrc': SyntaxLanguage.shell,
    '.zprofile': SyntaxLanguage.shell,
    '.env': SyntaxLanguage.shell,
    'dockerfile': SyntaxLanguage.dockerfile,
    'containerfile': SyntaxLanguage.dockerfile,
    'nginx.conf': SyntaxLanguage.nginx,
    'syslog': SyntaxLanguage.log,
    'messages': SyntaxLanguage.log,
    'auth.log': SyntaxLanguage.log,
    'kern.log': SyntaxLanguage.log,
    'dmesg': SyntaxLanguage.log,
    '.gitconfig': SyntaxLanguage.ini,
    '.editorconfig': SyntaxLanguage.ini,
    'pipfile': SyntaxLanguage.toml,
  };

  static SyntaxLanguage forFile(String path, {String firstLine = ''}) {
    final name = path.split('/').last.toLowerCase();
    final known = _byName[name];
    if (known != null) return known;
    // "Dockerfile.dev", "app.dockerfile".
    if (name.startsWith('dockerfile.') || name.startsWith('containerfile.')) return SyntaxLanguage.dockerfile;
    // nginx keeps its site files under nginx/ with any name.
    if (path.contains('/nginx/') && !name.endsWith('.json')) return SyntaxLanguage.nginx;
    // Rotated logs: "syslog.1", "app.log.2", "error.log.1".
    final rotated = name.replaceFirst(RegExp(r'(\.\d+)+$'), '');
    if (rotated != name && (_byName[rotated] == SyntaxLanguage.log || rotated.endsWith('.log'))) return SyntaxLanguage.log;
    final dot = name.lastIndexOf('.');
    if (dot >= 0) {
      final byExt = _byExtension[name.substring(dot + 1)];
      if (byExt != null) return byExt;
    }
    if (path.startsWith('/var/log/')) return SyntaxLanguage.log;
    return _fromShebang(firstLine);
  }

  static SyntaxLanguage _fromShebang(String line) {
    if (!line.startsWith('#!')) return SyntaxLanguage.plain;
    if (line.contains('python')) return SyntaxLanguage.python;
    if (line.contains('node') || line.contains('deno') || line.contains('bun')) return SyntaxLanguage.javascript;
    if (RegExp(r'\b(ba|z|k|da)?sh\b').hasMatch(line)) return SyntaxLanguage.shell;
    return SyntaxLanguage.plain;
  }
}
