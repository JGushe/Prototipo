import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/comparacion_diaria.dart';
import '../models/contexto_recomendacion.dart';
import '../models/intervalo_uso.dart';
import '../models/uso_pantalla.dart';
import '../database/database_helper.dart';
import 'monitoreo_uso_horarios_service.dart';

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

  /// Desbloqueos desde [inicio] hasta [fin], o null si la consulta falla
  /// (sin permiso, plugin ausente); así se distingue de un cero real.
  Future<int?> _contarDesbloqueos(DateTime inicio, DateTime fin) async {
    try {
      return contarDesbloqueos(await UsageStats.queryEvents(inicio, fin));
    } catch (e) {
      debugPrint('usage_stats: sin desbloqueos ($e)');
      return null;
    }
  }

  /// Compara el uso de hoy con el de ayer hasta la misma hora de corte.
  ///
  /// Los resúmenes diarios no guardan la hora de captura, así que el corte se
  /// reconstruye con eventos de UsageStats (retención ~7 días). Si no se
  /// pueden leer los eventos, devuelve insuficiente y no inventa valores.
  Future<ComparacionDiaria> compararHoyAyer({DateTime? ahora}) async {
    final momento = ahora ?? DateTime.now();
    final inicioHoy = DateTime(momento.year, momento.month, momento.day);
    final inicioAyer = DateTime(momento.year, momento.month, momento.day - 1);
    final corte = DateTime(momento.year, momento.month, momento.day,
        momento.hour, momento.minute);
    final corteAyer = DateTime(momento.year, momento.month, momento.day - 1,
        momento.hour, momento.minute);

    if (!await tienePermisoUso()) {
      return ComparacionDiaria.insuficiente(
        ahora: momento,
        explicacion:
            'Sin permiso de acceso al uso: no se puede comparar hoy con ayer.',
      );
    }

    final List<EventoUso> eventos;
    try {
      final crudos = await UsageStats.queryEvents(inicioAyer, momento);
      eventos = _eventosDeUso(crudos);
    } catch (e) {
      debugPrint('usage_stats: sin eventos para hoy/ayer ($e)');
      return ComparacionDiaria.insuficiente(
        ahora: momento,
        explicacion:
            'No se pudieron leer los eventos de uso de ayer y hoy.',
      );
    }

    final intervalos = MonitoreoUsoHorariosService.emparejarEventos(
      eventos,
      cierrePorDefecto: momento,
    );

    return ComparacionDiaria.calcular(
      ahora: momento,
      corte: corte,
      minutosHoy: _minutosEn(intervalos, inicioHoy, momento),
      minutosAyer: _minutosEn(intervalos, inicioAyer, corteAyer),
      distractorHoy:
          _minutosEn(intervalos, inicioHoy, momento, soloDistractores: true),
      distractorAyer: _minutosEn(intervalos, inicioAyer, corteAyer,
          soloDistractores: true),
    );
  }

  /// Convierte eventos crudos a RESUME/PAUSE descartando el resto.
  List<EventoUso> _eventosDeUso(List<EventUsageInfo> crudos) {
    final eventos = <EventoUso>[];
    for (final e in crudos) {
      final instante = e.timeStampDate;
      final paquete = e.packageName;
      final tipo = e.eventTypeValue;
      if (instante == null || paquete == null) continue;
      if (tipo != 1 && tipo != 2) continue; // ACTIVITY_RESUMED / PAUSED
      eventos.add(EventoUso(
        momento: instante,
        nombrePaquete: paquete,
        esResume: tipo == 1,
      ));
    }
    return eventos;
  }

  /// Minutos de intervalos dentro de [desde, hasta], recortando bordes.
  int _minutosEn(
    List<IntervaloUso> intervalos,
    DateTime desde,
    DateTime hasta, {
    bool soloDistractores = false,
  }) {
    var segundos = 0;
    for (final intervalo in intervalos) {
      if (soloDistractores &&
          !ContextoRecomendacion.paquetesDistractoresPorDefecto
              .contains(intervalo.nombrePaquete)) {
        continue;
      }
      final inicio =
          intervalo.inicio.isBefore(desde) ? desde : intervalo.inicio;
      final fin = intervalo.fin.isAfter(hasta) ? hasta : intervalo.fin;
      if (!fin.isAfter(inicio)) continue;
      segundos += fin.difference(inicio).inSeconds;
    }
    return segundos ~/ 60;
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

    final desbloqueos = await _contarDesbloqueos(inicioDelDia, now);
    // Si la consulta falló, conserva el valor ya guardado del día en lugar
    // de sobrescribirlo con 0.
    final desbloqueosPrevios = desbloqueos == null
        ? (await _db.obtenerUsoPorFecha(inicioDelDia))?.numeroDesbloqueos
        : null;

    final uso = UsoPantalla(
      fecha: inicioDelDia,
      tiempoTotalMinutos: tiempoTotal,
      numeroDesbloqueos: desbloqueos ?? desbloqueosPrevios ?? 0,
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
