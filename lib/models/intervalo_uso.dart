/// Evento puntual de uso tal como lo entrega UsageStatsManager.
///
/// Android notifica `ACTIVITY_RESUMED` (1) y `ACTIVITY_PAUSED` (2); emparejarlos
/// permite reconstruir los tramos reales de uso en primer plano.
class EventoUso {
  final DateTime momento;
  final String nombrePaquete;
  final String? nombreApp;

  /// `true` = RESUME (pasa a primer plano), `false` = PAUSE (pasa a segundo).
  final bool esResume;

  const EventoUso({
    required this.momento,
    required this.nombrePaquete,
    this.nombreApp,
    required this.esResume,
  });
}

/// Tramo continuo en el que una aplicación estuvo en primer plano.
///
/// Es la unidad real de análisis: UsageStatsManager no informa de cada segundo,
/// informa de eventos, y de ellos se derivan estos intervalos.
class IntervaloUso {
  final String nombrePaquete;
  final String nombreApp;
  final DateTime inicio;
  final DateTime fin;

  const IntervaloUso({
    required this.nombrePaquete,
    required this.nombreApp,
    required this.inicio,
    required this.fin,
  });

  Duration get duracion => fin.difference(inicio);

  bool get esValido => fin.isAfter(inicio);

  Map<String, dynamic> toMap() => {
        'nombrePaquete': nombrePaquete,
        'nombreApp': nombreApp,
        'inicio': inicio.toIso8601String(),
        'fin': fin.toIso8601String(),
      };

  factory IntervaloUso.fromMap(Map<String, dynamic> map) => IntervaloUso(
        nombrePaquete: map['nombrePaquete'] as String,
        nombreApp: map['nombreApp'] as String,
        inicio: DateTime.parse(map['inicio'] as String),
        fin: DateTime.parse(map['fin'] as String),
      );

  @override
  String toString() =>
      '$nombreApp [$inicio → $fin] = ${duracion.inMinutes} min';
}

/// Ventana temporal concreta (con fecha), derivada de un horario o una tarea.
class VentanaTiempo {
  final DateTime inicio;
  final DateTime fin;

  const VentanaTiempo(this.inicio, this.fin);

  Duration get duracion => fin.difference(inicio);

  @override
  String toString() => '[$inicio → $fin]';
}

/// Uso de una aplicación cruzado con el contexto temporal configurado.
///
/// Conserva **todo** el contexto: no decide si el uso es una distracción, solo
/// informa cuánto de ese uso cayó dentro de cada horario y tarea. La decisión
/// queda para las reglas del motor.
class UsoContextual {
  final String nombrePaquete;
  final String nombreApp;

  /// Tiempo total en primer plano dentro del periodo analizado.
  final Duration duracionTotal;

  /// Tiempo dentro de la unión de todos los horarios configurados.
  final Duration enHorariosConfigurados;

  final Duration enHorarioLaboral;
  final Duration enHorarioAcademico;

  /// Tiempo durante la franja planificada de alguna tarea.
  final Duration duranteTareaPlanificada;

  /// Intervalos que originaron el análisis (evidencia y trazabilidad).
  final List<IntervaloUso> intervalos;

  const UsoContextual({
    required this.nombrePaquete,
    required this.nombreApp,
    required this.duracionTotal,
    required this.enHorariosConfigurados,
    required this.enHorarioLaboral,
    required this.enHorarioAcademico,
    required this.duranteTareaPlanificada,
    this.intervalos = const [],
  });

  /// Tiempo fuera de cualquier horario configurado.
  Duration get fueraDeHorarios {
    final resto = duracionTotal - enHorariosConfigurados;
    return resto.isNegative ? Duration.zero : resto;
  }

  int get minutosTotales => duracionTotal.inMinutes;
  int get minutosEnHorarios => enHorariosConfigurados.inMinutes;
  int get minutosEnTareas => duranteTareaPlanificada.inMinutes;

  /// ¿Se usó durante algún horario configurado?
  bool get tieneUsoEnHorario => enHorariosConfigurados > Duration.zero;

  /// ¿Se usó durante la planificación de una tarea?
  bool get tieneUsoEnTarea => duranteTareaPlanificada > Duration.zero;

  /// Resumen legible, útil para notificaciones y evidencias.
  String descripcion() => '$nombreApp: ${duracionTotal.inMinutes} min en total, '
      '${enHorariosConfigurados.inMinutes} min en horarios '
      '(laboral ${enHorarioLaboral.inMinutes}, académico ${enHorarioAcademico.inMinutes}), '
      '${duranteTareaPlanificada.inMinutes} min en tareas planificadas';

  @override
  String toString() => descripcion();
}
