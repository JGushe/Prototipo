import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../database/database_helper.dart';
import 'motor_recomendaciones.dart';
import 'notificacion_service.dart';
import 'recomendaciones_notificador.dart';

/// Controla el monitoreo en segundo plano.
///
/// El trabajo periódico lo ejecuta Android con **WorkManager**: cada ~15 min
/// (mínimo del sistema) despierta un *FlutterEngine* headless y ejecuta
/// [monitoreoCallbackDispatcher] en un isolate propio. Así el monitoreo sigue
/// funcionando con la interfaz cerrada sin duplicar la lógica del motor: el
/// isolate de fondo reutiliza exactamente los mismos servicios que la app.
///
/// No se usa ningún `Timer` de Dart: cuando la app está cerrada, quien decide
/// cuándo ejecutar es WorkManager, respetando Doze y las restricciones de
/// Android.
class MonitoreoSegundoPlanoService {
  /// Canal de control (app ↔ nativo).
  static const MethodChannel canalControl = MethodChannel('prototipo_tesis/monitoreo');

  /// Canal que usa el isolate de fondo para avisar de que terminó.
  static const String canalCompletado = 'prototipo_tesis/monitoreo_completado';

  /// Nombre del trabajo periódico único en WorkManager.
  static const String nombreTrabajo = 'monitoreo_uso_horarios';

  /// ¿Hay monitoreo programado o en ejecución?
  Future<bool> estaActivo() async {
    try {
      return await canalControl.invokeMethod<bool>('estaActivo') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Programa el monitoreo periódico. Devuelve true si se pudo programar.
  ///
  /// Requiere el permiso de UsageStats concedido: sin él el ciclo de fondo se
  /// ejecutará pero no obtendrá datos (y no generará recomendaciones).
  Future<bool> iniciar() async {
    final handle = ui.PluginUtilities.getCallbackHandle(monitoreoCallbackDispatcher);
    if (handle == null) return false;
    try {
      return await canalControl.invokeMethod<bool>('iniciar', {
            'callbackHandle': handle.toRawHandle(),
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Cancela el monitoreo periódico.
  Future<bool> detener() async {
    try {
      return await canalControl.invokeMethod<bool>('detener') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Lanza una ejecución inmediata (útil para probar en el dispositivo).
  Future<bool> ejecutarAhora() async {
    try {
      return await canalControl.invokeMethod<bool>('ejecutarAhora') ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Punto de entrada que Android ejecuta en segundo plano.
///
/// Debe ser una función de nivel superior anotada con `vm:entry-point` y no
/// puede capturar estado de la aplicación: el isolate de fondo arranca desde
/// cero, así que aquí se reconstruyen todos los servicios.
@pragma('vm:entry-point')
void monitoreoCallbackDispatcher() {
  ui.DartPluginRegistrant.ensureInitialized();
  _cicloDeMonitoreo().whenComplete(() {
    // Avisa al Worker nativo de que el ciclo terminó y puede liberar el motor.
    const MethodChannel(MonitoreoSegundoPlanoService.canalCompletado)
        .invokeMethod<void>('completado')
        .catchError((Object _) {});
  });
}

/// Ciclo completo de monitoreo, idéntico al que ejecuta la interfaz:
/// contexto → reglas → cooldown → almacenamiento → notificación.
Future<void> _cicloDeMonitoreo() async {
  try {
    // Asegura la base de datos antes de construir el contexto.
    await DatabaseHelper.instance.database;

    // Inicializa notificaciones en este isolate (el registro es por isolate).
    try {
      await NotificacionService().init();
    } catch (_) {
      // Sin permiso o sin plugin: el ciclo continúa sin notificar.
    }

    final resultado = await MotorRecomendaciones().ejecutar();

    // Solo se notifican las recomendaciones que correspondan y con permiso;
    // el cooldown del motor ya evitó las repetidas.
    await RecomendacionesNotificador().notificarTodas(resultado.generadas);
  } catch (_) {
    // Un fallo en segundo plano nunca debe bloquear futuras ejecuciones.
  }
}
