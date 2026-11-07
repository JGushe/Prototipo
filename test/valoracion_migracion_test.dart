// Pruebas SQLite de la valoración de Tips y de la migración v6 -> v7.
//
// Usa un directorio temporal propio para no compartir `prototipo_tesis.db`
// con otras pruebas que abren la base en paralelo.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:prototipo_tesis/database/database_helper.dart';
import 'package:prototipo_tesis/models/recomendacion.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _ddlV6 = '''
CREATE TABLE recomendaciones (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  fecha TEXT NOT NULL,
  tipo TEXT NOT NULL,
  titulo TEXT NOT NULL,
  mensaje TEXT NOT NULL,
  leida INTEGER NOT NULL DEFAULT 0,
  reglaId TEXT,
  severidad TEXT NOT NULL DEFAULT 'info',
  motivo TEXT,
  clave TEXT
)
''';

Recomendacion _rec(String titulo, {DateTime? fecha}) => Recomendacion(
      fecha: fecha ?? DateTime(2026, 9, 19, 10),
      tipo: 'pausa',
      titulo: titulo,
      mensaje: 'm',
      severidad: 'info',
    );

String? _valoracionDe(List<Map<String, Object?>> filas, String titulo) =>
    filas.firstWhere((f) => f['titulo'] == titulo)['valoracion'] as String?;

void main() {
  late Database db;
  late List<Map<String, Object?>> columnas;
  late List<Map<String, Object?>> filasSemilla;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('proto_valoracion_').path);

    final ruta = p.join(await getDatabasesPath(), 'prototipo_tesis.db');
    final v6 = await databaseFactory.openDatabase(
      ruta,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (d, _) async => d.execute(_ddlV6),
      ),
    );
    await v6.insert('recomendaciones', {
      'fecha': '2026-09-19T10:00:00.000',
      'tipo': 'pausa',
      'titulo': 'Vieja',
      'mensaje': 'm',
      'leida': 0,
      'severidad': 'info',
    });
    await v6.close();

    db = await DatabaseHelper.instance.database; // ejecuta la migración
    columnas = await db.rawQuery('PRAGMA table_info(recomendaciones)');
    filasSemilla = await db.query('recomendaciones');
  });

  setUp(() async {
    await db.delete('recomendaciones');
  });

  test('migración v6 -> v7 añade valoracion y conserva filas', () {
    expect(columnas.map((c) => c['name']), contains('valoracion'));
    expect(filasSemilla, hasLength(1));
    expect(filasSemilla.single['titulo'], 'Vieja');
    expect(filasSemilla.single['valoracion'], isNull);
  });

  test('guardar, rectificar y quitar la valoración sin duplicar', () async {
    final id = await DatabaseHelper.instance.insertarRecomendacion(_rec('R1'));

    await DatabaseHelper.instance.valorarRecomendacion(id, 'util');
    var filas = await db.query('recomendaciones');
    expect(filas, hasLength(1));
    expect(filas.single['valoracion'], 'util');

    await DatabaseHelper.instance.valorarRecomendacion(id, 'no_util');
    filas = await db.query('recomendaciones');
    expect(filas, hasLength(1));
    expect(filas.single['valoracion'], 'no_util');

    await DatabaseHelper.instance.valorarRecomendacion(id, null);
    filas = await db.query('recomendaciones');
    expect(filas.single['valoracion'], isNull);
  });

  test('resumen: solo cuenta valoradas y calcula porcentaje', () async {
    await DatabaseHelper.instance.insertarRecomendacion(_rec('A'));
    await DatabaseHelper.instance.insertarRecomendacion(_rec('B'));
    await DatabaseHelper.instance.insertarRecomendacion(_rec('C'));
    final filas = await db.query('recomendaciones', orderBy: 'id ASC');
    final ids = filas.map((f) => f['id'] as int).toList();

    await DatabaseHelper.instance.valorarRecomendacion(ids[0], 'util');
    await DatabaseHelper.instance.valorarRecomendacion(ids[1], 'no_util');
    // La tercera queda sin respuesta: no entra en el denominador.

    final resumen = await DatabaseHelper.instance.obtenerResumenValoraciones();
    expect(resumen.total, 2);
    expect(resumen.utiles, 1);
    expect(resumen.noUtiles, 1);
    expect(resumen.porcentajeUtil, 50);
    expect(resumen.muestraSuficiente, isFalse);
  });

  test('sin valoraciones: total 0 y porcentaje nulo', () async {
    await DatabaseHelper.instance.insertarRecomendacion(_rec('D'));

    final resumen = await DatabaseHelper.instance.obtenerResumenValoraciones();
    expect(resumen.total, 0);
    expect(resumen.porcentajeUtil, isNull);
    expect(resumen.muestraSuficiente, isFalse);
  });

  test('el resumen por periodo solo cuenta su ventana', () async {
    final a = await DatabaseHelper.instance.insertarRecomendacion(_rec('A'));
    final b = await DatabaseHelper.instance.insertarRecomendacion(
        _rec('B', fecha: DateTime(2026, 9, 20, 10)));
    // Borde: 23:59 del día 19 sigue dentro del día 19.
    final c = await DatabaseHelper.instance.insertarRecomendacion(
        _rec('C', fecha: DateTime(2026, 9, 19, 23, 59)));

    await DatabaseHelper.instance.valorarRecomendacion(a, 'util');
    await DatabaseHelper.instance.valorarRecomendacion(b, 'no_util');
    await DatabaseHelper.instance.valorarRecomendacion(c, 'util');

    final dia19 = await DatabaseHelper.instance.obtenerResumenValoracionesEntre(
        DateTime(2026, 9, 19), DateTime(2026, 9, 19));
    expect(dia19.generadas, 2);
    expect(dia19.total, 2);
    expect(dia19.utiles, 2);

    final dia20 = await DatabaseHelper.instance.obtenerResumenValoracionesEntre(
        DateTime(2026, 9, 20), DateTime(2026, 9, 20));
    expect(dia20.generadas, 1);
    expect(dia20.total, 1);
    expect(dia20.utiles, 0);
    expect(dia20.porcentajeUtil, 0);
  });

  test('la valoración persiste en una conexión nueva', () async {
    final id = await DatabaseHelper.instance.insertarRecomendacion(_rec('E'));
    await DatabaseHelper.instance.valorarRecomendacion(id, 'util');

    final ruta = p.join(await getDatabasesPath(), 'prototipo_tesis.db');
    final otra = await databaseFactory.openDatabase(ruta);
    final fila = await otra.query('recomendaciones',
        where: 'id = ?', whereArgs: [id]);
    expect(_valoracionDe(fila, 'E'), 'util');
    await otra.close();
  });
}
