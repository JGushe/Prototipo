// Pruebas del modelo ContextoRecomendacion (Etapas 4 y 5).
//
// Verifican la clasificación configurable de aplicaciones distractoras y los
// campos derivados del contexto. Son pruebas de Dart puro: no necesitan base de
// datos ni el plugin de UsageStats.

import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/models/contexto_recomendacion.dart';
import 'package:prototipo_tesis/models/horario.dart';
import 'package:prototipo_tesis/models/tarea.dart';
import 'package:prototipo_tesis/models/uso_pantalla.dart';

AppUso app(String paquete, int minutos, {String? nombre}) => AppUso(
      nombrePaquete: paquete,
      nombreApp: nombre ?? paquete,
      tiempoUsoMinutos: minutos,
      numeroAperturas: 1,
    );

final momento = DateTime(2026, 8, 24, 10);

ContextoRecomendacion contexto({
  Horario? horarioActivo,
  List<Horario> horarios = const [],
  Tarea? tareaActiva,
  List<Tarea> tareasPendientes = const [],
  List<Tarea> tareasAlta = const [],
  int minutosPantalla = 0,
  bool hayDatosUso = false,
  List<AppUso> apps = const [],
  Map<int, int> usoPorHora = const {},
  int minutosNocturno = 0,
}) =>
    ContextoRecomendacion(
      momento: momento,
      horarios: horarios,
      horarioActivo: horarioActivo,
      tareaActiva: tareaActiva,
      tareasPendientes: tareasPendientes,
      tareasAltaPrioridadPendientes: tareasAlta,
      tiempoTotalPantallaMinutos: minutosPantalla,
      hayDatosUsoPantalla: hayDatosUso,
      appsMasUtilizadas: apps,
      usoPorHora: usoPorHora,
      minutosUsoNocturno: minutosNocturno,
    );

void main() {
  group('Contexto vacío', () {
    final vacio = contexto();

    test('sin datos el contexto es coherente', () {
      expect(vacio.tipoHorario, ContextoRecomendacion.tipoNinguno);
      expect(vacio.tipoHorarioTexto, 'Ninguno');
      expect(vacio.hayHorarioActivo, isFalse);
      expect(vacio.hayTareaActiva, isFalse);
      expect(vacio.hayTareaActivaPrioritaria, isFalse);
      expect(vacio.tareasPendientesTotal, 0);
      expect(vacio.tiempoTotalPantallaMinutos, 0);
      expect(vacio.hayDatosUsoPantalla, isFalse);
      expect(vacio.hayAppsMasUtilizadas, isFalse);
      expect(vacio.minutosPico, 0);
      expect(vacio.horaPico, 0);
      expect(vacio.horarioDelPico, isNull);
    });

    test('sin aplicaciones no hay distractoras', () {
      expect(vacio.appsDistractoras, isEmpty);
      expect(vacio.minutosAppsDistractoras, 0);
      expect(vacio.appDistractoraPrincipal, isNull);
      expect(vacio.hayAppsDistractoras, isFalse);
    });
  });

  group('Clasificación de paquetes distractores', () {
    final ctx = contexto();

    test('coincidencia exacta', () {
      expect(ctx.esPaqueteDistractor('com.instagram'), isTrue);
      expect(ctx.esPaqueteDistractor('com.whatsapp'), isTrue);
    });

    test('coincidencia por prefijo', () {
      expect(ctx.esPaqueteDistractor('com.instagram.android'), isTrue);
      expect(ctx.esPaqueteDistractor('com.facebook.katana'), isTrue);
      expect(ctx.esPaqueteDistractor('com.zhiliaoapp.musically'), isTrue);
    });

    test('no distingue mayúsculas', () {
      expect(ctx.esPaqueteDistractor('COM.INSTAGRAM'), isTrue);
    });

    test('un paquete no relacionado no es distractor', () {
      expect(ctx.esPaqueteDistractor('com.android.chrome'), isFalse);
      expect(ctx.esPaqueteDistractor('org.mozilla.firefox'), isFalse);
      // El prefijo debe terminar en punto: 'com.instagramx' no coincide.
      expect(ctx.esPaqueteDistractor('com.instagramx'), isFalse);
    });

    test('la clasificación es configurable', () {
      final personalizado = ContextoRecomendacion(
        momento: momento,
        paquetesDistractores: const ['com.ejemplo.juego'],
        appsMasUtilizadas: [
          app('com.ejemplo.juego', 40),
          app('com.instagram', 40),
        ],
      );

      expect(personalizado.esPaqueteDistractor('com.ejemplo.juego'), isTrue);
      // Instagram deja de ser distractora con esta clasificación.
      expect(personalizado.esPaqueteDistractor('com.instagram'), isFalse);
      expect(personalizado.minutosAppsDistractoras, 40);
      expect(personalizado.appDistractoraPrincipal?.nombrePaquete, 'com.ejemplo.juego');
    });

    test('clasificarDistractor es estático y reutilizable', () {
      expect(
        ContextoRecomendacion.clasificarDistractor('com.instagram.android',
            ContextoRecomendacion.paquetesDistractoresPorDefecto),
        isTrue,
      );
      expect(
        ContextoRecomendacion.clasificarDistractor(
            'com.android.chrome', const []),
        isFalse,
      );
    });
  });

  group('Derivados de las aplicaciones', () {
    final ctx = contexto(apps: [
      app('com.android.chrome', 50, nombre: 'Chrome'),
      app('com.instagram', 40, nombre: 'Instagram'),
      app('com.whatsapp', 15, nombre: 'WhatsApp'),
      app('com.spotify.music', 10, nombre: 'Spotify'),
    ]);

    test('appsDistractoras solo incluye las clasificadas', () {
      final paquetes = ctx.appsDistractoras.map((a) => a.nombrePaquete).toList();
      expect(paquetes, ['com.instagram', 'com.whatsapp']);
    });

    test('minutosAppsDistractoras suma solo las distractoras', () {
      expect(ctx.minutosAppsDistractoras, 55); // 40 + 15
    });

    test('appDistractoraPrincipal es la de mayor tiempo entre las distractoras', () {
      expect(ctx.appDistractoraPrincipal?.nombrePaquete, 'com.instagram');
      expect(ctx.appDistractoraPrincipal?.tiempoUsoMinutos, 40);
      expect(ctx.hayAppsDistractoras, isTrue);
    });

    test('sin distractoras no hay principal aunque haya apps', () {
      final soloNeutras = contexto(apps: [app('com.android.chrome', 50)]);
      expect(soloNeutras.hayAppsMasUtilizadas, isTrue);
      expect(soloNeutras.appDistractoraPrincipal, isNull);
      expect(soloNeutras.minutosAppsDistractoras, 0);
      expect(soloNeutras.hayAppsDistractoras, isFalse);
    });
  });

  group('Derivados del uso por hora', () {
    test('horaPico y minutosPico señalan la hora de mayor uso', () {
      final ctx = contexto(usoPorHora: {9: 20, 14: 55, 20: 30});
      expect(ctx.horaPico, 14);
      expect(ctx.minutosPico, 55);
    });

    test('horarioDelPico encuentra el horario que contiene el pico', () {
      final laboral = Horario(tipo: 'laboral', horaInicio: 8, horaFin: 16);
      final ctx = contexto(horarios: [laboral], usoPorHora: {14: 55});
      expect(ctx.horarioDelPico?.tipo, 'laboral');
    });

    test('sin pico dentro de los horarios no hay horarioDelPico', () {
      final laboral = Horario(tipo: 'laboral', horaInicio: 8, horaFin: 16);
      final ctx = contexto(horarios: [laboral], usoPorHora: {21: 55});
      expect(ctx.minutosPico, 55);
      expect(ctx.horarioDelPico, isNull);
    });
  });

  group('Horario y tarea activos', () {
    test('tipoHorario refleja el horario activo', () {
      final laboral = contexto(
        horarioActivo: Horario(tipo: 'laboral', horaInicio: 8, horaFin: 16),
      );
      expect(laboral.tipoHorario, ContextoRecomendacion.tipoLaboral);
      expect(laboral.tipoHorarioTexto, 'Laboral');
      expect(laboral.hayHorarioActivo, isTrue);

      final academico = contexto(
        horarioActivo: Horario(tipo: 'academico', horaInicio: 19, horaFin: 21),
      );
      expect(academico.tipoHorario, ContextoRecomendacion.tipoAcademico);
      expect(academico.tipoHorarioTexto, 'Académico');
    });

    test('tareaActiva y conteos de tareas', () {
      final ctx = contexto(
        tareaActiva: Tarea(
          titulo: 'Estudiar',
          fechaCreacion: momento,
          prioridad: 'alta',
        ),
        tareasPendientes: [
          Tarea(titulo: 'A', fechaCreacion: momento),
          Tarea(titulo: 'B', fechaCreacion: momento),
          Tarea(titulo: 'C', fechaCreacion: momento, prioridad: 'alta'),
        ],
        tareasAlta: [
          Tarea(titulo: 'C', fechaCreacion: momento, prioridad: 'alta'),
        ],
      );

      expect(ctx.hayTareaActiva, isTrue);
      expect(ctx.hayTareaActivaPrioritaria, isTrue);
      expect(ctx.tareaActiva?.titulo, 'Estudiar');
      expect(ctx.tareasPendientesTotal, 3);
      expect(ctx.tareasAltaPrioridadTotal, 1);
    });
  });
}
