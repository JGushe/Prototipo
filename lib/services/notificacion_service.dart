import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
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
}
