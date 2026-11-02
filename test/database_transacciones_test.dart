// Pruebas SQLite reales (sqflite_common_ffi) de la escritura compuesta de uso.
//
// `guardarUsoDelDia` debe escribir resumen + detalle por app como una sola
// unidad: si falla una app, no puede quedar un resumen del día a medias.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:prototipo_tesis/database/database_helper.dart';
import 'package:prototipo_tesis/models/uso_pantalla.dart';
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
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Base limpia por ejecución: el helper es un singleton por isolate.
    final archivo = File(p.join(await getDatabasesPath(), 'prototipo_tesis.db'));
    if (await archivo.exists()) await archivo.delete();
  });

  setUp(() async {
    db = await DatabaseHelper.instance.database;
    await db.delete('app_uso');
    await db.delete('uso_pantalla');
    await db.execute('DROP TRIGGER IF EXISTS falla_app_uso');
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
