// Pruebas del motor de reglas contextualizadas (Etapa 5).
//
// Cada regla se evalúa sobre un contexto construido directamente, de modo que
// las pruebas no dependen de la base de datos ni del plugin de UsageStats.

import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/models/contexto_recomendacion.dart';
import 'package:prototipo_tesis/models/horario.dart';
import 'package:prototipo_tesis/models/tarea.dart';
import 'package:prototipo_tesis/models/uso_pantalla.dart';
import 'package:prototipo_tesis/services/reglas/configuracion_motor.dart';
import 'package:prototipo_tesis/services/reglas/creador_recomendaciones.dart';
import 'package:prototipo_tesis/services/reglas/evaluador_reglas.dart';
import 'package:prototipo_tesis/services/reglas/regla_recomendacion.dart';
import 'package:prototipo_tesis/services/reglas/reglas_por_defecto.dart';

// --- Constructores de apoyo ---

AppUso _app(String paquete, int minutos, {String? nombre}) => AppUso(
      nombrePaquete: paquete,
      nombreApp: nombre ?? paquete,
      tiempoUsoMinutos: minutos,
      numeroAperturas: 1,
    );

Tarea _tarea({String titulo = 'Tarea', String prioridad = 'media'}) => Tarea(
      titulo: titulo,
      fechaCreacion: DateTime(2026, 8, 20),
      prioridad: prioridad,
    );

List<Tarea> _tareas(int cantidad, {String prioridad = 'media'}) =>
    List.generate(cantidad, (i) => _tarea(titulo: 'T$i', prioridad: prioridad));

Horario _horario(String tipo, {int horaInicio = 8, int horaFin = 16}) =>
    Horario(tipo: tipo, horaInicio: horaInicio, horaFin: horaFin);

final _momento = DateTime(2026, 8, 24, 10); // lunes

ContextoRecomendacion _contexto({
  Horario? horarioActivo,
  List<Horario> horarios = const [],
  Tarea? tareaActiva,
  List<Tarea> tareasPendientes = const [],
  int minutosPantalla = 0,
  bool hayDatosUso = false,
  List<AppUso> apps = const [],
  Map<int, int> usoPorHora = const {},
  int minutosNocturno = 0,
}) =>
    ContextoRecomendacion(
      momento: _momento,
      horarios: horarios,
      horarioActivo: horarioActivo,
      tareaActiva: tareaActiva,
      tareasPendientes: tareasPendientes,
      tareasAltaPrioridadPendientes:
          tareasPendientes.where((t) => t.prioridad == 'alta').toList(),
      tiempoTotalPantallaMinutos: minutosPantalla,
      hayDatosUsoPantalla: hayDatosUso,
      appsMasUtilizadas: apps,
      usoPorHora: usoPorHora,
      minutosUsoNocturno: minutosNocturno,
    );

List<String> _ids(ContextoRecomendacion ctx, [ConfiguracionMotor? config]) =>
    EvaluadorReglas(crearReglasPorDefecto(config)).idsQueAplican(ctx);

// --- Pruebas ---

void main() {
  group('Configuración centralizada', () {
    test('los umbrales por defecto conservan los valores previos del motor', () {
      const c = ConfiguracionMotor.porDefecto;
      expect(c.minutosDistractor, 30);
      expect(c.tareasPendientesLimite, 5);
      expect(c.minutosAltoUsoDiario, 240);
      expect(c.minutosCargaAltaUso, 180);
      expect(c.tareasCargaAltaLimite, 3);
      expect(c.minutosUsoNocturno, 60);
      expect(c.horaInicioNocturno, 22);
      expect(c.horaFinNocturno, 6);
    });

    test('cambiar la configuración cambia el resultado de las reglas', () {
      final ctx = _contexto(
        horarioActivo: _horario('academico', horaInicio: 19, horaFin: 21),
        apps: [_app('com.instagram', 20, nombre: 'Instagram')],
      );

      // Con el umbral por defecto (30) no se cumple.
      expect(_ids(ctx).contains('R1'), isFalse);
      // Con un umbral de 10 sí.
      expect(
        _ids(ctx, const ConfiguracionMotor(minutosDistractor: 10)).contains('R1'),
        isTrue,
      );
    });
  });

  group('R1 — Uso distractor durante el estudio', () {
    test('se cumple con horario académico y distractores sobre el umbral', () {
      final ctx = _contexto(
        horarioActivo: _horario('academico', horaInicio: 19, horaFin: 21),
        apps: [_app('com.instagram', 45, nombre: 'Instagram')],
      );
      expect(_ids(ctx).contains('R1'), isTrue);
    });

    test('no se cumple sin horario activo', () {
      final ctx = _contexto(apps: [_app('com.instagram', 45)]);
      expect(_ids(ctx).contains('R1'), isFalse);
    });

    test('no se cumple en horario laboral', () {
      final ctx = _contexto(
        horarioActivo: _horario('laboral'),
        apps: [_app('com.instagram', 45)],
      );
      expect(_ids(ctx).contains('R1'), isFalse);
    });

    test('no se cumple si el tiempo distractor no supera el umbral', () {
      final ctx = _contexto(
        horarioActivo: _horario('academico', horaInicio: 19, horaFin: 21),
        apps: [_app('com.instagram', 20)],
      );
      expect(_ids(ctx).contains('R1'), isFalse);
    });

    test('no se cumple si no hay aplicaciones distractoras', () {
      final ctx = _contexto(
        horarioActivo: _horario('academico', horaInicio: 19, horaFin: 21),
        apps: [_app('com.android.chrome', 90, nombre: 'Chrome')],
      );
      expect(_ids(ctx).contains('R1'), isFalse);
    });
  });

  group('R2 — Uso distractor durante el trabajo', () {
    test('se cumple con horario laboral y una distractora sobre el umbral', () {
      final ctx = _contexto(
        horarioActivo: _horario('laboral'),
        apps: [_app('com.instagram', 45, nombre: 'Instagram')],
      );
      expect(_ids(ctx).contains('R2'), isTrue);
    });

    test('no se cumple en horario académico', () {
      final ctx = _contexto(
        horarioActivo: _horario('academico', horaInicio: 19, horaFin: 21),
        apps: [_app('com.instagram', 45)],
      );
      expect(_ids(ctx).contains('R2'), isFalse);
    });

    test('no se cumple si ninguna distractora individual supera el umbral', () {
      // El total distractor (40) supera el umbral, pero ninguna app por separado.
      final ctx = _contexto(
        horarioActivo: _horario('laboral'),
        apps: [
          _app('com.instagram', 20),
          _app('com.tiktok', 20),
        ],
      );
      expect(ctx.minutosAppsDistractoras, 40);
      expect(ctx.appDistractoraPrincipal?.tiempoUsoMinutos, 20);
      expect(_ids(ctx).contains('R2'), isFalse);
      // R1 sí lo detectaría por tiempo total si el horario fuera académico.
      final academico = _contexto(
        horarioActivo: _horario('academico', horaInicio: 19, horaFin: 21),
        apps: [
          _app('com.instagram', 20),
          _app('com.tiktok', 20),
        ],
      );
      expect(_ids(academico).contains('R1'), isTrue);
    });
  });

  group('R3 — Tarea prioritaria durante un periodo de distracción', () {
    test('se cumple con tarea activa de alta prioridad y uso distractor', () {
      final ctx = _contexto(
        tareaActiva: _tarea(titulo: 'Entregar tesis', prioridad: 'alta'),
        apps: [_app('com.instagram', 5)],
      );
      expect(_ids(ctx).contains('R3'), isTrue);
    });

    test('no se cumple si la tarea activa no es de alta prioridad', () {
      final ctx = _contexto(
        tareaActiva: _tarea(titulo: 'Leer', prioridad: 'media'),
        apps: [_app('com.instagram', 45)],
      );
      expect(_ids(ctx).contains('R3'), isFalse);
    });

    test('no se cumple sin tarea activa', () {
      final ctx = _contexto(apps: [_app('com.instagram', 45)]);
      expect(_ids(ctx).contains('R3'), isFalse);
    });

    test('no se cumple sin uso distractor en el periodo', () {
      final ctx = _contexto(
        tareaActiva: _tarea(prioridad: 'alta'),
        apps: [_app('com.android.chrome', 45)],
      );
      expect(_ids(ctx).contains('R3'), isFalse);
    });
  });

  group('R4 — Exceso de tareas pendientes', () {
    test('se cumple con más tareas que el límite', () {
      expect(_ids(_contexto(tareasPendientes: _tareas(6))).contains('R4'), isTrue);
    });

    test('no se cumple justo en el límite', () {
      expect(_ids(_contexto(tareasPendientes: _tareas(5))).contains('R4'), isFalse);
    });
  });

  group('R5 — Alto uso acumulado', () {
    test('se cumple por encima del umbral con datos disponibles', () {
      final ctx = _contexto(minutosPantalla: 250, hayDatosUso: true);
      expect(_ids(ctx).contains('R5'), isTrue);
    });

    test('no se cumple en el umbral', () {
      final ctx = _contexto(minutosPantalla: 240, hayDatosUso: true);
      expect(_ids(ctx).contains('R5'), isFalse);
    });

    test('no se cumple sin datos de uso', () {
      final ctx = _contexto(minutosPantalla: 250, hayDatosUso: false);
      expect(_ids(ctx).contains('R5'), isFalse);
    });
  });

  group('R6 — Carga combinada', () {
    test('se cumple con muchas tareas y uso alto', () {
      final ctx = _contexto(
        tareasPendientes: _tareas(4),
        minutosPantalla: 200,
        hayDatosUso: true,
      );
      expect(_ids(ctx).contains('R6'), isTrue);
    });

    test('no se cumple si el uso no supera el umbral', () {
      final ctx = _contexto(
        tareasPendientes: _tareas(4),
        minutosPantalla: 180,
        hayDatosUso: true,
      );
      expect(_ids(ctx).contains('R6'), isFalse);
    });

    test('no se cumple si la carga de tareas no supera el umbral', () {
      final ctx = _contexto(
        tareasPendientes: _tareas(3),
        minutosPantalla: 200,
        hayDatosUso: true,
      );
      expect(_ids(ctx).contains('R6'), isFalse);
    });
  });

  group('R7 — Uso nocturno', () {
    test('se cumple por encima del umbral', () {
      expect(_ids(_contexto(minutosNocturno: 90)).contains('R7'), isTrue);
    });

    test('no se cumple en el umbral', () {
      expect(_ids(_contexto(minutosNocturno: 60)).contains('R7'), isFalse);
    });
  });

  group('R8 — Pico de uso dentro de un horario', () {
    test('se cumple si el pico cae dentro de un horario configurado', () {
      final ctx = _contexto(
        horarios: [_horario('laboral')],
        usoPorHora: {14: 55},
      );
      expect(_ids(ctx).contains('R8'), isTrue);
    });

    test('no se cumple si el pico cae fuera de los horarios', () {
      final ctx = _contexto(
        horarios: [_horario('laboral')],
        usoPorHora: {21: 55},
      );
      expect(_ids(ctx).contains('R8'), isFalse);
    });

    test('no se cumple sin datos de uso por hora', () {
      final ctx = _contexto(horarios: [_horario('laboral')]);
      expect(_ids(ctx).contains('R8'), isFalse);
    });
  });

  group('Evaluador', () {
    test('ordena las reglas por prioridad descendente', () {
      final ctx = _contexto(
        tareaActiva: _tarea(prioridad: 'alta'),
        tareasPendientes: _tareas(6),
        apps: [_app('com.instagram', 45)],
        minutosPantalla: 250,
        hayDatosUso: true,
      );
      final ids = _ids(ctx);

      expect(ids.contains('R3'), isTrue);
      expect(ids.contains('R4'), isTrue);
      expect(ids.contains('R5'), isTrue);
      // R3 (100) antes que R5 (50) antes que R4 (40).
      expect(ids.indexOf('R3'), lessThan(ids.indexOf('R5')));
      expect(ids.indexOf('R5'), lessThan(ids.indexOf('R4')));
    });

    test('una regla deshabilitada no se evalúa', () {
      final ctx = _contexto(minutosPantalla: 250, hayDatosUso: true);
      final reglas = crearReglasPorDefecto()
          .map((r) => r.id == 'R5' ? r.copyWith(habilitada: false) : r)
          .toList();

      expect(_ids(ctx).contains('R5'), isTrue);
      expect(EvaluadorReglas(reglas).idsQueAplican(ctx).contains('R5'), isFalse);
    });

    test('cada regla tiene un identificador único', () {
      final ids = crearReglasPorDefecto().map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids, containsAll(['R1', 'R2', 'R3', 'R4', 'R5', 'R6', 'R7']));
    });
  });

  group('Explicabilidad y creación de recomendaciones', () {
    const creador = CreadorRecomendaciones();

    test('la recomendación identifica su regla y explica el motivo', () {
      final ctx = _contexto(
        horarioActivo: _horario('academico', horaInicio: 19, horaFin: 21),
        apps: [_app('com.instagram', 45, nombre: 'Instagram')],
      );
      final resultados = EvaluadorReglas(crearReglasPorDefecto()).evaluar(ctx);
      final r1 = resultados.firstWhere((r) => r.regla.id == 'R1');

      final rec = creador.crear(r1, ctx);

      expect(rec.reglaId, 'R1');
      expect(rec.severidad, SeveridadRecomendacion.advertencia.name);
      expect(rec.tipo, 'pausa');
      expect(rec.titulo, isNotEmpty);
      expect(rec.mensaje, contains('45'));
      expect(rec.motivo, contains('R1'));
      expect(rec.motivo, contains('académico'));
      expect(rec.motivo, contains('45 min'));
      expect(rec.fecha, ctx.momento);
      expect(rec.leida, isFalse);
    });

    test('crearTodos conserva el orden de prioridad', () {
      final ctx = _contexto(
        tareaActiva: _tarea(prioridad: 'alta'),
        tareasPendientes: _tareas(6),
        apps: [_app('com.instagram', 45)],
      );
      final resultados = EvaluadorReglas(crearReglasPorDefecto()).evaluar(ctx);
      final recs = creador.crearTodos(resultados, ctx);

      expect(recs.length, resultados.length);
      expect(recs.first.reglaId, resultados.first.regla.id);
      expect(recs.map((r) => r.reglaId), containsAll(['R3', 'R4']));
    });

    test('cada condición sabe describirse con datos concretos', () {
      final ctx = _contexto(tareasPendientes: _tareas(8));
      final reglaR4 = crearReglasPorDefecto().firstWhere((r) => r.id == 'R4');

      expect(reglaR4.seCumple(ctx), isTrue);
      expect(reglaR4.explicaciones(ctx).single, contains('8'));
      expect(reglaR4.explicaciones(ctx).single, contains('5'));
    });
  });
}
