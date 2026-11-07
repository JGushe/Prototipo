/// Comparación del uso de pantalla entre hoy y ayer con la misma hora de corte.
///
/// Los resúmenes diarios (`uso_pantalla`) no guardan la hora de captura, así
/// que no permiten igualar el corte. La comparación se reconstruye con eventos
/// de UsageStats y se entrega recortada a la misma hora en ambos días.
enum EstadoComparacionDiaria { disponible, insuficiente }

enum MotivoComparacion { sinPermiso, sinDatos, error }

class ComparacionDiaria {
  /// Umbral de presentación para "sin cambio significativo".
  static const double umbralMinutos = 5;

  final DateTime diaHoy;
  final DateTime diaAyer;

  /// Instante de corte aplicado a ambos días, o null si no se pudo reconstruir.
  final DateTime? corte;

  /// Minutos hasta el corte, o null si no hay datos.
  final int? minutosHoy;
  final int? minutosAyer;

  /// Minutos en paquetes distractores hasta el corte, o null sin datos.
  final int? distractorHoy;
  final int? distractorAyer;
  final int? desbloqueosHoy;

  /// hoy - ayer. Null si falta algún lado.
  final int? diferenciaMinutos;

  /// Variación porcentual redondeada a un decimal; null si ayer es 0 o falta.
  final double? porcentaje;

  final EstadoComparacionDiaria estado;
  final String explicacion;
  final MotivoComparacion? motivo;

  const ComparacionDiaria._({
    required this.diaHoy,
    required this.diaAyer,
    required this.corte,
    required this.minutosHoy,
    required this.minutosAyer,
    required this.distractorHoy,
    required this.distractorAyer,
    this.desbloqueosHoy,
    required this.diferenciaMinutos,
    required this.porcentaje,
    required this.estado,
    required this.explicacion,
    this.motivo,
  });

  factory ComparacionDiaria.insuficiente({
    required DateTime ahora,
    required String explicacion,
    DateTime? corte,
    int? minutosHoy,
    int? minutosAyer,
    int? distractorHoy,
    int? distractorAyer,
    int? desbloqueosHoy,
    MotivoComparacion motivo = MotivoComparacion.sinDatos,
  }) {
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    return ComparacionDiaria._(
      diaHoy: hoy,
      diaAyer: DateTime(hoy.year, hoy.month, hoy.day - 1),
      corte: corte,
      minutosHoy: minutosHoy,
      minutosAyer: minutosAyer,
      distractorHoy: distractorHoy,
      distractorAyer: distractorAyer,
      desbloqueosHoy: desbloqueosHoy,
      diferenciaMinutos: null,
      porcentaje: null,
      estado: EstadoComparacionDiaria.insuficiente,
      explicacion: explicacion,
      motivo: motivo,
    );
  }

  factory ComparacionDiaria.calcular({
    required DateTime ahora,
    required int minutosHoy,
    required int minutosAyer,
    required int? distractorHoy,
    required int? distractorAyer,
    required DateTime corte,
    int? desbloqueosHoy,
  }) {
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final diferencia = minutosHoy - minutosAyer;
    return ComparacionDiaria._(
      diaHoy: hoy,
      diaAyer: DateTime(hoy.year, hoy.month, hoy.day - 1),
      corte: corte,
      minutosHoy: minutosHoy,
      minutosAyer: minutosAyer,
      distractorHoy: distractorHoy,
      distractorAyer: distractorAyer,
      desbloqueosHoy: desbloqueosHoy,
      diferenciaMinutos: diferencia,
      // División por cero: sin porcentaje cuando ayer no tuvo uso.
      porcentaje: minutosAyer == 0
          ? null
          : (diferencia / minutosAyer * 1000).round() / 10,
      estado: EstadoComparacionDiaria.disponible,
      explicacion: 'Comparación de ambos días hasta las '
          '${corte.hour.toString().padLeft(2, '0')}:'
          '${corte.minute.toString().padLeft(2, '0')}.',
    );
  }
}

extension TipsComparacionDiaria on ComparacionDiaria {
  /// Diferencia de minutos distractor (hoy - ayer), o null si falta un lado.
  int? get diferenciaDistractor {
    final hoy = distractorHoy;
    final ayer = distractorAyer;
    return (hoy == null || ayer == null) ? null : hoy - ayer;
  }

  /// Mensaje diario para Tips. Usa distractor si existe; si no, total de
  /// pantalla con etiqueta descriptiva. Nunca afirma productividad.
  String get mensajeTips {
    if (estado == EstadoComparacionDiaria.insuficiente) {
      return 'Datos insuficientes para comparar hoy con ayer.';
    }
    final diferenciaDistractor = this.diferenciaDistractor;
    if (diferenciaDistractor != null) {
      final hoy = distractorHoy!;
      final ayer = distractorAyer!;
      if (diferenciaDistractor.abs() < ComparacionDiaria.umbralMinutos) {
        return 'Tu uso distractor hoy ($hoy min) es similar al de ayer '
            '($ayer min) a la misma hora.';
      }
      if (diferenciaDistractor < 0) {
        return 'Hoy registraste ${-diferenciaDistractor} minutos menos de uso '
            'distractor que ayer a la misma hora '
            '($hoy min hoy · $ayer min ayer).';
      }
      return 'Hoy llevas $diferenciaDistractor minutos más de uso distractor '
          'que ayer a la misma hora ($hoy min hoy · $ayer min ayer).';
    }

    final diferencia = diferenciaMinutos!;
    if (diferencia.abs() < ComparacionDiaria.umbralMinutos) {
      return 'Tu uso de pantalla hoy es similar al de ayer a la misma hora.';
    }
    if (diferencia < 0) {
      return 'Hoy llevas ${-diferencia} minutos menos de uso de pantalla que '
          'ayer a la misma hora '
          '(indicador descriptivo, no distractor).';
    }
    return 'Hoy llevas $diferencia minutos más de uso de pantalla que ayer '
        'a la misma hora (indicador descriptivo, no distractor).';
  }

  /// Acción breve y voluntaria para el mensaje diario.
  String get accionTips {
    if (estado == EstadoComparacionDiaria.insuficiente) {
      return 'Vuelve a actualizar el uso cuando haya más datos.';
    }
    final diferenciaDistractor = this.diferenciaDistractor;
    if (diferenciaDistractor == null) {
      return 'Actualiza el uso desde el Dashboard para afinar la comparación.';
    }
    if (diferenciaDistractor < -ComparacionDiaria.umbralMinutos) {
      return 'Mantén el bloque que te funcionó hoy.';
    }
    if (diferenciaDistractor > ComparacionDiaria.umbralMinutos) {
      return 'Revisa si las distracciones se concentran en un horario.';
    }
    return 'Prueba un bloque de concentración de 25 minutos.';
  }
}
