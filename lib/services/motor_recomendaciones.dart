import '../models/contexto_recomendacion.dart';
import '../models/recomendacion.dart';
import '../database/database_helper.dart';
import 'analisis_horario_service.dart';
import 'contexto_recomendacion_service.dart';

class MotorRecomendaciones {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final AnalisisHorarioService _analisis = AnalisisHorarioService();
  final ContextoRecomendacionService _contextoService;

  /// [contextoService] es inyectable para facilitar pruebas; por defecto se usa
  /// la implementación real, consistente con el resto de la arquitectura.
  MotorRecomendaciones({ContextoRecomendacionService? contextoService})
      : _contextoService = contextoService ?? ContextoRecomendacionService();

  /// Evalúa todas las reglas y genera recomendaciones.
  ///
  /// El acceso a datos se concentra en [ContextoRecomendacion]: si se recibe
  /// [contexto] ya construido se reutiliza y no se vuelven a consultar las
  /// fuentes; en caso contrario se construye uno nuevo.
  Future<List<Recomendacion>> evaluarYGenerar({ContextoRecomendacion? contexto}) async {
    final recomendaciones = <Recomendacion>[];
    final ctx = contexto ?? await _contextoService.construir();

    // Datos del contexto (sin consultas adicionales).
    final tareas = ctx.tareasPendientes;
    final topApps = ctx.appsMasUtilizadas;
    final minutosUsoHoy =
        ctx.hayDatosUsoPantalla ? ctx.tiempoTotalPantallaMinutos : null;

    // REGLA 1: Si el uso total de pantalla supera 4 horas
    if (minutosUsoHoy != null && minutosUsoHoy > 240) {
      recomendaciones.add(Recomendacion(
        fecha: DateTime.now(),
        tipo: 'alerta_uso',
        titulo: '⏱️ Alto uso de pantalla',
        mensaje: 'Hoy has usado tu dispositivo $minutosUsoHoy minutos. '
            'Te recomendamos tomar un descanso.',
      ));
    }

    // REGLA 2: Si hay muchas tareas pendientes (> 5)
    if (tareas.length > 5) {
      recomendaciones.add(Recomendacion(
        fecha: DateTime.now(),
        tipo: 'sugerencia_foco',
        titulo: '📋 Muchas tareas pendientes',
        mensaje: 'Tienes ${tareas.length} tareas pendientes. '
            'Te sugerimos priorizar las de alta prioridad y dividirlas en bloques.',
      ));
    }

    // REGLA 3: Si una red social supera 30 minutos
    final redesSociales = ['com.facebook', 'com.instagram', 'com.twitter',
                           'com.whatsapp', 'com.tiktok', 'com.snapchat'];
    for (final app in topApps) {
      if (redesSociales.contains(app.nombrePaquete) && app.tiempoUsoMinutos > 30) {
        recomendaciones.add(Recomendacion(
          fecha: DateTime.now(),
          tipo: 'pausa',
          titulo: '📵 Pausa de redes sociales',
          mensaje: 'Has pasado ${app.tiempoUsoMinutos} minutos en ${app.nombreApp}. '
              'Considera tomar un descanso de 15 minutos.',
        ));
        break;
      }
    }

    // REGLA 4: Tareas urgentes sin completar
    final tareasUrgentes = ctx.tareasAltaPrioridadPendientes;
    if (tareasUrgentes.isNotEmpty) {
      recomendaciones.add(Recomendacion(
        fecha: DateTime.now(),
        tipo: 'sugerencia_foco',
        titulo: '🔥 Tareas urgentes',
        mensaje: 'Tienes ${tareasUrgentes.length} tarea(s) de alta prioridad sin completar. '
            'Dedica 25 minutos con la técnica Pomodoro.',
      ));
    }

    // REGLA 5: Combinación: mucho uso + muchas tareas = sobrecarga
    if (minutosUsoHoy != null && minutosUsoHoy > 180 && tareas.length > 3) {
      recomendaciones.add(Recomendacion(
        fecha: DateTime.now(),
        tipo: 'descanso',
        titulo: '🧘 Modo enfoque',
        mensaje: 'Detectamos alta carga de tareas y mucho uso de pantalla. '
            'Te recomendamos silenciar notificaciones y enfocarte 1 hora.',
      ));
    }

    // REGLA 6: Pico de uso dentro del horario laboral o académico
    final horarios = ctx.horarios;
    if (horarios.isNotEmpty) {
      final analisis = await _analisis.analizar(dias: 7);
      if (analisis.minutosPico > 0) {
        final horaPico = analisis.horaPico;
        for (final horario in horarios) {
          if (horario.contieneHora(horaPico)) {
            recomendaciones.add(Recomendacion(
              fecha: DateTime.now(),
              tipo: 'sugerencia_foco',
              titulo: horario.tipo == 'laboral'
                  ? '💼 Pico de uso en horario laboral'
                  : '📚 Pico de uso en horario académico',
              mensaje: 'Tu mayor uso de pantalla (${analisis.minutosPico} min) '
                  'ocurre alrededor de las ${AnalisisHorario.formatearHora(horaPico)}, '
                  'dentro de tu horario ${horario.tipoTexto.toLowerCase()} '
                  '(${horario.rangoTexto}). Considera limitar el teléfono en ese bloque.',
            ));
            break;
          }
        }
      }
    }

    // Guardar recomendaciones en la BD
    for (final rec in recomendaciones) {
      await _db.insertarRecomendacion(rec);
    }

    return recomendaciones;
  }
}
