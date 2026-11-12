// Apariencia: migración v9, persistencia y sugerencia por identidad.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/database/database_helper.dart';
import 'package:prototipo_tesis/models/perfil.dart';
import 'package:prototipo_tesis/theme/app_palettes.dart';
import 'package:prototipo_tesis/theme/theme_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final controller = AparienciaController.instance;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('proto_apariencia_').path);

    // BD v8 con un perfil que ya declaró identidad.
    final ruta = '${await getDatabasesPath()}/prototipo_tesis.db';
    final v8 = await databaseFactory.openDatabase(
      ruta,
      options: OpenDatabaseOptions(
        version: 8,
        onCreate: (d, _) async {
          await d.execute('''
            CREATE TABLE perfil (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              nombre TEXT,
              identidadGenero TEXT,
              autodescripcion TEXT
            )
          ''');
          await d.insert('perfil', {
            'id': 1,
            'nombre': 'Ana',
            'identidadGenero': Perfil.femenino,
          });
        },
      ),
    );
    await v8.close();
  });

  test('migración v8 -> v9 conserva el perfil', () async {
    final db = await DatabaseHelper.instance.database;
    final columnas = await db.rawQuery('PRAGMA table_info(perfil)');
    expect(columnas.map((c) => c['name']),
        containsAll(['temaModo', 'paleta']));
    final fila = await db.query('perfil', where: 'id = 1');
    expect(fila.single['nombre'], 'Ana');
    expect(fila.single['identidadGenero'], Perfil.femenino);
  });

  test('sin preferencias: sistema y paleta sugerida por identidad', () async {
    await controller.cargar();
    expect(controller.value.modo, ThemeMode.system);
    expect(controller.value.manual, isNull);
    expect(controller.value.familia, FamiliaPaleta.warm);
    expect(controller.value.clara, AppPaletteId.lightWarm);
    expect(controller.value.oscura, AppPaletteId.darkWarm);
  });

  test('selección manual persiste y no toca el perfil', () async {
    await controller.setModo(ThemeMode.dark);
    await controller.setFamilia(FamiliaPaleta.rgb);

    final ap = await DatabaseHelper.instance.obtenerApariencia();
    expect(ap.modo, 'dark');
    expect(ap.paleta, 'rgb');

    final perfil = await DatabaseHelper.instance.obtenerPerfil();
    expect(perfil!.nombre, 'Ana');
    expect(perfil.identidadGenero, Perfil.femenino);
    expect(controller.value.clara, AppPaletteId.lightRgb);
  });

  test('cambiar identidad no pisa la elección manual', () async {
    await controller.setFamilia(FamiliaPaleta.cool);
    await DatabaseHelper.instance.guardarPerfil(
        const Perfil(nombre: 'Ana', identidadGenero: Perfil.masculino));

    await controller.recargarSugerencia();
    expect(controller.value.sugerida, FamiliaPaleta.cool);
    expect(controller.value.familia, FamiliaPaleta.cool);
  });

  test('sin elección manual, la identidad cambia la sugerencia', () async {
    // Reabre un estado sin paleta manual.
    await DatabaseHelper.instance.guardarApariencia(modo: 'system', paleta: null);
    await controller.cargar();
    expect(controller.value.manual, isNull);
    expect(controller.value.familia, FamiliaPaleta.cool); // masculino

    await DatabaseHelper.instance.guardarPerfil(
        const Perfil(nombre: 'Ana', identidadGenero: Perfil.otra));
    await controller.recargarSugerencia();
    expect(controller.value.familia, FamiliaPaleta.rgb);

    await DatabaseHelper.instance
        .guardarPerfil(const Perfil(nombre: 'Ana', identidadGenero: null));
    await controller.recargarSugerencia();
    expect(controller.value.familia, FamiliaPaleta.cool);
  });

  test('las seis combinaciones resuelven a su paleta', () {
    for (final familia in FamiliaPaleta.values) {
      final ap = Apariencia(modo: ThemeMode.system, sugerida: familia);
      expect(ap.clara, isNotNull);
      expect(ap.oscura, isNotNull);
      expect(ap.clara, isNot(ap.oscura));
    }
  });
}
