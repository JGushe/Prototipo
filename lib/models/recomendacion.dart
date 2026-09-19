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
    );
  }
}
