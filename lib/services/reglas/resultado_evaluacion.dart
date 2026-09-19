import '../../models/recomendacion.dart';
import 'politica_cooldown.dart';

/// Resultado de una ejecución del motor.
///
/// Separa lo que se generó de lo que se descartó por cooldown, de modo que el
/// comportamiento del motor sea observable y verificable.
class ResultadoEvaluacion {
  /// Recomendaciones nuevas, ordenadas por prioridad de su regla.
  final List<Recomendacion> generadas;

  /// Recomendaciones descartadas por ser duplicados dentro de su cooldown.
  final List<DescarteCooldown> descartadas;

  /// Reglas que se cumplieron y, por tanto, se intentaron generar.
  final int reglasEvaluadas;

  const ResultadoEvaluacion({
    required this.generadas,
    required this.descartadas,
    required this.reglasEvaluadas,
  });

  bool get huboDescartes => descartadas.isNotEmpty;

  @override
  String toString() =>
      'ResultadoEvaluacion(reglas=$reglasEvaluadas, '
      'generadas=${generadas.length}, descartadas=${descartadas.length})';
}
