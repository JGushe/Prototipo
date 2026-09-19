// Pruebas de integración del motor (Etapa 7).
//
// Cada escenario construye su contexto (entrada), lo entrega al motor a través
// de un servicio de contexto fijo, y verifica el ciclo completo:
// contexto -> reglas -> cooldown -> recomendación almacenada.
//
// El repositorio es un doble en memoria, así que no se necesita SQLite ni el
// plugin de UsageStats.

import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/models/contexto_recomendacion.dart';
import 'package:prototipo_tesis/models/horario.dart';
import 'package:prototipo_tesis/models/recomendacion.dart';
import 'package:prototipo_tesis/models/tarea.dart';
import 'package:prototipo_tesis/models/uso_pantalla.dart';
import 'package:prototipo_tesis/services/contexto_recomendacion_service.dart';
import 'package:prototipo_tesis/services/motor_recomendaciones.dart';
import 'package:prototipo_tesis/services/reglas/repositorio_recomendaciones.dart';
import 'package:prototipo_tesis/services/reglas/resultado_evaluacion.dart';

// --- Dobles de prueba ---

class _RepositorioEnMemoria implements RepositorioRecomendaciones {
  final List<Recomendacion> almacenadas = [];

  @override
  Future<int> insertar(Recomendacion recomendacion) async {
    almacenadas.add(recomendacion);
    return almacenadas.length;
  }

  @override
  Future<List<Recomendacion>> obtenerDesde(DateTime desde) async => almacenadas
      .where((r) => !r.fecha.isBefore(desde))
      .toList();
}

class _ContextoFijo extends ContextoRecomendacionService {
  _ContextoFijo(this.contexto);

  final ContextoRecomendacion contexto;
  int llamadas = 0;

  @override
  Future<ContextoRecomendacion> construir(
      {DateTime? momento, int topApps = 5}) async {
    llamadas++;
    return contexto;
  }
}

class _Banco {
  _Banco(this.contexto, {List<Recomendacion>? historial}) {
    if (historial != null) repo.almacenadas.addAll(historial);
    servicio = _ContextoFijo(contexto);
    motor = MotorRecomendaciones(contextoService: servicio, repositorio: repo);
  }

  final ContextoRecomendacion contexto;
  final _RepositorioEnMemoria repo = _RepositorioEnMemoria();
  late final _ContextoFijo servicio;
  late final MotorRecomendaciones motor;

  Future<ResultadoEvaluacion> ejecutar() => motor.ejecutar();
}

// --- Constructores de entrada ---

final _momento = DateTime(2026, 8, 24, 10); // lunes

AppUso _app(String paquete, int minutos, {String? nombre}) => AppUso(
      nombrePaquete: paquete,
      nombreApp: nombre ?? paquete,
      tiempoUsoMinutos: minutos,
      numeroAperturas: 1,
    );

Horario _horario(String tipo, int horaInicio, int horaFin) =>
    Horario(tipo: tipo, horaInicio: horaInicio, horaFin: horaFin);

Tarea _tarea(String titulo, String prioridad) => Tarea(
      titulo: titulo,
      fechaCreacion: DateTime(2026, 8, 20),
      prioridad: prioridad,
    );

List<Tarea> _tareas(int cantidad) => List.generate(
      cantidad,
      (i) => _tarea('Tarea $i', 'media'),
    );

ContextoRecomendacion _ctx({
  Horario? horarioActivo,
  Tarea? tareaActiva,
  List<Tarea> tareasPendientes = const [],
  List<AppUso> apps = const [],
  int minutosPantalla = 0,
  bool hayDatosUso = false,
  bool permisoUso = true,
  Map<int, int> usoPorHora = const {},
  int minutosNocturno = 0,
}) =>
    ContextoRecomendacion(
      momento: _momento,
      horarioActivo: horarioActivo,
      tareaActiva: tareaActiva,
      tareasPendientes: tareasPendientes,
      tareasAltaPrioridadPendientes:
          tareasPendientes.where((t) => t.prioridad == 'alta').toList(),
      appsMasUtilizadas: apps,
      tiempoTotalPantallaMinutos: minutosPantalla,
      hayDatosUsoPantalla: hayDatosUso,
      permisoUsoDisponible: permisoUso,
      usoPorHora: usoPorHora,
      minutosUsoNocturno: minutosNocturno,
    );

List<String> _idsGeneradas(ResultadoEvaluacion resultado) =>
    resultado.generadas.map((r) => r.reglaId ?? '?').toList();

void main() {
  group('Escenarios de integración', () {
    test('A — usuario sin horario activo + uso elevado → R5', () async {
      final banco = _Banco(_ctx(minutosPantalla: 300, hayDatosUso: true));
      final resultado = await banco.ejecutar();

      expect(resultado.reglasActivadas, contains('R5'));
      expect(_idsGeneradas(resultado), contains('R5'));
      expect(_idsGeneradas(resultado), isNot(contains('R1')));
      expect(_idsGeneradas(resultado), isNot(contains('R2')));
      expect(_idsGeneradas(resultado), isNot(contains('R8')));

      final r5 = resultado.generadas.firstWhere((r) => r.reglaId == 'R5');
      expect(r5.tipo, 'alerta_uso');
      expect(r5.severidad, 'advertencia');

      // El contexto se adquirió una sola vez por el servicio.
      expect(banco.servicio.llamadas, 1);
      // Solo se almacenaron las recomendaciones válidas.
      expect(banco.repo.almacenadas.length, resultado.generadas.length);
    });

    test('B — horario académico + uso distractor sobre el umbral → R1', () async {
      final banco = _Banco(_ctx(
        horarioActivo: _horario('academico', 19, 21),
        apps: [_app('com.instagram', 45, nombre: 'Instagram')],
      ));
      final resultado = await banco.ejecutar();

      expect(resultado.reglasActivadas, contains('R1'));
      expect(_idsGeneradas(resultado), isNot(contains('R2')));

      final r1 = resultado.generadas.firstWhere((r) => r.reglaId == 'R1');
      expect(r1.tipo, 'pausa');
      expect(r1.severidad, 'advertencia');
      expect(r1.mensaje, contains('académico'));
      expect(r1.motivo, contains('45 min'));
    });

    test('C — horario laboral + uso distractor → R2', () async {
      final banco = _Banco(_ctx(
        horarioActivo: _horario('laboral', 8, 16),
        apps: [_app('com.instagram', 45, nombre: 'Instagram')],
      ));
      final resultado = await banco.ejecutar();

      expect(resultado.reglasActivadas, contains('R2'));
      expect(_idsGeneradas(resultado), isNot(contains('R1')));

      final r2 = resultado.generadas.firstWhere((r) => r.reglaId == 'R2');
      expect(r2.tipo, 'pausa');
      expect(r2.mensaje, contains('laboral'));
    });

    test('D — tarea de alta prioridad activa + uso distractor → R3', () async {
      final banco = _Banco(_ctx(
        tareaActiva: _tarea('Entregar tesis', 'alta'),
        apps: [_app('com.instagram', 5)],
      ));
      final resultado = await banco.ejecutar();

      expect(resultado.reglasActivadas, contains('R3'));

      final r3 = resultado.generadas.firstWhere((r) => r.reglaId == 'R3');
      expect(r3.tipo, 'sugerencia_foco');
      expect(r3.mensaje, contains('Entregar tesis'));
    });

    test('E — muchas tareas pendientes → R4', () async {
      final banco = _Banco(_ctx(tareasPendientes: _tareas(8)));
      final resultado = await banco.ejecutar();

      expect(resultado.reglasActivadas, contains('R4'));

      final r4 = resultado.generadas.firstWhere((r) => r.reglaId == 'R4');
      expect(r4.tipo, 'sugerencia_foco');
      expect(r4.severidad, 'sugerencia');
      expect(r4.mensaje, contains('8'));
    });

    test('F — uso nocturno por encima del umbral → R7', () async {
      final banco = _Banco(_ctx(minutosNocturno: 90));
      final resultado = await banco.ejecutar();

      expect(resultado.reglasActivadas, contains('R7'));

      final r7 = resultado.generadas.firstWhere((r) => r.reglaId == 'R7');
      expect(r7.tipo, 'descanso');
      expect(r7.mensaje, contains('22:00'));
    });

    test('G — varias reglas simultáneas, ordenadas por prioridad', () async {
      final banco = _Banco(_ctx(
        horarioActivo: _horario('laboral', 8, 16),
        apps: [_app('com.instagram', 45)],
        tareasPendientes: _tareas(8),
        minutosPantalla: 300,
        hayDatosUso: true,
        minutosNocturno: 90,
      ));
      final resultado = await banco.ejecutar();

      final ids = _idsGeneradas(resultado);
      expect(ids, containsAll(['R2', 'R4', 'R5', 'R6', 'R7']));
      expect(ids, isNot(contains('R1')));
      expect(ids, isNot(contains('R3')));

      // Orden por prioridad: R2 (90) > R7 (80) > R6 (60) > R5 (50) > R4 (40).
      expect(ids.indexOf('R2'), lessThan(ids.indexOf('R7')));
      expect(ids.indexOf('R7'), lessThan(ids.indexOf('R6')));
      expect(ids.indexOf('R6'), lessThan(ids.indexOf('R5')));
      expect(ids.indexOf('R5'), lessThan(ids.indexOf('R4')));

      // El detalle incluye todas las reglas registradas.
      final idsDetalle = resultado.evaluaciones.map((e) => e.reglaId).toList();
      expect(idsDetalle, containsAll(['R1', 'R2', 'R3', 'R4', 'R5', 'R6', 'R7', 'R8']));
    });

    test('H — la misma condición ejecutada varias veces no duplica', () async {
      final banco = _Banco(_ctx(minutosPantalla: 300, hayDatosUso: true));

      final primera = await banco.ejecutar();
      expect(primera.generadas, isNotEmpty);

      final segunda = await banco.ejecutar();
      expect(segunda.generadas, isEmpty);
      expect(segunda.descartadas, isNotEmpty);
      expect(segunda.reglasDescartadas, contains('R5'));

      final detalleR5 =
          segunda.evaluaciones.firstWhere((e) => e.reglaId == 'R5');
      expect(detalleR5.resultado,
          ResultadoReglaEjecucion.descartadaPorCooldown);
      expect(detalleR5.motivoDescarte, contains('R5'));

      // El historial solo contiene la primera recomendación.
      expect(banco.repo.almacenadas.length, 1);
    });

    test('I — sin permiso de UsageStats no hay reglas de apps', () async {
      final banco = _Banco(_ctx(
        minutosPantalla: 300,
        hayDatosUso: true,
        permisoUso: false,
      ));
      final resultado = await banco.ejecutar();

      expect(resultado.contexto.permisoUsoDisponible, isFalse);
      expect(_idsGeneradas(resultado), contains('R5'));
      expect(_idsGeneradas(resultado), isNot(contains('R1')));
      expect(_idsGeneradas(resultado), isNot(contains('R2')));
      expect(_idsGeneradas(resultado), isNot(contains('R3')));
    });

    test('J — sin tareas planificadas no hay recomendación de enfoque', () async {
      final banco = _Banco(_ctx(
        horarioActivo: _horario('academico', 19, 21),
        apps: [_app('com.instagram', 45)],
      ));
      final resultado = await banco.ejecutar();

      expect(_idsGeneradas(resultado), contains('R1'));
      expect(_idsGeneradas(resultado), isNot(contains('R3')));
      expect(resultado.contexto.hayTareaActiva, isFalse);
    });
  });

  group('Comportamiento del motor', () {
    test('las ejecuciones simultáneas reutilizan la misma ejecución', () async {
      final banco = _Banco(_ctx(minutosPantalla: 300, hayDatosUso: true));

      final futura1 = banco.motor.ejecutar();
      final futura2 = banco.motor.ejecutar();

      final resultado1 = await futura1;
      final resultado2 = await futura2;

      expect(identical(resultado1, resultado2), isTrue);
      // El contexto solo se construyó una vez.
      expect(banco.servicio.llamadas, 1);
      expect(banco.repo.almacenadas.length, resultado1.generadas.length);
    });

    test('el resumen describe contexto, reglas, generadas y descartes', () async {
      final banco = _Banco(_ctx(minutosPantalla: 300, hayDatosUso: true));
      final resultado = await banco.ejecutar();

      final resumen = resultado.resumen();
      expect(resumen, contains('tipoHorario='));
      expect(resumen, contains('[OK] R5'));
      expect(resumen, contains('[--] R1'));
      expect(resumen, contains('no aplica'));
      expect(resumen, contains('generadas=${resultado.generadas.length}'));

      // Tras una segunda ejecución el resumen muestra el descarte.
      final segunda = await banco.ejecutar();
      expect(segunda.resumen(), contains('[COOLDOWN] R5'));
    });
  });
}
