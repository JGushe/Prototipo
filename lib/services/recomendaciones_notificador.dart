import 'package:flutter/foundation.dart';

import '../models/recomendacion.dart';
import 'notificacion_service.dart';

/// Decide qué recomendaciones se notifican y las envía.
///
/// Solo se notifican las que **corresponden** (severidad `advertencia` o
/// `critica`), respetando el permiso de notificaciones de Android. No se envían
/// notificaciones repetidas: el motor ya aplica el cooldown antes de crear la
/// recomendación y el id de la notificación es estable por regla, de modo que
/// una nueva notificación de la misma regla reemplaza a la anterior.
class RecomendacionesNotificador {
  final NotificacionService _notificacion;

  RecomendacionesNotificador({NotificacionService? notificacion})
      : _notificacion = notificacion ?? NotificacionService();

  /// Severidades que merecen notificación. Las sugerencias e informativas se
  /// muestran solo en la aplicación.
  static const Set<String> severidadesNotificables = {
    'advertencia',
    'critica',
  };

  static bool debeNotificar(Recomendacion recomendacion) =>
      severidadesNotificables.contains(recomendacion.severidad);

  /// Envía las notificaciones que correspondan y devuelve cuántas se enviaron.
  ///
  /// Devuelve 0 si no hay permiso de notificaciones o si ninguna recomendación
  /// alcanza la severidad necesaria.
  Future<int> notificarTodas(List<Recomendacion> recomendaciones) async {
    if (recomendaciones.isEmpty) {
      _log('Nada que notificar: no se generaron recomendaciones nuevas');
      return 0;
    }

    if (!await _notificacion.tienePermisoNotificaciones()) {
      _log('No se notifica: falta el permiso de notificaciones de Android');
      return 0;
    }

    var enviadas = 0;
    for (final recomendacion in recomendaciones) {
      if (!debeNotificar(recomendacion)) {
        _log('Omitida ${recomendacion.reglaId}: la severidad '
            '"${recomendacion.severidad}" no se notifica');
        continue;
      }
      await _notificacion.notificarRecomendacion(recomendacion);
      _log('Notificada ${recomendacion.reglaId}: ${recomendacion.titulo}');
      enviadas++;
    }
    return enviadas;
  }

  /// Traza en modo desarrollo: permite saber por qué no llegó una notificación.
  void _log(String mensaje) {
    if (kDebugMode) debugPrint('[Notificador] $mensaje');
  }
}
