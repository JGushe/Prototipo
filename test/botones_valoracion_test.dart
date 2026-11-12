// Pruebas de los botones voluntarios de valoración (sin base de datos).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/screens/recomendaciones_screen.dart';

void main() {
  testWidgets('marca útil, permite rectificar y quitar la respuesta',
      (tester) async {
    String? valor;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              BotonesValoracion(
                valoracion: valor,
                onCambio: (v) => setState(() => valor = v),
              ),
              Text('estado:$valor'),
            ],
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Útil'));
    await tester.pump();
    expect(find.text('estado:util'), findsOneWidget);

    await tester.tap(find.text('No me sirvió'));
    await tester.pump();
    expect(find.text('estado:no_util'), findsOneWidget);

    // Tocar la opción activa la quita: sin respuesta.
    await tester.tap(find.text('No me sirvió'));
    await tester.pump();
    expect(find.text('estado:null'), findsOneWidget);
  });
}
