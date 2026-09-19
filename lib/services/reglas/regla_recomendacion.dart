import '../../models/contexto_recomendacion.dart';

/// Gravedad de una recomendación, de menor a mayor.
enum SeveridadRecomendacion { info, sugerencia, advertencia, critica }

/// Condición evaluable sobre un contexto, con descripción legible.
///
/// Cada condición sabe explicarse: [describir] devuelve el texto que justifica
/// la decisión, incluyendo los datos concretos cuando se aporta [detalle].
class CondicionRegla {
  /// Descripción corta de lo que comprueba la condición.
  final String descripcion;

  /// Evaluación sobre el contexto.
  final bool Function(ContextoRecomendacion contexto) evaluar;

  /// Explicación con datos concretos; si es null se usa [descripcion].
  final String Function(ContextoRecomendacion contexto)? detalle;

  const CondicionRegla({
    required this.descripcion,
    required this.evaluar,
    this.detalle,
  });

  bool seCumple(ContextoRecomendacion contexto) => evaluar(contexto);

  String describir(ContextoRecomendacion contexto) =>
      detalle?.call(contexto) ?? descripcion;
}

/// Definición declarativa de una regla del motor.
///
/// Una regla es **datos**, no código disperso: agregar una regla nueva consiste
/// en construir otra instancia y añadirla a la lista del evaluador, sin tocar
/// el motor.
class ReglaRecomendacion {
  /// Identificador estable de la regla (p. ej. 'R1').
  final String id;

  /// Nombre legible.
  final String nombre;

  /// Prioridad de atención; a mayor valor, antes se atiende.
  final int prioridad;

  /// Condiciones que deben cumplirse **todas** (AND).
  final List<CondicionRegla> condiciones;

  /// Tipo de recomendación producida (campo `tipo` de `Recomendacion`).
  final String tipo;

  /// Título de la recomendación, dependiente del contexto.
  final String Function(ContextoRecomendacion contexto) titulo;

  /// Mensaje de la recomendación, dependiente del contexto.
  final String Function(ContextoRecomendacion contexto) mensaje;

  /// Gravedad de la recomendación.
  final SeveridadRecomendacion severidad;

  /// Intervalo mínimo entre repeticiones de esta regla.
  final Duration cooldown;

  /// Permite desactivar la regla sin borrarla.
  final bool habilitada;

  const ReglaRecomendacion({
    required this.id,
    required this.nombre,
    required this.prioridad,
    required this.condiciones,
    required this.tipo,
    required this.titulo,
    required this.mensaje,
    this.severidad = SeveridadRecomendacion.sugerencia,
    this.cooldown = const Duration(hours: 6),
    this.habilitada = true,
  });

  /// ¿La regla está habilitada y se cumplen todas sus condiciones?
  bool seCumple(ContextoRecomendacion contexto) {
    if (!habilitada || condiciones.isEmpty) return false;
    for (final condicion in condiciones) {
      if (!condicion.seCumple(contexto)) return false;
    }
    return true;
  }

  /// Explicaciones de las condiciones cumplidas.
  List<String> explicaciones(ContextoRecomendacion contexto) => condiciones
      .where((c) => c.seCumple(contexto))
      .map((c) => c.describir(contexto))
      .toList();

  /// Copia la regla permitiendo cambiar algunos atributos (por ejemplo,
  /// deshabilitarla sin borrarla).
  ReglaRecomendacion copyWith({
    String? id,
    String? nombre,
    int? prioridad,
    List<CondicionRegla>? condiciones,
    String? tipo,
    String Function(ContextoRecomendacion contexto)? titulo,
    String Function(ContextoRecomendacion contexto)? mensaje,
    SeveridadRecomendacion? severidad,
    Duration? cooldown,
    bool? habilitada,
  }) {
    return ReglaRecomendacion(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      prioridad: prioridad ?? this.prioridad,
      condiciones: condiciones ?? this.condiciones,
      tipo: tipo ?? this.tipo,
      titulo: titulo ?? this.titulo,
      mensaje: mensaje ?? this.mensaje,
      severidad: severidad ?? this.severidad,
      cooldown: cooldown ?? this.cooldown,
      habilitada: habilitada ?? this.habilitada,
    );
  }
}
