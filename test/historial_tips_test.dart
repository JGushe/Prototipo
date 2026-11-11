import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/database/database_helper.dart';
import 'package:prototipo_tesis/models/recomendacion.dart';
import 'package:prototipo_tesis/services/historial_tips_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final helper = DatabaseHelper.instance;
  late Directory temporal;
  late Database db;
  var preferencias = <String>[];
  var fallarPreferencias = false;
  final fecha = DateTime(2026, 11, 10, 12);

  Future<void> insertar(int cantidad, {DateTime? momento}) async {
    final batch = db.batch();
    for (var i = 0; i < cantidad; i++) {
      batch.insert(
          'recomendaciones',
          Recomendacion(
                  fecha: momento ?? fecha,
                  tipo: 'pausa',
                  titulo: 'Consejo $i',
                  mensaje: 'Prueba aislada')
              .toMap());
    }
    await batch.commit(noResult: true);
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temporal = await Directory.systemTemp.createTemp('tips_historial_');
    await databaseFactory.setDatabasesPath(temporal.path);
    db = await helper.database;
  });
  tearDownAll(() async {
    await db.close();
    await temporal.delete(recursive: true);
  });
  setUp(() async {
    await db.delete('recomendaciones');
    preferencias = [];
    fallarPreferencias = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HistorialTipsController.preferencias,
            (call) async {
      if (fallarPreferencias) throw PlatformException(code: 'fallo');
      if (call.method == 'leerFechasOcultas') return preferencias;
      preferencias = List<String>.from(call.arguments as List);
      return null;
    });
  });

  for (final cantidad in [0, 1, 49, 50, 51]) {
    test('$cantidad registros: límite reciente y archivo sin modificar filas',
        () async {
      await insertar(cantidad);
      final antes = await db.query('recomendaciones');
      final h = HistorialTipsController();
      await h.cargar();
      expect(h.recientes.length, cantidad > 50 ? 50 : cantidad);
      expect(h.archivo.length, cantidad > 50 ? cantidad - 50 : 0);
      expect(h.hayMas, isFalse);
      if (cantidad == 51) expect(h.fechaCompartida('2026-11-10'), isTrue);
      expect(await db.query('recomendaciones'), antes);
      h.dispose();
    });
  }

  test('páginas estables con empates y nuevas inserciones; actualizar reinicia',
      () async {
    await insertar(151);
    final h = HistorialTipsController();
    await h.cargar();
    final originales = [...h.recientes, ...h.archivo].map((r) => r.id).toSet();
    expect(originales, hasLength(100));
    await insertar(1, momento: DateTime(2026, 11, 11));
    await insertar(1, momento: DateTime(2026, 1, 1));
    final pendiente = h.cargarMas();
    expect(h.cargarMas(), same(pendiente));
    await pendiente;
    await h.cargarMas();
    final ids = [...h.recientes, ...h.archivo].map((r) => r.id).toList();
    expect(ids, hasLength(151));
    expect(ids.toSet(), hasLength(151));
    expect(h.hayMas, isFalse);
    h.mostrarArchivo(true);
    await h.cargar();
    expect(h.viendoArchivo, isTrue);
    expect(h.archivo, hasLength(50));
    while (h.hayMas) {
      await h.cargarMas();
    }
    final todos = [...h.recientes, ...h.archivo];
    expect(todos, hasLength(153));
    expect(todos.map((r) => r.id).toSet(), hasLength(153));
    expect(todos.first.fecha, DateTime(2026, 11, 11));
    h.dispose();
  });

  test(
      'filtro persiste, no rellena recientes y no oculta archivo ni fechas nuevas',
      () async {
    await insertar(51);
    final h = HistorialTipsController();
    await h.cargar();
    final estadisticas = await helper.obtenerResumenValoraciones();
    await h.guardarOcultas({'2026-11-10'});
    expect(h.grupos, isEmpty);
    expect(h.recientes, hasLength(50));
    h.mostrarArchivo(true);
    expect(h.grupos.values.single, hasLength(1));
    h.dispose();
    await insertar(1, momento: DateTime(2026, 11, 11));
    final otro = HistorialTipsController();
    await otro.cargar();
    expect(otro.ocultas, {'2026-11-10'});
    expect(otro.grupos.keys, ['2026-11-11']);
    await otro.guardarOcultas({});
    expect(otro.grupos.length, 2);
    expect((await helper.obtenerResumenValoraciones()).generadas,
        estadisticas.generadas + 1);
    otro.dispose();
  });

  test('leer y valorar en ambas vistas conservan orden y páginas', () async {
    await insertar(51);
    final h = HistorialTipsController();
    await h.cargar();
    final ids = [...h.recientes, ...h.archivo].map((r) => r.id).toList();
    for (final r in [h.recientes.first, h.archivo.first]) {
      await h.actualizarRecomendacion(r, leer: true);
      await h.actualizarRecomendacion(r, valoracion: 'util');
    }
    expect([...h.recientes, ...h.archivo].map((r) => r.id), ids);
    expect(h.recientes.first.leida, isTrue);
    expect(h.archivo.first.valoracion, 'util');
    final resumen = await helper.obtenerResumenValoraciones();
    expect(resumen.generadas, 51);
    expect(resumen.utiles, 2);
    h.dispose();
  });

  test('recarga invalida una página pendiente y dispose no notifica tarde',
      () async {
    await insertar(151);
    final h = HistorialTipsController();
    await h.cargar();
    final iniciada = Completer<void>();
    final liberar = Completer<void>();
    final bloqueo = db.transaction((tx) async {
      iniciada.complete();
      await liberar.future;
    });
    await iniciada.future;
    final pagina = h.cargarMas();
    final recarga = h.cargar();
    expect(h.cargar(), same(recarga));
    liberar.complete();
    await bloqueo;
    await pagina;
    await recarga;
    expect(h.archivo, hasLength(50));
    var avisos = 0;
    h.addListener(() => avisos++);
    final ultima = h.cargar();
    final antes = avisos;
    h.dispose();
    await ultima;
    expect(avisos, antes);
  });

  test(
      'errores de preferencias y consulta conservan datos y permiten reintentar',
      () async {
    await insertar(1);
    fallarPreferencias = true;
    final h = HistorialTipsController();
    await h.cargar();
    expect(h.errorPreferencias, isTrue);
    expect(h.recientes, hasLength(1));
    await expectLater(
        h.guardarOcultas({'2026-11-10'}), throwsA(isA<PlatformException>()));
    expect(h.ocultas, isEmpty);
    fallarPreferencias = false;
    await h.cargar();
    expect(h.errorPreferencias, isFalse);
    await db.execute(
        'ALTER TABLE recomendaciones RENAME TO recomendaciones_prueba');
    try {
      await h.cargar();
      expect(h.error, isTrue);
      expect(h.recientes, hasLength(1));
    } finally {
      await db.execute(
          'ALTER TABLE recomendaciones_prueba RENAME TO recomendaciones');
    }
    await h.cargar();
    expect(h.error, isFalse);
    h.dispose();
  });

  test(
      'comprobaciones comparten consulta y conservan páginas si no hay novedades',
      () async {
    await insertar(151);
    final h = HistorialTipsController();
    await h.cargar();
    await h.cargarMas();
    final grupos = h.grupos;
    final pendiente = h.comprobarCambios();
    expect(h.comprobarCambios(), same(pendiente));
    expect(await pendiente, isFalse);
    expect(h.grupos, same(grupos));
    expect(h.archivo, hasLength(100));
    h.mostrarArchivo(true);
    await insertar(1, momento: DateTime(2026, 11, 11));
    expect(await h.comprobarCambios(), isTrue);
    expect(h.archivo, hasLength(50));
    expect(h.viendoArchivo, isTrue);
    expect(h.recientes.first.fecha, DateTime(2026, 11, 11));
    h.dispose();
  });

  test(
      'cambio de día invalida la instantánea aunque no haya nuevas recomendaciones',
      () async {
    var ahora = DateTime(2026, 11, 30, 23, 59);
    await insertar(151);
    final h = HistorialTipsController(reloj: () => ahora);
    await h.cargar();
    await h.cargarMas();
    expect(h.archivo, hasLength(100));
    ahora = DateTime(2026, 12, 1);
    expect(await h.comprobarCambios(), isTrue);
    expect(h.archivo, hasLength(50));
    expect(await h.comprobarCambios(), isFalse);
    h.dispose();
  });

  test('clave de agrupación usa calendario local al cambiar mes y año', () {
    expect(HistorialTipsController.dia(DateTime(2027, 1, 0, 23, 59)),
        '2026-12-31');
    expect(HistorialTipsController.dia(DateTime(2027, 1, 1)), '2027-01-01');
    final utc = DateTime.utc(2026, 11, 1, 2);
    expect(HistorialTipsController.dia(utc),
        '${utc.toLocal().year}-${utc.toLocal().month.toString().padLeft(2, '0')}-${utc.toLocal().day.toString().padLeft(2, '0')}');
  });

  test('valorar y leer notifican solo la tarjeta y el contador afectados',
      () async {
    await insertar(3);
    final h = HistorialTipsController();
    await h.cargar();
    expect(h.grupos, same(h.grupos));
    final r = h.recientes.first;
    final tarjeta = h.tarjeta(r);
    final otra = h.tarjeta(h.recientes.last);
    final contador = h.sinLeer('2026-11-10');
    var generales = 0, cambios = 0, otras = 0, contadores = 0;
    h.addListener(() => generales++);
    tarjeta.addListener(() => cambios++);
    otra.addListener(() => otras++);
    contador.addListener(() => contadores++);
    await h.actualizarRecomendacion(r, valoracion: 'util');
    expect(tarjeta.value.valoracion, 'util');
    expect(h.grupos.values.single.first.valoracion, 'util');
    expect([generales, cambios, otras, contadores], [0, 1, 0, 0]);
    await h.actualizarRecomendacion(r, leer: true);
    expect(contador.value, 2);
    expect([generales, cambios, otras, contadores], [0, 2, 0, 1]);
    h.dispose();
  });
}
