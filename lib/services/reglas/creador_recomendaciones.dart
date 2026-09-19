import '../../models/contexto_recomendacion.dart';
import '../../models/recomendacion.dart';
import 'evaluador_reglas.dart';

/// Convierte resultados de reglas en [Recomendacion] persistibles.
///
/// Responsabilidad única: **materializar la decisión**. No adquiere datos ni
/// evalúa condiciones. Deja traza de qué regla la generó ([Recomendacion.reglaId])
/// y por qué ([Recomendacion.motivo]).
class CreadorRecomendaciones {
  const CreadorRecomendaciones();

  Recomendacion crear(ResultadoRegla resultado, ContextoRecomendacion contexto) {
    final regla = resultado.regla;
    return Recomendacion(
      fecha: contexto.momento,
      tipo: regla.tipo,
      titulo: regla.titulo(contexto),
      mensaje: regla.mensaje(contexto),
      reglaId: regla.id,
      severidad: regla.severidad.name,
      motivo: resultado.motivo,
    );
  }

  List<Recomendacion> crearTodos(
    List<ResultadoRegla> resultados,
    ContextoRecomendacion contexto,
  ) =>
      resultados.map((r) => crear(r, contexto)).toList();
}
