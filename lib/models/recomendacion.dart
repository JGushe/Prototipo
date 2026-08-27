// Modelo: Recomendación generada por el motor de reglas
class Recomendacion {
  final int? id;
  final DateTime fecha;
  final String tipo; // 'pausa', 'alerta_uso', 'sugerencia_foco', 'descanso'
  final String titulo;
  final String mensaje;
  final bool leida;

  Recomendacion({
    this.id,
    required this.fecha,
    required this.tipo,
    required this.titulo,
    required this.mensaje,
    this.leida = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fecha': fecha.toIso8601String(),
      'tipo': tipo,
      'titulo': titulo,
      'mensaje': mensaje,
      'leida': leida ? 1 : 0,
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
    );
  }
}
