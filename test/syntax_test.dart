import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/ui/files/syntax/syntax_controller.dart';
import 'package:multiplex/ui/files/syntax/syntax_language.dart';
import 'package:multiplex/ui/files/syntax/syntax_palette.dart';
import 'package:multiplex/ui/files/syntax/syntax_tokenizer.dart';

/// "kind:text" for every coloured piece of [source], line by line.
List<String> tokens(SyntaxLanguage language, String source) {
  final tokenizer = SyntaxTokenizer.forLanguage(language)!;
  final lines = LineIndex(source);
  final out = <String>[];
  var state = LineState.normal;
  for (var i = 0; i < lines.count; i++) {
    state = tokenizer.line(source, lines.start(i), lines.end(i), state, (s, e, kind) => out.add('${kind.name}:${source.substring(s, e)}'));
  }
  return out;
}

/// The coloured pieces of a built span, as "colour index:text" is hard to
/// read; this keeps only the texts that got a colour.
List<String> coloured(TextSpan span) => [
  for (final child in span.children!.cast<TextSpan>())
    if (child.style?.color != null) child.text!,
];

void main() {
  group('language detection', () {
    test('by name, extension, rotated logs, folder and #! line', () {
      expect(SyntaxDetect.forFile('/etc/nginx/nginx.conf'), SyntaxLanguage.nginx);
      expect(SyntaxDetect.forFile('/etc/nginx/sites-enabled/default'), SyntaxLanguage.nginx);
      expect(SyntaxDetect.forFile('/home/a/.bashrc'), SyntaxLanguage.shell);
      expect(SyntaxDetect.forFile('/srv/app/docker-compose.yml'), SyntaxLanguage.yaml);
      expect(SyntaxDetect.forFile('/srv/app/Dockerfile'), SyntaxLanguage.dockerfile);
      expect(SyntaxDetect.forFile('/srv/app/Dockerfile.dev'), SyntaxLanguage.dockerfile);
      expect(SyntaxDetect.forFile('/srv/app/package.json'), SyntaxLanguage.json);
      expect(SyntaxDetect.forFile('/srv/app/Cargo.toml'), SyntaxLanguage.toml);
      expect(SyntaxDetect.forFile('/etc/systemd/system/app.service'), SyntaxLanguage.ini);
      expect(SyntaxDetect.forFile('/srv/app/main.py'), SyntaxLanguage.python);
      expect(SyntaxDetect.forFile('/srv/app/index.ts'), SyntaxLanguage.javascript);
      expect(SyntaxDetect.forFile('/srv/README.md'), SyntaxLanguage.markdown);
      expect(SyntaxDetect.forFile('/var/log/syslog.1'), SyntaxLanguage.log);
      expect(SyntaxDetect.forFile('/srv/app/error.log.2'), SyntaxLanguage.log);
      expect(SyntaxDetect.forFile('/var/log/journal-export'), SyntaxLanguage.log);
      expect(SyntaxDetect.forFile('/usr/local/bin/backup', firstLine: '#!/usr/bin/env bash'), SyntaxLanguage.shell);
      expect(SyntaxDetect.forFile('/usr/local/bin/tool', firstLine: '#!/usr/bin/python3'), SyntaxLanguage.python);
      expect(SyntaxDetect.forFile('/home/a/notes.txt'), SyntaxLanguage.plain);
    });
  });

  group('tokenizers', () {
    test('shell: comments only after a space, variables, keywords and quotes', () {
      expect(tokens(SyntaxLanguage.shell, 'if [ -n "\$HOME" ]; then echo \${#x} # done\nfi'), [
        'keyword:if',
        'string:"\$HOME"',
        'keyword:then',
        'variable:\${#x}',
        'comment:# done',
        'keyword:fi',
      ]);
      expect(tokens(SyntaxLanguage.shell, "echo 'a \$b' a#b"), ["string:'a \$b'"]);
    });

    test('yaml: keys, list dashes, constants, anchors and comments', () {
      expect(tokens(SyntaxLanguage.yaml, 'services:\n  - name: web # main\n    debug: True\n    base: *defaults'), [
        'key:services',
        'keyword:-',
        'key:name',
        'comment:# main',
        'key:debug',
        'constant:True',
        'key:base',
        'variable:*defaults',
      ]);
    });

    test('json: keys differ from values', () {
      expect(tokens(SyntaxLanguage.json, '{"port": 8080, "name": "box", "on": true}'), [
        'key:"port"',
        'number:8080',
        'key:"name"',
        'string:"box"',
        'key:"on"',
        'constant:true',
      ]);
    });

    test('ini and toml: sections and keys', () {
      expect(tokens(SyntaxLanguage.ini, '[Service]\nExecStart = /usr/bin/app\n; note\nRestart=always'), [
        'heading:[Service]',
        'key:ExecStart',
        'comment:; note',
        'key:Restart',
      ]);
      expect(tokens(SyntaxLanguage.toml, '[[bin]]\nname = "x"\nlto = true'), ['heading:[[bin]]', 'key:name', 'string:"x"', 'key:lto', 'constant:true']);
    });

    test('nginx: the first word of each statement is a directive', () {
      expect(tokens(SyntaxLanguage.nginx, 'server { listen 443 ssl; root \$doc_root; }'), [
        'keyword:server',
        'keyword:listen',
        'number:443',
        'constant:ssl',
        'keyword:root',
        'variable:\$doc_root',
      ]);
    });

    test('python and javascript: strings and comments that span lines', () {
      expect(tokens(SyntaxLanguage.python, 'def f():\n    """doc\n    more"""\n    return None'), [
        'keyword:def',
        'string:"""doc',
        'string:    more"""',
        'keyword:return',
        'constant:None',
      ]);
      expect(tokens(SyntaxLanguage.javascript, 'const a = `x\ny`; /* c\nd */ let b = null'), [
        'keyword:const',
        'string:`x',
        'string:y`',
        'comment:/* c',
        'comment:d */',
        'keyword:let',
        'constant:null',
      ]);
    });

    test('dockerfile: instructions at the line start, shell rules after', () {
      expect(tokens(SyntaxLanguage.dockerfile, 'FROM node:20 AS build\nRUN echo "\$PATH" # hi'), [
        'keyword:FROM',
        'number:20',
        'keyword:AS',
        'keyword:RUN',
        'string:"\$PATH"',
        'comment:# hi',
      ]);
    });

    test('markdown: headings, lists, code blocks and inline marks', () {
      expect(tokens(SyntaxLanguage.markdown, '# Title\n- item with `code` and **bold**\n```\n# not a heading\n```\n[site](http://x)'), [
        'heading:# Title',
        'keyword:-',
        'code:`code`',
        'strong:**bold**',
        'code:```',
        'code:# not a heading',
        'code:```',
        'key:[site]',
        'string:(http://x)',
      ]);
    });

    test('logs: times, severities in capitals or the common lower-case forms', () {
      expect(tokens(SyntaxLanguage.log, '2026-11-06T10:00:01Z ERROR disk "sda" failed at 98.5\nNov  6 10:00:02 box sshd[12]: warning info'), [
        'comment:2026-11-06T10:00:01Z',
        'error:ERROR',
        'string:"sda"',
        'error:failed',
        'number:98.5',
        'comment:Nov  6 10:00:02',
        'number:12',
        'warning:warning',
      ]);
    });
  });

  group('palette', () {
    test('every colour reads on both dark and light themes', () {
      for (final theme in BuiltInThemes.all) {
        final palette = SyntaxPalette.fromTheme(theme);
        for (final kind in SyntaxToken.values) {
          final color = palette.style(kind).color;
          if (color == null) continue;
          expect(SyntaxPalette.contrast(color, Color(theme.background)), greaterThanOrEqualTo(SyntaxPalette.minContrast - 0.01), reason: '${theme.name} ${kind.name}');
        }
      }
    });
  });

  group('controller', () {
    late BuildContext context;

    Future<void> grabContext(WidgetTester tester) async {
      await tester.pumpWidget(Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }));
    }

    SyntaxEditingController make(String text, SyntaxLanguage language) => SyntaxEditingController(text: text)
      ..language = language
      ..palette = SyntaxPalette.fromTheme(BuiltInThemes.matteBlack);

    testWidgets('colours only the lines near the screen on a big file', (tester) async {
      await grabContext(tester);
      final text = List.generate(20000, (i) => 'key$i: value # note').join('\n');
      final controller = make(text, SyntaxLanguage.yaml);
      var span = controller.buildTextSpan(context: context, withComposing: false);
      // Two coloured pieces per line, only for the lines in the window.
      final (first, last) = controller.window;
      expect(coloured(span).length, 2 * (last - first + 1));
      expect(coloured(span).first, 'key0');
      expect(span.toPlainText(), text);
      controller.showLines(15000, 15040);
      span = controller.buildTextSpan(context: context, withComposing: false);
      expect(coloured(span), contains('key15000'));
      expect(coloured(span), isNot(contains('key0')));
      expect(span.toPlainText(), text);
    });

    testWidgets('an edit above recolours the lines below it', (tester) async {
      await grabContext(tester);
      // A long string opens on line 2 and the screen shows line 900, so the
      // state of line 900 comes from the remembered line states.
      final filler = List.filled(1000, 'still a string').join('\n');
      final controller = make('x = 1\n"""\n$filler\n"""\ny = 2', SyntaxLanguage.python);
      controller.showLines(900, 920);
      expect(coloured(controller.buildTextSpan(context: context, withComposing: false)), contains('still a string'));
      // Remove the opening quotes: those lines are now plain code.
      controller.text = 'x = 1\n\n$filler\n"""\ny = 2';
      final after = coloured(controller.buildTextSpan(context: context, withComposing: false));
      expect(after, isNot(contains('still a string')));
    });

    testWidgets('keeps the underline of the word the keyboard is composing', (tester) async {
      await grabContext(tester);
      final controller = make('name: value', SyntaxLanguage.yaml);
      controller.value = controller.value.copyWith(composing: const TextRange(start: 2, end: 8));
      final span = controller.buildTextSpan(context: context, withComposing: true);
      final underlined = [
        for (final child in span.children!.cast<TextSpan>())
          if (child.style?.decoration == TextDecoration.underline) child.text,
      ];
      expect(underlined.join(), 'me: va');
      expect(span.toPlainText(), 'name: value');
    });
  });
}
