import 'uso_pantalla.dart';

/// Dirección del cambio con una tolerancia definida.
enum TendenciaEvolucion {
  reduccion,
  aumento,
  estable,
  sinDatos,
}

/// Estado de la comparación entre dos periodos de siete días.
enum EstadoEvolucion {
  /// Ambos periodos tienen los siete días y el periodo anterior tiene minutos.
  disponible,

  /// Falta al menos un día en alguno de los periodos: no se compara.
  insuficiente,

  /// Cobertura completa, pero el promedio anterior de pantalla es 0: hay
  /// diferencia absoluta y no hay porcentaje.
  noComparable,
}

/// Cobertura y promedios de un periodo de días completos.
///
/// Los promedios se calculan solo con días con registro: un día sin fila no
/// cuenta como 0 minutos, se descuenta del denominador.
class ResumenPeriodo {
  final DateTime desde;
  final DateTime hasta;
  final int diasEsperados;
  final int diasValidos;
  final double? promedioMinutosPantalla;
  final double? promedioDesbloqueos;

  const ResumenPeriodo({
    required this.desde,
    required this.hasta,
    required this.diasEsperados,
    required this.diasValidos,
    required this.promedioMinutosPantalla,
    required this.promedioDesbloqueos,
  });

  bool get coberturaCompleta => diasValidos == diasEsperados;
}

/// Comparación de los últimos siete días completos con los siete anteriores.
///
/// Excluye el día actual (parcial). Las métricas salen de `uso_pantalla`, que
/// es lo único persistido por día. La distracción **durante horarios** no se
/// incluye: los eventos de Android solo se conservan ~7 días y no hay historial
/// de horarios por fecha, así que no es reconstruible sin inventar datos.
class EvolucionSemanal {
  static const int diasVentana = 7;

  /// Diferencia de minutos/día por debajo de la cual no se habla de cambio.
  static const double umbralEstableMinutos = 5;

  final EstadoEvolucion estado;
  final String explicacion;
  final ResumenPeriodo reciente;
  final ResumenPeriodo anterior;

  /// El periodo anterior es línea base solo si tiene siete días completos y
  /// ninguna recomendación se generó antes de su fin.
  final bool esLineaBase;

  final double? diferenciaMinutos;
  final double? porcentajeMinutos;
  final double? diferenciaDesbloqueos;
  final double? porcentajeDesbloqueos;

  const EvolucionSemanal._({
    required this.estado,
    required this.explicacion,
    required this.reciente,
    required this.anterior,
    required this.esLineaBase,
    required this.diferenciaMinutos,
    required this.porcentajeMinutos,
    required this.diferenciaDesbloqueos,
    required this.porcentajeDesbloqueos,
  });

  /// Etiqueta correcta del periodo anterior: nunca "preintervención" si hubo
  /// recomendaciones antes de su fin.
  String get etiquetaAnterior =>
      esLineaBase ? 'línea base' : 'periodo anterior';

  /// Dirección del cambio con la tolerancia [umbralEstableMinutos].
  TendenciaEvolucion get tendencia {
    final diferencia = diferenciaMinutos;
    if (diferencia == null) return TendenciaEvolucion.sinDatos;
    if (diferencia.abs() < umbralEstableMinutos) {
      return TendenciaEvolucion.estable;
    }
    return diferencia < 0
        ? TendenciaEvolucion.reduccion
        : TendenciaEvolucion.aumento;
  }

  /// Mensaje concreto para Tips. Habla de uso de pantalla total, nunca de
  /// "distracción", y no atribuye el cambio a las recomendaciones.
  String get mensajeTips {
    if (tendencia == TendenciaEvolucion.sinDatos) {
      return 'Necesitamos más días de registro para comparar tu evolución '
          '(${reciente.diasValidos}/${reciente.diasEsperados} y '
          '${anterior.diasValidos}/${anterior.diasEsperados} días).';
    }

    final antes = anterior.promedioMinutosPantalla!.round();
    final ahora = reciente.promedioMinutosPantalla!.round();
    final porcentaje = porcentajeMinutos;
    final cambio = porcentaje == null
        ? ''
        : ' (${porcentaje >= 0 ? '+' : ''}'
            '${porcentaje.toStringAsFixed(1)} %)';
    final comparacion = tendencia == TendenciaEvolucion.estable
        ? 'similar al periodo anterior ($antes min/día)'
        : 'frente a $antes min/día del periodo anterior$cambio';

    return 'En los últimos 7 días completos tu promedio de uso de pantalla fue '
        '$ahora min/día, $comparacion. '
        '${_fecha(reciente.desde)}–${_fecha(reciente.hasta)} · '
        '${reciente.diasValidos}/${reciente.diasEsperados} días con registro.';
  }

  /// Acción breve y voluntaria según la tendencia.
  String get accionTips {
    switch (tendencia) {
      case TendenciaEvolucion.reduccion:
        return 'Mantén tu bloque de concentración.';
      case TendenciaEvolucion.aumento:
        return 'Revisa si las distracciones se concentran en un horario.';
      case TendenciaEvolucion.estable:
        return 'Prueba un bloque de concentración de 25 minutos.';
      case TendenciaEvolucion.sinDatos:
        return 'Actualiza el uso desde el Dashboard durante unos días.';
    }
  }

  static String _fecha(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/'
      '${fecha.month.toString().padLeft(2, '0')}';

  factory EvolucionSemanal.calcular({
    required Iterable<UsoPantalla> usos,
    required DateTime ahora,
    DateTime? primeraRecomendacion,
  }) {
    final porDia = <DateTime, UsoPantalla>{};
    for (final uso in usos) {
      porDia[DateTime(uso.fecha.year, uso.fecha.month, uso.fecha.day)] = uso;
    }

    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final reciente = _resumen(
      porDia,
      DateTime(hoy.year, hoy.month, hoy.day - diasVentana),
    );
    final anterior = _resumen(
      porDia,
      DateTime(hoy.year, hoy.month, hoy.day - diasVentana * 2),
      hasta: DateTime(hoy.year, hoy.month, hoy.day - diasVentana - 1),
    );

    final completo = reciente.coberturaCompleta && anterior.coberturaCompleta;

    EstadoEvolucion estado;
    String explicacion;
    double? diferenciaMinutos;
    double? porcentajeMinutos;
    double? diferenciaDesbloqueos;
    double? porcentajeDesbloqueos;

    if (!completo) {
      estado = EstadoEvolucion.insuficiente;
      explicacion = 'Datos insuficientes: periodo reciente '
          '${reciente.diasValidos}/${reciente.diasEsperados} días, '
          'periodo anterior ${anterior.diasValidos}/${anterior.diasEsperados} días.';
    } else {
      final promedioAnterior = anterior.promedioMinutosPantalla!;
      final promedioReciente = reciente.promedioMinutosPantalla!;
      diferenciaMinutos = promedioReciente - promedioAnterior;
      diferenciaDesbloqueos = reciente.promedioDesbloqueos! -
          anterior.promedioDesbloqueos!;
      porcentajeMinutos =
          _porcentaje(promedioAnterior, promedioReciente);
      porcentajeDesbloqueos = _porcentaje(
          anterior.promedioDesbloqueos!, reciente.promedioDesbloqueos!);
      estado = promedioAnterior > 0
          ? EstadoEvolucion.disponible
          : EstadoEvolucion.noComparable;
      explicacion = estado == EstadoEvolucion.disponible
          ? 'Comparación de 7 días completos con los 7 anteriores.'
          : 'El periodo anterior promedia 0 minutos: hay diferencia absoluta '
              'y no porcentaje.';
    }

    final finAnterior = anterior.hasta;
    final esLineaBase = completo &&
        (primeraRecomendacion == null ||
            finAnterior.isBefore(DateTime(primeraRecomendacion.year,
                primeraRecomendacion.month, primeraRecomendacion.day)));

    return EvolucionSemanal._(
      estado: estado,
      explicacion: explicacion,
      reciente: reciente,
      anterior: anterior,
      esLineaBase: esLineaBase,
      diferenciaMinutos: diferenciaMinutos,
      porcentajeMinutos: porcentajeMinutos,
      diferenciaDesbloqueos: diferenciaDesbloqueos,
      porcentajeDesbloqueos: porcentajeDesbloqueos,
    );
  }

  static ResumenPeriodo _resumen(
    Map<DateTime, UsoPantalla> porDia,
    DateTime desde, {
    DateTime? hasta,
  }) {
    final fin = hasta ??
        DateTime(desde.year, desde.month, desde.day + diasVentana - 1);
    var validos = 0;
    var minutos = 0;
    var desbloqueos = 0;

    // Avance por calendario (no por Duration) para no depender de la hora.
    for (var i = 0; i < diasVentana; i++) {
      final fecha = DateTime(desde.year, desde.month, desde.day + i);
      final uso = porDia[fecha];
      if (uso == null) continue;
      validos++;
      minutos += uso.tiempoTotalMinutos;
      desbloqueos += uso.numeroDesbloqueos;
    }

    return ResumenPeriodo(
      desde: desde,
      hasta: fin,
      diasEsperados: diasVentana,
      diasValidos: validos,
      promedioMinutosPantalla: validos == 0 ? null : minutos / validos,
      promedioDesbloqueos: validos == 0 ? null : desbloqueos / validos,
    );
  }

  /// Porcentaje redondeado a un decimal; null si no hay denominador.
  static double? _porcentaje(double anterior, double reciente) {
    if (anterior <= 0) return null;
    return ((reciente - anterior) / anterior * 1000).round() / 10;
  }
}
