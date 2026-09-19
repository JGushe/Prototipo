import 'package:usage_stats/usage_stats.dart';

import '../models/horario.dart';
import '../models/intervalo_uso.dart';
import '../models/tarea.dart';

/// Analiza el uso real de aplicaciones y cuánto de ese uso ocurre dentro de los
/// horarios y las tareas planificadas por el usuario.
///
/// Es una capa **de análisis**, no de decisión: devuelve el contexto temporal
/// del uso y deja que las reglas del motor decidan si merece una recomendación.
/// No clasifica ninguna aplicación como distractora por su nombre.
///
/// Los métodos `static` que trabajan sobre intervalos son puros (sin plugins ni
/// base de datos), de modo que se pueden probar con escenarios controlados.
class MonitoreoUsoHorariosService {
  // Tipos de evento de Android UsageEvents.
  static const int _activityResumed = 1;
  static const int _activityPaused = 2;

  /// Valores de [Horario.tipo] (se compara por cadena para no acoplar modelos).
  static const String tipoLaboral = 'laboral';
  static const String tipoAcademico = 'academico';

  /// Una sesión más larga que esto se considera anómala (app olvidada en
  /// primer plano, evento PAUSE perdido) y se acota.
  static const Duration duracionMaximaSesion = Duration(hours: 6);

  // ---------------------------------------------------------------------------
  // Adquisición (UsageStatsManager)
  // ---------------------------------------------------------------------------

  /// Obtiene los intervalos de uso reales entre [desde] y [hasta] a partir de
  /// los eventos de UsageStatsManager.
  ///
  /// Precisión real: Android entrega **eventos** (cambios de primer plano), no
  /// un muestreo continuo. La resolución depende de esos eventos y del rango
  /// consultado (los eventos detallados se conservan ~7 días). Las sesiones que
  /// quedan abiertas al cerrar el rango se cierran en [hasta].
  Future<List<IntervaloUso>> obtenerIntervalos({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final eventos = <EventoUso>[];
    try {
      final crudos = await UsageStats.queryEvents(desde, hasta);
      for (final e in crudos) {
        final momento = e.timeStampDate;
        final paquete = e.packageName;
        if (momento == null || paquete == null) continue;
        final tipo = e.eventTypeValue;
        if (tipo != _activityResumed && tipo != _activityPaused) continue;
        eventos.add(EventoUso(
          momento: momento,
          nombrePaquete: paquete,
          esResume: tipo == _activityResumed,
        ));
      }
    } catch (_) {
      // Sin permiso o sin datos: no hay intervalos.
      return const [];
    }

    final intervalos = emparejarEventos(eventos, cierrePorDefecto: hasta);
    return await _resolverNombres(intervalos);
  }

  /// Completa el nombre legible de cada aplicación (una consulta por paquete).
  Future<List<IntervaloUso>> _resolverNombres(List<IntervaloUso> intervalos) async {
    final nombres = <String, String>{};
    final resultado = <IntervaloUso>[];
    for (final intervalo in intervalos) {
      var nombre = nombres[intervalo.nombrePaquete];
      if (nombre == null) {
        try {
          final info = await UsageStats.getAppInfo(intervalo.nombrePaquete);
          nombre = info?.appName ?? intervalo.nombrePaquete;
        } catch (_) {
          nombre = intervalo.nombrePaquete;
        }
        nombres[intervalo.nombrePaquete] = nombre;
      }
      resultado.add(IntervaloUso(
        nombrePaquete: intervalo.nombrePaquete,
        nombreApp: nombre,
        inicio: intervalo.inicio,
        fin: intervalo.fin,
      ));
    }
    return resultado;
  }

  // ---------------------------------------------------------------------------
  // Análisis puro
  // ---------------------------------------------------------------------------

  /// Empareja eventos RESUME → PAUSE en intervalos de uso.
  ///
  /// Si un paquete queda abierto al final y se indica [cierrePorDefecto], la
  /// sesión se cierra en ese momento. [duracionMaxima] acota sesiones anómalas.
  static List<IntervaloUso> emparejarEventos(
    List<EventoUso> eventos, {
    DateTime? cierrePorDefecto,
    Duration duracionMaxima = duracionMaximaSesion,
  }) {
    final ordenados = [...eventos]
      ..sort((a, b) => a.momento.compareTo(b.momento));

    final abiertos = <String, EventoUso>{};
    final resultado = <IntervaloUso>[];

    void cerrar(EventoUso inicio, DateTime fin) {
      if (!fin.isAfter(inicio.momento)) return;
      var duracion = fin.difference(inicio.momento);
      if (duracion > duracionMaxima) duracion = duracionMaxima;
      resultado.add(IntervaloUso(
        nombrePaquete: inicio.nombrePaquete,
        nombreApp: inicio.nombreApp ?? inicio.nombrePaquete,
        inicio: inicio.momento,
        fin: inicio.momento.add(duracion),
      ));
    }

    for (final evento in ordenados) {
      if (evento.esResume) {
        // El RESUME más reciente del paquete es el que abre la sesión.
        abiertos[evento.nombrePaquete] = evento;
      } else {
        final inicio = abiertos.remove(evento.nombrePaquete);
        if (inicio != null) cerrar(inicio, evento.momento);
      }
    }

    if (cierrePorDefecto != null) {
      for (final inicio in abiertos.values) {
        cerrar(inicio, cierrePorDefecto);
      }
    }

    resultado.sort((a, b) => a.inicio.compareTo(b.inicio));
    return resultado;
  }

  /// Ventanas concretas (con fecha) de un horario entre [desde] y [hasta].
  ///
  /// Reutiliza la semántica de [Horario]: `diasSemana` indica el día en que
  /// **empieza** el bloque, `cruzaMedianoche` alarga el fin al día siguiente y
  /// un horario sin duración (`inicio == fin`) no genera ventana.
  static List<VentanaTiempo> ventanasDeHorario(
    Horario horario,
    DateTime desde,
    DateTime hasta,
  ) {
    final ventanas = <VentanaTiempo>[];
    if (!horario.tieneDuracion || horario.diasSemana.isEmpty) return ventanas;

    // Se mira un día antes y un día después para cubrir bloques nocturnos.
    var dia = DateTime(desde.year, desde.month, desde.day)
        .subtract(const Duration(days: 1));
    final limite = DateTime(hasta.year, hasta.month, hasta.day)
        .add(const Duration(days: 1));

    while (!dia.isAfter(limite)) {
      if (horario.diasSemana.contains(dia.weekday)) {
        final inicio = DateTime(dia.year, dia.month, dia.day, horario.horaInicio,
            horario.minutoInicio);
        var fin = DateTime(
            dia.year, dia.month, dia.day, horario.horaFin, horario.minutoFin);
        if (horario.cruzaMedianoche) {
          fin = fin.add(const Duration(days: 1));
        }
        if (fin.isAfter(inicio)) ventanas.add(VentanaTiempo(inicio, fin));
      }
      dia = dia.add(const Duration(days: 1));
    }
    return ventanas;
  }

  /// Tiempo de [intervalo] dentro de [horario] (soporta cruce de medianoche y
  /// uso que atraviesa el inicio o el fin del horario).
  static Duration duracionEnHorario(IntervaloUso intervalo, Horario horario) {
    if (!intervalo.esValido) return Duration.zero;
    final ventanas = ventanasDeHorario(horario, intervalo.inicio, intervalo.fin);
    return _unionDeIntersecciones(intervalo, ventanas);
  }

  /// Tiempo de [intervalo] dentro de la franja planificada de [tarea].
  static Duration duracionEnTarea(IntervaloUso intervalo, Tarea tarea) {
    if (!intervalo.esValido) return Duration.zero;
    final inicio = tarea.inicioPlanificado;
    final fin = tarea.finPlanificado;
    if (inicio == null || fin == null || !fin.isAfter(inicio)) {
      return Duration.zero;
    }
    return _unionDeIntersecciones(intervalo, [VentanaTiempo(inicio, fin)]);
  }

  /// Cruza cada aplicación con los horarios y tareas configurados.
  ///
  /// Devuelve un [UsoContextual] por paquete, ordenado por tiempo dentro de
  /// horarios (descendente) y, a igualdad, por tiempo total.
  static List<UsoContextual> analizar({
    required List<IntervaloUso> intervalos,
    required List<Horario> horarios,
    required List<Tarea> tareas,
  }) {
    final porPaquete = <String, List<IntervaloUso>>{};
    for (final intervalo in intervalos) {
      if (!intervalo.esValido) continue;
      porPaquete.putIfAbsent(intervalo.nombrePaquete, () => []).add(intervalo);
    }

    final resultado = <UsoContextual>[];
    porPaquete.forEach((paquete, lista) {
      var total = Duration.zero;
      var enHorarios = Duration.zero;
      var laboral = Duration.zero;
      var academico = Duration.zero;
      var enTarea = Duration.zero;

      for (final intervalo in lista) {
        total += intervalo.duracion;

        // Unión de todos los horarios: evita contar dos veces si se solapan.
        final ventanas = <VentanaTiempo>[
          for (final horario in horarios)
            ...ventanasDeHorario(horario, intervalo.inicio, intervalo.fin),
        ];
        enHorarios += _unionDeIntersecciones(intervalo, ventanas);

        for (final horario in horarios) {
          final minutos = duracionEnHorario(intervalo, horario);
          if (horario.tipo == tipoLaboral) {
            laboral += minutos;
          } else if (horario.tipo == tipoAcademico) {
            academico += minutos;
          }
        }

        for (final tarea in tareas) {
          enTarea += duracionEnTarea(intervalo, tarea);
        }
      }

      resultado.add(UsoContextual(
        nombrePaquete: paquete,
        nombreApp: lista.first.nombreApp,
        duracionTotal: total,
        enHorariosConfigurados: enHorarios,
        enHorarioLaboral: laboral,
        enHorarioAcademico: academico,
        duranteTareaPlanificada: enTarea,
        intervalos: List.unmodifiable(lista),
      ));
    });

    resultado.sort((a, b) {
      final porHorario =
          b.enHorariosConfigurados.compareTo(a.enHorariosConfigurados);
      if (porHorario != 0) return porHorario;
      return b.duracionTotal.compareTo(a.duracionTotal);
    });
    return resultado;
  }

  /// Suma de las intersecciones de [intervalo] con [ventanas], fusionando
  /// solapes para no contar dos veces el mismo minuto.
  static Duration _unionDeIntersecciones(
    IntervaloUso intervalo,
    List<VentanaTiempo> ventanas,
  ) {
    final tramos = <VentanaTiempo>[];
    for (final ventana in ventanas) {
      final inicio =
          intervalo.inicio.isAfter(ventana.inicio) ? intervalo.inicio : ventana.inicio;
      final fin = intervalo.fin.isBefore(ventana.fin) ? intervalo.fin : ventana.fin;
      if (fin.isAfter(inicio)) tramos.add(VentanaTiempo(inicio, fin));
    }
    if (tramos.isEmpty) return Duration.zero;

    tramos.sort((a, b) => a.inicio.compareTo(b.inicio));
    var total = Duration.zero;
    var actual = tramos.first;
    for (final tramo in tramos.skip(1)) {
      if (!tramo.inicio.isAfter(actual.fin)) {
        if (tramo.fin.isAfter(actual.fin)) {
          actual = VentanaTiempo(actual.inicio, tramo.fin);
        }
      } else {
        total += actual.duracion;
        actual = tramo;
      }
    }
    total += actual.duracion;
    return total;
  }
}
