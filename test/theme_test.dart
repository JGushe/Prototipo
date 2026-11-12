// Verifica la arquitectura de temas: seis paletas, extensión y contraste.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/theme/app_palettes.dart';
import 'package:prototipo_tesis/theme/app_theme.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('hay seis paletas y seis temas', () {
    expect(AppPalette.all, hasLength(6));
    expect(AppTheme.all, hasLength(6));
  });

  test('cada tema tiene ColorScheme, Material 3 y extensión', () {
    for (final paleta in AppPalette.all) {
      final theme = AppTheme.of(paleta.id);
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, paleta.brightness);
      expect(theme.extension<AppThemeColors>(), isNotNull);
      expect(theme.extension<AppThemeColors>()!.chartColors.length,
          greaterThanOrEqualTo(4));
    }
  });

  test('texto sobre acentos cumple contraste AA (4.5:1)', () {
    for (final p in AppPalette.all) {
      expect(_contrast(p.primary, p.onPrimary), greaterThanOrEqualTo(4.5),
          reason: '${p.label} primary');
      expect(_contrast(p.secondary, p.onSecondary), greaterThanOrEqualTo(4.5),
          reason: '${p.label} secondary');
      expect(_contrast(p.tertiary, p.onTertiary), greaterThanOrEqualTo(4.5),
          reason: '${p.label} tertiary');
      expect(_contrast(p.surface, p.onSurface), greaterThanOrEqualTo(4.5),
          reason: '${p.label} surface');
    }
  });
}
