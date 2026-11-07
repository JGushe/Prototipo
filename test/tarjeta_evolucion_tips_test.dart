// Pruebas de la tarjeta de evolución que se muestra en Tips.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/models/comparacion_diaria.dart';
import 'package:prototipo_tesis/models/evolucion_semanal.dart';
import 'package:prototipo_tesis/models/uso_pantalla.dart';
import 'package:prototipo_tesis/screens/recomendaciones_screen.dart';

final _ahora = DateTime(2026, 11, 2, 10);

EvolucionSemanal _evolucion({bool completo = true}) {
  final usos = <UsoPantalla>[
    for (var i = 0; i < 7; i++)
      UsoPantalla(
        fecha: DateTime(2026, 10, 19 + i),
        tiempoTotalMinutos: 300,
        numeroDesbloqueos: 40,
      ),
    for (var i = 0; i < 7; i++)
      UsoPantalla(
        fecha: DateTime(2026, 10, 26 + i),
        tiempoTotalMinutos: 280,
        numeroDesbloqueos: 40,
      ),
  ];
  if (!completo) usos.removeAt(0);
  return EvolucionSemanal.calcular(usos: usos, ahora: _ahora);
}

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

ComparacionDiaria _diaria() => ComparacionDiaria.calcular(
      ahora: DateTime(2026, 11, 2, 10),
      corte: DateTime(2026, 11, 2, 10),
      minutosHoy: 60,
      minutosAyer: 90,
      distractorHoy: 5,
      distractorAyer: 25,
    );

void main() {
  testWidgets('con comparación diaria usa el mensaje de ayer/hoy',
      (tester) async {
    await tester.pumpWidget(_app(TarjetaEvolucionTips(
      evolucion: _evolucion(),
      comparacion: _diaria(),
    )));

    expect(find.textContaining('20 minutos menos de uso distractor'),
        findsOneWidget);
    expect(find.text('Mantén el bloque que te funcionó hoy.'), findsOneWidget);
    // No mezcla el mensaje semanal.
    expect(find.textContaining('min/día'), findsNothing);
  });

  testWidgets('tendencia disponible: mensaje y acción', (tester) async {
    await tester
        .pumpWidget(_app(TarjetaEvolucionTips(evolucion: _evolucion())));

    expect(find.text('Tu evolución'), findsOneWidget);
    expect(find.textContaining('280 min/día'), findsOneWidget);
    expect(find.text('Mantén tu bloque de concentración.'), findsOneWidget);
  });

  testWidgets('sin datos: texto neutral', (tester) async {
    await tester.pumpWidget(
        _app(TarjetaEvolucionTips(evolucion: _evolucion(completo: false))));

    expect(find.textContaining('Necesitamos más días de registro'), findsOneWidget);
    expect(
        find.text('Actualiza el uso desde el Dashboard durante unos días.'),
        findsOneWidget);
  });
}
