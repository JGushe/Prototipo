import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/main.dart';
import 'package:prototipo_tesis/screens/uso_screen.dart';
import 'package:prototipo_tesis/models/comparacion_diaria.dart';
import 'package:prototipo_tesis/models/contexto_recomendacion.dart';
import 'package:prototipo_tesis/models/uso_pantalla.dart';
import 'package:prototipo_tesis/services/analisis_horario_service.dart';
import 'package:prototipo_tesis/services/ciclo_monitoreo_service.dart';
import 'package:prototipo_tesis/services/lectura_uso_controller.dart';
import 'package:prototipo_tesis/services/reglas/resultado_evaluacion.dart';
import 'package:prototipo_tesis/services/uso_pantalla_service.dart';
import 'package:prototipo_tesis/theme/app_palettes.dart';
import 'package:prototipo_tesis/theme/app_theme.dart';
import 'package:prototipo_tesis/widgets/estado_lectura_uso.dart';

final _corte = DateTime(2026, 11, 6, 12, 34);

ComparacionDiaria _diaria() => ComparacionDiaria.calcular(
      ahora: _corte,
      corte: _corte,
      minutosHoy: 426,
      minutosAyer: 450,
      distractorHoy: 96,
      distractorAyer: 120,
      desbloqueosHoy: 12,
    );

class _UsoPrueba extends UsoPantallaService {
  Future<ComparacionDiaria> Function() respuesta = () async => _diaria();
  Future<ComparacionDiaria> Function(DateTime ahora)? porHora;
  final List<DateTime> ahoras = [];
  int lecturas = 0;
  int detalles = 0;
  Future<List<AppUso>> Function(DateTime)? detallePorHora;
  Completer<List<AppUso>>? detallePendiente;

  @override
  Future<ComparacionDiaria> compararHoyAyer({DateTime? ahora}) {
    lecturas++;
    ahoras.add(ahora ?? DateTime.now());
    if (porHora case final fn?) return fn(ahora ?? DateTime.now());
    return respuesta();
  }

  @override
  Future<List<AppUso>> obtenerTopAppsDelDia(
      {int top = 5, DateTime? ahora}) async {
    detalles++;
    expect(ahora, ahoras.last);
    if (detallePorHora case final fn?) return fn(ahora!);
    if (detallePendiente case final pendiente?) return pendiente.future;
    return [];
  }

  @override
  Future<bool> solicitarPermisoUso() async => true;
}

class _AnalisisPrueba extends AnalisisHorarioService {
  @override
  Future<AnalisisHorario> analizar({int dias = 7, DateTime? ahora}) async =>
      AnalisisHorario(
        usoPorHora: {},
        horaPico: 0,
        minutosPico: 0,
        horarios: [],
        sugerencias: [],
      );
}

class _CicloPrueba extends CicloMonitoreoService {
  final termina =
      Completer<({ResultadoEvaluacion resultado, int notificadas})>();
  int capturas = 0;

  @override
  Future<({ResultadoEvaluacion resultado, int notificadas})> ejecutar() {
    capturas++;
    return termina.future;
  }
}

ComparacionDiaria _para(DateTime ahora) => ComparacionDiaria.calcular(
      ahora: ahora,
      corte: ahora,
      minutosHoy: ahora.day == 7 ? 10 : 426,
      minutosAyer: 400,
      distractorHoy: 1,
      distractorAyer: 2,
      desbloqueosHoy: 3,
    );

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('prototipo_tesis/preferencias_tips'),
            (_) async => <String>[]);
  });
  for (final motivo in MotivoComparacion.values) {
    testWidgets('medianoche renueva una lectura sin corte: $motivo',
        (tester) async {
      var ahora = DateTime(2026, 11, 30, 23, 59);
      final uso = _UsoPrueba()
        ..porHora = (momento) async => ComparacionDiaria.insuficiente(
              ahora: momento,
              explicacion: 'Sin sesiones',
              motivo: momento.month == 11 ? motivo : MotivoComparacion.sinDatos,
            );
      final lectura = LecturaUsoController(uso: uso, reloj: () => ahora);
      await lectura.leer();

      ahora = DateTime(2026, 12, 1);
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();

      expect(uso.lecturas, 2);
      expect(lectura.comparacion?.diaHoy, DateTime(2026, 12, 1));
      expect(lectura.comparacion?.minutosHoy, isNull);
      expect(lectura.estado, EstadoLecturaUso.sinDatos);
      lectura.dispose();
    });
  }

  testWidgets('Uso renueva detalles y descarta el detalle tardío de ayer',
      (tester) async {
    var ahora = DateTime(2026, 11, 6, 23, 59);
    final anterior = Completer<List<AppUso>>();
    final nuevo = Completer<List<AppUso>>();
    final uso = _UsoPrueba()
      ..porHora = ((momento) async => _para(momento))
      ..detallePorHora =
          (momento) => momento.day == 6 ? anterior.future : nuevo.future;
    final lectura = LecturaUsoController(
      uso: uso,
      analisis: _AnalisisPrueba(),
      reloj: () => ahora,
    );
    await lectura.leer();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.of(AppPaletteId.lightCool),
      home: UsoScreen(lectura: lectura),
    ));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    ahora = DateTime(2026, 11, 7);
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(uso.detalles, 2);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    nuevo.complete([
      AppUso(
          nombrePaquete: 'nueva',
          nombreApp: 'App nueva',
          tiempoUsoMinutos: 1,
          numeroAperturas: 1),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('App nueva'), findsOneWidget);
    anterior.complete([
      AppUso(
          nombrePaquete: 'anterior',
          nombreApp: 'App anterior',
          tiempoUsoMinutos: 10,
          numeroAperturas: 1),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('App anterior'), findsNothing);
    expect(find.text('App nueva'), findsOneWidget);
    expect(find.text('Tiempo único de pantalla: 10 min'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    lectura.dispose();
  });

  testWidgets('medianoche y lectura manual comparten consulta sin bucles',
      (tester) async {
    var ahora = DateTime(2026, 11, 6, 23, 59);
    final uso = _UsoPrueba()..porHora = (momento) async => _para(momento);
    final lectura = LecturaUsoController(uso: uso, reloj: () => ahora);
    await lectura.leer();
    final pendiente = Completer<ComparacionDiaria>();
    uso.porHora = (_) => pendiente.future;

    ahora = DateTime(2026, 11, 7);
    await tester.pump(const Duration(minutes: 1));
    final manual = lectura.leer(forzar: true);
    expect(uso.lecturas, 2);
    expect(lectura.estado, EstadoLecturaUso.leyendo);
    pendiente.complete(ComparacionDiaria.insuficiente(
      ahora: ahora,
      corte: ahora,
      explicacion: 'Sin sesiones',
    ));
    await manual;
    ahora = ahora.add(LecturaUsoController.vigencia);
    await tester.pump(LecturaUsoController.vigencia);
    expect(uso.lecturas, 2);
    expect(lectura.comparacion?.minutosHoy, isNull);
    lectura.dispose();
  });

  testWidgets('medianoche consulta el día nuevo sin tocar el reloj',
      (tester) async {
    var ahora = DateTime(2026, 11, 6, 23, 59);
    final uso = _UsoPrueba()..porHora = (momento) async => _para(momento);
    final lectura = LecturaUsoController(
      uso: uso,
      analisis: _AnalisisPrueba(),
      reloj: () => ahora,
    );

    await lectura.leer();
    expect(lectura.comparacion?.diaHoy, DateTime(2026, 11, 6));

    ahora = DateTime(2026, 11, 7, 0, 0);
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();

    expect(lectura.comparacion?.diaHoy, DateTime(2026, 11, 7));
    expect(uso.ahoras.last, DateTime(2026, 11, 7, 0, 0));
    lectura.dispose();
  });

  test('una consulta que termina tras medianoche no guarda el día anterior',
      () async {
    var ahora = DateTime(2026, 11, 6, 23, 59, 30);
    final uso = _UsoPrueba();
    final primera = Completer<ComparacionDiaria>();
    final iniciada = Completer<void>();
    uso.porHora = (momento) {
      if (momento.day == 6) {
        iniciada.complete();
        return primera.future;
      }
      return Future.value(_para(momento));
    };
    final lectura = LecturaUsoController(uso: uso, reloj: () => ahora);

    final pendiente = lectura.leer(forzar: true);
    await iniciada.future;
    ahora = DateTime(2026, 11, 7, 0, 0, 5);
    primera.complete(_para(DateTime(2026, 11, 6, 23, 59, 30)));
    await pendiente;

    expect(lectura.comparacion?.diaHoy, DateTime(2026, 11, 7));
    expect(uso.ahoras.length, 2);
    expect(uso.ahoras.first, DateTime(2026, 11, 6, 23, 59, 30));
    lectura.dispose();
  });

  testWidgets('al volver del segundo plano consulta el día actual',
      (tester) async {
    var ahora = DateTime(2026, 11, 6, 23, 0);
    final uso = _UsoPrueba()..porHora = (momento) async => _para(momento);
    final lectura = LecturaUsoController(
      uso: uso,
      analisis: _AnalisisPrueba(),
      reloj: () => ahora,
    );

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.of(AppPaletteId.lightCool),
      home: HomeScreen(lectura: lectura),
    ));
    await tester.pump();
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    ahora = DateTime(2026, 11, 7, 9, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(lectura.comparacion?.diaHoy, DateTime(2026, 11, 7));
    await tester.pumpWidget(const SizedBox());
    lectura.dispose();
  });

  testWidgets('dispose cancela el temporizador de medianoche', (tester) async {
    var ahora = DateTime(2026, 11, 6, 23, 59);
    final uso = _UsoPrueba()..porHora = (momento) async => _para(momento);
    final lectura = LecturaUsoController(uso: uso, reloj: () => ahora);

    await lectura.leer();
    final llamadas = uso.lecturas;
    lectura.dispose();

    ahora = DateTime(2026, 11, 7, 0, 0);
    await tester.pump(const Duration(minutes: 2));
    expect(uso.lecturas, llamadas);
  });

  for (final tema in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('Dashboard, Uso y Tips conservan el corte en tema $tema',
        (tester) async {
      final semantica = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(390, 830));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final uso = _UsoPrueba();
      final detalle = Completer<List<AppUso>>();
      uso.detallePendiente = detalle;
      final lectura = LecturaUsoController(
        uso: uso,
        analisis: _AnalisisPrueba(),
        reloj: () => _corte,
      );

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.of(AppPaletteId.lightCool),
        darkTheme: AppTheme.of(AppPaletteId.darkCool),
        themeMode: tema,
        home: HomeScreen(lectura: lectura),
      ));
      await tester.pumpAndSettle();

      expect(find.text('7 h 6 min'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('23 por ciento')), findsOneWidget);
      expect(find.textContaining('Corte 12:34'), findsOneWidget);
      expect(find.textContaining('Fuente:'), findsNothing);
      expect(find.byTooltip('Actualizar datos'), findsOneWidget);

      await tester.tap(find.text('Uso'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      detalle.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('Tiempo único de pantalla: 7 h 6 min'), findsOneWidget);
      expect(find.text('Desbloqueos: 12'), findsOneWidget);
      expect(find.textContaining('Corte'), findsNothing);
      expect(find.textContaining('Fuente:'), findsNothing);

      await tester.tap(find.text('Tips'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Corte'), findsNothing);
      expect(find.textContaining('Fuente:'), findsNothing);

      await tester.tap(find.text('Uso'));
      await tester.pumpAndSettle();
      expect(uso.lecturas, 1);
      expect(uso.detalles, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      lectura.dispose();
      semantica.dispose();
    });
  }

  testWidgets(
      'estados compartidos distinguen permiso, datos, antigüedad y error',
      (tester) async {
    var ahora = _corte;
    final uso = _UsoPrueba();
    final primera = Completer<ComparacionDiaria>();
    uso.respuesta = () => primera.future;
    final lectura = LecturaUsoController(uso: uso, reloj: () => ahora);
    final pendiente = lectura.leer();
    await tester.pumpWidget(MaterialApp(
      home: ListenableBuilder(
        listenable: lectura,
        builder: (_, __) => EtiquetaLecturaUso(lectura, mostrarCorte: true),
      ),
    ));
    expect(find.textContaining('Consultando uso'), findsOneWidget);

    primera.complete(ComparacionDiaria.insuficiente(
      ahora: ahora,
      motivo: MotivoComparacion.sinPermiso,
      explicacion: 'Sin permiso',
    ));
    await pendiente;
    await tester.pump();
    expect(find.textContaining('Acceso al uso desactivado'), findsOneWidget);

    uso.respuesta = () async => ComparacionDiaria.insuficiente(
          ahora: ahora,
          corte: ahora,
          explicacion: 'Sin sesiones',
        );
    await lectura.leer(forzar: true);
    await tester.pump();
    expect(find.textContaining('Datos insuficientes'), findsOneWidget);

    uso.respuesta = () async => _diaria();
    await lectura.leer(forzar: true);
    await tester.pump();
    expect(find.textContaining('Lectura actual'), findsNothing);
    expect(find.textContaining('Corte 12:34'), findsOneWidget);

    ahora = ahora.add(LecturaUsoController.vigencia);
    await tester.pump(LecturaUsoController.vigencia);
    expect(find.textContaining('Captura antigua'), findsOneWidget);

    uso.respuesta = () async => throw StateError('fallo simulado');
    await lectura.leer(forzar: true);
    await tester.pump();
    expect(find.textContaining('No se pudo actualizar'), findsOneWidget);
    expect(find.textContaining('Corte 12:34'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    lectura.dispose();
  });

  testWidgets('dos actualizaciones simultáneas comparten captura y lectura',
      (tester) async {
    final uso = _UsoPrueba();
    final ciclo = _CicloPrueba();
    final lectura = LecturaUsoController(
      uso: uso,
      ciclo: ciclo,
      reloj: () => _corte,
    );
    await lectura.leer();
    final primera = lectura.actualizar();
    expect(lectura.actualizar(), same(primera));
    final alNavegar = lectura.leer();
    await tester.pumpWidget(MaterialApp(
      home: ListenableBuilder(
        listenable: lectura,
        builder: (_, __) => EtiquetaLecturaUso(lectura),
      ),
    ));
    expect(lectura.estado, EstadoLecturaUso.actualizando);
    expect(find.textContaining('Actualizando captura'), findsOneWidget);
    expect(ciclo.capturas, 1);
    expect(uso.lecturas, 1);

    ciclo.termina.complete((
      resultado: ResultadoEvaluacion(
        contexto: ContextoRecomendacion(momento: _corte),
        evaluaciones: [],
        generadas: [],
        descartadas: [],
        reglasEvaluadas: 0,
      ),
      notificadas: 0,
    ));
    await primera;
    await alNavegar;
    expect(uso.lecturas, 2);
    expect(lectura.estado, EstadoLecturaUso.disponible);
    await tester.pumpWidget(const SizedBox());
    lectura.dispose();
  });

  test('formato y porcentajes con datos ausentes o incoherentes', () {
    expect(formatearMinutosUso(426), '7 h 6 min');
    expect(formatearMinutosUso(0), '0 min');
    expect(porcentajeDistractor(426, 96), 23);
    expect(porcentajeDistractor(25, 25), 100);
    expect(porcentajeDistractor(25, 0), 0);
    expect(porcentajeDistractor(25, 26), isNull);
    expect(porcentajeDistractor(0, 0), isNull);
    expect(porcentajeDistractor(null, 0), isNull);
  });
}
