// Pruebas del selector Diario / 7 días de "Tu evolución digital".

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/main.dart';
import 'package:prototipo_tesis/models/comparacion_diaria.dart';
import 'package:prototipo_tesis/models/evolucion_semanal.dart';
import 'package:prototipo_tesis/models/recomendacion.dart';
import 'package:prototipo_tesis/models/uso_pantalla.dart';
import 'package:prototipo_tesis/screens/dashboard_screen.dart';
import 'package:prototipo_tesis/theme/app_palettes.dart';
import 'package:prototipo_tesis/theme/app_theme.dart';

final _ahora = DateTime(2026, 11, 2, 10);

UsoPantalla _uso(DateTime fecha, int minutos) => UsoPantalla(
      fecha: fecha,
      tiempoTotalMinutos: minutos,
      numeroDesbloqueos: 40,
    );

EvolucionSemanal _evolucion({
  int minutosAnterior = 300,
  int minutosReciente = 280,
  bool faltaUnDia = false,
}) {
  final usos = <UsoPantalla>[
    for (var i = 0; i < 7; i++)
      _uso(DateTime(2026, 10, 19 + i), minutosAnterior),
    for (var i = 0; i < 7; i++)
      _uso(DateTime(2026, 10, 26 + i), minutosReciente),
  ];
  if (faltaUnDia) usos.removeAt(0);
  return EvolucionSemanal.calcular(usos: usos, ahora: _ahora);
}

ComparacionDiaria _diaria({
  int minutosHoy = 5,
  int minutosAyer = 40,
  int distractorHoy = 5,
  int distractorAyer = 10,
}) =>
    ComparacionDiaria.calcular(
      ahora: _ahora,
      corte: DateTime(2026, 11, 2, 10),
      minutosHoy: minutosHoy,
      minutosAyer: minutosAyer,
      distractorHoy: distractorHoy,
      distractorAyer: distractorAyer,
    );

class _Harness extends StatefulWidget {
  const _Harness({
    required this.evolucion,
    this.comparacion,
    this.resumenDiario,
    this.resumenSemanal,
    this.inicial = ModoEvolucion.diario,
  });

  final EvolucionSemanal evolucion;
  final ComparacionDiaria? comparacion;
  final ResumenValoraciones? resumenDiario;
  final ResumenValoraciones? resumenSemanal;
  final ModoEvolucion inicial;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late ModoEvolucion _modo = widget.inicial;

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: AppTheme.of(AppPaletteId.lightCool),
        darkTheme: AppTheme.of(AppPaletteId.darkCool),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SeccionEvolucionDigital(
              evolucion: widget.evolucion,
              comparacion: widget.comparacion,
              resumenDiario: widget.resumenDiario,
              resumenSemanal: widget.resumenSemanal,
              modo: _modo,
              onCambioModo: (m) => setState(() => _modo = m),
            ),
          ),
        ),
      );
}

void main() {
  group('Diario', () {
    testWidgets('muestra ayer, hoy, cambio y distractor', (tester) async {
      await tester.pumpWidget(_Harness(
        evolucion: _evolucion(),
        comparacion: _diaria(),
      ));

      expect(find.textContaining('Ayer · 01/11'), findsOneWidget);
      expect(find.textContaining('Hoy · 02/11'), findsOneWidget);
      expect(find.textContaining('-35 min'), findsOneWidget);
      expect(find.textContaining('-87.5%'), findsOneWidget);
      expect(find.textContaining('Distractor: 5 min hoy · 10 min ayer'),
          findsOneWidget);
      expect(find.textContaining('Menos uso que ayer'), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
    });

    testWidgets('sin comparación válida: datos insuficientes', (tester) async {
      await tester.pumpWidget(_Harness(
        evolucion: _evolucion(),
        comparacion: ComparacionDiaria.insuficiente(
          ahora: _ahora,
          explicacion: 'Sin permiso de acceso al uso.',
        ),
      ));

      expect(find.text('Datos insuficientes para comparar'), findsOneWidget);
      expect(find.textContaining('Sin permiso'), findsOneWidget);
    });

    testWidgets('incluye recomendaciones y valoraciones de hoy',
        (tester) async {
      await tester.pumpWidget(_Harness(
        evolucion: _evolucion(),
        comparacion: _diaria(),
        resumenDiario: const ResumenValoraciones(
            total: 1, utiles: 1, noUtiles: 0, generadas: 3),
      ));

      expect(
        find.textContaining(
            'Recomendaciones hoy: 3 · valoradas 1 · muestra insuficiente'),
        findsOneWidget,
      );
    });

    testWidgets('sin recomendaciones hoy: texto explícito', (tester) async {
      await tester.pumpWidget(_Harness(
        evolucion: _evolucion(),
        comparacion: _diaria(),
        resumenDiario: const ResumenValoraciones(
            total: 0, utiles: 0, noUtiles: 0, generadas: 0),
      ));

      expect(find.text('Sin recomendaciones hoy'), findsOneWidget);
    });
  });

  group('7 días', () {
    for (final dias in [0, 1, 5, 7]) {
      testWidgets('$dias días recientes sin exigir la semana anterior',
          (tester) async {
        final evolucion = EvolucionSemanal.calcular(
          ahora: _ahora,
          usos: [
            for (var i = 0; i < dias; i++)
              _uso(
                  DateTime(
                      2026,
                      10,
                      26 +
                          i +
                          (dias == 5 && i >= 2 ? 1 : 0) +
                          (dias == 5 && i >= 4 ? 1 : 0)),
                  i == 0 ? 0 : 60),
            // Fuera del periodo: no debe aparecer en el gráfico ni el promedio.
            _uso(_ahora, 999),
            _uso(DateTime(2026, 10, 19), 300),
          ],
        );
        await tester.pumpWidget(_Harness(
          evolucion: evolucion,
          inicial: ModoEvolucion.sieteDias,
        ));
        expect(find.text('26/10 – 01/11'), findsOneWidget);
        expect(find.text('$dias/7 días con registro'), findsOneWidget);
        expect(
            find.textContaining('Comparación no disponible'), findsOneWidget);
        expect(find.textContaining('capturas pueden ser parciales'),
            findsOneWidget);
        if (dias == 0) {
          expect(find.text('Sin registros de uso en estos siete días.'),
              findsOneWidget);
          expect(find.byType(LineChart), findsNothing);
        } else {
          final grafico = tester.widget<LineChart>(find.byType(LineChart));
          final puntos = grafico.data.lineBarsData.single.spots;
          expect(puntos, hasLength(7));
          expect(puntos.first, const FlSpot(0, 0));
          expect(
              puntos.where((p) => p == FlSpot.nullSpot), hasLength(7 - dias));
          expect(grafico.data.maxX, 6);
          if (dias == 5) {
            expect(puntos[2], FlSpot.nullSpot);
            expect(puntos[5], FlSpot.nullSpot);
          }
          expect(find.text('${((dias - 1) * 60 / dias).round()} min/día'),
              findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('muestra la comparación semanal existente', (tester) async {
      await tester.pumpWidget(_Harness(
        evolucion: _evolucion(),
        inicial: ModoEvolucion.sieteDias,
      ));

      expect(find.textContaining('300 min/día'), findsOneWidget);
      expect(find.textContaining('280 min/día'), findsNWidgets(2));
      expect(find.textContaining('-20 min/día'), findsOneWidget);
      expect(find.textContaining('-6.7%'), findsOneWidget);
      expect(find.text('7/7 días'), findsNWidgets(2));
    });

    testWidgets('cobertura incompleta: conserva resumen y gráfico',
        (tester) async {
      await tester.pumpWidget(_Harness(
        evolucion: _evolucion(faltaUnDia: true),
        inicial: ModoEvolucion.sieteDias,
      ));

      expect(find.textContaining('280 min/día'), findsOneWidget);
      expect(find.textContaining('Comparación no disponible'), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('incluye recomendaciones y utilidad del periodo',
        (tester) async {
      await tester.pumpWidget(_Harness(
        evolucion: _evolucion(),
        inicial: ModoEvolucion.sieteDias,
        resumenSemanal: const ResumenValoraciones(
            total: 6, utiles: 5, noUtiles: 1, generadas: 10),
      ));

      expect(
        find.textContaining(
            'Recomendaciones en 7 días: 10 · valoradas 6 · 83 % útiles'),
        findsOneWidget,
      );
      expect(find.textContaining('Tendencia de distractor semanal: sin datos'),
          findsOneWidget);
    });
  });

  testWidgets('el selector alterna sin navegar', (tester) async {
    await tester.pumpWidget(_Harness(
      evolucion: _evolucion(),
      comparacion: _diaria(),
    ));

    expect(find.textContaining('Ayer · 01/11'), findsOneWidget);

    await tester.tap(find.text('7 días'));
    await tester.pumpAndSettle();
    expect(find.textContaining('300 min/día'), findsOneWidget);
    expect(find.textContaining('Ayer · 01/11'), findsNothing);

    await tester.tap(find.text('Diario'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ayer · 01/11'), findsOneWidget);
  });

  testWidgets('pantalla pequeña sin desbordes (diario)', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_Harness(
      evolucion: _evolucion(),
      comparacion: _diaria(),
    ));

    expect(tester.takeException(), isNull);
  });

  testWidgets('pantalla pequeña muestra semana con cobertura incompleta',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_Harness(
      evolucion: _evolucion(faltaUnDia: true),
      inicial: ModoEvolucion.sieteDias,
    ));
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.textContaining('Comparación no disponible'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el refresh conserva la navegación y el botón', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    final refrescar = find.byTooltip('Actualizar datos');
    expect(refrescar, findsOneWidget);

    await tester.tap(refrescar);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(refrescar, findsOneWidget);
  });
}
