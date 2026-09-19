// Pruebas del control de duplicados y frecuencia (Etapa 6).
//
// La política es pura (recibe el historial ya cargado), así que todo el
// comportamiento se verifica sin base de datos ni emulador.

import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/models/contexto_recomendacion.dart';
import 'package:prototipo_tesis/models/horario.dart';
import 'package:prototipo_tesis/models/recomendacion.dart';
import 'package:prototipo_tesis/models/tarea.dart';
import 'package:prototipo_tesis/models/uso_pantalla.dart';
import 'package:prototipo_tesis/services/reglas/creador_recomendaciones.dart';
import 'package:prototipo_tesis/services/reglas/evaluador_reglas.dart';
import 'package:prototipo_tesis/services/reglas/politica_cooldown.dart';
import 'package:prototipo_tesis/services/reglas/regla_recomendacion.dart';
import 'package:prototipo_tesis/services/reglas/reglas_por_defecto.dart';

// --- Apoyo ---

const _politica = PoliticaCooldown();
const _creador = CreadorRecomendaciones();

final _momento = DateTime(2026, 8, 24, 10); // lunes

AppUso _app(String paquete, int minutos, {String? nombre}) => AppUso(
      nombrePaquete: paquete,
      nombreApp: nombre ?? paquete,
      tiempoUsoMinutos: minutos,
      numeroAperturas: 1,
    );

Horario _horario(String tipo, int horaInicio, int horaFin) =>
    Horario(tipo: tipo, horaInicio: horaInicio, horaFin: horaFin);

List<Tarea> _tareas(int cantidad) => List.generate(
      cantidad,
      (i) => Tarea(titulo: 'T$i', fechaCreacion: DateTime(2026, 8, 20)),
    );

ContextoRecomendacion _ctx({
  DateTime? momento,
  Horario? horarioActivo,
  Tarea? tareaActiva,
  List<Tarea> tareasPendientes = const [],
  List<AppUso> apps = const [],
  int minutosPantalla = 0,
  bool hayDatosUso = false,
  Map<int, int> usoPorHora = const {},
  int minutosNocturno = 0,
}) =>
    ContextoRecomendacion(
      momento: momento ?? _momento,
      horarioActivo: horarioActivo,
      tareaActiva: tareaActiva,
      tareasPendientes: tareasPendientes,
      tareasAltaPrioridadPendientes:
          tareasPendientes.where((t) => t.prioridad == 'alta').toList(),
      appsMasUtilizadas: apps,
      tiempoTotalPantallaMinutos: minutosPantalla,
      hayDatosUsoPantalla: hayDatosUso,
      usoPorHora: usoPorHora,
      minutosUsoNocturno: minutosNocturno,
    );

ReglaRecomendacion _regla(String id) =>
    crearReglasPorDefecto().firstWhere((r) => r.id == id);

/// Recomendación histórica generada por [regla] en el contexto [generadoEn].
Recomendacion _historico(
  ReglaRecomendacion regla,
  ContextoRecomendacion generadoEn,
  DateTime fecha,
) =>
    Recomendacion(
      fecha: fecha,
      tipo: regla.tipo,
      titulo: 'Histórico',
      mensaje: 'Histórico',
      reglaId: regla.id,
      clave: regla.claveEquivalencia(generadoEn),
    );

void main() {
  group('Claves de equivalencia', () {
    test('el ámbito "día" incluye la fecha', () {
      final r5 = _regla('R5');
      expect(r5.ambito, AmbitoCooldown.dia);

      final hoy = r5.claveEquivalencia(_ctx(momento: DateTime(2026, 8, 24, 10)));
      final ayer = r5.claveEquivalencia(_ctx(momento: DateTime(2026, 8, 23, 10)));

      expect(hoy, contains('2026-08-24'));
      expect(hoy, isNot(ayer));
    });

    test('el ámbito "horario" incluye la fecha y el bloque activo', () {
      final r1 = _regla('R1');
      expect(r1.ambito, AmbitoCooldown.horario);

      final academico =
          r1.claveEquivalencia(_ctx(horarioActivo: _horario('academico', 19, 21)));
      final laboral =
          r1.claveEquivalencia(_ctx(horarioActivo: _horario('laboral', 8, 16)));

      expect(academico, contains('academico:19:00-21:00'));
      expect(academico, isNot(laboral));
    });

    test('el ámbito "regla" no depende del contexto', () {
      final r3 = _regla('R3');
      expect(r3.ambito, AmbitoCooldown.regla);

      expect(
        r3.claveEquivalencia(_ctx()),
        r3.claveEquivalencia(_ctx(momento: DateTime(2026, 8, 25, 9))),
      );
    });

    test('reglas distintas producen claves distintas', () {
      final ctx = _ctx();
      final claves =
          crearReglasPorDefecto().map((r) => r.claveEquivalencia(ctx)).toList();
      expect(claves.toSet().length, claves.length);
    });
  });

  group('Ventanas de cooldown', () {
    test('ámbito "regla": empieza en momento - cooldown', () {
      final r3 = _regla('R3'); // cooldown por defecto: 90 min
      final ctx = _ctx(momento: DateTime(2026, 8, 24, 10, 0));
      expect(r3.inicioVentanaCooldown(ctx), DateTime(2026, 8, 24, 8, 30));
    });

    test('ámbito "día": empieza al inicio del día natural', () {
      final r5 = _regla('R5');
      final ctx = _ctx(momento: DateTime(2026, 8, 24, 23, 30));
      expect(r5.inicioVentanaCooldown(ctx), DateTime(2026, 8, 24));
    });

    test('cada regla puede tener un cooldown diferente', () {
      final reglas = crearReglasPorDefecto().where(
        (r) => r.ambito == AmbitoCooldown.regla,
      );
      final cooldowns = reglas.map((r) => r.cooldown).toSet();
      expect(cooldowns.length, greaterThan(1));
    });
  });

  group('Ciclo de cooldown (R3, ámbito regla, 90 min)', () {
    final r3 = _regla('R3');
    final ctx = _ctx(momento: DateTime(2026, 8, 24, 10, 0));

    test('primera ejecución: sin historial se genera', () {
      expect(
        _politica.evaluar(regla: r3, contexto: ctx, historial: const []),
        isNull,
      );
    });

    test('segunda ejecución dentro del cooldown se descarta', () {
      final historial = [_historico(r3, ctx, DateTime(2026, 8, 24, 9, 30))];
      final descarte =
          _politica.evaluar(regla: r3, contexto: ctx, historial: historial);

      expect(descarte, isNotNull);
      expect(descarte!.reglaId, 'R3');
      expect(descarte.fechaExistente, DateTime(2026, 8, 24, 9, 30));
      expect(descarte.inicioVentana, DateTime(2026, 8, 24, 8, 30));
      expect(descarte.motivo, contains('R3'));
      expect(descarte.motivo, contains('ya existe'));
    });

    test('ejecución después del cooldown se genera', () {
      final historial = [_historico(r3, ctx, DateTime(2026, 8, 24, 8, 0))];
      expect(
        _politica.evaluar(regla: r3, contexto: ctx, historial: historial),
        isNull,
      );
    });

    test('justo en el límite del cooldown todavía se descarta', () {
      final historial = [_historico(r3, ctx, DateTime(2026, 8, 24, 8, 30))];
      expect(
        _politica.evaluar(regla: r3, contexto: ctx, historial: historial),
        isNotNull,
      );
    });

    test('se toma la recomendación equivalente más reciente', () {
      final historial = [
        _historico(r3, ctx, DateTime(2026, 8, 24, 8, 45)),
        _historico(r3, ctx, DateTime(2026, 8, 24, 9, 45)),
        _historico(r3, ctx, DateTime(2026, 8, 24, 9, 0)),
      ];
      final descarte =
          _politica.evaluar(regla: r3, contexto: ctx, historial: historial);
      expect(descarte!.fechaExistente, DateTime(2026, 8, 24, 9, 45));
    });
  });

  group('Ámbito día (R5)', () {
    final r5 = _regla('R5');

    test('el mismo día bloquea aunque pasen muchas horas', () {
      final ctx = _ctx(momento: DateTime(2026, 8, 24, 23, 0));
      final historial = [
        _historico(r5, _ctx(momento: DateTime(2026, 8, 24, 0, 30)),
            DateTime(2026, 8, 24, 0, 30)),
      ];
      expect(
        _politica.evaluar(regla: r5, contexto: ctx, historial: historial),
        isNotNull,
      );
    });

    test('al día siguiente vuelve a generarse', () {
      final ctx = _ctx(momento: DateTime(2026, 8, 24, 10));
      final historial = [
        _historico(r5, _ctx(momento: DateTime(2026, 8, 23, 10)),
            DateTime(2026, 8, 23, 10)),
      ];
      expect(
        _politica.evaluar(regla: r5, contexto: ctx, historial: historial),
        isNull,
      );
    });
  });

  group('Contextos diferentes (R1, ámbito horario)', () {
    final r1 = _regla('R1');
    final academico = _ctx(horarioActivo: _horario('academico', 19, 21));
    final laboral = _ctx(horarioActivo: _horario('laboral', 8, 16));

    test('el mismo día y el mismo horario bloquea', () {
      final historial = [_historico(r1, academico, academico.momento)];
      expect(
        _politica.evaluar(regla: r1, contexto: academico, historial: historial),
        isNotNull,
      );
    });

    test('pasado el cooldown vuelve a avisar el mismo día y horario', () {
      // R1 debe repetirse cada 90 min mientras la distracción continúe.
      final historial = [
        _historico(r1, academico, academico.momento.subtract(const Duration(minutes: 120))),
      ];
      expect(
        _politica.evaluar(regla: r1, contexto: academico, historial: historial),
        isNull,
        reason: '120 min > cooldown de 90 min',
      );

      final reciente = [
        _historico(r1, academico, academico.momento.subtract(const Duration(minutes: 30))),
      ];
      expect(
        _politica.evaluar(regla: r1, contexto: academico, historial: reciente),
        isNotNull,
        reason: '30 min < cooldown de 90 min',
      );
    });

    test('la ventana del ámbito horario respeta el cooldown, no el día', () {
      expect(
        r1.inicioVentanaCooldown(academico),
        academico.momento.subtract(r1.cooldown),
      );
    });

    test('un horario distinto no bloquea', () {
      final historial = [_historico(r1, laboral, laboral.momento)];
      expect(
        _politica.evaluar(regla: r1, contexto: academico, historial: historial),
        isNull,
      );
    });

    test('el mismo horario en otro día no bloquea', () {
      final otroDia = _ctx(
        momento: DateTime(2026, 8, 25, 10),
        horarioActivo: _horario('academico', 19, 21),
      );
      final historial = [_historico(r1, academico, academico.momento)];
      expect(
        _politica.evaluar(regla: r1, contexto: otroDia, historial: historial),
        isNull,
      );
    });
  });

  group('Independencia entre reglas', () {
    test('una recomendación de R4 no bloquea a R5', () {
      final ctx = _ctx(
        tareasPendientes: _tareas(8),
        minutosPantalla: 300,
        hayDatosUso: true,
      );
      final historial = [_historico(_regla('R4'), ctx, ctx.momento)];

      expect(
        _politica.evaluar(regla: _regla('R4'), contexto: ctx, historial: historial),
        isNotNull,
      );
      expect(
        _politica.evaluar(regla: _regla('R5'), contexto: ctx, historial: historial),
        isNull,
      );
    });
  });

  group('Compatibilidad con el historial antiguo', () {
    test('una recomendación sin clave no bloquea pero se conserva', () {
      final r3 = _regla('R3');
      final ctx = _ctx();
      final antigua = Recomendacion(
        fecha: ctx.momento,
        tipo: 'sugerencia_foco',
        titulo: 'Antigua',
        mensaje: 'Antigua',
        reglaId: 'R3',
      );

      expect(antigua.clave, isNull);
      expect(
        _politica.evaluar(regla: r3, contexto: ctx, historial: [antigua]),
        isNull,
      );
      // El historial permanece intacto.
      expect([antigua].length, 1);
    });

    test('la política no modifica el historial que recibe', () {
      final r3 = _regla('R3');
      final ctx = _ctx();
      final historial = [_historico(r3, ctx, ctx.momento)];

      _politica.evaluar(regla: r3, contexto: ctx, historial: historial);

      expect(historial, hasLength(1));
    });
  });

  group('Creación con clave', () {
    test('la recomendación creada lleva su clave de equivalencia', () {
      final r1 = _regla('R1');
      final ctx = _ctx(
        horarioActivo: _horario('academico', 19, 21),
        apps: [_app('com.instagram', 45)],
      );
      final resultados = EvaluadorReglas(crearReglasPorDefecto()).evaluar(ctx);
      final resultado = resultados.firstWhere((r) => r.regla.id == 'R1');

      final rec = _creador.crear(resultado, ctx);

      expect(rec.clave, r1.claveEquivalencia(ctx));
      expect(rec.reglaId, 'R1');
    });
  });

  group('Ejecuciones repetidas', () {
    // Reproduce el ciclo del motor sin base de datos: evaluar, descartar por
    // cooldown, crear e incorporar al historial.
    List<Recomendacion> ejecutarSimulado(
      ContextoRecomendacion ctx,
      List<Recomendacion> historial,
    ) {
      final evaluador = EvaluadorReglas(crearReglasPorDefecto());
      final nuevas = <Recomendacion>[];
      for (final resultado in evaluador.evaluar(ctx)) {
        final descarte = _politica.evaluar(
          regla: resultado.regla,
          contexto: ctx,
          historial: historial,
        );
        if (descarte != null) continue;
        final rec = _creador.crear(resultado, ctx);
        historial.add(rec);
        nuevas.add(rec);
      }
      return nuevas;
    }

    test('la primera ejecución genera y la segunda no duplica', () {
      final ctx = _ctx(
        horarioActivo: _horario('academico', 19, 21),
        apps: [_app('com.instagram', 45)],
        tareasPendientes: _tareas(8),
        minutosPantalla: 300,
        hayDatosUso: true,
      );
      final historial = <Recomendacion>[];

      final primera = ejecutarSimulado(ctx, historial);
      final segunda = ejecutarSimulado(ctx, historial);

      expect(primera, isNotEmpty);
      expect(segunda, isEmpty);
      expect(historial.length, primera.length);
    });

    test('pasado el cooldown la misma regla vuelve a generar', () {
      final ctx = _ctx(
        momento: DateTime(2026, 8, 24, 10, 0),
        tareaActiva: Tarea(
          titulo: 'Entregar tesis',
          fechaCreacion: DateTime(2026, 8, 20),
          prioridad: 'alta',
        ),
        apps: [_app('com.instagram', 5)],
      );
      final historial = <Recomendacion>[];

      final primera = ejecutarSimulado(ctx, historial);
      expect(primera.map((r) => r.reglaId), contains('R3'));

      // 100 minutos después: fuera del cooldown de R3 (90 min).
      final despues = _ctx(
        momento: DateTime(2026, 8, 24, 11, 40),
        tareaActiva: Tarea(
          titulo: 'Entregar tesis',
          fechaCreacion: DateTime(2026, 8, 20),
          prioridad: 'alta',
        ),
        apps: [_app('com.instagram', 5)],
      );

      final segunda = ejecutarSimulado(despues, historial);
      expect(segunda.map((r) => r.reglaId), contains('R3'));
    });
  });
}
