import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/database/database_helper.dart';
import 'package:prototipo_tesis/services/monitoreo_segundo_plano_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mensajero =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const uso = MethodChannel('usage_stats');
  const notificaciones =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const completado =
      MethodChannel(MonitoreoSegundoPlanoService.canalCompletado);
  late Directory directorio;
  late Database db;
  late List<MethodCall> llamadasUso;
  late List<MethodCall> llamadasNotificaciones;
  late List<Map<Object?, Object?>> resultados;
  late bool permiso;
  late bool datos;
  late bool fallaConsulta;
  late bool fallaNotificacion;
  late int minutosAcreditados;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directorio = await Directory.systemTemp.createTemp('proto_monitoreo_');
    await databaseFactory.setDatabasesPath(directorio.path);
    db = await DatabaseHelper.instance.database;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
  });

  setUp(() async {
    await db.delete('uso_pantalla');
    await db.delete('recomendaciones');
    permiso = true;
    datos = true;
    fallaConsulta = false;
    fallaNotificacion = false;
    llamadasUso = [];
    llamadasNotificaciones = [];
    resultados = [];
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final fin = ahora.subtract(const Duration(milliseconds: 1));
    final inicioPropuesto = fin.subtract(const Duration(minutes: 2));
    final inicio = inicioPropuesto.isBefore(hoy) ? hoy : inicioPropuesto;
    minutosAcreditados = fin.difference(inicio).inMinutes;
    Map<String, String> evento(int tipo, DateTime instante) => {
          'eventType': '$tipo',
          'packageName': 'test.app',
          'timeStamp': '${instante.millisecondsSinceEpoch}',
        };
    final eventos = [
      evento(1, inicio),
      evento(2, fin),
      for (final dias in [2, 3]) ...[
        evento(15, DateTime(hoy.year, hoy.month, hoy.day - dias)),
        evento(1, DateTime(hoy.year, hoy.month, hoy.day - dias)),
        evento(2, DateTime(hoy.year, hoy.month, hoy.day - dias, 4)),
        evento(16, DateTime(hoy.year, hoy.month, hoy.day - dias, 4)),
      ],
    ];
    mensajero.setMockMethodCallHandler(uso, (llamada) async {
      llamadasUso.add(llamada);
      switch (llamada.method) {
        case 'isUsagePermission':
          return permiso;
        case 'queryUsageStats':
          if (fallaConsulta) throw PlatformException(code: 'consulta_fallida');
          return [
            if (datos)
              {'packageName': 'test.app', 'totalTimeInForeground': '18000000'},
          ];
        case 'queryEvents':
          final argumentos = llamada.arguments as Map;
          return eventos.where((e) {
            final instante = int.parse(e['timeStamp']!);
            return instante >= (argumentos['start'] as int) &&
                instante < (argumentos['end'] as int);
          }).toList();
        default:
          return null;
      }
    });
    mensajero.setMockMethodCallHandler(notificaciones, (llamada) async {
      llamadasNotificaciones.add(llamada);
      if (llamada.method == 'show' && fallaNotificacion) {
        throw PlatformException(code: 'notificacion_fallida');
      }
      return true;
    });
    mensajero.setMockMethodCallHandler(completado, (llamada) async {
      expect(llamada.method, 'completado');
      resultados.add(llamada.arguments as Map<Object?, Object?>);
      return null;
    });
  });

  tearDownAll(() async {
    for (final canal in [uso, notificaciones, completado]) {
      mensajero.setMockMethodCallHandler(canal, null);
    }
    debugDefaultTargetPlatformOverride = null;
    await db.close();
    await directorio.delete(recursive: true);
  });

  test('captura, evalúa y notifica con una consulta de estadísticas por ciclo',
      () async {
    await monitoreoCallbackDispatcher();
    expect(
        resultados.single, {'estado': 'ok', 'generadas': 1, 'notificadas': 1});
    expect((await db.query('uso_pantalla')).single['tiempoTotalMinutos'],
        minutosAcreditados);
    expect((await db.query('recomendaciones')).single['reglaId'], 'R7');
    expect(
        llamadasUso.where((c) => c.method == 'queryUsageStats'), hasLength(1));
    expect(llamadasUso.where((c) => c.method == 'queryEvents'), hasLength(2));
    expect(llamadasNotificaciones.map((c) => c.method),
        ['initialize', 'areNotificationsEnabled', 'show']);

    await monitoreoCallbackDispatcher();
    expect(resultados.last, {'estado': 'ok', 'generadas': 0, 'notificadas': 0});
    expect(await db.query('recomendaciones'), hasLength(1));
  });

  test('sin permiso o sin muestra no escribe un resumen de cero', () async {
    permiso = false;
    await monitoreoCallbackDispatcher();
    expect(resultados.single['estado'], 'sin_permiso_uso');
    expect(llamadasUso.map((c) => c.method), ['isUsagePermission']);

    permiso = true;
    datos = false;
    await monitoreoCallbackDispatcher();
    expect(resultados.last['estado'], 'sin_datos_uso');
    expect(await db.query('uso_pantalla'), isEmpty);
  });

  test('distingue error de captura de error posterior al commit', () async {
    fallaConsulta = true;
    await monitoreoCallbackDispatcher();
    expect(resultados.single['estado'], 'error_ciclo');
    expect(await db.query('uso_pantalla'), isEmpty);

    fallaConsulta = false;
    fallaNotificacion = true;
    await monitoreoCallbackDispatcher();
    expect(resultados.last['estado'], 'error_notificacion');
    expect(await db.query('recomendaciones'), hasLength(1));
  });
}
