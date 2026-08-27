import 'dart:async';
import 'package:usage_stats/usage_stats.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/uso_pantalla.dart';
import '../database/database_helper.dart';

class UsoPantallaService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Solicita permisos de UsageStats (requiere acción manual en Ajustes)
  Future<bool> solicitarPermisoUso() async {
    // Verificar si ya tiene permiso
    bool granted = await UsageStats.checkUsagePermission() ?? false;
    if (granted) return true;

    // Solicitar permiso (abre ajustes de Android)
    await UsageStats.grantUsagePermission();
    await Future.delayed(const Duration(seconds: 1));
    granted = await UsageStats.checkUsagePermission() ?? false;
    return granted;
  }

  /// Solicita permiso de notificaciones (Android 13+)
  Future<bool> solicitarPermisoNotificaciones() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Obtiene el nombre legible de una app a partir de su paquete
  Future<String> _nombreApp(String packageName) async {
    try {
      final info = await UsageStats.getAppInfo(packageName);
      return info?.appName ?? packageName;
    } catch (_) {
      return packageName;
    }
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

    // Guardar en base de datos
    await _db.insertarOActualizarUsoPantalla(uso);

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
