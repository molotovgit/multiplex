import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/backdrops/backdrop_painter.dart';
import 'package:multiplex/app/gloss.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/app/theme_style.dart';

void main() {
  test('the glossy style shades the bars and buttons and gives the main button a start shape', () {
    final t = AppTheme.build(BuiltInThemes.millennium);
    expect(t.appBarTheme.shape, isA<GlossBorder>());
    expect(t.appBarTheme.foregroundColor, Colors.white);
    final fab = t.floatingActionButtonTheme.shape! as GlossBorder;
    expect(fab.radius.topLeft.x, lessThan(fab.radius.topRight.x));
    expect(t.floatingActionButtonTheme.backgroundColor, Color(BuiltInThemes.millennium.ansi[2]));
    expect(t.filledButtonTheme.style?.backgroundBuilder, isNotNull);
    expect(t.elevatedButtonTheme.style?.backgroundBuilder, isNotNull);
  });

  test('other styles keep plain buttons', () {
    final t = AppTheme.build(BuiltInThemes.matteBlack);
    expect(t.appBarTheme.shape, isNull);
    expect(t.filledButtonTheme.style?.backgroundBuilder, isNull);
  });

  test('a pressed button is darker at the top than a resting one', () {
    const face = Color(0xFFECE9D8);
    expect(Gloss.pressed(face).colors.first.computeLuminance(), lessThan(Gloss.button(face).colors.first.computeLuminance()));
  });

  test('the hills backdrop draws', () {
    final recorder = ui.PictureRecorder();
    BackdropPainter.of(BackdropPattern.hills).paint(Canvas(recorder), const Size(360, 780), BackdropColors.of(BuiltInThemes.millennium));
    expect(recorder.endRecording(), isNotNull);
  });
}
