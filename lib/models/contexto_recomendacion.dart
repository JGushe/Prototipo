import 'horario.dart';
import 'tarea.dart';
import 'uso_pantalla.dart';

/// Estado contextual del usuario en un momento concreto.
///
/// Es un **contenedor de datos**: reúne todo lo que el motor necesita saber
/// antes de decidir. No contiene reglas de negocio ni genera recomendaciones;
/// esas viven en `MotorRecomendaciones`.
///
/// Los campos derivados (tipo de horario, aplicaciones distractoras, etc.) se
/// exponen como getters para que no puedan quedar inconsistentes con los datos
/// de origen.
class ContextoRecomendacion {
  /// Valores posibles de [tipoHorario].
  static const String tipoLaboral = 'laboral';
  static const String tipoAcademico = 'academico';
  static const String tipoNinguno = 'ninguno';

  /// Paquetes considerados potencialmente distractores.
  ///
  /// La comparación es por prefijo, de modo que `com.instagram` también
  /// clasifica a `com.instagram.android`.
  static const List<String> paquetesDistractores = [
    'com.facebook',
    'com.instagram',
    'com.twitter',
    'com.x',
    'com.whatsapp',
    'com.tiktok',
    'com.zhiliaoapp.musically',
    'com.snapchat',
  ];

  /// Momento al que corresponde este contexto.
  final DateTime momento;

  /// Todos los horarios configurados (laboral y académico).
  final List<Horario> horarios;

  /// Horario que contiene [momento], si existe.
  final Horario? horarioActivo;

  /// Tarea planificada activa en [momento], si existe.
  final Tarea? tareaActiva;

  /// Tareas pendientes (no completadas).
  final List<Tarea> tareasPendientes;

  /// Subconjunto de [tareasPendientes] con prioridad 'alta'.
  final List<Tarea> tareasAltaPrioridadPendientes;

  /// Minutos totales de pantalla registrados para el día de [momento].
  final int tiempoTotalPantallaMinutos;

  /// Indica si existe un registro de uso de pantalla para ese día.
  final bool hayDatosUsoPantalla;

  /// Indica si el permiso de UsageStats estaba disponible al construir.
  final bool permisoUsoDisponible;

  /// Aplicaciones más utilizadas del día, de mayor a menor tiempo de uso.
  final List<AppUso> appsMasUtilizadas;

  ContextoRecomendacion({
    required this.momento,
    this.horarios = const [],
    this.horarioActivo,
    this.tareaActiva,
    this.tareasPendientes = const [],
    this.tareasAltaPrioridadPendientes = const [],
    this.tiempoTotalPantallaMinutos = 0,
    this.hayDatosUsoPantalla = false,
    this.permisoUsoDisponible = false,
    this.appsMasUtilizadas = const [],
  });

  // --- Derivados del horario ---

  /// Tipo de horario activo: 'laboral', 'academico' o 'ninguno'.
  String get tipoHorario => horarioActivo?.tipo ?? tipoNinguno;

  /// Nombre legible del tipo de horario.
  String get tipoHorarioTexto {
    switch (tipoHorario) {
      case tipoLaboral:
        return 'Laboral';
      case tipoAcademico:
        return 'Académico';
      default:
        return 'Ninguno';
    }
  }

  bool get hayHorarioActivo => horarioActivo != null;

  // --- Derivados de las tareas ---

  bool get hayTareaActiva => tareaActiva != null;

  int get tareasPendientesTotal => tareasPendientes.length;

  int get tareasAltaPrioridadTotal => tareasAltaPrioridadPendientes.length;

  // --- Derivados de las aplicaciones ---

  bool get hayAppsMasUtilizadas => appsMasUtilizadas.isNotEmpty;

  /// Aplicaciones de [appsMasUtilizadas] clasificadas como distractoras.
  List<AppUso> get appsDistractoras =>
      appsMasUtilizadas.where((a) => esPaqueteDistractor(a.nombrePaquete)).toList();

  /// Minutos totales en aplicaciones distractoras.
  int get minutosAppsDistractoras {
    var total = 0;
    for (final app in appsMasUtilizadas) {
      if (esPaqueteDistractor(app.nombrePaquete)) {
        total += app.tiempoUsoMinutos;
      }
    }
    return total;
  }

  /// Aplicación distractora con más tiempo de uso, o null si no hay ninguna.
  AppUso? get appDistractoraPrincipal {
    AppUso? principal;
    for (final app in appsMasUtilizadas) {
      if (!esPaqueteDistractor(app.nombrePaquete)) continue;
      if (principal == null || app.tiempoUsoMinutos > principal.tiempoUsoMinutos) {
        principal = app;
      }
    }
    return principal;
  }

  bool get hayAppsDistractoras => appDistractoraPrincipal != null;

  /// ¿El paquete corresponde a una aplicación potencialmente distractora?
  static bool esPaqueteDistractor(String nombrePaquete) {
    final paquete = nombrePaquete.toLowerCase();
    for (final distractor in paquetesDistractores) {
      if (paquete == distractor || paquete.startsWith('$distractor.')) {
        return true;
      }
    }
    return false;
  }
}
