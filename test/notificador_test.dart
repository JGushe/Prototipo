// Pruebas del notificador de recomendaciones (Etapa 7).
//
// Verifican que solo se notifiquen las recomendaciones que correspondan, que se
// respete el permiso de notificaciones y que el id sea estable por regla.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/models/recomendacion.dart';
import 'package:prototipo_tesis/services/notificacion_service.dart';
import 'package:prototipo_tesis/services/recomendaciones_notificador.dart';

class _NotifFalsa extends NotificacionService {
  bool permiso = true;
  final List<String> notificadas = [];

  @override
  Future<bool> tienePermisoNotificaciones() async => permiso;

  @override
  Future<void> notificarRecomendacion(Recomendacion recomendacion) async {
    notificadas.add(recomendacion.reglaId ?? '?');
  }
}

Recomendacion _rec(String reglaId, String severidad) => Recomendacion(
      fecha: DateTime(2026, 8, 24, 10),
      tipo: 'pausa',
      titulo: 'Título',
      mensaje: 'Mensaje',
      reglaId: reglaId,
      severidad: severidad,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('RecomendacionesNotificador', () {
    test('solo se notifican advertencias y críticas', () async {
      final notif = _NotifFalsa();
      final notificador = RecomendacionesNotificador(notificacion: notif);

      final enviadas = await notificador.notificarTodas([
        _rec('R1', 'advertencia'),
        _rec('R3', 'critica'),
        _rec('R4', 'sugerencia'),
        _rec('R8', 'info'),
      ]);

      expect(enviadas, 2);
      expect(notif.notificadas, ['R1', 'R3']);
    });

    test('sin permiso de notificaciones no se envía nada', () async {
      final notif = _NotifFalsa()..permiso = false;
      final notificador = RecomendacionesNotificador(notificacion: notif);

      final enviadas =
          await notificador.notificarTodas([_rec('R1', 'advertencia')]);

      expect(enviadas, 0);
      expect(notif.notificadas, isEmpty);
    });

    test('una lista vacía no notifica', () async {
      final notif = _NotifFalsa();
      final notificador = RecomendacionesNotificador(notificacion: notif);

      final enviadas = await notificador.notificarTodas(const []);

      expect(enviadas, 0);
    });

    test('debeNotificar distingue severidades', () {
      expect(RecomendacionesNotificador.debeNotificar(_rec('R1', 'advertencia')), isTrue);
      expect(RecomendacionesNotificador.debeNotificar(_rec('R1', 'critica')), isTrue);
      expect(RecomendacionesNotificador.debeNotificar(_rec('R4', 'sugerencia')), isFalse);
      expect(RecomendacionesNotificador.debeNotificar(_rec('R8', 'info')), isFalse);
    });
  });

  group('Id de notificación estable por regla', () {
    test('se deriva del número de la regla', () {
      expect(NotificacionService.idNotificacionParaRegla('R1'), 1001);
      expect(NotificacionService.idNotificacionParaRegla('R3'), 1003);
      expect(NotificacionService.idNotificacionParaRegla('R10'), 1010);
      expect(NotificacionService.idNotificacionParaRegla(null), 2000);
    });

    test('el mismo reglaId produce siempre el mismo id', () {
      expect(
        NotificacionService.idNotificacionParaRegla('R3'),
        NotificacionService.idNotificacionParaRegla('R3'),
      );
    });

    test('el id de tarea vive en un rango propio, sin choques', () {
      expect(NotificacionService.idNotificacionParaTarea(1), 10001);
      expect(NotificacionService.idNotificacionParaTarea(1001), 11001);
      // Por encima de reglas (1000-2000) y de la prueba (9001).
      expect(
        NotificacionService.idNotificacionParaTarea(1),
        greaterThan(NotificacionService.idNotificacionParaRegla(null)),
      );
      expect(
        NotificacionService.idNotificacionParaTarea(1),
        greaterThan(NotificacionService.idNotificacionDePrueba),
      );
    });
  });

  group('Entrega Android (canal simulado)', () {
    const canal = MethodChannel('dexterous.com/flutter/local_notifications');
    late TestDefaultBinaryMessenger mensajero;
    late List<Map<Object?, Object?>> mostradas;

    setUpAll(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();
    });

    setUp(() {
      mensajero =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      mostradas = [];
      mensajero.setMockMethodCallHandler(canal, (call) async {
        if (call.method == 'show') {
          mostradas.add(call.arguments as Map<Object?, Object?>);
        }
        return null;
      });
    });

    tearDown(() {
      mensajero.setMockMethodCallHandler(canal, null);
    });

    tearDownAll(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('cada regla usa su id y comparte grupo', () async {
      await NotificacionService().notificarRecomendacion(_rec('R1', 'advertencia'));
      await NotificacionService().notificarRecomendacion(_rec('R5', 'advertencia'));

      expect(mostradas, hasLength(2));
      expect(mostradas[0]['id'], 1001);
      expect(mostradas[1]['id'], 1005);

      final detalles0 =
          mostradas[0]['platformSpecifics'] as Map<Object?, Object?>;
      final detalles1 =
          mostradas[1]['platformSpecifics'] as Map<Object?, Object?>;
      expect(detalles0['groupKey'], NotificacionService.grupoRecomendaciones);
      expect(detalles1['groupKey'], NotificacionService.grupoRecomendaciones);
    });

    test('la misma regla reutiliza el id: Android reemplaza, no apila', () async {
      await NotificacionService().notificarRecomendacion(_rec('R3', 'critica'));
      await NotificacionService().notificarRecomendacion(_rec('R3', 'critica'));

      expect(mostradas, hasLength(2));
      expect(mostradas[0]['id'], mostradas[1]['id']);
    });

    test('la notificación de prueba no se agrupa', () async {
      await NotificacionService().enviarNotificacionDePrueba();

      final detalles =
          mostradas.single['platformSpecifics'] as Map<Object?, Object?>;
      expect(mostradas.single['id'], NotificacionService.idNotificacionDePrueba);
      expect(detalles['groupKey'], isNull);
    });
  });
}
