// Pruebas SQLite reales (sqflite_common_ffi) de la escritura compuesta de uso.
//
// `guardarUsoDelDia` debe escribir resumen + detalle por app como una sola
// unidad: si falla una app, no puede quedar un resumen del día a medias.

import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/database/database_helper.dart';
import 'package:prototipo_tesis/models/contexto_recomendacion.dart';
import 'package:prototipo_tesis/models/uso_pantalla.dart';
import 'package:prototipo_tesis/services/motor_recomendaciones.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

UsoPantalla _uso(int minutos) => UsoPantalla(
      fecha: DateTime(2026, 9, 20),
      tiempoTotalMinutos: minutos,
      numeroDesbloqueos: 4,
      appMasUsada: 'WhatsApp',
      tiempoAppMasUsada: 60,
    );

AppUso _app(String paquete, int minutos) => AppUso(
      nombrePaquete: paquete,
      nombreApp: paquete,
      tiempoUsoMinutos: minutos,
      numeroAperturas: 3,
    );

void main() {
  late Directory directorio;
  late Database db;
  final helper = DatabaseHelper.instance;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    directorio = await Directory.systemTemp.createTemp('proto_transacciones_');
    await databaseFactory.setDatabasesPath(directorio.path);
    final apertura = helper.database;
    expect(helper.database, same(apertura));
    db = await apertura;
  });

  tearDownAll(() async {
    await db.close();
    await directorio.delete(recursive: true);
  });

  setUp(() async {
    await db.delete('app_uso');
    await db.delete('uso_pantalla');
    await db.delete('recomendaciones');
    await db.execute('DROP TRIGGER IF EXISTS falla_app_uso');
    await db.execute('DROP TRIGGER IF EXISTS falla_recomendacion');
  });

  test('dos escrituras directas por paquete no duplican filas', () async {
    final app = _app('com.whatsapp', 60);
    final fecha = _uso(120).fecha;
    await Future.wait([
      helper.insertarOActualizarAppUso(app, fecha: fecha),
      helper.insertarOActualizarAppUso(app, fecha: fecha),
    ]);
    expect(await db.query('app_uso'), hasLength(1));
  });

  test('dos capturas simultáneas dejan un resumen y detalle coherentes',
      () async {
    await Future.wait([
      helper.guardarUsoDelDia(_uso(120), [_app('com.whatsapp', 120)]),
      helper.guardarUsoDelDia(_uso(200), [_app('com.whatsapp', 200)]),
    ]);
    final resumen = (await db.query('uso_pantalla')).single;
    final app = (await db.query('app_uso')).single;
    expect(resumen['tiempoTotalMinutos'], anyOf(120, 200));
    expect(app['tiempoUsoMinutos'], resumen['tiempoTotalMinutos']);
  });

  test('dos motores comparten el cooldown persistido y conservan valoraciones',
      () async {
    final momento = DateTime(2026, 9, 20, 10);
    final contexto = ContextoRecomendacion(
      momento: momento,
      tiempoTotalPantallaMinutos: 300,
      hayDatosUsoPantalla: true,
    );
    final primero = MotorRecomendaciones();
    final segundo = MotorRecomendaciones();
    final resultados = await Future.wait([
      primero.ejecutar(contexto: contexto),
      segundo.ejecutar(contexto: contexto),
    ]);
    expect(resultados.expand((r) => r.generadas).map((r) => r.reglaId), ['R5']);
    expect(
        resultados.expand((r) => r.descartadas).map((r) => r.reglaId), ['R5']);

    final fila = (await db.query('recomendaciones')).single;
    await helper.valorarRecomendacion(fila['id'] as int, 'util');
    final reintento = await segundo.ejecutar(contexto: contexto);
    expect(reintento.generadas, isEmpty);
    expect(await db.query('recomendaciones'), [
      {...fila, 'valoracion': 'util'},
    ]);
  });

  test('dos isolates coordinan capturas y cooldown en el mismo archivo',
      () async {
    final ruta = directorio.path;
    final generadas = await Future.wait([
      _ejecutarEnIsolate(ruta, 120),
      _ejecutarEnIsolate(ruta, 200),
    ]);
    expect(generadas, unorderedEquals([0, 1]));
    final resumen = (await db.query('uso_pantalla')).single;
    final app = (await db.query('app_uso')).single;
    expect(app['tiempoUsoMinutos'], resumen['tiempoTotalMinutos']);
    expect((await db.query('recomendaciones')).single['reglaId'], 'R5');
  });

  test('un fallo al guardar la segunda recomendación revierte el ciclo',
      () async {
    await db.execute('''
      CREATE TRIGGER falla_recomendacion BEFORE INSERT ON recomendaciones
      WHEN (SELECT COUNT(*) FROM recomendaciones) = 1
      BEGIN SELECT RAISE(ABORT, 'fallo simulado'); END
    ''');
    final contexto = ContextoRecomendacion(
      momento: DateTime(2026, 9, 20, 10),
      tiempoTotalPantallaMinutos: 300,
      hayDatosUsoPantalla: true,
      minutosUsoNocturno: 421,
    );
    final motor = MotorRecomendaciones();
    await expectLater(
      motor.ejecutar(contexto: contexto),
      throwsA(isA<DatabaseException>()),
    );
    expect(await db.query('recomendaciones'), isEmpty);
    await db.execute('DROP TRIGGER falla_recomendacion');
    expect((await motor.ejecutar(contexto: contexto)).generadas, hasLength(2));
  });

  test('una captura conserva filas históricas incluso si ya estaban duplicadas',
      () async {
    final antigua = _app('com.whatsapp', 30);
    final datos = {...antigua.toMap(), 'fecha': '2026-09-19'};
    await db.insert('app_uso', datos);
    await db.insert('app_uso', {...datos, 'tiempoUsoMinutos': 45});
    final historial = await db.query('app_uso', orderBy: 'id');

    await helper.guardarUsoDelDia(_uso(120), [_app('com.whatsapp', 120)]);
    expect(
        await db.query('app_uso',
            where: 'fecha = ?', whereArgs: ['2026-09-19'], orderBy: 'id'),
        historial);
  });

  test('guarda resumen y detalle del día juntos', () async {
    await DatabaseHelper.instance.guardarUsoDelDia(_uso(120), [
      _app('com.whatsapp', 60),
      _app('com.instagram', 60),
    ]);

    final usos = await db.query('uso_pantalla');
    final apps = await db.query('app_uso');

    expect(usos, hasLength(1));
    expect(usos.single['tiempoTotalMinutos'], 120);
    expect(apps, hasLength(2));
  });

  test('una segunda captura del mismo día actualiza sin duplicar', () async {
    await DatabaseHelper.instance.guardarUsoDelDia(_uso(120), [
      _app('com.whatsapp', 60),
      _app('com.instagram', 60),
    ]);
    await DatabaseHelper.instance.guardarUsoDelDia(_uso(200), [
      _app('com.whatsapp', 120),
      _app('com.instagram', 80),
    ]);

    final usos = await db.query('uso_pantalla');
    final apps = await db.query('app_uso', orderBy: 'tiempoUsoMinutos DESC');

    expect(usos, hasLength(1));
    expect(usos.single['tiempoTotalMinutos'], 200);
    expect(apps, hasLength(2));
    expect(apps.first['tiempoUsoMinutos'], 120);
  });

  test('si falla una app, la transacción revierte todo el día', () async {
    // Estado previo consistente: una captura válida del mismo día.
    await DatabaseHelper.instance.guardarUsoDelDia(_uso(120), [
      _app('com.whatsapp', 60),
    ]);

    // El trigger hace fallar la inserción de 'com.falla' a mitad del lote.
    await db.execute('''
      CREATE TRIGGER falla_app_uso BEFORE INSERT ON app_uso
      WHEN NEW.nombrePaquete = 'com.falla'
      BEGIN SELECT RAISE(ABORT, 'fallo simulado'); END
    ''');

    await expectLater(
      DatabaseHelper.instance.guardarUsoDelDia(_uso(999), [
        _app('com.tiktok', 30),
        _app('com.falla', 30),
      ]),
      throwsA(isA<DatabaseException>()),
    );

    // Nada de la captura fallida quedó escrito; se conserva la previa.
    final usos = await db.query('uso_pantalla');
    final apps = await db.query('app_uso');

    expect(usos, hasLength(1));
    expect(usos.single['tiempoTotalMinutos'], 120);
    expect(apps, hasLength(1));
    expect(apps.single['nombrePaquete'], 'com.whatsapp');
  });
}

Future<int> _ejecutarEnIsolate(String ruta, int minutos) =>
    Isolate.run(() => _capturarYRecomendar(ruta, minutos));

Future<int> _capturarYRecomendar(String ruta, int minutos) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  await databaseFactory.setDatabasesPath(ruta);
  final helper = DatabaseHelper.instance;
  final db = await helper.database;
  // FFI usa conexiones separadas. Da tiempo a la otra para confirmar.
  await db.execute('PRAGMA busy_timeout = 5000');
  try {
    await helper
        .guardarUsoDelDia(_uso(minutos), [_app('com.whatsapp', minutos)]);
    final resultado = await MotorRecomendaciones().ejecutar(
      contexto: ContextoRecomendacion(
        momento: DateTime(2026, 9, 20, 10),
        tiempoTotalPantallaMinutos: 300,
        hayDatosUsoPantalla: true,
      ),
    );
    return resultado.generadas.length;
  } finally {
    await db.close();
  }
}
