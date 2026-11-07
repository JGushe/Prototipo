import '../models/horario.dart';
import '../models/intervalo_uso.dart';
import '../database/database_helper.dart';
import 'monitoreo_uso_horarios_service.dart';

/// Resultado del análisis de uso por hora y su cruce con los horarios.
class AnalisisHorario {
  final Map<int, int> usoPorHora; // hora (0-23) -> minutos acumulados
  final int horaPico; // hora con más uso
  final int minutosPico;
  final List<Horario> horarios;
  final List<String> sugerencias;

  /// Horario configurado que contiene el momento real del pico, o null si el
  /// pico ocurrió fuera de los horarios configurados.
  final Horario? horarioPico;

  AnalisisHorario({
    required this.usoPorHora,
    required this.horaPico,
    required this.minutosPico,
    required this.horarios,
    required this.sugerencias,
    this.horarioPico,
  });

  /// Formatea una hora (0-23) a texto legible (ej: "14:00").
  static String formatearHora(int hora) {
    final h = hora.toString().padLeft(2, '0');
    return '$h:00';
  }

  /// Devuelve el rango legible del pico (ej: "14:00 - 15:00").
  String get picoTexto =>
      '${formatearHora(horaPico)} - ${formatearHora(horaPico + 1)}';
}

/// Duraciones sin solapes, repartidas por hora civil.
class UsoPorHora {
  final Map<int, Duration> duraciones;
  final Map<int, DateTime> momentoRepresentativo;

  UsoPorHora(this.duraciones, this.momentoRepresentativo);

  Map<int, int> get minutos =>
      duraciones.map((hora, duracion) => MapEntry(hora, duracion.inMinutes));

  int minutosEntre(int desde, int hasta) {
    var total = Duration.zero;
    for (var hora = desde % 24; hora != hasta % 24; hora = (hora + 1) % 24) {
      total += duraciones[hora] ?? Duration.zero;
    }
    return total.inMinutes;
  }
}

class AnalisisHorarioService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Devuelve el horario configurado que contiene [momento], o null.
  ///
  /// Usa [Horario.contieneDateTime], por lo que considera día de la semana,
  /// hora, minutos y horarios que cruzan medianoche. Si [horarios] se omite,
  /// se leen de la base de datos.
  Future<Horario?> horarioActivoEn(DateTime momento,
      {List<Horario>? horarios}) async {
    final lista = horarios ?? await _db.obtenerHorarios(soloActivos: true);
    for (final h in lista) {
      if (h.contieneDateTime(momento)) return h;
    }
    return null;
  }

  static UsoPorHora repartirPorHora(
    Iterable<IntervaloUso> intervalos,
    VentanaTiempo ventana,
  ) {
    final duraciones = <int, Duration>{};
    final momentos = <int, DateTime>{};
    final tramos = VentanaTiempo.unir([
      for (final intervalo in intervalos)
        if (intervalo.ventana.interseccion(ventana) case final tramo?) tramo,
    ]);
    for (final tramo in tramos) {
      var inicio = tramo.inicio;
      while (inicio.isBefore(tramo.fin)) {
        final hastaSiguienteHora = const Duration(hours: 1) -
            Duration(
              minutes: inicio.minute,
              seconds: inicio.second,
              milliseconds: inicio.millisecond,
              microseconds: inicio.microsecond,
            );
        final siguienteHora = inicio.add(hastaSiguienteHora);
        final fin =
            siguienteHora.isBefore(tramo.fin) ? siguienteHora : tramo.fin;
        final hora = inicio.hour;
        duraciones[hora] =
            (duraciones[hora] ?? Duration.zero) + fin.difference(inicio);
        momentos[hora] = inicio;
        inicio = fin;
      }
    }
    return UsoPorHora(duraciones, momentos);
  }

  /// Analiza el uso por hora y lo cruza con los horarios configurados,
  /// generando sugerencias de mejora.
  Future<AnalisisHorario> analizar({int dias = 7, DateTime? ahora}) async {
    final corte = ahora ?? DateTime.now();
    final ventana = VentanaTiempo(corte.subtract(Duration(days: dias)), corte);
    TrazaUso? traza;
    try {
      traza = await MonitoreoUsoHorariosService().obtenerTraza(
        desde: ventana.inicio,
        hasta: ventana.fin,
      );
    } catch (_) {
      // La ausencia de eventos queda sin muestra.
    }
    final calculado = repartirPorHora(traza?.intervalos ?? [], ventana);
    final usoPorHora = {
      if (calculado.duraciones.isNotEmpty)
        for (var hora = 0; hora < 24; hora++) hora: 0,
      ...calculado.minutos,
    };
    final horarios = await _db.obtenerHorarios(soloActivos: true);

    // Encontrar la hora pico (la de mayor uso)
    int horaPico = 0;
    int minutosPico = 0;
    usoPorHora.forEach((hora, minutos) {
      if (minutos > minutosPico) {
        minutosPico = minutos;
        horaPico = hora;
      }
    });

    final sugerencias = <String>[];
    Horario? horarioPico;

    if (minutosPico == 0) {
      sugerencias.add(
        'Aún no hay suficientes datos de uso. Usa el teléfono unos días '
        'para obtener un análisis.',
      );
    } else {
      // Momento real del pico: permite cruzar con los horarios considerando
      // día de la semana, hora y minutos (no solo la hora entera).
      final momentoPico = calculado.momentoRepresentativo[horaPico]!;
      horarioPico = await horarioActivoEn(momentoPico, horarios: horarios);

      if (horarioPico == null) {
        sugerencias.add(
          'Tu mayor uso es de ${AnalisisHorario.formatearHora(horaPico)} a '
          '${AnalisisHorario.formatearHora(horaPico + 1)} '
          '($minutosPico min). Está fuera de tus horarios, es tu tiempo libre.',
        );
      } else if (horarioPico.tipo == 'laboral') {
        sugerencias.add(
          '⚠️ Tu pico de uso es de ${AnalisisHorario.formatearHora(horaPico)} a '
          '${AnalisisHorario.formatearHora(horaPico + 1)} ($minutosPico min), '
          'que coincide con tu horario LABORAL (${horarioPico.rangoTexto}). '
          'Considera activar modo enfoque o silenciar notificaciones en ese bloque.',
        );
      } else {
        sugerencias.add(
          '📚 Tu pico de uso es de ${AnalisisHorario.formatearHora(horaPico)} a '
          '${AnalisisHorario.formatearHora(horaPico + 1)} ($minutosPico min), '
          'que coincide con tu horario ACADÉMICO (${horarioPico.rangoTexto}). '
          'Intenta dejar el teléfono en otra habitación mientras estudias.',
        );
      }

      // Regla adicional: uso nocturno excesivo
      final usoNocturno = repartirPorHora(traza?.interactivos ?? [], ventana)
          .minutosEntre(22, 6);
      if (usoNocturno > 60) {
        sugerencias.add(
          '🌙 Usas el teléfono $usoNocturno min entre las 22:00 y las 06:00. '
          'Reducir el uso nocturno mejora la calidad del sueño.',
        );
      }
    }

    return AnalisisHorario(
      usoPorHora: usoPorHora,
      horaPico: horaPico,
      minutosPico: minutosPico,
      horarios: horarios,
      sugerencias: sugerencias,
      horarioPico: horarioPico,
    );
  }
}
