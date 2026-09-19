// Modelo de datos: Uso de Pantalla
class UsoPantalla {
  final int? id;
  final DateTime fecha;
  final int tiempoTotalMinutos;
  final int numeroDesbloqueos;
  final String? appMasUsada;
  final int tiempoAppMasUsada;

  UsoPantalla({
    this.id,
    required this.fecha,
    required this.tiempoTotalMinutos,
    required this.numeroDesbloqueos,
    this.appMasUsada,
    this.tiempoAppMasUsada = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fecha': fecha.toIso8601String(),
      'tiempoTotalMinutos': tiempoTotalMinutos,
      'numeroDesbloqueos': numeroDesbloqueos,
      'appMasUsada': appMasUsada,
      'tiempoAppMasUsada': tiempoAppMasUsada,
    };
  }

  factory UsoPantalla.fromMap(Map<String, dynamic> map) {
    return UsoPantalla(
      id: map['id'] as int?,
      fecha: DateTime.parse(map['fecha'] as String),
      tiempoTotalMinutos: map['tiempoTotalMinutos'] as int,
      numeroDesbloqueos: map['numeroDesbloqueos'] as int,
      appMasUsada: map['appMasUsada'] as String?,
      tiempoAppMasUsada: map['tiempoAppMasUsada'] as int? ?? 0,
    );
  }
}

// Modelo: Detalle de uso por aplicación
class AppUso {
  final String nombrePaquete;
  final String nombreApp;
  final int tiempoUsoMinutos;
  final int numeroAperturas;

  AppUso({
    required this.nombrePaquete,
    required this.nombreApp,
    required this.tiempoUsoMinutos,
    required this.numeroAperturas,
  });

  Map<String, dynamic> toMap() {
    return {
      'nombrePaquete': nombrePaquete,
      'nombreApp': nombreApp,
      'tiempoUsoMinutos': tiempoUsoMinutos,
      'numeroAperturas': numeroAperturas,
    };
  }

  factory AppUso.fromMap(Map<String, dynamic> map) {
    return AppUso(
      nombrePaquete: map['nombrePaquete'] as String,
      nombreApp: map['nombreApp'] as String,
      tiempoUsoMinutos: map['tiempoUsoMinutos'] as int,
      numeroAperturas: map['numeroAperturas'] as int,
    );
  }
}
