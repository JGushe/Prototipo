import 'horario.dart';
import 'tarea.dart';
import 'uso_pantalla.dart';

/// Estado contextual del usuario en un momento concreto.
///
/// Es un **contenedor de datos**: reúne todo lo que el motor necesita saber
/// antes de decidir. No contiene reglas de negocio ni genera recomendaciones;
/// esas viven en las reglas del motor.
///
/// Los campos derivados (tipo de horario, aplicaciones distractoras, pico, etc.)
/// se exponen como getters para que no puedan quedar inconsistentes con los
/// datos de origen.
class ContextoRecomendacion {
  /// Valores posibles de [tipoHorario].
  static const String tipoLaboral = 'laboral';
  static const String tipoAcademico = 'academico';
  static const String tipoNinguno = 'ninguno';

  /// Clasificación por defecto de paquetes potencialmente distractores.
  ///
  /// Es solo un punto de partida: [paquetesDistractores] permite sustituirla.
  static const List<String> paquetesDistractoresPorDefecto = [
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

  /// Minutos de uso por hora del día (0-23) en la ventana analizada.
  final Map<int, int> usoPorHora;

  /// Minutos de uso dentro del rango nocturno configurado.
  final int minutosUsoNocturno;

  /// Clasificación de aplicaciones distractoras aplicada a este contexto.
  final List<String> paquetesDistractores;

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
    this.usoPorHora = const {},
    this.minutosUsoNocturno = 0,
    List<String>? paquetesDistractores,
  }) : paquetesDistractores =
            paquetesDistractores ?? paquetesDistractoresPorDefecto;

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

  /// ¿Hay una tarea planificada activa de prioridad alta?
  bool get hayTareaActivaPrioritaria => tareaActiva?.prioridad == 'alta';

  int get tareasPendientesTotal => tareasPendientes.length;

  int get tareasAltaPrioridadTotal => tareasAltaPrioridadPendientes.length;

  // --- Derivados del uso por hora ---

  /// Minutos de la hora con más uso (0 si no hay datos).
  int get minutosPico {
    var maximo = 0;
    for (final minutos in usoPorHora.values) {
      if (minutos > maximo) maximo = minutos;
    }
    return maximo;
  }

  /// Hora (0-23) con más uso (0 si no hay datos).
  int get horaPico {
    var maximo = 0;
    var hora = 0;
    usoPorHora.forEach((h, minutos) {
      if (minutos > maximo) {
        maximo = minutos;
        hora = h;
      }
    });
    return hora;
  }

  /// Horario configurado cuyo rango horario contiene la hora pico, o null.
  Horario? get horarioDelPico {
    if (minutosPico <= 0) return null;
    final pico = horaPico;
    for (final horario in horarios) {
      if (horario.contieneHora(pico)) return horario;
    }
    return null;
  }

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
  ///
  /// Usa la clasificación de este contexto ([paquetesDistractores]).
  bool esPaqueteDistractor(String nombrePaquete) =>
      clasificarDistractor(nombrePaquete, paquetesDistractores);

  /// Clasificación configurable por prefijo: `com.instagram` también cubre
  /// `com.instagram.android`, pero no `com.instagramx`.
  static bool clasificarDistractor(
    String nombrePaquete,
    List<String> paquetes,
  ) {
    final paquete = nombrePaquete.toLowerCase();
    for (final distractor in paquetes) {
      if (paquete == distractor || paquete.startsWith('$distractor.')) {
        return true;
      }
    }
    return false;
  }
}
