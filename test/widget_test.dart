// Test básico de humo para el prototipo de tesis.
// Verifica que la aplicación se construye correctamente.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prototipo_tesis/main.dart';

void main() {
  testWidgets('La app se construye y muestra la navegación', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Verificar que la navegación inferior está presente
    expect(find.byType(NavigationBar), findsOneWidget);

    // Verificar los destinos de navegación
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Tareas'), findsWidgets);
    expect(find.text('Uso'), findsWidgets);
    expect(find.text('Tips'), findsWidgets);
  });
}
