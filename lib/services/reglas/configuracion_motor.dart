import '../../models/contexto_recomendacion.dart';

/// Configuración centralizada del sistema de recomendaciones.
///
/// Reúne **todos** los umbrales de las reglas y las ventanas de datos que usa
/// el servicio de contexto, de modo que no haya valores mágicos dispersos.
/// Se puede sustituir por otra instancia (por ejemplo en pruebas) sin tocar las
/// reglas ni el motor.
class ConfiguracionMotor {
  // --- Umbrales de las reglas ---

  /// R1, R2, R3: minutos de uso distractor que se consideran significativos.
  final int minutosDistractor;

  /// R4: número de tareas pendientes a partir del cual se sugiere organizar.
  final int tareasPendientesLimite;

  /// R5: minutos de pantalla al día que se consideran uso alto.
  final int minutosAltoUsoDiario;

  /// R6: minutos de pantalla que, junto con la carga de tareas, indica sobrecarga.
  final int minutosCargaAltaUso;

  /// R6: tareas pendientes que, junto al uso alto, indican sobrecarga.
  final int tareasCargaAltaLimite;

  /// R7: minutos de uso nocturno que se consideran excesivos.
  final int minutosUsoNocturno;

  /// R7: hora de inicio del rango nocturno (0-23).
  final int horaInicioNocturno;

  /// R7: hora de fin del rango nocturno (0-23).
  final int horaFinNocturno;

  // --- Ventanas de datos del contexto ---

  /// Días hacia atrás que se analizan para el uso por hora.
  final int diasAnalisis;

  /// Clasificación de paquetes potencialmente distractores.
  final List<String> paquetesDistractores;

  // --- Cooldown por familia de reglas ---
  //
  // Están definidos aquí para que la representación de cada regla sea completa,
  // pero el motor todavía **no** los aplica (ver informe de la etapa 5).

  final Duration cooldownDistractor;
  final Duration cooldownTareas;
  final Duration cooldownUso;
  final Duration cooldownNocturno;
  final Duration cooldownPico;

  const ConfiguracionMotor({
    this.minutosDistractor = 30,
    this.tareasPendientesLimite = 5,
    this.minutosAltoUsoDiario = 240,
    this.minutosCargaAltaUso = 180,
    this.tareasCargaAltaLimite = 3,
    this.minutosUsoNocturno = 60,
    this.horaInicioNocturno = 22,
    this.horaFinNocturno = 6,
    this.diasAnalisis = 7,
    this.paquetesDistractores =
        ContextoRecomendacion.paquetesDistractoresPorDefecto,
    this.cooldownDistractor = const Duration(minutes: 90),
    this.cooldownTareas = const Duration(hours: 12),
    this.cooldownUso = const Duration(hours: 6),
    this.cooldownNocturno = const Duration(hours: 12),
    this.cooldownPico = const Duration(hours: 12),
  });

  /// Configuración por defecto del prototipo.
  static const ConfiguracionMotor porDefecto = ConfiguracionMotor();
}
