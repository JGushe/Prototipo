// Pruebas del perfil local opcional y su diálogo.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/database/database_helper.dart';
import 'package:prototipo_tesis/models/perfil.dart';
import 'package:prototipo_tesis/screens/configuracion_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('proto_perfil_').path);

    // BD v7 sin tablas: la apertura del helper debe crear `perfil`.
    final ruta = '${await getDatabasesPath()}/prototipo_tesis.db';
    final vieja = await databaseFactory.openDatabase(
      ruta,
      options: OpenDatabaseOptions(version: 7, onCreate: (_, __) async {}),
    );
    await vieja.close();
  });

  setUp(() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('perfil');
  });

  test('sin perfil devuelve null', () async {
    expect(await DatabaseHelper.instance.obtenerPerfil(), isNull);
  });

  test('migración v7 -> v8 crea la tabla sin tocar nada más', () async {
    final db = await DatabaseHelper.instance.database;
    final columnas = await db.rawQuery('PRAGMA table_info(perfil)');
    expect(columnas.map((c) => c['name']),
        containsAll(['id', 'nombre', 'identidadGenero', 'autodescripcion']));
  });

  test('guarda nombre, identidad y descripción', () async {
    await DatabaseHelper.instance.guardarPerfil(const Perfil(
      nombre: 'Alex',
      identidadGenero: Perfil.otra,
      autodescripcion: 'Género fluido',
    ));

    final perfil = await DatabaseHelper.instance.obtenerPerfil();
    expect(perfil!.nombre, 'Alex');
    expect(perfil.identidadGenero, Perfil.otra);
    expect(perfil.identidadVisible, 'Género fluido');
  });

  test('editar y eliminar la identidad conserva el nombre y una sola fila',
      () async {
    await DatabaseHelper.instance.guardarPerfil(
        const Perfil(nombre: 'Alex', identidadGenero: Perfil.femenino));
    await DatabaseHelper.instance.guardarPerfil(
        const Perfil(nombre: 'Alex', identidadGenero: Perfil.noBinario));
    await DatabaseHelper.instance
        .guardarPerfil(const Perfil(nombre: 'Alex', identidadGenero: null));

    final perfil = await DatabaseHelper.instance.obtenerPerfil();
    expect(perfil!.nombre, 'Alex');
    expect(perfil.identidadGenero, isNull);
    expect(perfil.identidadVisible, isNull);

    final filas = await (await DatabaseHelper.instance.database)
        .query('perfil');
    expect(filas, hasLength(1));
  });

  testWidgets('el diálogo permite elegir, autodescribir y guardar',
      (tester) async {
    Perfil? guardado;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PerfilDialog(
          perfilInicial: const Perfil(),
          alGuardar: (p) async => guardado = p,
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Configura tu perfil'), findsOneWidget);
    expect(find.text('Identidad de género (opcional)'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Nombre o apodo (opcional)'), 'Sam');
    await tester.tap(find.text('Otra identidad'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Describe tu identidad (opcional)'),
        'No binario');
    await tester.tap(find.text('Guardar'));
    await tester.pump();

    expect(guardado!.nombre, 'Sam');
    expect(guardado!.identidadGenero, Perfil.otra);
    expect(guardado!.autodescripcion, 'No binario');
  });

  testWidgets('seleccionar la opción activa la quita', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PerfilDialog(
          perfilInicial: const Perfil(),
          alGuardar: (_) async {},
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Prefiero no responder'));
    await tester.pumpAndSettle();
    expect(find.text('Eliminar respuesta'), findsOneWidget);

    await tester.tap(find.text('Eliminar respuesta'));
    await tester.pumpAndSettle();
    expect(find.text('Eliminar respuesta'), findsNothing);
  });
}
