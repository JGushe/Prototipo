import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/database/database_helper.dart';
import 'package:prototipo_tesis/main.dart';
import 'package:prototipo_tesis/models/comparacion_diaria.dart';
import 'package:prototipo_tesis/models/contexto_recomendacion.dart';
import 'package:prototipo_tesis/models/perfil.dart';
import 'package:prototipo_tesis/models/uso_pantalla.dart';
import 'package:prototipo_tesis/services/ciclo_monitoreo_service.dart';
import 'package:prototipo_tesis/services/lectura_uso_controller.dart';
import 'package:prototipo_tesis/services/reglas/resultado_evaluacion.dart';
import 'package:prototipo_tesis/services/uso_pantalla_service.dart';
import 'package:prototipo_tesis/theme/app_palettes.dart';
import 'package:prototipo_tesis/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Uso extends UsoPantallaService {
  @override
  Future<ComparacionDiaria> compararHoyAyer({DateTime? ahora}) async =>
      ComparacionDiaria.insuficiente(
        ahora: ahora!,
        corte: ahora,
        explicacion: 'Sin sesiones de prueba',
      );

  @override
  Future<bool> solicitarPermisoUso() async => true;
}

class _Captura extends CicloMonitoreoService {
  _Captura(this.resumen);
  final UsoPantalla resumen;

  @override
  Future<({ResultadoEvaluacion resultado, int notificadas})> ejecutar() async {
    await DatabaseHelper.instance.guardarUsoDelDia(resumen, []);
    return (
      resultado: ResultadoEvaluacion(
        contexto: ContextoRecomendacion(momento: DateTime.now()),
        evaluaciones: [],
        generadas: [],
        descartadas: [],
        reglasEvaluadas: 0,
      ),
      notificadas: 0
    );
  }
}

Future<void> _esperarPanel(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty &&
        find.byType(RefreshIndicator).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('El Dashboard no terminó de cargar');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final helper = DatabaseHelper.instance;
  late Directory temporal;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temporal = await Directory.systemTemp.createTemp('semanal_dashboard_');
    await databaseFactory.setDatabasesPath(temporal.path);
    db = await helper.database;
    await helper.guardarPerfil(const Perfil(nombre: 'Prueba local'));
  });

  tearDownAll(() async {
    await db.close();
    await temporal.delete(recursive: true);
  });

  testWidgets('recarga al seleccionar, regresar y finalizar una captura',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final hoy = DateTime.now();
    UsoPantalla uso(int dias, [int minutos = 60]) => UsoPantalla(
          fecha: DateTime(hoy.year, hoy.month, hoy.day - dias),
          tiempoTotalMinutos: minutos,
          numeroDesbloqueos: 2,
        );
    await tester.runAsync(() async {
      for (var dias = 1; dias <= 5; dias++) {
        await helper.guardarUsoDelDia(uso(dias), []);
      }
      await helper.guardarUsoDelDia(uso(10), []);
    });
    final lectura =
        LecturaUsoController(uso: _Uso(), ciclo: _Captura(uso(1, 120)));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.of(AppPaletteId.lightCool),
      home: HomeScreen(lectura: lectura),
    ));
    await _esperarPanel(tester);
    await tester.ensureVisible(find.text('7 días'));
    await tester.tap(find.text('7 días'));
    await _esperarPanel(tester);
    expect(find.text('5/7 días con registro'), findsOneWidget);
    expect(find.text('60 min/día'), findsOneWidget);

    await tester.runAsync(() => helper.guardarUsoDelDia(uso(6), []));
    await tester.tap(find.text('Diario'));
    await tester.pump();
    await tester.tap(find.text('7 días'));
    await _esperarPanel(tester);
    expect(find.text('6/7 días con registro'), findsOneWidget);

    await tester.runAsync(() => helper.guardarUsoDelDia(uso(7), []));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _esperarPanel(tester);
    expect(find.text('7/7 días con registro'), findsOneWidget);

    await tester.runAsync(() => lectura.actualizar());
    await _esperarPanel(tester);
    expect(find.text('69 min/día'), findsOneWidget);
    expect(find.textContaining('Comparación no disponible'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    lectura.dispose();
  });
}
