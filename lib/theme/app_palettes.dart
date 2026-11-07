import 'package:flutter/material.dart';

import 'app_tokens.dart';

enum AppPaletteId {
  lightCool,
  darkCool,
  lightWarm,
  darkWarm,
  lightRgb,
  darkRgb,
}

/// Segunda capa: colores semánticos por paleta. `background` y `surface`
/// describen el lienzo; `primary`/`secondary`/`tertiary` el acento.
class AppPalette {
  final AppPaletteId id;
  final String label;
  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;
  final Color tertiary;
  final Color onTertiary;
  final Color onBackground;
  final Color onSurface;
  final Color outline;
  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color error;
  final Color onError;
  final Color gradientStart;
  final Color gradientEnd;
  final List<Color> chart;

  const AppPalette({
    required this.id,
    required this.label,
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.tertiary,
    required this.onTertiary,
    required this.onBackground,
    required this.onSurface,
    required this.outline,
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.error,
    required this.onError,
    required this.gradientStart,
    required this.gradientEnd,
    required this.chart,
  });

  bool get isDark => brightness == Brightness.dark;

  static const lightCool = AppPalette(
    id: AppPaletteId.lightCool,
    label: 'Light Cool',
    brightness: Brightness.light,
    background: AppPrimitives.coolBg,
    surface: AppPrimitives.coolSurface,
    surfaceAlt: Color(0xFFE8F1F5),
    primary: AppPrimitives.coolTeal,
    onPrimary: Colors.white,
    secondary: AppPrimitives.coolSky,
    onSecondary: Colors.white,
    tertiary: AppPrimitives.coolIndigo,
    onTertiary: Colors.white,
    onBackground: AppPrimitives.ink,
    onSurface: AppPrimitives.ink,
    outline: AppPrimitives.line,
    success: AppPrimitives.green600,
    onSuccess: Colors.white,
    warning: AppPrimitives.amber600,
    onWarning: Colors.white,
    error: AppPrimitives.red600,
    onError: Colors.white,
    gradientStart: Color(0xFF0F766E),
    gradientEnd: Color(0xFF38BDF8),
    chart: [
      AppPrimitives.coolTeal,
      AppPrimitives.coolSky,
      AppPrimitives.coolIndigo,
      Color(0xFFF59E0B),
    ],
  );

  static const darkCool = AppPalette(
    id: AppPaletteId.darkCool,
    label: 'Dark Cool',
    brightness: Brightness.dark,
    background: AppPrimitives.coolBgDark,
    surface: AppPrimitives.coolSurfaceDark,
    surfaceAlt: Color(0xFF15384A),
    primary: AppPrimitives.coolMint,
    onPrimary: Color(0xFF04241B),
    secondary: AppPrimitives.coolSkySoft,
    onSecondary: Color(0xFF052A3A),
    tertiary: Color(0xFFA5B4FC),
    onTertiary: Color(0xFF1E1B4B),
    onBackground: Color(0xFFE6F4F1),
    onSurface: Color(0xFFE6F4F1),
    outline: AppPrimitives.lineDark,
    success: AppPrimitives.green300,
    onSuccess: Color(0xFF052E1B),
    warning: AppPrimitives.amber300,
    onWarning: Color(0xFF3A2503),
    error: AppPrimitives.red300,
    onError: Color(0xFF3A0A12),
    gradientStart: Color(0xFF6EE7B7),
    gradientEnd: Color(0xFF38BDF8),
    chart: [
      AppPrimitives.coolMint,
      AppPrimitives.coolSkySoft,
      Color(0xFFA5B4FC),
      AppPrimitives.amber300,
    ],
  );

  static const lightWarm = AppPalette(
    id: AppPaletteId.lightWarm,
    label: 'Light Warm',
    brightness: Brightness.light,
    background: AppPrimitives.warmBg,
    surface: AppPrimitives.warmSurface,
    surfaceAlt: Color(0xFFF6E9DF),
    primary: AppPrimitives.warmRaspberry,
    onPrimary: Colors.white,
    secondary: AppPrimitives.warmPeach,
    onSecondary: Color(0xFF3A160F),
    tertiary: AppPrimitives.warmPlum,
    onTertiary: Colors.white,
    onBackground: Color(0xFF3A2A2A),
    onSurface: Color(0xFF3A2A2A),
    outline: Color(0xFFE2CFC3),
    success: AppPrimitives.green600,
    onSuccess: Colors.white,
    warning: AppPrimitives.amber600,
    onWarning: Colors.white,
    error: AppPrimitives.red600,
    onError: Colors.white,
    gradientStart: Color(0xFFC2185B),
    gradientEnd: Color(0xFFF6A57A),
    chart: [
      AppPrimitives.warmRaspberry,
      AppPrimitives.warmPeach,
      AppPrimitives.warmPlum,
      Color(0xFF8A9A5B),
    ],
  );

  static const darkWarm = AppPalette(
    id: AppPaletteId.darkWarm,
    label: 'Dark Warm',
    brightness: Brightness.dark,
    background: AppPrimitives.warmBgDark,
    surface: AppPrimitives.warmSurfaceDark,
    surfaceAlt: Color(0xFF4A2035),
    primary: AppPrimitives.warmPink,
    onPrimary: Color(0xFF3B0A22),
    secondary: Color(0xFFFDBA74),
    onSecondary: Color(0xFF3A1D05),
    tertiary: Color(0xFFC4B5FD),
    onTertiary: Color(0xFF2A1A5E),
    onBackground: Color(0xFFFCE7F3),
    onSurface: Color(0xFFFCE7F3),
    outline: Color(0xFF6B3350),
    success: AppPrimitives.green300,
    onSuccess: Color(0xFF052E1B),
    warning: AppPrimitives.amber300,
    onWarning: Color(0xFF3A2503),
    error: AppPrimitives.red300,
    onError: Color(0xFF3A0A12),
    gradientStart: Color(0xFFF472B6),
    gradientEnd: Color(0xFFFDBA74),
    chart: [
      AppPrimitives.warmPink,
      Color(0xFFFDBA74),
      Color(0xFFC4B5FD),
      Color(0xFF6EE7B7),
    ],
  );

  static const lightRgb = AppPalette(
    id: AppPaletteId.lightRgb,
    label: 'Light RGB',
    brightness: Brightness.light,
    background: AppPrimitives.rgbBg,
    surface: AppPrimitives.rgbSurface,
    surfaceAlt: Color(0xFFEAE4FF),
    primary: AppPrimitives.rgbViolet,
    onPrimary: Colors.white,
    secondary: AppPrimitives.rgbTurquoise,
    onSecondary: Colors.white,
    tertiary: AppPrimitives.rgbCoral,
    onTertiary: Color(0xFF3B120C),
    onBackground: Color(0xFF1E1B2E),
    onSurface: Color(0xFF1E1B2E),
    outline: Color(0xFFD8D3F0),
    success: AppPrimitives.green600,
    onSuccess: Colors.white,
    warning: AppPrimitives.amber600,
    onWarning: Colors.white,
    error: Color(0xFFBE123C),
    onError: Colors.white,
    gradientStart: Color(0xFF6D28D9),
    gradientEnd: Color(0xFF22D3EE),
    chart: [
      AppPrimitives.rgbViolet,
      AppPrimitives.rgbTurquoise,
      AppPrimitives.rgbCoral,
      Color(0xFFF59E0B),
    ],
  );

  static const darkRgb = AppPalette(
    id: AppPaletteId.darkRgb,
    label: 'Dark RGB',
    brightness: Brightness.dark,
    background: AppPrimitives.rgbBgDark,
    surface: AppPrimitives.rgbSurfaceDark,
    surfaceAlt: Color(0xFF262633),
    primary: AppPrimitives.rgbVioletSoft,
    onPrimary: Color(0xFF1B1035),
    secondary: AppPrimitives.rgbCyan,
    onSecondary: Color(0xFF052A33),
    tertiary: Color(0xFFF472B6),
    onTertiary: Color(0xFF3B0A22),
    onBackground: Color(0xFFECEAF5),
    onSurface: Color(0xFFECEAF5),
    outline: Color(0xFF3A3A48),
    success: AppPrimitives.green300,
    onSuccess: Color(0xFF052E1B),
    warning: AppPrimitives.amber300,
    onWarning: Color(0xFF3A2503),
    error: AppPrimitives.red300,
    onError: Color(0xFF3A0A12),
    gradientStart: Color(0xFFA78BFA),
    gradientEnd: Color(0xFF22D3EE),
    chart: [
      AppPrimitives.rgbVioletSoft,
      AppPrimitives.rgbCyan,
      Color(0xFFF472B6),
      Color(0xFFA3E635),
    ],
  );

  static const List<AppPalette> all = [
    lightCool,
    darkCool,
    lightWarm,
    darkWarm,
    lightRgb,
    darkRgb,
  ];
}
