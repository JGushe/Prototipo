import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/database/database_helper.dart';
import 'package:prototipo_tesis/models/tarea.dart';
import 'package:prototipo_tesis/screens/tareas_screen.dart';
import 'package:prototipo_tesis/theme/app_palettes.dart';
import 'package:prototipo_tesis/theme/app_theme.dart';

class _BasePrueba implements DatabaseHelper {
  _BasePrueba(this.lectura);

  final Future<List<Tarea>> lectura;
  final List<Tarea> guardadas = [];

  @override
  Future<List<Tarea>> obtenerTareas({bool? completada}) async =>
      [...await lectura, ...guardadas];

  @override
  Future<int> insertarTarea(Tarea tarea) async {
    guardadas.add(tarea);
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('un título en blanco conserva el formulario y permite guardar',
      (tester) async {
    final db = _BasePrueba(Future.value([]));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.of(AppPaletteId.lightCool),
      home: TareasScreen(database: db),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Nueva tarea'), findsOneWidget);
    expect(find.text('Ingresa un título.'), findsOneWidget);
    expect(db.guardadas, isEmpty);

    await tester.enterText(find.byType(TextField).first, '  Ensayo  ');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(db.guardadas.single.titulo, 'Ensayo');
    expect(find.text('Nueva tarea'), findsNothing);
  });

  testWidgets('el calendario abre al editar una tarea vencida', (tester) async {
    final ayer = DateTime.now().subtract(const Duration(days: 1));
    final db = _BasePrueba(Future.value([
      Tarea(
          id: 1,
          titulo: 'Vencida',
          fechaCreacion: ayer,
          fechaVencimiento: ayer),
    ]));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.of(AppPaletteId.lightCool),
      home: TareasScreen(database: db),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Vence:').last);
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('salir de Tareas con una lectura pendiente es seguro',
      (tester) async {
    final pendiente = Completer<List<Tarea>>();
    final db = _BasePrueba(pendiente.future);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.of(AppPaletteId.lightCool),
      home: TareasScreen(database: db),
    ));
    await tester.pumpWidget(const SizedBox());
    pendiente.complete([]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
