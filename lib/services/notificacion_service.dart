import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/recomendacion.dart';
import '../models/tarea.dart';

class NotificacionService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings: initSettings);

    // Solicitar permisos en Android 13+
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();

    _initialized = true;
  }

  /// Programa una notificación para una tarea con fecha de vencimiento
  Future<void> programarNotificacionTarea(Tarea tarea) async {
    if (tarea.fechaVencimiento == null || tarea.id == null) return;

    final fechaNotif = tarea.fechaVencimiento!.subtract(const Duration(minutes: 30));
    if (fechaNotif.isBefore(DateTime.now())) return;

    final tzDateTime = tz.TZDateTime.from(fechaNotif, tz.local);

    const androidDetails = AndroidNotificationDetails(
      'tareas_channel',
      'Recordatorios de Tareas',
      channelDescription: 'Notificaciones de tareas pendientes',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.zonedSchedule(
      id: tarea.id!,
      title: '⏰ ${tarea.titulo}',
      body: tarea.descripcion ?? 'Tienes una tarea próxima a vencer',
      scheduledDate: tzDateTime,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// Envía una notificación inmediata
  Future<void> enviarNotificacion(String titulo, String mensaje, {int id = 0}) async {
    const androidDetails = AndroidNotificationDetails(
      'general_channel',
      'Notificaciones',
      channelDescription: 'Notificaciones generales del prototipo',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id: id,
      title: titulo,
      body: mensaje,
      notificationDetails: details,
    );
  }

  Future<void> cancelarNotificacion(int id) async {
    await _plugin.cancel(id: id);
  }

  Future<void> cancelarTodas() async {
    await _plugin.cancelAll();
  }

  // --- Notificaciones de recomendaciones ---

  /// ¿El sistema permite mostrar notificaciones? (respeta Android 13+)
  Future<bool> tienePermisoNotificaciones() async {
    try {
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Solicita el permiso de notificaciones (Android 13+) si aún no está dado.
  Future<bool> solicitarPermisoNotificaciones() async {
    try {
      final status = await Permission.notification.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Identificador reservado para la notificación de prueba.
  static const int idNotificacionDePrueba = 9001;

  /// Envía una notificación de prueba para verificar que el canal funciona.
  Future<void> enviarNotificacionDePrueba() async {
    await enviarNotificacion(
      '🔔 Prueba de notificación',
      'Si ves este mensaje, las notificaciones del prototipo funcionan. '
          'Las recomendaciones reales llegan igual, indicando su regla.',
      id: idNotificacionDePrueba,
    );
  }

  /// Envía una notificación para una recomendación usando un id **estable por
  /// regla**: si la misma regla vuelve a notificar, Android reemplaza la
  /// notificación anterior en lugar de apilar repetidas.
  Future<void> notificarRecomendacion(Recomendacion recomendacion) async {
    await enviarNotificacion(
      recomendacion.titulo,
      recomendacion.mensaje,
      id: idNotificacionParaRegla(recomendacion.reglaId),
    );
  }

  /// Identificador de notificación estable para una regla: 1000 + número de la
  /// regla ('R3' -> 1003). Con un `reglaId` desconocido se usa su hash.
  static int idNotificacionParaRegla(String? reglaId) {
    if (reglaId == null) return 2000;
    final numero = int.tryParse(reglaId.replaceAll(RegExp(r'[^0-9]'), ''));
    return 1000 + (numero ?? reglaId.hashCode.abs() % 1000);
  }
}
