import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/comparacion_diaria.dart';
import '../models/contexto_recomendacion.dart';
import 'reglas/configuracion_motor.dart';
import '../models/intervalo_uso.dart';
import '../models/uso_pantalla.dart';
import '../database/database_helper.dart';
import 'monitoreo_uso_horarios_service.dart';

typedef MuestraUso = ({
  DateTime momento,
  UsoPantalla resumen,
  List<AppUso> apps
});

enum CapturaUsoNoDisponible implements Exception { sinPermiso, sinDatos }

class UsoPantallaService {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final ConfiguracionMotor _config;
  final _monitoreo = MonitoreoUsoHorariosService();

  UsoPantallaService({ConfiguracionMotor? configuracion})
      : _config = configuracion ?? ConfiguracionMotor.porDefecto;

  /// Paquetes cuyo error de nombre ya se registró: evita repetir el log en
  /// cada captura (el monitoreo de fondo corre cada ~15 min).
  final Set<String> _paquetesConErrorDeNombre = {};

  /// Comprueba si el permiso de UsageStats está concedido, **sin solicitarlo**.
  /// Devuelve false ante cualquier error (plugin ausente, sin permiso, etc.),
  /// de modo que las capas superiores puedan funcionar con datos parciales.
  Future<bool> tienePermisoUso() async {
    try {
      return await UsageStats.checkUsagePermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Solicita permisos de UsageStats (requiere acción manual en Ajustes)
  Future<bool> solicitarPermisoUso() async {
    // Verificar si ya tiene permiso
    if (await tienePermisoUso()) return true;

    // Solicitar permiso (abre ajustes de Android)
    await UsageStats.grantUsagePermission();
    await Future.delayed(const Duration(seconds: 1));
    return await tienePermisoUso();
  }

  /// Solicita permiso de notificaciones (Android 13+)
  Future<bool> solicitarPermisoNotificaciones() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Obtiene el nombre legible de una app a partir de su paquete.
  ///
  /// Si el paquete no se resuelve (null) o la consulta falla, se usa el
  /// [packageName] como fallback para no romper el monitoreo.
  Future<String> _nombreApp(String packageName) async {
    try {
      final info = await UsageStats.getAppInfo(packageName);
      return info?.appName ?? packageName;
    } on MissingPluginException {
      _registrarErrorNombre(packageName, 'plugin usage_stats no disponible');
      return packageName;
    } on PlatformException catch (e) {
      _registrarErrorNombre(packageName, 'PlatformException(${e.code})');
      return packageName;
    } catch (e) {
      // Red de seguridad: un fallo inesperado nunca debe romper el monitoreo.
      _registrarErrorNombre(packageName, 'error inesperado (${e.runtimeType})');
      return packageName;
    }
  }

  /// Registra el fallo una sola vez por paquete y sin datos sensibles.
  void _registrarErrorNombre(String packageName, String motivo) {
    if (!_paquetesConErrorDeNombre.add(packageName)) return;
    debugPrint('usage_stats: no se pudo resolver un nombre ($motivo)');
  }

  /// Evento de `UsageEvents` que indica que el usuario desbloqueó el equipo.
  ///
  /// `SCREEN_INTERACTIVE` (15) solo enciende la pantalla; no es un desbloqueo.
  static const int eventoKeyguardHidden = 18;

  /// Cuenta desbloqueos reales en [eventos]: solo `KEYGUARD_HIDDEN` (18),
  /// deduplicados por instante para no repetir eventos.
  static int contarDesbloqueos(Iterable<EventUsageInfo> eventos) {
    final instantes = <String>{};
    for (final evento in eventos) {
      final instante = evento.timeStamp;
      if (evento.eventTypeValue == eventoKeyguardHidden && instante != null) {
        instantes.add(instante);
      }
    }
    return instantes.length;
  }

  /// Compara ventanas locales hasta el mismo minuto en ambos días.
  Future<ComparacionDiaria> compararHoyAyer({DateTime? ahora}) async {
    final momento = ahora ?? DateTime.now();
    final hoy = DateTime(momento.year, momento.month, momento.day);
    final ayer = DateTime(momento.year, momento.month, momento.day - 1);
    final corte =
        DateTime(hoy.year, hoy.month, hoy.day, momento.hour, momento.minute);
    final corteAyer =
        DateTime(ayer.year, ayer.month, ayer.day, momento.hour, momento.minute);

    final TrazaUso traza;
    try {
      if (await UsageStats.checkUsagePermission() != true) {
        return ComparacionDiaria.insuficiente(
          ahora: momento,
          motivo: MotivoComparacion.sinPermiso,
          explicacion: 'Sin permiso de acceso al uso para comparar hoy y ayer.',
        );
      }
      traza = await _monitoreo.obtenerTraza(desde: ayer, hasta: momento);
    } catch (_) {
      return ComparacionDiaria.insuficiente(
        ahora: momento,
        motivo: MotivoComparacion.error,
        explicacion: 'No se pudieron leer los eventos de uso de ayer y hoy.',
      );
    }

    final ventanaHoy = VentanaTiempo(hoy, corte);
    final ventanaAyer = VentanaTiempo(ayer, corteAyer);
    final trazaHoy = _trazaEn(traza, ventanaHoy);
    final trazaAyer = _trazaEn(traza, ventanaAyer);
    final minutosHoy = trazaHoy.minutosUnicos(ventanaHoy);
    final desbloqueosHoy =
        minutosHoy == null ? null : trazaHoy.desbloqueosEn(ventanaHoy);
    final minutosAyer = trazaAyer.minutosUnicos(ventanaAyer);
    final distractorHoy = minutosHoy == null
        ? null
        : _minutosDistractores(trazaHoy.en(ventanaHoy));
    final distractorAyer = minutosAyer == null
        ? null
        : _minutosDistractores(trazaAyer.en(ventanaAyer));

    if (minutosHoy == null || minutosAyer == null) {
      return ComparacionDiaria.insuficiente(
        ahora: momento,
        corte: corte,
        minutosHoy: minutosHoy,
        minutosAyer: minutosAyer,
        distractorHoy: distractorHoy,
        distractorAyer: distractorAyer,
        desbloqueosHoy: desbloqueosHoy,
        explicacion: 'Faltan sesiones acreditadas para comparar ambos días.',
      );
    }
    return ComparacionDiaria.calcular(
      ahora: momento,
      corte: corte,
      minutosHoy: minutosHoy,
      minutosAyer: minutosAyer,
      distractorHoy: distractorHoy,
      distractorAyer: distractorAyer,
      desbloqueosHoy: desbloqueosHoy,
    );
  }

  TrazaUso _trazaEn(TrazaUso traza, VentanaTiempo ventana) {
    final desde = ventana.inicio
        .subtract(MonitoreoUsoHorariosService.duracionMaximaSesion);
    return MonitoreoUsoHorariosService.reconstruir(traza.eventos
        .where(
          (e) => !e.momento.isBefore(desde) && !e.momento.isAfter(ventana.fin),
        )
        .toList());
  }

  Future<int?> minutosUnicosHoy({DateTime? ahora}) async {
    if (!await tienePermisoUso()) return null;
    final momento = ahora ?? DateTime.now();
    final hoy = DateTime(momento.year, momento.month, momento.day);
    final corte =
        DateTime(hoy.year, hoy.month, hoy.day, momento.hour, momento.minute);
    final ventana = VentanaTiempo(hoy, corte);
    try {
      final traza = await _monitoreo.obtenerTraza(desde: hoy, hasta: momento);
      return _trazaEn(traza, ventana).minutosUnicos(ventana);
    } catch (_) {
      return null;
    }
  }

  int _minutosDistractores(List<IntervaloUso> intervalos) =>
      VentanaTiempo.duracionUnica([
        for (final intervalo in intervalos)
          if (ContextoRecomendacion.clasificarDistractor(
            intervalo.nombrePaquete,
            _config.paquetesDistractores,
          ))
            intervalo.ventana,
      ]).inMinutes;

  /// Captura el uso de pantalla del día actual
  Future<UsoPantalla> capturarUsoDelDia() async =>
      (await capturarMuestraDelDia()).resumen;

  Future<MuestraUso> capturarMuestraDelDia() async {
    if (await UsageStats.checkUsagePermission() != true) {
      throw CapturaUsoNoDisponible.sinPermiso;
    }

    final now = DateTime.now();
    final inicioDelDia = DateTime(now.year, now.month, now.day);
    final ventana = VentanaTiempo(inicioDelDia, now);
    final traza =
        await _monitoreo.obtenerTraza(desde: inicioDelDia, hasta: now);
    final tiempoTotal = traza.minutosUnicos(ventana);
    if (tiempoTotal == null) throw CapturaUsoNoDisponible.sinDatos;

    // La métrica por app usa los agregados de Android y tiene otra semántica.
    final stats = await UsageStats.queryUsageStats(inicioDelDia, now);
    if (stats.isEmpty) throw CapturaUsoNoDisponible.sinDatos;

    String? appMasUsada;
    int tiempoAppMasUsada = 0;
    final apps = <AppUso>[];

    for (final stat in stats) {
      final tiempoMs = stat.totalTimeInForegroundMs ?? 0;
      final tiempoMinutos = (tiempoMs / 60000).round();

      // Obtener nombre legible de la app
      final nombreApp = await _nombreApp(stat.packageName ?? '');

      if (tiempoMinutos > tiempoAppMasUsada) {
        tiempoAppMasUsada = tiempoMinutos;
        appMasUsada = nombreApp;
      }

      if (tiempoMinutos > 0) {
        apps.add(AppUso(
          nombrePaquete: stat.packageName ?? '',
          nombreApp: nombreApp,
          tiempoUsoMinutos: tiempoMinutos,
          numeroAperturas: 1,
        ));
      }
    }

    final uso = UsoPantalla(
      fecha: inicioDelDia,
      tiempoTotalMinutos: tiempoTotal,
      numeroDesbloqueos: traza.desbloqueosEn(ventana),
      appMasUsada: appMasUsada,
      tiempoAppMasUsada: tiempoAppMasUsada,
    );

    // Resumen y detalle en una sola transacción: si falla una app no queda
    // un resumen parcial del día.
    await _db.guardarUsoDelDia(uso, apps);

    apps.sort((a, b) => b.tiempoUsoMinutos.compareTo(a.tiempoUsoMinutos));
    return (momento: now, resumen: uso, apps: apps);
  }

  /// Obtiene las top N aplicaciones más usadas del día
  Future<List<AppUso>> obtenerTopAppsDelDia({int top = 5, DateTime? ahora}) async {
    final now = ahora ?? DateTime.now();
    final inicioDelDia = DateTime(now.year, now.month, now.day);
    final stats = await UsageStats.queryUsageStats(inicioDelDia, now);
    final apps = <AppUso>[];

    for (final stat in stats) {
      final tiempoMs = stat.totalTimeInForegroundMs ?? 0;
      final tiempoMinutos = (tiempoMs / 60000).round();

      if (tiempoMinutos > 0) {
        final nombreApp = await _nombreApp(stat.packageName ?? '');
        apps.add(AppUso(
          nombrePaquete: stat.packageName ?? '',
          nombreApp: nombreApp,
          tiempoUsoMinutos: tiempoMinutos,
          numeroAperturas: 1,
        ));
      }
    }

    apps.sort((a, b) => b.tiempoUsoMinutos.compareTo(a.tiempoUsoMinutos));
    return apps.take(top).toList();
  }
}
