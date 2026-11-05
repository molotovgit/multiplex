import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/selection_look.dart';
import 'package:multiplex/app/theme_spec.dart';

void main() {
  test('selected text reads well in every built-in theme', () {
    for (final theme in BuiltInThemes.all) {
      final look = SelectionLook.of(theme);
      expect(SelectionLook.contrast(look.text, look.fill), greaterThanOrEqualTo(SelectionLook.minContrast), reason: theme.name);
    }
  });

  test("the theme's own text colour is kept when it reads well enough", () {
    final look = SelectionLook.of(BuiltInThemes.matteBlack);
    expect(look.text, Color(BuiltInThemes.matteBlack.foreground));
  });

  test("a scheme's own selection colour is used as it is", () {
    expect(SelectionLook.of(BuiltInThemes.matteBlack).fill, const Color(0xFF2A2A2A));
    expect(SelectionLook.of(BuiltInThemes.nightOwl).fill, const Color(0xFF0D486E));
  });

  test('falls back to white or black when no theme colour reads', () {
    const grey = Color(0xFF777777);
    expect(SelectionLook.readableOn(grey, [const Color(0xFF787878)]), const Color(0xFF000000));
    expect(SelectionLook.readableOn(const Color(0xFF222222), [const Color(0xFF333333)]), const Color(0xFFFFFFFF));
  });
}
