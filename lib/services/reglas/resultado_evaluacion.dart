import '../../models/contexto_recomendacion.dart';
import '../../models/recomendacion.dart';
import 'politica_cooldown.dart';

/// Estado de una regla tras una ejecución del motor.
enum ResultadoReglaEjecucion {
  /// La recomendación se generó y se almacenó.
  generada,

  /// Se cumplió pero se descartó por cooldown.
  descartadaPorCooldown,

  /// Sus condiciones no se cumplieron.
  noAplicable,
}

/// Detalle de la evaluación de una regla concreta: permite inspeccionar en
/// desarrollo qué regla se activó, cuál se descartó y por qué.
class EvaluacionRegla {
  final String reglaId;
  final String nombre;
  final int prioridad;
  final bool aplica;

  /// Condiciones cumplidas, con sus datos concretos.
  final List<String> explicaciones;

  /// Condiciones que fallaron (descripciones cortas).
  final List<String> condicionesFallidas;

  /// Qué pasó con la regla en esta ejecución.
  final ResultadoReglaEjecucion resultado;

  /// Motivo del descarte, si [resultado] es [ResultadoReglaEjecucion.descartadaPorCooldown].
  final String? motivoDescarte;

  const EvaluacionRegla({
    required this.reglaId,
    required this.nombre,
    required this.prioridad,
    required this.aplica,
    this.explicaciones = const [],
    this.condicionesFallidas = const [],
    this.resultado = ResultadoReglaEjecucion.noAplicable,
    this.motivoDescarte,
  });
}

/// Resultado completo de una ejecución del motor.
///
/// Separa lo que se generó de lo que se descartó por cooldown y conserva el
/// contexto y el detalle de cada regla, de modo que el comportamiento del motor
/// sea observable, verificable y documentable como evidencia de evaluación.
class ResultadoEvaluacion {
  /// Contexto sobre el que se decidió.
  final ContextoRecomendacion contexto;

  /// Evaluación de **todas** las reglas registradas, en orden de prioridad.
  final List<EvaluacionRegla> evaluaciones;

  /// Recomendaciones nuevas, ordenadas por prioridad de su regla.
  final List<Recomendacion> generadas;

  /// Recomendaciones descartadas por ser duplicados dentro de su cooldown.
  final List<DescarteCooldown> descartadas;

  /// Reglas que se cumplieron y, por tanto, se intentaron generar.
  final int reglasEvaluadas;

  const ResultadoEvaluacion({
    required this.contexto,
    required this.evaluaciones,
    required this.generadas,
    required this.descartadas,
    required this.reglasEvaluadas,
  });

  bool get huboDescartes => descartadas.isNotEmpty;

  /// Identificadores de las reglas cuyas condiciones se cumplieron.
  List<String> get reglasActivadas => evaluaciones
      .where((e) => e.aplica)
      .map((e) => e.reglaId)
      .toList();

  /// Identificadores de las reglas descartadas por cooldown.
  List<String> get reglasDescartadas => evaluaciones
      .where((e) => e.resultado == ResultadoReglaEjecucion.descartadaPorCooldown)
      .map((e) => e.reglaId)
      .toList();

  /// Resumen legible de la ejecución, útil para logs de desarrollo y para
  /// documentar la evaluación del prototipo.
  String resumen() {
    final buffer = StringBuffer()
      ..writeln('=== Ejecución del motor (${contexto.momento.toIso8601String()}) ===')
      ..writeln('Contexto: tipoHorario=${contexto.tipoHorario}'
          ' tareaActiva=${contexto.hayTareaActiva ? contexto.tareaActiva!.titulo : 'ninguna'}'
          ' tareasPendientes=${contexto.tareasPendientesTotal}'
          ' pantalla=${contexto.tiempoTotalPantallaMinutos}min'
          ' distractor=${contexto.minutosAppsDistractoras}min'
          ' nocturno=${contexto.minutosUsoNocturno}min'
          ' permisoUso=${contexto.permisoUsoDisponible}');

    for (final evaluacion in evaluaciones) {
      if (evaluacion.resultado == ResultadoReglaEjecucion.generada) {
        buffer.writeln(
            '  [OK] ${evaluacion.reglaId} ${evaluacion.nombre} -> generada');
        for (final motivo in evaluacion.explicaciones) {
          buffer.writeln('       - $motivo');
        }
      } else if (evaluacion.resultado ==
          ResultadoReglaEjecucion.descartadaPorCooldown) {
        buffer.writeln(
            '  [COOLDOWN] ${evaluacion.reglaId} ${evaluacion.nombre} -> '
            '${evaluacion.motivoDescarte ?? 'descartada'}');
      } else {
        buffer.writeln(
            '  [--] ${evaluacion.reglaId} ${evaluacion.nombre} -> no aplica '
            '(falla: ${evaluacion.condicionesFallidas.join(', ')})');
      }
    }

    buffer.writeln(
        'Total: reglas cumplidas=$reglasEvaluadas, '
        'generadas=${generadas.length}, descartadas=${descartadas.length}');
    return buffer.toString();
  }

  @override
  String toString() =>
      'ResultadoEvaluacion(reglas=$reglasEvaluadas, '
      'generadas=${generadas.length}, descartadas=${descartadas.length})';
}
