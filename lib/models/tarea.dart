// Modelo de datos: Tarea
class Tarea {
  final int? id;
  final String titulo;
  final String? descripcion;
  final DateTime fechaCreacion;
  final DateTime? fechaVencimiento;
  final bool completada;
  final String prioridad; // 'alta', 'media', 'baja'

  Tarea({
    this.id,
    required this.titulo,
    this.descripcion,
    required this.fechaCreacion,
    this.fechaVencimiento,
    this.completada = false,
    this.prioridad = 'media',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'titulo': titulo,
      'descripcion': descripcion,
      'fechaCreacion': fechaCreacion.toIso8601String(),
      'fechaVencimiento': fechaVencimiento?.toIso8601String(),
      'completada': completada ? 1 : 0,
      'prioridad': prioridad,
    };
  }

  factory Tarea.fromMap(Map<String, dynamic> map) {
    return Tarea(
      id: map['id'] as int?,
      titulo: map['titulo'] as String,
      descripcion: map['descripcion'] as String?,
      fechaCreacion: DateTime.parse(map['fechaCreacion'] as String),
      fechaVencimiento: map['fechaVencimiento'] != null
          ? DateTime.parse(map['fechaVencimiento'] as String)
          : null,
      completada: (map['completada'] as int) == 1,
      prioridad: map['prioridad'] as String? ?? 'media',
    );
  }

  Tarea copyWith({
    int? id,
    String? titulo,
    String? descripcion,
    DateTime? fechaCreacion,
    DateTime? fechaVencimiento,
    bool? completada,
    String? prioridad,
  }) {
    return Tarea(
      id: id ?? this.id,
      titulo: titulo ?? this.titulo,
      descripcion: descripcion ?? this.descripcion,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      fechaVencimiento: fechaVencimiento ?? this.fechaVencimiento,
      completada: completada ?? this.completada,
      prioridad: prioridad ?? this.prioridad,
    );
  }
}
