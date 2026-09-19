import '../../models/contexto_recomendacion.dart';
import '../../models/recomendacion.dart';
import 'evaluador_reglas.dart';

/// Convierte resultados de reglas en [Recomendacion] persistibles.
///
/// Responsabilidad única: **materializar la decisión**. No adquiere datos ni
/// evalúa condiciones. Deja traza de qué regla la generó ([Recomendacion.reglaId]),
/// por qué ([Recomendacion.motivo]) y su clave de equivalencia
/// ([Recomendacion.clave]) para el control de duplicados.
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
      clave: regla.claveEquivalencia(contexto),
    );
  }

  List<Recomendacion> crearTodos(
    List<ResultadoRegla> resultados,
    ContextoRecomendacion contexto,
  ) =>
      resultados.map((r) => crear(r, contexto)).toList();
}
