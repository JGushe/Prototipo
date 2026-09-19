import '../../models/contexto_recomendacion.dart';
import '../../models/recomendacion.dart';
import 'regla_recomendacion.dart';

/// Motivo por el que una recomendación se descartó por cooldown.
class DescarteCooldown {
  final String reglaId;
  final String clave;

  /// Fecha de la recomendación equivalente que ya existía.
  final DateTime fechaExistente;

  /// Inicio de la ventana de cooldown evaluada.
  final DateTime inicioVentana;

  const DescarteCooldown({
    required this.reglaId,
    required this.clave,
    required this.fechaExistente,
    required this.inicioVentana,
  });

  String get motivo =>
      'Regla $reglaId descartada: ya existe una recomendación equivalente '
      '(clave "$clave") del ${fechaExistente.toIso8601String()}, dentro de la '
      'ventana iniciada el ${inicioVentana.toIso8601String()}';

  @override
  String toString() => motivo;
}

/// Decide si una recomendación es un duplicado de otra ya generada.
///
/// Es una pieza **pura**: recibe el historial ya cargado y no accede a la base
/// de datos, de modo que su comportamiento es determinista y verificable.
///
/// Dos recomendaciones se consideran equivalentes cuando comparten
/// [ReglaRecomendacion.claveEquivalencia] y la existente está dentro de
/// [ReglaRecomendacion.inicioVentanaCooldown].
class PoliticaCooldown {
  const PoliticaCooldown();

  /// Devuelve el descarte correspondiente si [regla] ya generó una
  /// recomendación equivalente sobre [contexto] dentro de su ventana; en caso
  /// contrario devuelve null y la recomendación debe generarse.
  DescarteCooldown? evaluar({
    required ReglaRecomendacion regla,
    required ContextoRecomendacion contexto,
    required Iterable<Recomendacion> historial,
  }) {
    final clave = regla.claveEquivalencia(contexto);
    final inicioVentana = regla.inicioVentanaCooldown(contexto);

    Recomendacion? equivalente;
    for (final recomendacion in historial) {
      // Las recomendaciones anteriores al control de cooldown tienen clave nula
      // y se conservan como historial, pero no bloquean a las nuevas.
      if (recomendacion.clave != clave) continue;
      if (recomendacion.fecha.isBefore(inicioVentana)) continue;
      if (equivalente == null || recomendacion.fecha.isAfter(equivalente.fecha)) {
        equivalente = recomendacion;
      }
    }

    if (equivalente == null) return null;
    return DescarteCooldown(
      reglaId: regla.id,
      clave: clave,
      fechaExistente: equivalente.fecha,
      inicioVentana: inicioVentana,
    );
  }
}
