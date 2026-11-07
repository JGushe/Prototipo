// Modelo: Recomendación generada por el motor de reglas
//
// Además del contenido visible, cada recomendación conserva de qué regla
// proviene y por qué se generó, para que el resultado sea explicable.
class Recomendacion {
  final int? id;
  final DateTime fecha;
  final String tipo; // 'pausa', 'alerta_uso', 'sugerencia_foco', 'descanso'
  final String titulo;
  final String mensaje;
  final bool leida;

  /// Identificador de la regla que la generó (p. ej. 'R1'), si se conoce.
  final String? reglaId;

  /// Severidad: 'info', 'sugerencia', 'advertencia' o 'critica'.
  final String severidad;

  /// Explicación de por qué se generó (condiciones que se cumplieron).
  final String? motivo;

  /// Clave de equivalencia: dos recomendaciones con la misma clave y dentro de
  /// la misma ventana se consideran duplicadas. Es null en recomendaciones
  /// anteriores a la incorporación del control de cooldown.
  final String? clave;

  /// Valoración voluntaria: 'util', 'no_util' o null (sin respuesta).
  /// No implica que la recomendación se haya aplicado.
  final String? valoracion;

  Recomendacion({
    this.id,
    required this.fecha,
    required this.tipo,
    required this.titulo,
    required this.mensaje,
    this.leida = false,
    this.reglaId,
    this.severidad = 'info',
    this.motivo,
    this.clave,
    this.valoracion,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fecha': fecha.toIso8601String(),
      'tipo': tipo,
      'titulo': titulo,
      'mensaje': mensaje,
      'leida': leida ? 1 : 0,
      'reglaId': reglaId,
      'severidad': severidad,
      'motivo': motivo,
      'clave': clave,
      'valoracion': valoracion,
    };
  }

  factory Recomendacion.fromMap(Map<String, dynamic> map) {
    return Recomendacion(
      id: map['id'] as int?,
      fecha: DateTime.parse(map['fecha'] as String),
      tipo: map['tipo'] as String,
      titulo: map['titulo'] as String,
      mensaje: map['mensaje'] as String,
      leida: (map['leida'] as int) == 1,
      reglaId: map['reglaId'] as String?,
      severidad: map['severidad'] as String? ?? 'info',
      motivo: map['motivo'] as String?,
      clave: map['clave'] as String?,
      valoracion: map['valoracion'] as String?,
    );
  }
}

/// Conteo de valoraciones. El denominador es solo lo valorado, nunca lo leído.
class ResumenValoraciones {
  /// Mínimo de valoraciones para hablar de porcentaje sin muestra insuficiente.
  static const int minimoMuestra = 5;

  final int total;
  final int utiles;
  final int noUtiles;

  /// Recomendaciones generadas en el periodo consultado.
  final int generadas;

  const ResumenValoraciones({
    required this.total,
    required this.utiles,
    required this.noUtiles,
    this.generadas = 0,
  });

  /// Porcentaje de útiles, o null si no hay valoraciones.
  double? get porcentajeUtil => total == 0 ? null : utiles / total * 100;

  bool get muestraSuficiente => total >= minimoMuestra;
}
