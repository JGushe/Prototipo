import 'package:usage_stats/usage_stats.dart';
import '../models/horario.dart';
import '../database/database_helper.dart';

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

/// Uso por hora junto con un momento real representativo de cada hora.
class _UsoPorHoraCalculado {
  final Map<int, int> minutos; // hora (0-23) -> minutos
  final Map<int, DateTime> momentoRepresentativo; // hora (0-23) -> DateTime

  _UsoPorHoraCalculado(this.minutos, this.momentoRepresentativo);
}

class AnalisisHorarioService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  // Constantes de tipos de evento de Android UsageEvents.
  static const int _activityResumed = 1;
  static const int _activityPaused = 2;

  /// Devuelve el horario configurado que contiene [momento], o null.
  ///
  /// Usa [Horario.contieneDateTime], por lo que considera día de la semana,
  /// hora, minutos y horarios que cruzan medianoche. Si [horarios] se omite,
  /// se leen de la base de datos.
  Future<Horario?> horarioActivoEn(DateTime momento, {List<Horario>? horarios}) async {
    final lista = horarios ?? await _db.obtenerHorarios(soloActivos: true);
    for (final h in lista) {
      if (h.contieneDateTime(momento)) return h;
    }
    return null;
  }

  /// Reconstruye el uso de pantalla por hora del día a partir de los eventos
  /// de UsageStats (queryEvents), acumulando los últimos [dias] días.
  Future<Map<int, int>> obtenerUsoPorHora({int dias = 7}) async {
    final calculado = await _calcularUsoPorHora(dias: dias);
    return calculado.minutos;
  }

  /// Igual que [obtenerUsoPorHora], pero además devuelve para cada hora el
  /// último momento real (DateTime) en que se registró uso en esa hora. Ese
  /// momento es el que permite cruzar el pico con los horarios usando día y
  /// minutos, en lugar de solo la hora entera.
  Future<_UsoPorHoraCalculado> _calcularUsoPorHora({int dias = 7}) async {
    final now = DateTime.now();
    final inicio = now.subtract(Duration(days: dias));

    final usoPorHora = <int, int>{};
    for (int i = 0; i < 24; i++) {
      usoPorHora[i] = 0;
    }
    final momentoRepresentativo = <int, DateTime>{};

    try {
      final eventos = await UsageStats.queryEvents(inicio, now);

      // Ordenar por marca de tiempo
      eventos.sort((a, b) {
        final ta = a.timeStampDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = b.timeStampDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        return ta.compareTo(tb);
      });

      // Emparejar eventos RESUME -> PAUSE para calcular tiempo activo.
      // Guarda la hora de inicio por cada paquete.
      final sesionesActivas = <String, DateTime>{};

      for (final e in eventos) {
        final ts = e.timeStampDate;
        if (ts == null) continue;
        final tipo = e.eventTypeValue;
        final paquete = e.packageName ?? '';

        if (tipo == _activityResumed) {
          // La app pasó a primer plano
          sesionesActivas[paquete] = ts;
        } else if (tipo == _activityPaused && sesionesActivas.containsKey(paquete)) {
          // La app pasó a segundo plano: calcular duración
          final inicioSesion = sesionesActivas.remove(paquete)!;
          final duracion = ts.difference(inicioSesion);
          final minutos = duracion.inSeconds ~/ 60;
          if (minutos > 0 && minutos <= 120) {
            final hora = inicioSesion.hour;
            usoPorHora[hora] = (usoPorHora[hora] ?? 0) + minutos;
            // El evento más reciente de esa hora es el representativo.
            momentoRepresentativo[hora] = inicioSesion;
          }
        }
      }
    } catch (_) {
      // Sin permiso o sin datos: devolver ceros.
    }

    return _UsoPorHoraCalculado(usoPorHora, momentoRepresentativo);
  }

  /// Analiza el uso por hora y lo cruza con los horarios configurados,
  /// generando sugerencias de mejora.
  Future<AnalisisHorario> analizar({int dias = 7}) async {
    final calculado = await _calcularUsoPorHora(dias: dias);
    final usoPorHora = calculado.minutos;
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
      final momentoPico = calculado.momentoRepresentativo[horaPico] ??
          _momentoDeHoyParaHora(horaPico);
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
      final usoNocturno = _sumarHoras(usoPorHora, 22, 6);
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

  /// Construye un DateTime de hoy a la hora indicada (respaldo defensivo
  /// cuando no hay un momento real registrado para esa hora).
  DateTime _momentoDeHoyParaHora(int hora) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hora);
  }

  /// Suma los minutos en un rango de horas (soporta cruce de medianoche).
  int _sumarHoras(Map<int, int> uso, int desde, int hasta) {
    int total = 0;
    int hora = desde;
    while (true) {
      total += uso[hora % 24] ?? 0;
      if (hora % 24 == hasta) break;
      hora++;
    }
    return total;
  }
}
