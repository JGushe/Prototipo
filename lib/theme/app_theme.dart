import 'package:flutter/material.dart';

import 'app_palettes.dart';
import 'app_tokens.dart';

/// Tercera capa: tokens de componente expuestos por tema.
///
/// Se leen con `AppTheme.colors(context)`. Mantiene lo que `ColorScheme` no
/// cubre: gráficos, estados de tendencia y geometría de tarjetas.
@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;

  /// Serie para gráficos (orden estable). Nunca comunicar solo por color:
  /// acompañar con etiqueta o patrón.
  final List<Color> chartColors;
  final Color chartGrid;
  final Color chartAxis;

  /// Degradado controlado para cabeceras y tarjetas destacadas.
  final LinearGradient gradient;

  final double cardRadius;
  final double sectionSpacing;

  const AppThemeColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.chartColors,
    required this.chartGrid,
    required this.chartAxis,
    required this.gradient,
    required this.cardRadius,
    required this.sectionSpacing,
  });

  @override
  AppThemeColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    List<Color>? chartColors,
    Color? chartGrid,
    Color? chartAxis,
    LinearGradient? gradient,
    double? cardRadius,
    double? sectionSpacing,
  }) {
    return AppThemeColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      chartColors: chartColors ?? this.chartColors,
      chartGrid: chartGrid ?? this.chartGrid,
      chartAxis: chartAxis ?? this.chartAxis,
      gradient: gradient ?? this.gradient,
      cardRadius: cardRadius ?? this.cardRadius,
      sectionSpacing: sectionSpacing ?? this.sectionSpacing,
    );
  }

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    final max = chartColors.length > other.chartColors.length
        ? chartColors.length
        : other.chartColors.length;
    return AppThemeColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      chartColors: List.generate(
        max,
        (i) => Color.lerp(
          chartColors[i % chartColors.length],
          other.chartColors[i % other.chartColors.length],
          t,
        )!,
      ),
      chartGrid: Color.lerp(chartGrid, other.chartGrid, t)!,
      chartAxis: Color.lerp(chartAxis, other.chartAxis, t)!,
      gradient: LinearGradient(
        colors: [
          Color.lerp(gradient.colors.first, other.gradient.colors.first, t)!,
          Color.lerp(gradient.colors.last, other.gradient.colors.last, t)!,
        ],
      ),
      cardRadius: lerpDouble(cardRadius, other.cardRadius, t),
      sectionSpacing: lerpDouble(sectionSpacing, other.sectionSpacing, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

/// Construye los seis temas a partir de las paletas.
class AppTheme {
  AppTheme._();

  static ThemeData build(AppPalette p) {
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      secondary: p.secondary,
      onSecondary: p.onSecondary,
      tertiary: p.tertiary,
      onTertiary: p.onTertiary,
      error: p.error,
      onError: p.onError,
      surface: p.surface,
      onSurface: p.onSurface,
      outline: p.outline,
      surfaceContainerHighest: p.surfaceAlt,
    );

    final base = ThemeData(brightness: p.brightness).textTheme;
    final textTheme = base
        .copyWith(
          displaySmall: base.displaySmall?.copyWith(
              fontSize: AppPrimitives.text3xl,
              fontWeight: AppPrimitives.bold,
              height: 1.2),
          headlineSmall: base.headlineSmall?.copyWith(
              fontSize: AppPrimitives.text2xl,
              fontWeight: AppPrimitives.semibold,
              height: 1.25),
          titleLarge: base.titleLarge?.copyWith(
              fontSize: AppPrimitives.textXl,
              fontWeight: AppPrimitives.semibold,
              height: 1.3),
          titleMedium: base.titleMedium?.copyWith(
              fontSize: AppPrimitives.textLg,
              fontWeight: AppPrimitives.semibold),
          bodyLarge: base.bodyLarge?.copyWith(
              fontSize: AppPrimitives.textLg, height: 1.5),
          bodyMedium: base.bodyMedium?.copyWith(
              fontSize: AppPrimitives.textMd, height: 1.45),
          bodySmall: base.bodySmall?.copyWith(
              fontSize: AppPrimitives.textSm, height: 1.4),
          labelLarge: base.labelLarge?.copyWith(
              fontSize: AppPrimitives.textMd,
              fontWeight: AppPrimitives.medium),
          labelSmall: base.labelSmall?.copyWith(
              fontSize: AppPrimitives.textXs,
              fontWeight: AppPrimitives.medium),
        )
        .apply(bodyColor: p.onSurface, displayColor: p.onBackground);

    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppPrimitives.radiusLg),
      side: BorderSide(color: p.outline.withValues(alpha: 0.5)),
    );

    final buttonShape = WidgetStatePropertyAll(
      RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppPrimitives.radiusMd)),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.onBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: p.onBackground),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: cardShape,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.onSurface.withValues(alpha: 0.75),
        textColor: p.onSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppPrimitives.space4),
      ),
      dividerTheme: DividerThemeData(
        color: p.outline.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.primary.withValues(alpha: 0.16),
        elevation: 0,
        height: 72,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelSmall),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? p.primary : p.onSurface.withValues(alpha: 0.6),
            size: 24,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(p.primary),
          foregroundColor: WidgetStatePropertyAll(p.onPrimary),
          minimumSize: const WidgetStatePropertyAll(
              Size(AppPrimitives.touchTarget, AppPrimitives.touchTarget)),
          shape: buttonShape,
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(p.primary),
          side: WidgetStatePropertyAll(BorderSide(color: p.outline)),
          shape: buttonShape,
          minimumSize: const WidgetStatePropertyAll(
              Size(AppPrimitives.touchTarget, AppPrimitives.touchTarget)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(p.primary),
          shape: buttonShape,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppPrimitives.space3, vertical: AppPrimitives.space3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppPrimitives.radiusMd),
          borderSide: BorderSide(color: p.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppPrimitives.radiusMd),
          borderSide: BorderSide(color: p.outline.withValues(alpha: 0.7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppPrimitives.radiusMd),
          borderSide: BorderSide(color: p.primary, width: 1.5),
        ),
        hintStyle:
            TextStyle(color: p.onSurface.withValues(alpha: 0.55)),
        labelStyle: TextStyle(color: p.onSurface.withValues(alpha: 0.75)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceAlt,
        selectedColor: p.primary.withValues(alpha: 0.16),
        side: BorderSide(color: p.outline.withValues(alpha: 0.7)),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(color: p.onSurface, fontSize: AppPrimitives.textSm),
        padding: const EdgeInsets.symmetric(
            horizontal: AppPrimitives.space2, vertical: AppPrimitives.space1),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? p.primary
                : p.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? p.onPrimary
                : p.onSurface.withValues(alpha: 0.8);
          }),
          side: WidgetStatePropertyAll(BorderSide(color: p.outline)),
          shape: buttonShape,
          minimumSize: const WidgetStatePropertyAll(
              Size(0, AppPrimitives.touchTarget)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? p.primary
              : p.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? p.primary.withValues(alpha: 0.35)
              : p.surfaceAlt;
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.onSurface,
        contentTextStyle: TextStyle(color: p.background),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppPrimitives.radiusMd)),
      ),
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: p.primary, linearTrackColor: p.surfaceAlt),
      extensions: [
        AppThemeColors(
          success: p.success,
          onSuccess: p.onSuccess,
          warning: p.warning,
          onWarning: p.onWarning,
          chartColors: p.chart,
          chartGrid: p.outline.withValues(alpha: 0.35),
          chartAxis: p.onSurface.withValues(alpha: 0.65),
          gradient: LinearGradient(
            colors: [p.gradientStart, p.gradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          cardRadius: AppPrimitives.radiusLg,
          sectionSpacing: AppPrimitives.space6,
        ),
      ],
    );
  }

  /// Los seis temas listos para `MaterialApp(theme: ...)` por paleta.
  static final Map<AppPaletteId, ThemeData> all = {
    for (final paleta in AppPalette.all) paleta.id: build(paleta),
  };

  static ThemeData of(AppPaletteId id) => all[id]!;

  /// Tokens de componente del tema activo.
  static AppThemeColors colors(BuildContext context) =>
      Theme.of(context).extension<AppThemeColors>()!;

  static AppThemeColors? maybeColors(BuildContext context) =>
      Theme.of(context).extension<AppThemeColors>();
}
