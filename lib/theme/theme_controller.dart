import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/perfil.dart';
import 'app_palettes.dart';

/// Familia cromática elegible. El modo claro/oscuro es independiente.
enum FamiliaPaleta { cool, warm, rgb }

/// Estado de apariencia: modo del sistema/claro/oscuro y familia manual
/// (o la sugerida por el perfil si no hay elección).
@immutable
class Apariencia {
  final ThemeMode modo;

  /// Elección manual; tiene prioridad absoluta sobre la sugerencia.
  final FamiliaPaleta? manual;

  /// Sugerencia derivada de la identidad del perfil (nunca persistida).
  final FamiliaPaleta sugerida;

  const Apariencia({
    required this.modo,
    required this.sugerida,
    this.manual,
  });

  FamiliaPaleta get familia => manual ?? sugerida;

  AppPaletteId get clara => switch (familia) {
        FamiliaPaleta.cool => AppPaletteId.lightCool,
        FamiliaPaleta.warm => AppPaletteId.lightWarm,
        FamiliaPaleta.rgb => AppPaletteId.lightRgb,
      };

  AppPaletteId get oscura => switch (familia) {
        FamiliaPaleta.cool => AppPaletteId.darkCool,
        FamiliaPaleta.warm => AppPaletteId.darkWarm,
        FamiliaPaleta.rgb => AppPaletteId.darkRgb,
      };

  Apariencia copyWith({
    ThemeMode? modo,
    FamiliaPaleta? manual,
    FamiliaPaleta? sugerida,
  }) =>
      Apariencia(
        modo: modo ?? this.modo,
        manual: manual ?? this.manual,
        sugerida: sugerida ?? this.sugerida,
      );
}

/// Notificador global mínimo: `ValueListenableBuilder` en `MaterialApp`.
class AparienciaController extends ValueNotifier<Apariencia> {
  AparienciaController._()
      : super(const Apariencia(
          modo: ThemeMode.system,
          sugerida: FamiliaPaleta.cool,
        ));

  static final AparienciaController instance = AparienciaController._();

  /// Sugerencia inicial desde la identidad. Solo aplica sin elección manual.
  static FamiliaPaleta sugeridaPara(String? identidad) {
    switch (identidad) {
      case Perfil.femenino:
        return FamiliaPaleta.warm;
      case Perfil.noBinario:
      case Perfil.otra:
        return FamiliaPaleta.rgb;
      default:
        return FamiliaPaleta.cool;
    }
  }

  Future<void> cargar() async {
    try {
      final ap = await DatabaseHelper.instance.obtenerApariencia();
      final perfil = await DatabaseHelper.instance.obtenerPerfil();
      value = Apariencia(
        modo: _modoDesde(ap.modo),
        manual: _familiaDesde(ap.paleta),
        sugerida: sugeridaPara(perfil?.identidadGenero),
      );
    } catch (e) {
      debugPrint('Apariencia no disponible: $e');
    }
  }

  /// Recalcula solo la sugerencia (p. ej. tras editar el perfil).
  Future<void> recargarSugerencia() async {
    try {
      final perfil = await DatabaseHelper.instance.obtenerPerfil();
      value = value.copyWith(sugerida: sugeridaPara(perfil?.identidadGenero));
    } catch (e) {
      debugPrint('Sugerencia de paleta no disponible: $e');
    }
  }

  Future<void> setModo(ThemeMode modo) async {
    value = value.copyWith(modo: modo);
    await _persistir();
  }

  Future<void> setFamilia(FamiliaPaleta familia) async {
    value = value.copyWith(manual: familia);
    await _persistir();
  }

  Future<void> _persistir() async {
    try {
      await DatabaseHelper.instance.guardarApariencia(
        modo: _modoValor(value.modo),
        paleta: _familiaValor(value.manual),
      );
    } catch (e) {
      debugPrint('No se pudo guardar la apariencia: $e');
    }
  }

  static ThemeMode _modoDesde(String? valor) => switch (valor) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _modoValor(ThemeMode modo) => switch (modo) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static FamiliaPaleta? _familiaDesde(String? valor) => switch (valor) {
        'cool' => FamiliaPaleta.cool,
        'warm' => FamiliaPaleta.warm,
        'rgb' => FamiliaPaleta.rgb,
        _ => null,
      };

  static String? _familiaValor(FamiliaPaleta? familia) => switch (familia) {
        FamiliaPaleta.cool => 'cool',
        FamiliaPaleta.warm => 'warm',
        FamiliaPaleta.rgb => 'rgb',
        null => null,
      };
}
