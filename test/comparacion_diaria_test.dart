// Pruebas de la comparación Hoy vs Ayer con la misma hora de corte.
//
// El canal 'usage_stats' se simula: no hay dispositivo en el entorno de test.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/models/comparacion_diaria.dart';
import 'package:prototipo_tesis/services/uso_pantalla_service.dart';

const MethodChannel _canalUso = MethodChannel('usage_stats');

Map<String, Object?> _evento(int tipo, DateTime momento, String paquete) => {
      'eventType': '$tipo',
      'timeStamp': '${momento.millisecondsSinceEpoch}',
      'packageName': paquete,
    };

final _ahora = DateTime(2026, 11, 2, 12, 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mensajero =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void simular({
    bool permiso = true,
    List<Map<String, Object?>> eventos = const [],
    bool fallarEventos = false,
  }) {
    mensajero.setMockMethodCallHandler(_canalUso, (call) async {
      if (call.method == 'isUsagePermission') return permiso;
      if (call.method == 'queryEvents') {
        if (fallarEventos) {
          throw PlatformException(code: 'usage_stats_error', message: 'x');
        }
        return eventos;
      }
      return null;
    });
  }

  tearDown(() {
    mensajero.setMockMethodCallHandler(_canalUso, null);
  });

  test('compara ambos días hasta la misma hora y calcula distractor', () async {
    simular(eventos: [
      // Ayer: 10 min Instagram + 30 min Chrome.
      _evento(1, DateTime(2026, 11, 1, 10), 'com.instagram'),
      _evento(2, DateTime(2026, 11, 1, 10, 10), 'com.instagram'),
      _evento(1, DateTime(2026, 11, 1, 11), 'com.android.chrome'),
      _evento(2, DateTime(2026, 11, 1, 11, 30), 'com.android.chrome'),
      // Hoy: 5 min Instagram.
      _evento(1, DateTime(2026, 11, 2, 9), 'com.instagram'),
      _evento(2, DateTime(2026, 11, 2, 9, 5), 'com.instagram'),
    ]);

    final c = await UsoPantallaService().compararHoyAyer(ahora: _ahora);

    expect(c.estado, EstadoComparacionDiaria.disponible);
    expect(c.minutosHoy, 5);
    expect(c.minutosAyer, 40);
    expect(c.diferenciaMinutos, -35);
    expect(c.porcentaje, -87.5);
    expect(c.distractorHoy, 5);
    expect(c.distractorAyer, 10);
    expect(c.corte, DateTime(2026, 11, 2, 12));
  });

  test('el corte excluye lo posterior a la hora actual en ayer', () async {
    simular(eventos: [
      _evento(1, DateTime(2026, 11, 1, 10), 'com.instagram'),
      _evento(2, DateTime(2026, 11, 1, 10, 10), 'com.instagram'),
      // 12:30 de ayer queda fuera: el corte es 12:00.
      _evento(1, DateTime(2026, 11, 1, 12, 30), 'com.instagram'),
      _evento(2, DateTime(2026, 11, 1, 13), 'com.instagram'),
    ]);

    final c = await UsoPantallaService().compararHoyAyer(ahora: _ahora);

    expect(c.minutosAyer, 10);
    expect(c.minutosHoy, 0);
    expect(c.porcentaje, -100);
  });

  test('hoy en cero es un cero real, no dato ausente', () async {
    simular(eventos: [
      _evento(1, DateTime(2026, 11, 1, 10), 'com.instagram'),
      _evento(2, DateTime(2026, 11, 1, 10, 10), 'com.instagram'),
    ]);

    final c = await UsoPantallaService().compararHoyAyer(ahora: _ahora);

    expect(c.estado, EstadoComparacionDiaria.disponible);
    expect(c.minutosHoy, 0);
    expect(c.minutosAyer, 10);
  });

  test('ayer en cero: hay diferencia absoluta, no porcentaje', () async {
    simular(eventos: [
      _evento(1, DateTime(2026, 11, 2, 9), 'com.instagram'),
      _evento(2, DateTime(2026, 11, 2, 9, 5), 'com.instagram'),
    ]);

    final c = await UsoPantallaService().compararHoyAyer(ahora: _ahora);

    expect(c.minutosAyer, 0);
    expect(c.diferenciaMinutos, 5);
    expect(c.porcentaje, isNull);
  });

  test('sin permiso: insuficiente, sin inventar ceros', () async {
    simular(permiso: false);

    final c = await UsoPantallaService().compararHoyAyer(ahora: _ahora);

    expect(c.estado, EstadoComparacionDiaria.insuficiente);
    expect(c.minutosHoy, isNull);
    expect(c.minutosAyer, isNull);
    expect(c.diferenciaMinutos, isNull);
    expect(c.explicacion, contains('Sin permiso'));
  });

  test('error al leer eventos: insuficiente', () async {
    simular(fallarEventos: true);

    final c = await UsoPantallaService().compararHoyAyer(ahora: _ahora);

    expect(c.estado, EstadoComparacionDiaria.insuficiente);
    expect(c.minutosHoy, isNull);
    expect(c.porcentaje, isNull);
    expect(c.explicacion, contains('No se pudieron leer'));
  });

  group('mensajes de Tips (diario)', () {
    ComparacionDiaria diaria({
      int? distractorHoy = 5,
      int? distractorAyer = 25,
      int minutosHoy = 60,
      int minutosAyer = 90,
    }) =>
        ComparacionDiaria.calcular(
          ahora: _ahora,
          corte: DateTime(2026, 11, 2, 12),
          minutosHoy: minutosHoy,
          minutosAyer: minutosAyer,
          distractorHoy: distractorHoy,
          distractorAyer: distractorAyer,
        );

    test('reducción de distractor: minutos menos y acción de mantener', () {
      final c = diaria();

      expect(c.mensajeTips, contains('20 minutos menos de uso distractor'));
      expect(c.mensajeTips, contains('12:00'));
      expect(c.accionTips, contains('Mantén'));
    });

    test('aumento de distractor: minutos más y acción de revisar', () {
      final c = diaria(distractorHoy: 30, distractorAyer: 10);

      expect(c.mensajeTips, contains('20 minutos más de uso distractor'));
      expect(c.accionTips, contains('Revisa'));
    });

    test('sin cambio: similar, sin elogios', () {
      final c = diaria(distractorHoy: 11, distractorAyer: 13);

      expect(c.mensajeTips, contains('similar al de ayer'));
      expect(c.mensajeTips, isNot(contains('menos')));
      expect(c.accionTips, contains('25 minutos'));
    });

    test('sin distractor: usa total con etiqueta descriptiva', () {
      final c = diaria(distractorHoy: null, distractorAyer: null);

      expect(c.mensajeTips, contains('uso de pantalla'));
      expect(c.mensajeTips, contains('no distractor'));
      expect(c.accionTips, contains('Actualiza'));
    });

    test('base distractor en cero: diferencia absoluta sin porcentaje', () {
      final c = diaria(distractorHoy: 5, distractorAyer: 0);

      expect(c.mensajeTips, contains('5 minutos más de uso distractor'));
      expect(c.mensajeTips, isNot(contains('%')));
    });

    test('sin datos: mensaje neutral', () {
      final c = ComparacionDiaria.insuficiente(
        ahora: _ahora,
        explicacion: 'Sin permiso.',
      );

      expect(c.mensajeTips, contains('Datos insuficientes'));
      expect(c.accionTips, contains('Vuelve a actualizar'));
    });

    test('nunca afirma productividad ni causalidad', () {
      final c = diaria();
      final texto = '${c.mensajeTips} ${c.accionTips}'.toLowerCase();

      expect(texto, isNot(contains('productividad')));
      expect(texto, isNot(contains('mejora')));
      expect(texto, isNot(contains('gracias a')));
    });
  });
}
