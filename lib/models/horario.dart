// Modelo de datos: Horario (laboral o académico)
class Horario {
  final int? id;
  final String tipo; // 'laboral' o 'academico'
  final int horaInicio; // 0-23 (ej: 8 = 8 AM)
  final int minutoInicio; // 0-59
  final int horaFin; // 0-23 (ej: 16 = 4 PM)
  final int minutoFin; // 0-59
  final List<int> diasSemana; // 1=lunes ... 7=domingo

  Horario({
    this.id,
    required this.tipo,
    required this.horaInicio,
    this.minutoInicio = 0,
    required this.horaFin,
    this.minutoFin = 0,
    this.diasSemana = const [1, 2, 3, 4, 5],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tipo': tipo,
      'horaInicio': horaInicio,
      'minutoInicio': minutoInicio,
      'horaFin': horaFin,
      'minutoFin': minutoFin,
      'diasSemana': diasSemana.join(','),
    };
  }

  factory Horario.fromMap(Map<String, dynamic> map) {
    final diasStr = map['diasSemana'] as String? ?? '1,2,3,4,5';
    return Horario(
      id: map['id'] as int?,
      tipo: map['tipo'] as String,
      horaInicio: map['horaInicio'] as int,
      minutoInicio: map['minutoInicio'] as int? ?? 0,
      horaFin: map['horaFin'] as int,
      minutoFin: map['minutoFin'] as int? ?? 0,
      diasSemana: diasStr
          .split(',')
          .where((s) => s.isNotEmpty)
          .map((s) => int.tryParse(s.trim()) ?? 0)
          .where((d) => d > 0)
          .toList(),
    );
  }

  /// Devuelve la hora de inicio como texto legible (ej: "08:00")
  String get inicioTexto => _formato(horaInicio, minutoInicio);

  /// Devuelve la hora de fin como texto legible (ej: "16:00")
  String get finTexto => _formato(horaFin, minutoFin);

  String _formato(int h, int m) {
    final hh = h.toString().padLeft(2, '0');
    final mm = m.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// Devuelve el rango completo (ej: "08:00 - 16:00")
  String get rangoTexto => '$inicioTexto - $finTexto';

  /// Devuelve el nombre legible del tipo (ej: "Laboral")
  String get tipoTexto => tipo == 'laboral' ? 'Laboral' : 'Académico';

  /// Minutos transcurridos desde medianoche para una hora/minuto dados.
  static int minutosDesdeMedianoche(int hora, int minuto) => hora * 60 + minuto;

  /// Inicio del horario expresado en minutos desde medianoche.
  int get minutosInicio => minutosDesdeMedianoche(horaInicio, minutoInicio);

  /// Fin del horario expresado en minutos desde medianoche.
  int get minutosFin => minutosDesdeMedianoche(horaFin, minutoFin);

  /// ¿El horario cubre algún minuto? Si inicio y fin coinciden, el rango es
  /// vacío y ningún DateTime pertenece a él.
  bool get tieneDuracion => minutosInicio != minutosFin;

  /// ¿El horario cruza la medianoche? (ej. 22:00 - 02:00)
  bool get cruzaMedianoche => minutosFin < minutosInicio;

  /// Determina si [fechaHora] pertenece a este horario considerando el día de
  /// la semana, la hora y los minutos.
  ///
  /// En un horario que cruza medianoche, [diasSemana] indica el día en que
  /// **empieza** el bloque: un horario del lunes 22:00-02:00 cubre la noche del
  /// lunes y la madrugada del martes (aunque el martes no esté configurado).
  bool contieneDateTime(DateTime fechaHora) {
    if (!tieneDuracion) return false;

    final minutos = minutosDesdeMedianoche(fechaHora.hour, fechaHora.minute);
    final dia = fechaHora.weekday; // 1=lunes ... 7=domingo

    if (!cruzaMedianoche) {
      if (!diasSemana.contains(dia)) return false;
      return minutos >= minutosInicio && minutos < minutosFin;
    }

    // Horario nocturno: tramo de la noche (mismo día de inicio).
    if (minutos >= minutosInicio) {
      return diasSemana.contains(dia);
    }
    // Tramo de la madrugada (el bloque empezó el día anterior).
    if (minutos < minutosFin) {
      final diaAnterior = dia == DateTime.monday ? DateTime.sunday : dia - 1;
      return diasSemana.contains(diaAnterior);
    }
    return false;
  }

  /// Devuelve si una hora determinada cae dentro de este horario.
  ///
  /// Comprobación heredada que solo compara horas enteras, sin minutos ni días
  /// de la semana. Se conserva por compatibilidad con el motor de
  /// recomendaciones; para lógica nueva usar [contieneDateTime].
  bool contieneHora(int hora) {
    if (horaInicio <= horaFin) {
      return hora >= horaInicio && hora < horaFin;
    } else {
      // Horario que cruza medianoche (ej: 22:00 - 02:00)
      return hora >= horaInicio || hora < horaFin;
    }
  }
}
