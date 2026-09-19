import '../../models/contexto_recomendacion.dart';
import 'regla_recomendacion.dart';

/// Resultado de evaluar una regla que se cumple: la regla y sus explicaciones.
class ResultadoRegla {
  final ReglaRecomendacion regla;

  /// Condiciones cumplidas, con sus datos concretos.
  final List<String> explicaciones;

  ResultadoRegla(this.regla, this.explicaciones);

  /// Explicación completa de por qué se generó la recomendación.
  String get motivo =>
      'Regla ${regla.id} (${regla.nombre}): ${explicaciones.join('; ')}';
}

/// Evalúa un conjunto de reglas sobre un contexto ya construido.
///
/// Responsabilidad única: **decidir qué reglas aplican**. No adquiere datos ni
/// construye recomendaciones.
class EvaluadorReglas {
  final List<ReglaRecomendacion> reglas;

  const EvaluadorReglas(this.reglas);

  /// Reglas cuyas condiciones se cumplen, ordenadas por prioridad descendente.
  List<ResultadoRegla> evaluar(ContextoRecomendacion contexto) {
    final resultados = <ResultadoRegla>[];
    for (final regla in reglas) {
      if (!regla.seCumple(contexto)) continue;
      resultados.add(ResultadoRegla(regla, regla.explicaciones(contexto)));
    }
    resultados.sort((a, b) => b.regla.prioridad.compareTo(a.regla.prioridad));
    return resultados;
  }

  /// Identificadores de las reglas que se cumplen, en orden de prioridad.
  List<String> idsQueAplican(ContextoRecomendacion contexto) =>
      evaluar(contexto).map((r) => r.regla.id).toList();
}
