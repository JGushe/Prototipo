// Modelo de datos: Tarea
//
// La planificación temporal (opcional) es independiente del vencimiento:
//   - `fechaVencimiento`  -> cuándo debe estar terminada (recordatorio).
//   - `fechaPlanificada`  -> qué día se planea trabajar en ella.
//   - `horaInicioPlanificada` / `horaFinPlanificada` -> franja horaria de ese día,
//     en formato 'HH:mm'.
//
// Una tarea antigua (sin planificación) conserva los tres campos en null.
class Tarea {
  final int? id;
  final String titulo;
  final String? descripcion;
  final DateTime fechaCreacion;
  final DateTime? fechaVencimiento;
  final bool completada;
  final String prioridad; // 'alta', 'media', 'baja'

  // --- Planificación temporal (opcional) ---
  final DateTime? fechaPlanificada;
  final String? horaInicioPlanificada; // 'HH:mm'
  final String? horaFinPlanificada; // 'HH:mm'

  Tarea({
    this.id,
    required this.titulo,
    this.descripcion,
    required this.fechaCreacion,
    this.fechaVencimiento,
    this.completada = false,
    this.prioridad = 'media',
    this.fechaPlanificada,
    this.horaInicioPlanificada,
    this.horaFinPlanificada,
  });

  /// ¿Tiene una fecha planificada?
  bool get tieneFechaPlanificada => fechaPlanificada != null;

  /// ¿Tiene un rango horario planificado completo?
  bool get tieneRangoHorario =>
      horaInicioPlanificada != null && horaFinPlanificada != null;

  /// Inicio planificado combinado (fecha + hora), o null si falta información.
  DateTime? get inicioPlanificado =>
      _combinarFechaHora(fechaPlanificada, horaInicioPlanificada);

  /// Fin planificado combinado (fecha + hora), o null si falta información.
  DateTime? get finPlanificado =>
      _combinarFechaHora(fechaPlanificada, horaFinPlanificada);

  /// Caso especial: la franja termina al día siguiente (p. ej. 23:00 → 01:00).
  bool get cruzaMedianoche {
    final inicio = _horaAMinutos(horaInicioPlanificada);
    final fin = _horaAMinutos(horaFinPlanificada);
    if (inicio == null || fin == null) return false;
    return fin < inicio;
  }

  /// ¿La tarea está planificada y activa en [momento]?
  ///
  /// - Sin fecha planificada -> nunca activa.
  /// - Con fecha pero sin horario -> activa durante todo el día planificado.
  /// - Con horario -> activa dentro de [inicio, fin); si cruza medianoche,
  ///   el fin se desplaza al día siguiente.
  bool estaPlanificadaEn(DateTime momento) {
    final fecha = fechaPlanificada;
    if (fecha == null) return false;

    final inicio = inicioPlanificado;
    final fin = finPlanificado;

    // Solo fecha planificada: todo el día.
    if (inicio == null || fin == null) {
      return fecha.year == momento.year &&
          fecha.month == momento.month &&
          fecha.day == momento.day;
    }

    if (cruzaMedianoche) {
      final finAjustado = fin.add(const Duration(days: 1));
      return !momento.isBefore(inicio) && momento.isBefore(finAjustado);
    }
    return !momento.isBefore(inicio) && momento.isBefore(fin);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'titulo': titulo,
      'descripcion': descripcion,
      'fechaCreacion': fechaCreacion.toIso8601String(),
      'fechaVencimiento': fechaVencimiento?.toIso8601String(),
      'completada': completada ? 1 : 0,
      'prioridad': prioridad,
      'fechaPlanificada':
          fechaPlanificada == null ? null : _soloFecha(fechaPlanificada!),
      'horaInicioPlanificada': horaInicioPlanificada,
      'horaFinPlanificada': horaFinPlanificada,
    };
  }

  factory Tarea.fromMap(Map<String, dynamic> map) {
    final fechaPlanificada = map['fechaPlanificada'] as String?;
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
      fechaPlanificada: fechaPlanificada != null
          ? DateTime.parse(fechaPlanificada)
          : null,
      horaInicioPlanificada: map['horaInicioPlanificada'] as String?,
      horaFinPlanificada: map['horaFinPlanificada'] as String?,
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
    DateTime? fechaPlanificada,
    String? horaInicioPlanificada,
    String? horaFinPlanificada,
  }) {
    return Tarea(
      id: id ?? this.id,
      titulo: titulo ?? this.titulo,
      descripcion: descripcion ?? this.descripcion,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      fechaVencimiento: fechaVencimiento ?? this.fechaVencimiento,
      completada: completada ?? this.completada,
      prioridad: prioridad ?? this.prioridad,
      fechaPlanificada: fechaPlanificada ?? this.fechaPlanificada,
      horaInicioPlanificada:
          horaInicioPlanificada ?? this.horaInicioPlanificada,
      horaFinPlanificada: horaFinPlanificada ?? this.horaFinPlanificada,
    );
  }

  // --- Utilidades de validación ---

  /// Valida una franja horaria en formato 'HH:mm'.
  ///
  /// Por defecto exige `horaInicio < horaFin`. El caso especial de una franja
  /// que cruza la medianoche (`horaFin < horaInicio`) solo se acepta cuando
  /// [permitirCruceMedianoche] es true.
  static bool rangoHorarioValido(
    String? horaInicio,
    String? horaFin, {
    bool permitirCruceMedianoche = false,
  }) {
    if (horaInicio == null && horaFin == null) return true;
    if (horaInicio == null || horaFin == null) return false;

    final inicio = _horaAMinutos(horaInicio);
    final fin = _horaAMinutos(horaFin);
    if (inicio == null || fin == null) return false; // formato inválido
    if (inicio == fin) return false;

    return inicio < fin ? true : permitirCruceMedianoche;
  }

  /// Normaliza una [hora] a 'HH:mm', o null si es inválida.
  static String? formatearHora(int hora, int minuto) {
    if (hora < 0 || hora > 23 || minuto < 0 || minuto > 59) return null;
    return '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}';
  }
}

// --- Helpers internos ---

String _soloFecha(DateTime fecha) => fecha.toIso8601String().substring(0, 10);

int? _horaAMinutos(String? hora) {
  if (hora == null) return null;
  final partes = hora.split(':');
  if (partes.length != 2) return null;
  final h = int.tryParse(partes[0]);
  final m = int.tryParse(partes[1]);
  if (h == null || m == null) return null;
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

DateTime? _combinarFechaHora(DateTime? fecha, String? hora) {
  if (fecha == null) return null;
  final minutos = _horaAMinutos(hora);
  if (minutos == null) return null;
  return DateTime(
    fecha.year,
    fecha.month,
    fecha.day,
    minutos ~/ 60,
    minutos % 60,
  );
}
