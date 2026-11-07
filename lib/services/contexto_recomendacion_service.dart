import '../database/database_helper.dart';
import '../models/contexto_recomendacion.dart';
import '../models/horario.dart';
import '../models/intervalo_uso.dart';
import '../models/tarea.dart';
import '../models/uso_pantalla.dart';
import 'analisis_horario_service.dart';
import 'monitoreo_uso_horarios_service.dart';
import 'reglas/configuracion_motor.dart';
import 'uso_pantalla_service.dart';

/// Construye el [ContextoRecomendacion] consultando las fuentes de datos.
///
/// Responsabilidad única: **adquirir y normalizar** el estado del usuario.
/// No aplica reglas de negocio ni genera recomendaciones; eso corresponde al
/// evaluador de reglas y al creador de recomendaciones.
///
/// Para evitar consultas repetidas, cada fuente se lee una sola vez y todo lo
/// demás se deriva en memoria.
class ContextoRecomendacionService {
  final DatabaseHelper _db;
  final UsoPantallaService _usoService;
  final MonitoreoUsoHorariosService _monitoreo;
  final ConfiguracionMotor _config;

  /// Todas las dependencias son inyectables para facilitar pruebas.
  ContextoRecomendacionService({
    DatabaseHelper? db,
    UsoPantallaService? usoService,
    MonitoreoUsoHorariosService? monitoreo,
    ConfiguracionMotor? config,
  })  : _db = db ?? DatabaseHelper.instance,
        _usoService = usoService ?? UsoPantallaService(),
        _monitoreo = monitoreo ?? MonitoreoUsoHorariosService(),
        _config = config ?? ConfiguracionMotor.porDefecto;

  /// Construye el contexto para [momento] (por defecto, ahora).
  ///
  /// [topApps] limita cuántas aplicaciones se piden a la fuente de uso; su valor
  /// por defecto (5) reproduce el comportamiento previo del motor.
  Future<ContextoRecomendacion> construir({
    DateTime? momento,
    int topApps = 5,
  }) =>
      _construir(momento: momento ?? DateTime.now(), topApps: topApps);

  Future<ContextoRecomendacion> construirDesdeMuestra(MuestraUso muestra) =>
      _construir(momento: muestra.momento, topApps: 5, muestra: muestra);

  Future<ContextoRecomendacion> _construir({
    required DateTime momento,
    required int topApps,
    MuestraUso? muestra,
  }) async {
    final ahora = momento;

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

    // 2) Horarios ACTIVOS: una sola consulta. Los desactivados no participan
    //    ni en el contexto ni en las reglas.
    final horarios = await _db.obtenerHorarios(soloActivos: true);
    Horario? horarioActivo;
    for (final horario in ordenarPorPrecedencia(horarios)) {
      if (horario.contieneDateTime(ahora)) {
        horarioActivo = horario;
        break;
      }
    }

    final permisoUso = muestra != null || await _usoService.tienePermisoUso();
    final apps = muestra?.apps.take(topApps).toList() ??
        await _topApps(
          permisoUso,
          topApps,
        );
    final inicioDia = DateTime(ahora.year, ahora.month, ahora.day);
    final inicioAnalisis = ahora.subtract(Duration(days: _config.diasAnalisis));
    final ventanaAnalisis = VentanaTiempo(inicioAnalisis, ahora);
    TrazaUso? traza;
    if (permisoUso) {
      try {
        traza = await _monitoreo.obtenerTraza(
          desde:
              inicioAnalisis.isBefore(inicioDia) ? inicioAnalisis : inicioDia,
          hasta: ahora,
        );
      } catch (_) {
        // Las reglas temporales necesitan evidencia, no un resumen anterior.
      }
    }

    final minutosPantalla = muestra?.resumen.tiempoTotalMinutos ??
        traza?.minutosUnicos(VentanaTiempo(inicioDia, ahora));
    final intervalos = traza?.intervalos ?? [];
    final horas =
        AnalisisHorarioService.repartirPorHora(intervalos, ventanaAnalisis);
    final minutosNocturno = AnalisisHorarioService.repartirPorHora(
      traza?.interactivos ?? [],
      ventanaAnalisis,
    ).minutosEntre(_config.horaInicioNocturno, _config.horaFinNocturno);

    final nombres = {
      for (final app in muestra?.apps ?? apps) app.nombrePaquete: app.nombreApp
    };
    List<IntervaloUso> conNombres(List<IntervaloUso> tramos) => [
          for (final tramo in tramos)
            IntervaloUso(
              nombrePaquete: tramo.nombrePaquete,
              nombreApp: nombres[tramo.nombrePaquete] ?? tramo.nombreApp,
              inicio: tramo.inicio,
              fin: tramo.fin,
            ),
        ];
    final usosContextuales = MonitoreoUsoHorariosService.analizar(
      intervalos: conNombres(traza?.en(VentanaTiempo(inicioDia, ahora)) ?? []),
      horarios: horarios,
      tareas: tareasPendientes,
    );
    final usosBloqueActivo = <UsoContextual>[];
    if (traza != null && horarioActivo != null) {
      for (final bloque in MonitoreoUsoHorariosService.ventanasDeHorario(
        horarioActivo,
        ahora,
        ahora,
      )) {
        if (ahora.isBefore(bloque.inicio) || !ahora.isBefore(bloque.fin)) {
          continue;
        }
        usosBloqueActivo.addAll(MonitoreoUsoHorariosService.analizar(
          intervalos: conNombres(traza.en(VentanaTiempo(bloque.inicio, ahora))),
          horarios: [horarioActivo],
          tareas: const [],
        ));
      }
    }

    final inicioTarea = tareaActiva?.inicioPlanificado;
    final minutosDistractoresTareaActiva = inicioTarea == null || traza == null
        ? 0
        : VentanaTiempo.duracionUnica([
            for (final tramo in traza.en(VentanaTiempo(inicioTarea, ahora)))
              if (ContextoRecomendacion.clasificarDistractor(
                tramo.nombrePaquete,
                _config.paquetesDistractores,
              ))
                tramo.ventana,
          ]).inMinutes;

    return ContextoRecomendacion(
      momento: ahora,
      horarios: horarios,
      horarioActivo: horarioActivo,
      tareaActiva: tareaActiva,
      tareasPendientes: tareasPendientes,
      tareasAltaPrioridadPendientes: tareasAltaPrioridad,
      tiempoTotalPantallaMinutos: minutosPantalla ?? 0,
      hayDatosUsoPantalla: minutosPantalla != null,
      permisoUsoDisponible: permisoUso,
      appsMasUtilizadas: apps,
      usoPorHora: horas.minutos,
      momentosPorHora: horas.momentoRepresentativo,
      minutosUsoNocturno: minutosNocturno,
      usosContextuales: usosContextuales,
      usosBloqueActivo: usosBloqueActivo,
      minutosDistractoresTareaActiva: minutosDistractoresTareaActiva,
      paquetesDistractores: _config.paquetesDistractores,
    );
  }

  /// Ordena los horarios por precedencia para elegir [horarioActivo] cuando
  /// varios se solapan:
  ///
  /// 1. primero las categorías laboral y académico (las que alimentan R1/R2),
  /// 2. luego por hora de inicio más temprana,
  /// 3. y por último por `id`, para que el resultado sea determinista.
  static List<Horario> ordenarPorPrecedencia(List<Horario> horarios) {
    final copia = [...horarios];
    copia.sort((a, b) {
      final pesoA = _pesoPrecedencia(a.tipo);
      final pesoB = _pesoPrecedencia(b.tipo);
      if (pesoA != pesoB) return pesoA.compareTo(pesoB);
      final porInicio = a.minutosInicio.compareTo(b.minutosInicio);
      if (porInicio != 0) return porInicio;
      return (a.id ?? 0).compareTo(b.id ?? 0);
    });
    return copia;
  }

  static int _pesoPrecedencia(String tipo) =>
      (tipo == Horario.tipoLaboral || tipo == Horario.tipoAcademico) ? 0 : 1;

  Future<List<AppUso>> _topApps(bool permisoUso, int topApps) async {
    if (!permisoUso) return [];
    try {
      return await _usoService.obtenerTopAppsDelDia(top: topApps);
    } catch (_) {
      return [];
    }
  }
}
