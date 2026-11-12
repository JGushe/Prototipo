/// Perfil local del usuario. Opcional y sin salir del dispositivo.
///
/// `identidadGenero` usa valores internos estables; null = sin declarar.
/// No se usa para reglas, métricas ni recomendaciones: solo para el trato.
class Perfil {
  static const String masculino = 'masculino';
  static const String femenino = 'femenino';
  static const String noBinario = 'no_binario';
  static const String otra = 'otra';
  static const String prefiereNoResponder = 'prefiere_no_responder';

  static const List<String> identidades = [
    masculino,
    femenino,
    noBinario,
    otra,
    prefiereNoResponder,
  ];

  final String? nombre;
  final String? identidadGenero;
  final String? autodescripcion;

  const Perfil({this.nombre, this.identidadGenero, this.autodescripcion});

  bool get tieneNombre => nombre != null && nombre!.trim().isNotEmpty;

  /// Nombre o apodo elegido; si no hay, trato neutro.
  String get nombreVisible => tieneNombre ? nombre!.trim() : 'Usuario';

  /// Etiqueta visible de la identidad, o null si no declaró.
  String? get identidadVisible {
    switch (identidadGenero) {
      case masculino:
        return 'Masculino';
      case femenino:
        return 'Femenino';
      case noBinario:
        return 'No binario';
      case otra:
        final texto = autodescripcion?.trim();
        return (texto == null || texto.isEmpty) ? 'Otra identidad' : texto;
      case prefiereNoResponder:
        return 'Prefiero no responder';
      default:
        return null;
    }
  }

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'identidadGenero': identidadGenero,
        'autodescripcion': autodescripcion,
      };

  factory Perfil.fromMap(Map<String, dynamic> map) => Perfil(
        nombre: map['nombre'] as String?,
        identidadGenero: map['identidadGenero'] as String?,
        autodescripcion: map['autodescripcion'] as String?,
      );
}
