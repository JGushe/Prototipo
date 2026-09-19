// Pruebas del monitoreo de uso cruzado con horarios y tareas.
//
// Cubren los escenarios controlados del enunciado (A–E), el cruce de
// medianoche, los límites exactos, el emparejamiento de eventos y la coherencia
// con Horario.contieneDateTime. Son pruebas de Dart puro: no necesitan el
// plugin de UsageStats ni base de datos.

import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/models/contexto_recomendacion.dart';
import 'package:prototipo_tesis/models/horario.dart';
import 'package:prototipo_tesis/models/intervalo_uso.dart';
import 'package:prototipo_tesis/models/tarea.dart';
import 'package:prototipo_tesis/services/monitoreo_uso_horarios_service.dart';

const _todosLosDias = [1, 2, 3, 4, 5, 6, 7];

/// Lunes 24/08/2026 (verificado en las pruebas de fecha).
final _lunes = DateTime(2026, 8, 24);
final _martes = DateTime(2026, 8, 25);

Horario _laboral({
  int horaInicio = 8,
  int horaFin = 17,
  List<int> dias = _todosLosDias,
}) =>
    Horario(
      tipo: 'laboral',
      horaInicio: horaInicio,
      horaFin: horaFin,
      diasSemana: dias,
    );

IntervaloUso _uso(
  int h1,
  int m1,
  int h2,
  int m2, {
  DateTime? dia,
  String app = 'TikTok',
  String paquete = 'com.zhiliaoapp.musically',
}) {
  final d = dia ?? _lunes;
  return IntervaloUso(
    nombrePaquete: paquete,
    nombreApp: app,
    inicio: DateTime(d.year, d.month, d.day, h1, m1),
    fin: DateTime(d.year, d.month, d.day, h2, m2),
  );
}

IntervaloUso _usoEntre(DateTime inicio, DateTime fin, {String app = 'TikTok'}) =>
    IntervaloUso(
      nombrePaquete: 'com.zhiliaoapp.musically',
      nombreApp: app,
      inicio: inicio,
      fin: fin,
    );

Tarea _tareaPlanificada(int h1, int m1, int h2, int m2, {DateTime? dia}) {
  final d = dia ?? _lunes;
  return Tarea(
    titulo: 'Estudiar',
    fechaCreacion: d,
    prioridad: 'alta',
    fechaPlanificada: d,
    horaInicioPlanificada: '${h1.toString().padLeft(2, '0')}:${m1.toString().padLeft(2, '0')}',
    horaFinPlanificada: '${h2.toString().padLeft(2, '0')}:${m2.toString().padLeft(2, '0')}',
  );
}

int _min(Duration d) => d.inMinutes;

void main() {
  group('Escenarios del enunciado', () {
    test('A — uso dentro del horario: 09:00-09:15 → 15 min', () {
      final minutos = MonitoreoUsoHorariosService.duracionEnHorario(
          _uso(9, 0, 9, 15), _laboral());
      expect(_min(minutos), 15);
    });

    test('B — uso fuera del horario: 19:00-19:20 → 0 min', () {
      final minutos = MonitoreoUsoHorariosService.duracionEnHorario(
          _uso(19, 0, 19, 20), _laboral());
      expect(_min(minutos), 0);
    });

    test('C — cruce del inicio: 07:50-08:10 → 10 min', () {
      final minutos = MonitoreoUsoHorariosService.duracionEnHorario(
          _uso(7, 50, 8, 10), _laboral());
      expect(_min(minutos), 10);
    });

    test('D — cruce del final: 16:50-17:20 → 10 min', () {
      final minutos = MonitoreoUsoHorariosService.duracionEnHorario(
          _uso(16, 50, 17, 20), _laboral());
      expect(_min(minutos), 10);
    });

    test('E — tarea planificada dentro del horario', () {
      final horario = _laboral();
      final tarea = _tareaPlanificada(9, 0, 11, 0);
      final uso = _uso(9, 30, 9, 45);

      final enHorario =
          MonitoreoUsoHorariosService.duracionEnHorario(uso, horario);
      final enTarea = MonitoreoUsoHorariosService.duracionEnTarea(uso, tarea);

      expect(_min(enHorario), 15, reason: 'dentro del horario laboral');
      expect(_min(enTarea), 15, reason: 'dentro de la tarea planificada');

      final contexto = MonitoreoUsoHorariosService.analizar(
        intervalos: [uso],
        horarios: [horario],
        tareas: [tarea],
      ).single;

      expect(contexto.tieneUsoEnHorario, isTrue);
      expect(contexto.tieneUsoEnTarea, isTrue);
      expect(contexto.minutosEnHorarios, 15);
      expect(contexto.minutosEnTareas, 15);
    });

    test('F — el uso fuera de todo contexto no entra en ningún horario', () {
      final contexto = MonitoreoUsoHorariosService.analizar(
        intervalos: [_uso(19, 0, 19, 40)],
        horarios: [_laboral()],
        tareas: const [],
      ).single;

      expect(contexto.minutosEnHorarios, 0);
      expect(contexto.tieneUsoEnHorario, isFalse);
      expect(_min(contexto.fueraDeHorarios), 40);
    });
  });

  group('Límites exactos', () {
    test('el inicio del horario está incluido', () {
      expect(
        _min(MonitoreoUsoHorariosService.duracionEnHorario(
            _uso(8, 0, 8, 10), _laboral())),
        10,
      );
    });

    test('el fin del horario está excluido', () {
      expect(
        _min(MonitoreoUsoHorariosService.duracionEnHorario(
            _uso(17, 0, 17, 30), _laboral())),
        0,
      );
    });

    test('un minuto antes del fin sí cuenta', () {
      expect(
        _min(MonitoreoUsoHorariosService.duracionEnHorario(
            _uso(16, 59, 17, 30), _laboral())),
        1,
      );
    });

    test('un día no configurado no aporta minutos', () {
      final soloLunes = _laboral(dias: const [1]);
      expect(
        _min(MonitoreoUsoHorariosService.duracionEnHorario(
            _uso(10, 0, 11, 0, dia: _martes), soloLunes)),
        0,
      );
      expect(
        _min(MonitoreoUsoHorariosService.duracionEnHorario(
            _uso(10, 0, 11, 0, dia: _lunes), soloLunes)),
        60,
      );
    });
  });

  group('Horario que cruza medianoche (22:00-02:00)', () {
    final nocturno = Horario(
      tipo: 'laboral',
      horaInicio: 22,
      horaFin: 2,
      diasSemana: const [1], // empieza el lunes
    );

    test('el uso de la noche pertenece al bloque', () {
      final uso = _usoEntre(
        DateTime(2026, 8, 24, 23, 30),
        DateTime(2026, 8, 25, 0, 30),
      );
      expect(_min(MonitoreoUsoHorariosService.duracionEnHorario(uso, nocturno)), 60);
    });

    test('la madrugada del día siguiente pertenece al bloque del lunes', () {
      final uso = _usoEntre(
        DateTime(2026, 8, 25, 1, 0),
        DateTime(2026, 8, 25, 1, 45),
      );
      expect(_min(MonitoreoUsoHorariosService.duracionEnHorario(uso, nocturno)), 45);
    });

    test('la madrugada del miércoles ya no pertenece', () {
      final uso = _usoEntre(
        DateTime(2026, 8, 26, 1, 0),
        DateTime(2026, 8, 26, 1, 30),
      );
      expect(_min(MonitoreoUsoHorariosService.duracionEnHorario(uso, nocturno)), 0);
    });
  });

  group('Coherencia con contieneDateTime', () {
    test('un instante está en las ventanas si y solo si contieneDateTime', () {
      final horarios = [
        _laboral(dias: const [1]),
        Horario(tipo: 'academico', horaInicio: 20, horaFin: 22, diasSemana: const [1]),
        Horario(tipo: 'laboral', horaInicio: 22, horaFin: 2, diasSemana: const [2]),
      ];

      for (final horario in horarios) {
        final desde = DateTime(2026, 8, 23);
        final hasta = DateTime(2026, 8, 27);
        final ventanas = MonitoreoUsoHorariosService.ventanasDeHorario(
            horario, desde, hasta);

        var t = desde;
        while (t.isBefore(hasta)) {
          final enVentana = ventanas.any(
              (v) => !t.isBefore(v.inicio) && t.isBefore(v.fin));
          expect(
            enVentana,
            horario.contieneDateTime(t),
            reason: 'Discrepancia en $t para ${horario.tipo} '
                '${horario.rangoTexto} días ${horario.diasSemana}',
          );
          t = t.add(const Duration(minutes: 17));
        }
      }
    });
  });

  group('Sin doble conteo', () {
    test('dos horarios solapados no suman dos veces el mismo minuto', () {
      final a = _laboral();
      final b = _laboral();
      final contexto = MonitoreoUsoHorariosService.analizar(
        intervalos: [_uso(9, 0, 10, 0)],
        horarios: [a, b],
        tareas: const [],
      ).single;

      expect(contexto.minutosEnHorarios, 60);
      expect(contexto.minutosTotales, 60);
    });
  });

  group('Emparejamiento de eventos', () {
    test('RESUME + PAUSE producen un intervalo', () {
      final intervalos = MonitoreoUsoHorariosService.emparejarEventos([
        EventoUso(
            momento: DateTime(2026, 8, 24, 9, 0),
            nombrePaquete: 'p',
            esResume: true),
        EventoUso(
            momento: DateTime(2026, 8, 24, 9, 15),
            nombrePaquete: 'p',
            esResume: false),
      ]);

      expect(intervalos, hasLength(1));
      expect(_min(intervalos.single.duracion), 15);
    });

    test('un PAUSE sin RESUME previo se ignora', () {
      final intervalos = MonitoreoUsoHorariosService.emparejarEventos([
        EventoUso(
            momento: DateTime(2026, 8, 24, 9, 15),
            nombrePaquete: 'p',
            esResume: false),
      ]);
      expect(intervalos, isEmpty);
    });

    test('una sesión abierta se cierra con cierrePorDefecto', () {
      final intervalos = MonitoreoUsoHorariosService.emparejarEventos(
        [
          EventoUso(
              momento: DateTime(2026, 8, 24, 9, 0),
              nombrePaquete: 'p',
              esResume: true),
        ],
        cierrePorDefecto: DateTime(2026, 8, 24, 9, 30),
      );

      expect(intervalos, hasLength(1));
      expect(_min(intervalos.single.duracion), 30);
    });

    test('una sesión anómala se acota a la duración máxima', () {
      final intervalos = MonitoreoUsoHorariosService.emparejarEventos(
        [
          EventoUso(
              momento: DateTime(2026, 8, 24, 0, 0),
              nombrePaquete: 'p',
              esResume: true),
          EventoUso(
              momento: DateTime(2026, 8, 25, 0, 0),
              nombrePaquete: 'p',
              esResume: false),
        ],
        duracionMaxima: const Duration(hours: 2),
      );

      expect(_min(intervalos.single.duracion), 120);
    });
  });

  group('Análisis agregado', () {
    test('separa el uso por aplicación y lo ordena por tiempo en horario', () {
      final contexto = MonitoreoUsoHorariosService.analizar(
        intervalos: [
          _uso(9, 0, 9, 10, app: 'YouTube', paquete: 'com.google.android.youtube'),
          _uso(9, 0, 9, 45),
          _uso(19, 0, 19, 30, app: 'WhatsApp', paquete: 'com.whatsapp'),
        ],
        horarios: [_laboral()],
        tareas: const [],
      );

      expect(contexto, hasLength(3));
      // TikTok: 45 min en horario; YouTube: 10; WhatsApp: 0.
      expect(contexto.first.nombreApp, 'TikTok');
      expect(contexto.first.minutosEnHorarios, 45);
      expect(contexto[1].nombreApp, 'YouTube');
      expect(contexto.last.nombreApp, 'WhatsApp');
      expect(contexto.last.minutosEnHorarios, 0);
      expect(_min(contexto.last.fueraDeHorarios), 30);
    });

    test('el resumen descriptivo incluye el desglose', () {
      final contexto = MonitoreoUsoHorariosService.analizar(
        intervalos: [_uso(9, 0, 9, 20)],
        horarios: [_laboral()],
        tareas: [_tareaPlanificada(9, 0, 11, 0)],
      ).single;

      expect(contexto.descripcion(), contains('TikTok'));
      expect(contexto.descripcion(), contains('20 min en total'));
      expect(contexto.descripcion(), contains('20 min en horarios'));
      expect(contexto.descripcion(), contains('20 min en tareas planificadas'));
    });
  });

  group('Integración con el contexto de recomendaciones', () {
    ContextoRecomendacion contextoCon({
      required List<IntervaloUso> intervalos,
      List<Tarea> tareas = const [],
    }) =>
        ContextoRecomendacion(
          momento: _lunes,
          horarios: [_laboral()],
          usosContextuales: MonitoreoUsoHorariosService.analizar(
            intervalos: intervalos,
            horarios: [_laboral()],
            tareas: tareas,
          ),
        );

    test('el contexto expone el uso contextual y sus derivados', () {
      final contexto = contextoCon(intervalos: [_uso(9, 0, 9, 30)]);

      expect(contexto.hayUsosContextuales, isTrue);
      expect(contexto.minutosTotalesEnHorarios, 30);
      expect(contexto.distractoresEnHorarios, hasLength(1));
      expect(contexto.minutosDistractoresEnHorarios, 30);
      expect(contexto.distractorPrincipalEnHorario?.nombreApp, 'TikTok');
      expect(contexto.usoContextualDe('com.zhiliaoapp.musically')?.minutosEnHorarios, 30);
    });

    test('una app no clasificada como distractora no cuenta como distractor', () {
      final contexto = contextoCon(intervalos: [
        _uso(9, 0, 9, 30, app: 'Notas', paquete: 'com.ejemplo.notas'),
      ]);

      // El tiempo dentro del horario sí se registra...
      expect(contexto.minutosTotalesEnHorarios, 30);
      // ...pero no se clasifica como distracción por el nombre de la app.
      expect(contexto.distractoresEnHorarios, isEmpty);
      expect(contexto.minutosDistractoresEnHorarios, 0);
      expect(contexto.distractorPrincipalEnHorario, isNull);
    });

    test('el uso durante una tarea planificada queda como contexto', () {
      final contexto = contextoCon(
        intervalos: [_uso(9, 30, 9, 45)],
        tareas: [_tareaPlanificada(9, 0, 11, 0)],
      );

      expect(contexto.minutosDistractoresEnTareas, 15);
      expect(
        contexto.usoContextualDe('com.zhiliaoapp.musically')?.minutosEnTareas,
        15,
      );
    });

    test('sin datos de uso contextual los derivados son neutros', () {
      final contexto = ContextoRecomendacion(momento: _lunes);

      expect(contexto.hayUsosContextuales, isFalse);
      expect(contexto.minutosTotalesEnHorarios, 0);
      expect(contexto.minutosDistractoresEnHorarios, 0);
      expect(contexto.distractorPrincipalEnHorario, isNull);
    });
  });
}
