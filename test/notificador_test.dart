// Pruebas del notificador de recomendaciones (Etapa 7).
//
// Verifican que solo se notifiquen las recomendaciones que correspondan, que se
// respete el permiso de notificaciones y que el id sea estable por regla.

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
  });
}
