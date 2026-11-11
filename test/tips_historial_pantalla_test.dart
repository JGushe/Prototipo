import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/database/database_helper.dart';
import 'package:prototipo_tesis/main.dart';
import 'package:prototipo_tesis/models/perfil.dart';
import 'package:prototipo_tesis/models/comparacion_diaria.dart';
import 'package:prototipo_tesis/models/recomendacion.dart';
import 'package:prototipo_tesis/screens/recomendaciones_screen.dart';
import 'package:prototipo_tesis/services/historial_tips_controller.dart';
import 'package:prototipo_tesis/services/lectura_uso_controller.dart';
import 'package:prototipo_tesis/services/uso_pantalla_service.dart';
import 'package:prototipo_tesis/theme/app_palettes.dart';
import 'package:prototipo_tesis/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Uso extends UsoPantallaService {
  @override
  Future<ComparacionDiaria> compararHoyAyer({DateTime? ahora}) async =>
      ComparacionDiaria.insuficiente(
          ahora: ahora!, corte: ahora, explicacion: 'Sin sesiones');
}

class _HistorialMedido extends HistorialTipsController {
  int cargas = 0;
  int gruposConsultados = 0;
  final tarjetasCreadas = <int>{};
  @override
  Future<void> cargar() {
    cargas++;
    return super.cargar();
  }

  @override
  Map<String, List<Recomendacion>> get grupos {
    gruposConsultados++;
    return super.grupos;
  }

  @override
  ValueListenable<Recomendacion> tarjeta(Recomendacion rec) {
    tarjetasCreadas.add(rec.id!);
    return super.tarjeta(rec);
  }
}

Future<void> esperar(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }
  fail('La carga no terminó');
}

Future<void> irA(WidgetTester tester, Finder elemento) async {
  if (elemento.evaluate().isEmpty) {
    await tester.scrollUntilVisible(elemento, 240,
        scrollable: find.byType(Scrollable).first, maxScrolls: 50);
  }
  await tester.ensureVisible(elemento);
  await tester.pumpAndSettle();
}

Future<void> arriba(WidgetTester tester) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final helper = DatabaseHelper.instance;
  late Database db;
  late Directory temporal;
  var ocultas = <String>[];
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temporal = await Directory.systemTemp.createTemp('tips_interfaz_');
    await databaseFactory.setDatabasesPath(temporal.path);
    db = await helper.database;
  });
  tearDownAll(() async {
    await db.close();
    await temporal.delete(recursive: true);
  });
  setUp(() async {
    await db.delete('recomendaciones');
    ocultas = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HistorialTipsController.preferencias,
            (call) async {
      if (call.method == 'leerFechasOcultas') return ocultas;
      ocultas = List<String>.from(call.arguments as List);
      return null;
    });
  });
  for (final oscura in [false, true]) {
    testWidgets('grupos, filtro y archivo en pantalla pequeña; oscuro=$oscura',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final hoy = DateTime.now();
      await tester.runAsync(() async {
        final batch = db.batch();
        for (var i = 0; i < 52; i++) {
          batch.insert(
              'recomendaciones',
              Recomendacion(
                fecha: i == 51
                    ? hoy
                    : DateTime(hoy.year, hoy.month, hoy.day - 1, 12),
                tipo: 'pausa',
                titulo: i == 51 ? 'Tip de hoy' : 'Tip anterior $i',
                mensaje: 'Mensaje de prueba',
                motivo: i == 50 ? 'Motivo del consejo anterior' : null,
              ).toMap());
        }
        await batch.commit(noResult: true);
      });
      final lectura = LecturaUsoController(uso: _Uso());
      await lectura.leer();
      final captura = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: captura,
          child: MaterialApp(
            theme: AppTheme.of(
                oscura ? AppPaletteId.darkCool : AppPaletteId.lightCool),
            home: RecomendacionesScreen(lectura: lectura),
          )));
      await esperar(tester);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final imagen = await (captura.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
        await File('build/tips-redisenado-${oscura ? 'oscuro' : 'claro'}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        imagen.dispose();
      });
      await irA(tester, find.text('Tip de hoy'));
      expect(find.text('Tip de hoy'), findsOneWidget);
      expect(find.text('Tip anterior 50'), findsNothing);
      await irA(tester, find.text('Ayer'));
      await tester.tap(find.text('Ayer'));
      await tester.pumpAndSettle();
      expect(find.text('Más recomendaciones de esta fecha en el archivo.'),
          findsOneWidget);
      await irA(tester, find.text('Tip anterior 50'));
      expect(find.text('Tip anterior 50'), findsOneWidget);
      expect(find.text('Motivo del consejo anterior'), findsNothing);
      await irA(tester, find.text('Por qué este consejo'));
      await tester.tap(find.text('Por qué este consejo'));
      await tester.pumpAndSettle();
      expect(find.text('Motivo del consejo anterior'), findsOneWidget);
      await arriba(tester);
      await irA(tester, find.text('Ayer'));
      await tester.tap(find.text('Ayer'));
      await tester.pumpAndSettle();

      await arriba(tester);
      await irA(tester, find.text('Fechas visibles'));
      await tester.tap(find.text('Fechas visibles'));
      await tester.pumpAndSettle();
      for (final checkbox
          in find.byType(CheckboxListTile).evaluate().toList()) {
        await tester.tap(find.byWidget(checkbox.widget));
        await tester.pump();
      }
      await tester.tap(find.text('Guardar'));
      await esperar(tester);
      await tester.pumpAndSettle();
      expect(find.text('No hay recomendaciones para las fechas seleccionadas'),
          findsOneWidget);
      expect(ocultas, hasLength(2));
      await arriba(tester);
      await irA(tester, find.text('Ver archivo'));
      await tester.tap(find.text('Ver archivo'));
      await tester.pumpAndSettle();
      expect(find.text('Archivo de recomendaciones'), findsOneWidget);
      expect(find.text('Ayer'), findsOneWidget);
      expect(find.text('Fechas visibles'), findsNothing);
      await irA(tester, find.text('Ayer'));
      await tester.tap(find.text('Ayer'));
      await tester.pumpAndSettle();
      expect(
          find.text('También hay recomendaciones de esta fecha en recientes.'),
          findsOneWidget);
      await irA(tester, find.text('Tip anterior 0'));
      expect(find.text('Tip anterior 0'), findsOneWidget);
      await arriba(tester);
      await irA(tester, find.text('Volver a recientes'));
      await tester.tap(find.text('Volver a recientes'));
      await tester.pumpAndSettle();
      await irA(tester, find.text('Restaurar todas las fechas'));
      await tester.tap(find.text('Restaurar todas las fechas'));
      await esperar(tester);
      expect(ocultas, isEmpty);
      expect(find.text('Hoy'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      lectura.dispose();
    });
  }
  test('contraste de cabecera y textos en todas las paletas', () {
    double contraste(Color texto, Color fondo) {
      final a = texto.computeLuminance();
      final b = fondo.computeLuminance();
      return ((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05);
    }

    for (final paleta in AppPaletteId.values) {
      final scheme = AppTheme.of(paleta).colorScheme;
      final finalDegradado = Color.alphaBlend(
          scheme.onPrimaryContainer.withValues(alpha: 0.06),
          scheme.primaryContainer);
      expect(contraste(scheme.onPrimaryContainer, scheme.primaryContainer),
          greaterThanOrEqualTo(4.5),
          reason: '$paleta: inicio de cabecera');
      expect(contraste(scheme.onPrimaryContainer, finalDegradado),
          greaterThanOrEqualTo(4.5),
          reason: '$paleta: final de cabecera');
      expect(contraste(scheme.onSurfaceVariant, scheme.surface),
          greaterThanOrEqualTo(4.5),
          reason: '$paleta: texto de recomendaciones');
    }
  });

  for (final caso in [
    (tamano: const Size(375, 812), escala: 2.0),
    (tamano: const Size(812, 375), escala: 1.0),
    (tamano: const Size(1024, 768), escala: 1.0),
  ]) {
    testWidgets('diseño adaptable ${caso.tamano}, texto ${caso.escala}',
        (tester) async {
      await tester.binding.setSurfaceSize(caso.tamano);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() => helper.insertarRecomendacion(Recomendacion(
            fecha: DateTime.now(),
            tipo: 'pausa',
            titulo: 'Consejo accesible',
            mensaje:
                'Un mensaje largo que debe adaptarse al tamaño del texto sin perder contenido.',
            motivo: 'Una explicación que se puede abrir y cerrar.',
            severidad: 'advertencia',
          )));
      final lectura = LecturaUsoController(uso: _Uso());
      await lectura.leer();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.of(AppPaletteId.darkCool),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(caso.escala),
                disableAnimations: true),
            child: child!),
        home: RecomendacionesScreen(lectura: lectura),
      ));
      await esperar(tester);
      await tester.pumpAndSettle();
      await irA(tester, find.text('Consejo accesible'));
      await irA(tester, find.text('Por qué este consejo'));
      await tester.tap(find.text('Por qué este consejo'));
      await tester.pumpAndSettle();
      expect(find.text('Una explicación que se puede abrir y cerrar.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      lectura.dispose();
    });
  }

  testWidgets(
      '50 tarjetas bajo demanda; uso y valoraciones no reconstruyen el historial',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      final batch = db.batch();
      for (var i = 0; i < 50; i++) {
        batch.insert(
            'recomendaciones',
            Recomendacion(
                    fecha: DateTime.now(),
                    tipo: 'pausa',
                    titulo: 'Consejo $i',
                    mensaje:
                        'Contenido que ocupa una tarjeta con texto y valoración.')
                .toMap());
      }
      await batch.commit(noResult: true);
    });
    final h = _HistorialMedido();
    final lectura = LecturaUsoController(uso: _Uso());
    await lectura.leer();
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.of(AppPaletteId.darkCool),
        home: RecomendacionesScreen(lectura: lectura, historial: h)));
    await esperar(tester);
    await tester.pumpAndSettle();
    await irA(tester, find.text('Consejo 49'));
    expect(h.tarjetasCreadas.length, lessThan(50));
    final cargas = h.cargas, consultas = h.gruposConsultados;
    final reconstruidas = <String, int>{};
    final anterior = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (elemento, _) {
      final clave = elemento.widget.key;
      if (clave is ValueKey<String> && clave.value.startsWith('tip-')) {
        reconstruidas.update(clave.value, (n) => n + 1, ifAbsent: () => 1);
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = anterior);
    await lectura.leer(forzar: true);
    await tester.pumpAndSettle();
    expect(reconstruidas, isEmpty);
    expect(h.gruposConsultados, consultas);
    final rec = h.recientes.first;
    await tester
        .runAsync(() => h.actualizarRecomendacion(rec, valoracion: 'util'));
    await tester.pumpAndSettle();
    expect(reconstruidas, {'tip-${rec.id}': 1});
    expect(h.cargas, cargas);
    expect(h.gruposConsultados, consultas);
    reconstruidas.clear();
    await tester.runAsync(() => h.actualizarRecomendacion(rec, leer: true));
    await tester.pumpAndSettle();
    expect(reconstruidas, {'tip-${rec.id}': 1});
    expect(h.sinLeer(HistorialTipsController.dia(h.ahora)).value, 49);
    await tester.pumpWidget(const SizedBox());
    lectura.dispose();
    h.dispose();
  });

  testWidgets(
      'Tips se crea al visitarlo y conserva estado y desplazamiento al volver',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await helper.guardarPerfil(const Perfil(nombre: 'Prueba'));
      final batch = db.batch();
      for (var i = 0; i < 10; i++) {
        batch.insert(
            'recomendaciones',
            Recomendacion(
                    fecha: DateTime.now(),
                    tipo: 'pausa',
                    titulo: 'Persistente $i',
                    mensaje: 'Contenido para desplazar la lista.')
                .toMap());
      }
      await batch.commit(noResult: true);
    });
    final lectura = LecturaUsoController(uso: _Uso());
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.of(AppPaletteId.darkCool),
        home: HomeScreen(lectura: lectura)));
    await esperar(tester);
    expect(
        find.byType(RecomendacionesScreen, skipOffstage: false), findsNothing);
    await tester.tap(find.text('Tips'));
    await esperar(tester);
    await tester.pumpAndSettle();
    await irA(tester, find.text('Persistente 9'));
    final pantalla = tester.state(find.byType(RecomendacionesScreen));
    final scroll = tester.state<ScrollableState>(find
        .descendant(
            of: find.byType(RecomendacionesScreen),
            matching: find.byType(Scrollable))
        .first);
    final offset = scroll.position.pixels;
    await tester.tap(find.text('Dashboard'));
    await esperar(tester);
    expect(find.byType(RecomendacionesScreen), findsNothing);
    await tester.tap(find.text('Tips'));
    await esperar(tester);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(RecomendacionesScreen)), same(pantalla));
    expect(scroll.position.pixels, closeTo(offset, 1));
    expect(find.text('Persistente 9'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    lectura.dispose();
  });

  testWidgets('salir durante una carga no actualiza el widget destruido',
      (tester) async {
    final lectura = LecturaUsoController(uso: _Uso());
    await lectura.leer();
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.of(AppPaletteId.lightCool),
        home: RecomendacionesScreen(lectura: lectura)));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => db.transaction((tx) async {
          await tx.rawQuery('SELECT 1');
        }));
    await esperar(tester);
    expect(tester.takeException(), isNull);
    lectura.dispose();
  });
}
