import '../../models/contexto_recomendacion.dart';
import 'configuracion_motor.dart';
import 'regla_recomendacion.dart';

/// Prioridad de cada regla (a mayor valor, antes se atiende).
class PrioridadRegla {
  static const int tareaPrioritariaEnDistraccion = 100; // R3
  static const int distractorContextual = 90; // R1, R2
  static const int usoNocturno = 80; // R7
  static const int picoEnHorario = 70; // R8
  static const int cargaCombinada = 60; // R6
  static const int altoUso = 50; // R5
  static const int tareasPendientes = 40; // R4

  const PrioridadRegla._();
}

/// Construye el conjunto de reglas por defecto del prototipo.
///
/// Añadir una regla nueva consiste en crear otra [ReglaRecomendacion] y
/// incluirla aquí: el motor y el evaluador no cambian.
List<ReglaRecomendacion> crearReglasPorDefecto(
    [ConfiguracionMotor? configuracion]) {
  final c = configuracion ?? ConfiguracionMotor.porDefecto;
  return [
    _r3(c),
    _r1(c),
    _r2(c),
    _r7(c),
    _r8(c),
    _r6(c),
    _r5(c),
    _r4(c),
  ];
}

// --- Utilidades de formato ---

String _horaTexto(int hora) => '${hora.toString().padLeft(2, '0')}:00';

String _rangoNocturnoTexto(ConfiguracionMotor c) =>
    '${_horaTexto(c.horaInicioNocturno)} y las ${_horaTexto(c.horaFinNocturno)}';

// --- R1: Uso distractor durante el estudio ---

ReglaRecomendacion _r1(ConfiguracionMotor c) => ReglaRecomendacion(
      id: 'R1',
      nombre: 'Uso distractor durante el estudio',
      prioridad: PrioridadRegla.distractorContextual,
      condiciones: [
        CondicionRegla(
          descripcion: 'Hay un horario académico activo',
          evaluar: (ctx) => ctx.tipoHorario == ContextoRecomendacion.tipoAcademico,
          detalle: (ctx) =>
              'Horario académico activo (${ctx.horarioActivo?.rangoTexto ?? 'sin rango'})',
        ),
        CondicionRegla(
          descripcion: 'Hay aplicaciones distractoras con uso registrado',
          evaluar: (ctx) => ctx.appDistractoraPrincipal != null,
          detalle: (ctx) {
            final app = ctx.appDistractoraPrincipal;
            return app == null
                ? 'Sin aplicaciones distractoras'
                : 'App distractora principal: ${app.nombreApp}';
          },
        ),
        CondicionRegla(
          descripcion: 'El tiempo distractor supera el umbral',
          evaluar: (ctx) => ctx.minutosAppsDistractoras > c.minutosDistractor,
          detalle: (ctx) =>
              'Tiempo en distractoras: ${ctx.minutosAppsDistractoras} min '
              '(umbral ${c.minutosDistractor} min)',
        ),
      ],
      tipo: 'pausa',
      titulo: (_) => '📚 Distracción durante el estudio',
      mensaje: (ctx) {
        final app = ctx.appDistractoraPrincipal;
        final detalleApp = app == null
            ? ''
            : ' (${app.nombreApp}: ${app.tiempoUsoMinutos} min)';
        return 'Estás en horario académico y acumulas '
            '${ctx.minutosAppsDistractoras} min en aplicaciones distractoras'
            '$detalleApp. Considera silenciar notificaciones y volver al estudio.';
      },
      severidad: SeveridadRecomendacion.advertencia,
      cooldown: c.cooldownDistractor,
      ambito: AmbitoCooldown.horario,
    );

// --- R2: Uso distractor durante el trabajo ---

ReglaRecomendacion _r2(ConfiguracionMotor c) => ReglaRecomendacion(
      id: 'R2',
      nombre: 'Uso distractor durante el trabajo',
      prioridad: PrioridadRegla.distractorContextual,
      condiciones: [
        CondicionRegla(
          descripcion: 'Hay un horario laboral activo',
          evaluar: (ctx) => ctx.tipoHorario == ContextoRecomendacion.tipoLaboral,
          detalle: (ctx) =>
              'Horario laboral activo (${ctx.horarioActivo?.rangoTexto ?? 'sin rango'})',
        ),
        CondicionRegla(
          descripcion: 'Una aplicación distractora supera el umbral',
          evaluar: (ctx) {
            final app = ctx.appDistractoraPrincipal;
            return app != null && app.tiempoUsoMinutos > c.minutosDistractor;
          },
          detalle: (ctx) {
            final app = ctx.appDistractoraPrincipal;
            if (app == null) return 'Sin aplicaciones distractoras';
            return '${app.nombreApp}: ${app.tiempoUsoMinutos} min '
                '(umbral ${c.minutosDistractor} min)';
          },
        ),
      ],
      tipo: 'pausa',
      titulo: (_) => '💼 Distracción durante el trabajo',
      mensaje: (ctx) {
        final app = ctx.appDistractoraPrincipal;
        final nombre = app?.nombreApp ?? 'una aplicación distractora';
        final minutos = app?.tiempoUsoMinutos ?? 0;
        return 'En horario laboral has dedicado $minutos min a $nombre. '
            'Considera una pausa consciente de 15 minutos y retomar el trabajo.';
      },
      severidad: SeveridadRecomendacion.advertencia,
      cooldown: c.cooldownDistractor,
      ambito: AmbitoCooldown.horario,
    );

// --- R3: Tarea prioritaria durante un periodo de distracción ---

ReglaRecomendacion _r3(ConfiguracionMotor c) => ReglaRecomendacion(
      id: 'R3',
      nombre: 'Tarea prioritaria durante un periodo de distracción',
      prioridad: PrioridadRegla.tareaPrioritariaEnDistraccion,
      condiciones: [
        CondicionRegla(
          descripcion: 'Hay una tarea planificada activa de prioridad alta',
          evaluar: (ctx) => ctx.hayTareaActivaPrioritaria,
          detalle: (ctx) {
            final tarea = ctx.tareaActiva;
            if (tarea == null) return 'Sin tarea planificada activa';
            return 'Tarea activa de prioridad alta: "${tarea.titulo}"';
          },
        ),
        CondicionRegla(
          descripcion: 'Existe uso distractor en el mismo periodo',
          evaluar: (ctx) => ctx.minutosAppsDistractoras > 0,
          detalle: (ctx) =>
              'Uso distractor en el periodo: ${ctx.minutosAppsDistractoras} min',
        ),
      ],
      tipo: 'sugerencia_foco',
      titulo: (_) => '🎯 Tarea prioritaria frente a distracciones',
      mensaje: (ctx) {
        final tarea = ctx.tareaActiva;
        final nombre = tarea?.titulo ?? 'tu tarea prioritaria';
        return 'Tienes planificada "$nombre" (prioridad alta) y llevas '
            '${ctx.minutosAppsDistractoras} min en aplicaciones distractoras '
            'en ese periodo. Dedica 25 minutos con la técnica Pomodoro.';
      },
      severidad: SeveridadRecomendacion.advertencia,
      cooldown: c.cooldownDistractor,
    );

// --- R4: Exceso de tareas pendientes ---

ReglaRecomendacion _r4(ConfiguracionMotor c) => ReglaRecomendacion(
      id: 'R4',
      nombre: 'Exceso de tareas pendientes',
      prioridad: PrioridadRegla.tareasPendientes,
      condiciones: [
        CondicionRegla(
          descripcion: 'Hay más tareas pendientes que el límite',
          evaluar: (ctx) => ctx.tareasPendientesTotal > c.tareasPendientesLimite,
          detalle: (ctx) =>
              'Tareas pendientes: ${ctx.tareasPendientesTotal} '
              '(límite ${c.tareasPendientesLimite})',
        ),
      ],
      tipo: 'sugerencia_foco',
      titulo: (_) => '📋 Muchas tareas pendientes',
      mensaje: (ctx) =>
          'Tienes ${ctx.tareasPendientesTotal} tareas pendientes '
          '(más de ${c.tareasPendientesLimite}). Te sugerimos priorizar las de '
          'alta prioridad y dividirlas en bloques.',
      severidad: SeveridadRecomendacion.sugerencia,
      cooldown: c.cooldownTareas,
    );

// --- R5: Alto uso acumulado de pantalla ---

ReglaRecomendacion _r5(ConfiguracionMotor c) => ReglaRecomendacion(
      id: 'R5',
      nombre: 'Alto uso acumulado de pantalla',
      prioridad: PrioridadRegla.altoUso,
      condiciones: [
        CondicionRegla(
          descripcion: 'El uso de pantalla del día supera el umbral',
          evaluar: (ctx) =>
              ctx.hayDatosUsoPantalla &&
              ctx.tiempoTotalPantallaMinutos > c.minutosAltoUsoDiario,
          detalle: (ctx) =>
              'Uso de pantalla hoy: ${ctx.tiempoTotalPantallaMinutos} min '
              '(umbral ${c.minutosAltoUsoDiario} min)',
        ),
      ],
      tipo: 'alerta_uso',
      titulo: (_) => '⏱️ Alto uso de pantalla',
      mensaje: (ctx) =>
          'Hoy has usado tu dispositivo ${ctx.tiempoTotalPantallaMinutos} minutos '
          '(más de ${c.minutosAltoUsoDiario}). Te recomendamos tomar un descanso.',
      severidad: SeveridadRecomendacion.advertencia,
      cooldown: c.cooldownUso,
      ambito: AmbitoCooldown.dia,
    );

// --- R6: Combinación de carga de tareas y uso de pantalla ---

ReglaRecomendacion _r6(ConfiguracionMotor c) => ReglaRecomendacion(
      id: 'R6',
      nombre: 'Carga combinada de tareas y pantalla',
      prioridad: PrioridadRegla.cargaCombinada,
      condiciones: [
        CondicionRegla(
          descripcion: 'Hay una carga elevada de tareas pendientes',
          evaluar: (ctx) => ctx.tareasPendientesTotal > c.tareasCargaAltaLimite,
          detalle: (ctx) =>
              'Tareas pendientes: ${ctx.tareasPendientesTotal} '
              '(umbral ${c.tareasCargaAltaLimite})',
        ),
        CondicionRegla(
          descripcion: 'Hay un uso de pantalla elevado',
          evaluar: (ctx) =>
              ctx.hayDatosUsoPantalla &&
              ctx.tiempoTotalPantallaMinutos > c.minutosCargaAltaUso,
          detalle: (ctx) =>
              'Uso de pantalla hoy: ${ctx.tiempoTotalPantallaMinutos} min '
              '(umbral ${c.minutosCargaAltaUso} min)',
        ),
      ],
      tipo: 'descanso',
      titulo: (_) => '🧘 Modo enfoque',
      mensaje: (ctx) =>
          'Detectamos ${ctx.tareasPendientesTotal} tareas pendientes y '
          '${ctx.tiempoTotalPantallaMinutos} min de pantalla. Te recomendamos '
          'silenciar notificaciones y planificar un bloque de enfoque de 1 hora.',
      severidad: SeveridadRecomendacion.advertencia,
      cooldown: c.cooldownUso,
    );

// --- R7: Uso nocturno excesivo ---

ReglaRecomendacion _r7(ConfiguracionMotor c) => ReglaRecomendacion(
      id: 'R7',
      nombre: 'Uso nocturno excesivo',
      prioridad: PrioridadRegla.usoNocturno,
      condiciones: [
        CondicionRegla(
          descripcion: 'El uso en el rango nocturno supera el umbral',
          evaluar: (ctx) => ctx.minutosUsoNocturno > c.minutosUsoNocturno,
          detalle: (ctx) =>
              'Uso nocturno: ${ctx.minutosUsoNocturno} min '
              '(umbral ${c.minutosUsoNocturno} min)',
        ),
      ],
      tipo: 'descanso',
      titulo: (_) => '🌙 Uso nocturno elevado',
      mensaje: (ctx) =>
          'Usas el teléfono ${ctx.minutosUsoNocturno} min entre las '
          '${_rangoNocturnoTexto(c)} (umbral ${c.minutosUsoNocturno} min). '
          'Reducir el uso nocturno mejora la calidad del sueño.',
      severidad: SeveridadRecomendacion.advertencia,
      cooldown: c.cooldownNocturno,
    );

// --- R8: Pico de uso dentro de un horario configurado ---

ReglaRecomendacion _r8(ConfiguracionMotor c) => ReglaRecomendacion(
      id: 'R8',
      nombre: 'Pico de uso dentro de un horario configurado',
      prioridad: PrioridadRegla.picoEnHorario,
      condiciones: [
        CondicionRegla(
          descripcion: 'Existe un pico de uso registrado',
          evaluar: (ctx) => ctx.minutosPico > 0,
          detalle: (ctx) =>
              'Pico de uso a las ${_horaTexto(ctx.horaPico)}: ${ctx.minutosPico} min',
        ),
        CondicionRegla(
          descripcion: 'El pico cae dentro de un horario configurado',
          evaluar: (ctx) => ctx.horarioDelPico != null,
          detalle: (ctx) {
            final horario = ctx.horarioDelPico;
            if (horario == null) return 'El pico cae fuera de tus horarios';
            return 'Coincide con el horario ${horario.tipoTexto.toLowerCase()} '
                '(${horario.rangoTexto})';
          },
        ),
      ],
      tipo: 'sugerencia_foco',
      titulo: (ctx) {
        final horario = ctx.horarioDelPico;
        return horario != null && horario.tipo == ContextoRecomendacion.tipoLaboral
            ? '💼 Pico de uso en horario laboral'
            : '📚 Pico de uso en horario académico';
      },
      mensaje: (ctx) {
        final horario = ctx.horarioDelPico;
        final tipo = horario?.tipoTexto.toLowerCase() ?? 'configurado';
        final rango = horario?.rangoTexto ?? 'sin rango';
        return 'Tu mayor uso de pantalla (${ctx.minutosPico} min) ocurre '
            'alrededor de las ${_horaTexto(ctx.horaPico)}, dentro de tu horario '
            '$tipo ($rango). Considera limitar el teléfono en ese bloque.';
      },
      severidad: SeveridadRecomendacion.sugerencia,
      cooldown: c.cooldownPico,
    );
