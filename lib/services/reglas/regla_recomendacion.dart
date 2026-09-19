import '../../models/contexto_recomendacion.dart';

/// Gravedad de una recomendación, de menor a mayor.
enum SeveridadRecomendacion { info, sugerencia, advertencia, critica }

/// Ámbito que define cuándo dos recomendaciones de una misma regla se
/// consideran equivalentes (es decir, cuándo la segunda es un duplicado).
enum AmbitoCooldown {
  /// Una vez por día natural: la clave incluye la fecha.
  dia,

  /// Una vez por bloque de horario dentro del día: la clave incluye la fecha y
  /// el horario activo (tipo y rango), de modo que dos horarios distintos no se
  /// estorban entre sí.
  horario,

  /// Sujeta únicamente al [ReglaRecomendacion.cooldown] temporal de la regla.
  regla,
}

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
  ///
  /// Aplica al ámbito [AmbitoCooldown.regla]; en los ámbitos `dia` y `horario`
  /// la propia clave ya acota el periodo al día natural.
  final Duration cooldown;

  /// Define qué recomendaciones de esta regla se consideran equivalentes.
  final AmbitoCooldown ambito;

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
    this.ambito = AmbitoCooldown.regla,
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

  /// Clave que identifica recomendaciones equivalentes de esta regla.
  ///
  /// Dos recomendaciones con la misma clave y dentro de la misma ventana son
  /// duplicados. La clave incluye el identificador de la regla, de modo que
  /// reglas distintas nunca se bloquean entre sí.
  String claveEquivalencia(ContextoRecomendacion contexto) {
    switch (ambito) {
      case AmbitoCooldown.dia:
        return '$id|dia:${_soloFecha(contexto.momento)}';
      case AmbitoCooldown.horario:
        final horario = contexto.horarioActivo;
        final bloque = horario == null
            ? 'ninguno'
            : '${horario.tipo}:${horario.inicioTexto}-${horario.finTexto}';
        return '$id|horario:${_soloFecha(contexto.momento)}|$bloque';
      case AmbitoCooldown.regla:
        return '$id|regla';
    }
  }

  /// Inicio de la ventana en la que una recomendación equivalente bloquea.
  ///
  /// - `dia`: el inicio del día natural (una sola vez al día).
  /// - `regla` y `horario`: `momento - cooldown`, de modo que la recomendación
  ///   puede repetirse periódicamente. En `horario` la clave ya distingue el
  ///   bloque y el día, así que esto convierte la regla contextual en un
  ///   recordatorio periódico mientras la distracción continúa.
  DateTime inicioVentanaCooldown(ContextoRecomendacion contexto) {
    if (ambito == AmbitoCooldown.dia) {
      return DateTime(
        contexto.momento.year,
        contexto.momento.month,
        contexto.momento.day,
      );
    }
    return contexto.momento.subtract(cooldown);
  }

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
    AmbitoCooldown? ambito,
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
      ambito: ambito ?? this.ambito,
      habilitada: habilitada ?? this.habilitada,
    );
  }
}

String _soloFecha(DateTime fecha) => fecha.toIso8601String().substring(0, 10);
