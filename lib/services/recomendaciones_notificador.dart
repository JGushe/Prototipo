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
    if (recomendaciones.isEmpty) return 0;
    if (!await _notificacion.tienePermisoNotificaciones()) return 0;

    var enviadas = 0;
    for (final recomendacion in recomendaciones) {
      if (!debeNotificar(recomendacion)) continue;
      await _notificacion.notificarRecomendacion(recomendacion);
      enviadas++;
    }
    return enviadas;
  }
}
