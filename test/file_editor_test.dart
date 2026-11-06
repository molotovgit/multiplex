import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/ui/files/syntax/code_editor_view.dart';
import 'package:multiplex/ui/files/syntax/syntax_controller.dart';
import 'package:multiplex/ui/files/syntax/syntax_language.dart';

import 'support/files_fixtures.dart';

void main() {
  setUpAll(() async {
    Fixtures.store = await VaultStore.open(MemoryBackend());
    Fixtures.sessions = SessionManager(Fixtures.store);
  });
  tearDownAll(() => Fixtures.sessions.dispose());

  LineNumberPainter? numbers(WidgetTester tester) =>
      tester.widgetList<CustomPaint>(find.byType(CustomPaint)).map((p) => p.painter).whereType<LineNumberPainter>().firstOrNull;

  SyntaxEditingController controller(WidgetTester tester) => tester.widget<EditableText>(find.byType(EditableText)).controller as SyntaxEditingController;

  testWidgets('colours a YAML file, numbers its lines, wraps and recolours on request', (tester) async {
    Fixtures.phone(tester);
    final tree = Fixtures.tree();
    tree['/home/ann']!.add(Fixtures.entry('/home/ann', 'compose.yml'));
    final files = FakeFiles(tree)..texts['/home/ann/compose.yml'] = 'services:\n  web:\n    image: nginx # front\n';
    await Fixtures.showFiles(tester, FakeSsh(files));
    await tester.tap(find.text('compose.yml'));
    await tester.pumpAndSettle();

    expect(controller(tester).language, SyntaxLanguage.yaml);
    expect(numbers(tester)?.lineCount, 4);
    expect(numbers(tester)?.lastDrawn, (1, 4));
    final span = controller(tester).buildTextSpan(context: tester.element(find.byType(EditableText)), withComposing: false);
    final keys = [
      for (final child in span.children!.cast<TextSpan>())
        if (child.style?.color != null) child.text,
    ];
    expect(keys, ['services', 'web', 'image', '# front']);
    await Fixtures.checkTouchRules(tester);

    // Typing still works and the numbers follow.
    await tester.enterText(find.byType(TextField), 'a: 1\nb: 2');
    await tester.pumpAndSettle();
    expect(numbers(tester)?.lineCount, 2);
    expect(find.text('compose.yml (not saved)'), findsOneWidget);

    await tester.tap(find.byTooltip('Editor options'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckedPopupMenuItem<int>));
    await tester.pumpAndSettle();
    expect(numbers(tester), isNull);

    await tester.tap(find.byTooltip('Editor options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Colours: YAML'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plain text'));
    await tester.pumpAndSettle();
    expect(controller(tester).language, SyntaxLanguage.plain);
  });

  testWidgets('a 1 MB log opens, scrolls and colours the lines it reaches', (tester) async {
    Fixtures.phone(tester);
    final tree = Fixtures.tree();
    tree['/home/ann']!.add(Fixtures.entry('/home/ann', 'app.log'));
    final line = '2026-11-06T10:00:01Z INFO request served in 12 ms';
    final text = List.generate(1024 * 1024 ~/ (line.length + 1), (i) => i == 15000 ? '2026-11-06T10:00:01Z ERROR disk full' : line).join('\n');
    final files = FakeFiles(tree)..texts['/home/ann/app.log'] = text;
    await Fixtures.showFiles(tester, FakeSsh(files));
    await tester.tap(find.text('app.log'));
    await tester.pumpAndSettle();
    expect(controller(tester).language, SyntaxLanguage.log);
    // The real height of a line, as laid out; the numbers must follow it.
    final editable = tester.renderObject<RenderEditable>(find.descendant(of: find.byType(EditableText), matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Editable')));
    final scrollable = tester.state<ScrollableState>(find.descendant(of: find.byType(EditableText), matching: find.byType(Scrollable)));
    scrollable.position.jumpTo(14990 * editable.preferredLineHeight);
    await tester.pumpAndSettle();
    final (first, last) = controller(tester).window;
    expect(first, lessThanOrEqualTo(15000));
    expect(last, greaterThanOrEqualTo(15000));
    expect(numbers(tester)!.lastDrawn.$1, 14991);
  });
}
