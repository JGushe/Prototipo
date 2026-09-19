import '../database/database_helper.dart';
import '../models/contexto_recomendacion.dart';
import '../models/horario.dart';
import '../models/tarea.dart';
import '../models/uso_pantalla.dart';
import 'uso_pantalla_service.dart';

/// Construye el [ContextoRecomendacion] consultando las fuentes de datos.
///
/// Responsabilidad única: **adquirir y normalizar** el estado del usuario.
/// No aplica reglas de negocio ni genera recomendaciones; eso corresponde al
/// motor.
///
/// Para evitar consultas repetidas, cada fuente se lee una sola vez y todo lo
/// demás se deriva en memoria.
class ContextoRecomendacionService {
  final DatabaseHelper _db;
  final UsoPantallaService _usoService;

  /// [db] y [usoService] son inyectables para facilitar pruebas.
  ContextoRecomendacionService({
    DatabaseHelper? db,
    UsoPantallaService? usoService,
  })  : _db = db ?? DatabaseHelper.instance,
        _usoService = usoService ?? UsoPantallaService();

  /// Construye el contexto para [momento] (por defecto, ahora).
  ///
  /// [topApps] limita cuántas aplicaciones se piden a la fuente de uso; su valor
  /// por defecto (5) reproduce el comportamiento previo del motor.
  Future<ContextoRecomendacion> construir({
    DateTime? momento,
    int topApps = 5,
  }) async {
    final ahora = momento ?? DateTime.now();

    // 1) Tareas: una sola consulta; pendientes y alta prioridad se derivan.
    final tareasPendientes = await _db.obtenerTareas(completada: false);
    final tareasAltaPrioridad = <Tarea>[];
    Tarea? tareaActiva;
    for (final tarea in tareasPendientes) {
      if (tarea.prioridad == 'alta') {
        tareasAltaPrioridad.add(tarea);
      }
      if (tareaActiva == null && tarea.estaPlanificadaEn(ahora)) {
        tareaActiva = tarea;
      }
    }

    // 2) Horarios: una sola consulta.
    final horarios = await _db.obtenerHorarios();
    Horario? horarioActivo;
    for (final horario in horarios) {
      if (horario.contieneDateTime(ahora)) {
        horarioActivo = horario;
        break;
      }
    }

    // 3) Uso de pantalla del día: una sola consulta.
    final usoPantalla = await _db.obtenerUsoPorFecha(ahora);

    // 4) Aplicaciones: permiso + una sola consulta.
    final permisoUso = await _usoService.tienePermisoUso();
    var apps = <AppUso>[];
    if (permisoUso) {
      try {
        apps = await _usoService.obtenerTopAppsDelDia(top: topApps);
      } catch (_) {
        // Sin datos accesibles en vivo: el contexto queda sin aplicaciones.
        apps = <AppUso>[];
      }
    } else {
      // Sin permiso de UsageStats: se usa lo que ya esté persistido, si existe.
      try {
        apps = await _db.obtenerAppsUsoDelDia(fecha: ahora, top: topApps);
      } catch (_) {
        apps = <AppUso>[];
      }
    }

    return ContextoRecomendacion(
      momento: ahora,
      horarios: horarios,
      horarioActivo: horarioActivo,
      tareaActiva: tareaActiva,
      tareasPendientes: tareasPendientes,
      tareasAltaPrioridadPendientes: tareasAltaPrioridad,
      tiempoTotalPantallaMinutos: usoPantalla?.tiempoTotalMinutos ?? 0,
      hayDatosUsoPantalla: usoPantalla != null,
      permisoUsoDisponible: permisoUso,
      appsMasUtilizadas: apps,
    );
  }
}
