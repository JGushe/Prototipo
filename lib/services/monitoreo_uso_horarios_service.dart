import 'package:usage_stats/usage_stats.dart';

import '../models/horario.dart';
import '../models/intervalo_uso.dart';
import '../models/tarea.dart';

class TrazaUso {
  final List<IntervaloUso> intervalos;
  final List<IntervaloUso> interactivos;
  final List<EventoUso> eventos;

  const TrazaUso(this.intervalos, this.interactivos, this.eventos);

  List<IntervaloUso> en(VentanaTiempo ventana) => [
        for (final intervalo in intervalos)
          if (intervalo.ventana.interseccion(ventana) case final tramo?)
            intervalo.conVentana(tramo),
      ];

  int? minutosUnicos(VentanaTiempo ventana) {
    final tramos = en(ventana);
    if (tramos.isEmpty) return null;
    return VentanaTiempo.duracionUnica(tramos.map((i) => i.ventana)).inMinutes;
  }

  int desbloqueosEn(VentanaTiempo ventana) => eventos
      .where((e) =>
          e.tipo == TipoEventoUso.desbloqueo &&
          !e.momento.isBefore(ventana.inicio) &&
          e.momento.isBefore(ventana.fin))
      .map((e) => e.momento)
      .toSet()
      .length;
}

class _SesionAbierta {
  final EventoUso inicio;
  DateTime? desdeInteractivo;
  DateTime? limite;

  _SesionAbierta(this.inicio, this.desdeInteractivo);
}

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
  /// Valores de [Horario.tipo] (se compara por cadena para no acoplar modelos).
  static const String tipoLaboral = 'laboral';
  static const String tipoAcademico = 'academico';

  /// Descarta pares anómalos que exceden este límite, incluso al recortarlos.
  static const duracionMaximaSesion = Duration(hours: 6);

  /// Lee antes de la ventana para reconstruir sesiones que cruzan su inicio.
  Future<TrazaUso> obtenerTraza({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final crudos = await UsageStats.queryEvents(
      desde.subtract(duracionMaximaSesion),
      hasta,
    );
    final eventos = <EventoUso>[];
    for (final crudo in crudos) {
      final momento = crudo.timeStampDate;
      if (momento == null || momento.isAfter(hasta)) continue;
      final tipo = crudo.eventTypeValue;
      if (tipo == 1 || tipo == 2 || tipo == 23) {
        final paquete = crudo.packageName;
        if (paquete == null || paquete.isEmpty) continue;
        eventos.add(EventoUso(
          momento: momento,
          nombrePaquete: paquete,
          clase: crudo.className,
          esResume: tipo == 1,
        ));
      } else {
        final estado = switch (tipo) {
          15 => TipoEventoUso.pantallaInteractiva,
          16 => TipoEventoUso.pantallaInactiva,
          17 => TipoEventoUso.bloqueo,
          18 => TipoEventoUso.desbloqueo,
          26 || 27 => TipoEventoUso.reinicio,
          _ => null,
        };
        if (estado != null) eventos.add(EventoUso.sistema(momento, estado));
      }
    }
    return reconstruir(eventos);
  }

  /// Solo acredita pares de la misma actividad. Un cambio a otra app no
  /// cierra la anterior, porque Android admite multiventana.
  static TrazaUso reconstruir(
    List<EventoUso> eventos, {
    Duration duracionMaxima = duracionMaximaSesion,
  }) {
    // Índice explícito para respetar el orden original en empates.
    final ordenados = eventos.indexed.toList()
      ..sort((a, b) {
        final porInstante = a.$2.momento.compareTo(b.$2.momento);
        return porInstante == 0 ? a.$1.compareTo(b.$1) : porInstante;
      });
    final abiertas = <(String, String?), _SesionAbierta>{};
    final intervalos = <IntervaloUso>[];
    final interactivos = <IntervaloUso>[];
    bool? pantallaInteractiva;
    var bloqueada = false;

    for (final (_, evento) in ordenados) {
      final momento = evento.momento;
      final clave = (evento.nombrePaquete, evento.clase);
      switch (evento.tipo) {
        case TipoEventoUso.resume:
          // Un nuevo RESUME sustituye un inicio sin cierre acreditado.
          abiertas.remove(clave);
          if (!bloqueada && pantallaInteractiva != false) {
            abiertas[clave] = _SesionAbierta(
              evento,
              pantallaInteractiva == true ? momento : null,
            );
          }
        case TipoEventoUso.pause:
          final sesion = abiertas.remove(clave);
          if (sesion == null) continue;
          final inicio = sesion.inicio.momento;
          final fin = sesion.limite ?? momento;
          if (!fin.isAfter(inicio) || fin.difference(inicio) > duracionMaxima) {
            continue;
          }
          final intervalo = IntervaloUso(
            nombrePaquete: evento.nombrePaquete,
            nombreApp: sesion.inicio.nombreApp ?? evento.nombrePaquete,
            inicio: inicio,
            fin: fin,
          );
          intervalos.add(intervalo);
          final desdeInteractivo = sesion.desdeInteractivo;
          if (desdeInteractivo != null && fin.isAfter(desdeInteractivo)) {
            interactivos.add(
                intervalo.conVentana(VentanaTiempo(desdeInteractivo, fin)));
          }
        case TipoEventoUso.pantallaInteractiva:
          pantallaInteractiva = true;
          if (!bloqueada) {
            for (final sesion in abiertas.values) {
              if (sesion.limite == null) sesion.desdeInteractivo ??= momento;
            }
          }
        case TipoEventoUso.pantallaInactiva:
        case TipoEventoUso.bloqueo:
          if (evento.tipo == TipoEventoUso.bloqueo) {
            bloqueada = true;
          } else {
            pantallaInteractiva = false;
          }
          for (final sesion in abiertas.values) {
            sesion.limite ??= momento;
          }
        case TipoEventoUso.desbloqueo:
          bloqueada = false;
        case TipoEventoUso.reinicio:
          abiertas.clear();
          pantallaInteractiva = null;
          bloqueada = false;
      }
    }
    return TrazaUso(intervalos, interactivos, eventos);
  }

  static List<IntervaloUso> emparejarEventos(
    List<EventoUso> eventos, {
    Duration duracionMaxima = duracionMaximaSesion,
  }) =>
      reconstruir(eventos, duracionMaxima: duracionMaxima).intervalos;

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
    var dia = DateTime(desde.year, desde.month, desde.day - 1);
    final limite = DateTime(hasta.year, hasta.month, hasta.day + 1);

    while (!dia.isAfter(limite)) {
      if (horario.diasSemana.contains(dia.weekday)) {
        final inicio = DateTime(dia.year, dia.month, dia.day,
            horario.horaInicio, horario.minutoInicio);
        var fin = DateTime(
            dia.year, dia.month, dia.day, horario.horaFin, horario.minutoFin);
        if (horario.cruzaMedianoche) {
          fin = DateTime(dia.year, dia.month, dia.day + 1, horario.horaFin,
              horario.minutoFin);
        }
        if (fin.isAfter(inicio)) ventanas.add(VentanaTiempo(inicio, fin));
      }
      dia = DateTime(dia.year, dia.month, dia.day + 1);
    }
    return ventanas;
  }

  /// Tiempo de [intervalo] dentro de [horario] (soporta cruce de medianoche y
  /// uso que atraviesa el inicio o el fin del horario).
  static Duration duracionEnHorario(IntervaloUso intervalo, Horario horario) {
    if (!intervalo.esValido) return Duration.zero;
    final ventanas =
        ventanasDeHorario(horario, intervalo.inicio, intervalo.fin);
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

      final ventanasTareas = <VentanaTiempo>[
        for (final tarea in tareas)
          if (tarea.inicioPlanificado != null && tarea.finPlanificado != null)
            VentanaTiempo(tarea.inicioPlanificado!, tarea.finPlanificado!),
      ];
      for (final ventana in VentanaTiempo.unir(lista.map((i) => i.ventana))) {
        final intervalo = lista.first.conVentana(ventana);
        total += intervalo.duracion;
        final porTipo = <String, List<VentanaTiempo>>{};
        for (final horario in horarios) {
          porTipo.putIfAbsent(horario.tipo, () => []).addAll(
              ventanasDeHorario(horario, intervalo.inicio, intervalo.fin));
        }
        enHorarios += _unionDeIntersecciones(
          intervalo,
          porTipo.values.expand((tramos) => tramos),
        );
        laboral +=
            _unionDeIntersecciones(intervalo, porTipo[tipoLaboral] ?? []);
        academico +=
            _unionDeIntersecciones(intervalo, porTipo[tipoAcademico] ?? []);
        enTarea += _unionDeIntersecciones(intervalo, ventanasTareas);
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
    Iterable<VentanaTiempo> ventanas,
  ) =>
      VentanaTiempo.duracionUnica([
        for (final ventana in ventanas)
          if (intervalo.ventana.interseccion(ventana) case final tramo?) tramo,
      ]);
}
