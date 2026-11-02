import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/uso_pantalla.dart';
import '../database/database_helper.dart';

class UsoPantallaService {
  final DatabaseHelper _db = DatabaseHelper.instance;

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
    debugPrint('usage_stats: sin nombre para $packageName ($motivo)');
  }

  /// Captura el uso de pantalla del día actual
  Future<UsoPantalla> capturarUsoDelDia() async {
    final now = DateTime.now();
    final inicioDelDia = DateTime(now.year, now.month, now.day);
    final finDelDia = inicioDelDia.add(const Duration(days: 1));

    // Consultar estadísticas de uso
    final stats = await UsageStats.queryUsageStats(inicioDelDia, finDelDia);

    int tiempoTotal = 0;
    String? appMasUsada;
    int tiempoAppMasUsada = 0;
    final apps = <AppUso>[];

    for (final stat in stats) {
      final tiempoMs = stat.totalTimeInForegroundMs ?? 0;
      final tiempoMinutos = (tiempoMs / 60000).round();
      tiempoTotal += tiempoMinutos;

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
      numeroDesbloqueos: 0,
      appMasUsada: appMasUsada,
      tiempoAppMasUsada: tiempoAppMasUsada,
    );

    // Resumen y detalle en una sola transacción: si falla una app no queda
    // un resumen parcial del día.
    await _db.guardarUsoDelDia(uso, apps);

    return uso;
  }

  /// Obtiene las top N aplicaciones más usadas del día
  Future<List<AppUso>> obtenerTopAppsDelDia({int top = 5}) async {
    final now = DateTime.now();
    final inicioDelDia = DateTime(now.year, now.month, now.day);
    final finDelDia = inicioDelDia.add(const Duration(days: 1));

    final stats = await UsageStats.queryUsageStats(inicioDelDia, finDelDia);
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
