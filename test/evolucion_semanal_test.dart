// Pruebas del cálculo de evolución semanal: solo lógica pura, sin SQLite.
//
// Regla central: un día sin registro no es un día con 0 minutos; si falta
// alguno de los siete, el resultado es "insuficiente".

import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/models/evolucion_semanal.dart';
import 'package:prototipo_tesis/models/uso_pantalla.dart';

UsoPantalla _uso(DateTime fecha, {int minutos = 0, int desbloqueos = 0}) =>
    UsoPantalla(
      fecha: fecha,
      tiempoTotalMinutos: minutos,
      numeroDesbloqueos: desbloqueos,
    );

/// Días consecutivos desde [desde] (inclusive), con los mismos valores.
List<UsoPantalla> _dias(
  DateTime desde,
  int cantidad, {
  int minutos = 0,
  int desbloqueos = 0,
}) =>
    List.generate(
      cantidad,
      (i) => _uso(
        DateTime(desde.year, desde.month, desde.day + i),
        minutos: minutos,
        desbloqueos: desbloqueos,
      ),
    );

final _ahora = DateTime(2026, 11, 2, 10); // hoy parcial, excluido
final _inicioAnterior = DateTime(2026, 10, 19);
final _inicioReciente = DateTime(2026, 10, 26);

List<UsoPantalla> _dosSemanas({
  int minutosAnterior = 300,
  int minutosReciente = 280,
  int desbloqueosAnterior = 50,
  int desbloqueosReciente = 40,
}) =>
    [
      ..._dias(_inicioAnterior, 7,
          minutos: minutosAnterior, desbloqueos: desbloqueosAnterior),
      ..._dias(_inicioReciente, 7,
          minutos: minutosReciente, desbloqueos: desbloqueosReciente),
    ];

void main() {
  group('14 días válidos', () {
    test('compara promedios, diferencia y porcentaje', () {
      final e = EvolucionSemanal.calcular(usos: _dosSemanas(), ahora: _ahora);

      expect(e.estado, EstadoEvolucion.disponible);
      expect(e.anterior.desde, _inicioAnterior);
      expect(e.anterior.hasta, DateTime(2026, 10, 25));
      expect(e.reciente.desde, _inicioReciente);
      expect(e.reciente.hasta, DateTime(2026, 11, 1));

      expect(e.anterior.promedioMinutosPantalla, 300);
      expect(e.reciente.promedioMinutosPantalla, 280);
      expect(e.diferenciaMinutos, -20);
      expect(e.porcentajeMinutos, -6.7);

      expect(e.anterior.promedioDesbloqueos, 50);
      expect(e.reciente.promedioDesbloqueos, 40);
      expect(e.diferenciaDesbloqueos, -10);
      expect(e.porcentajeDesbloqueos, -20);
    });

    test('redondea el porcentaje a un decimal', () {
      final e = EvolucionSemanal.calcular(
        usos: _dosSemanas(minutosAnterior: 300, minutosReciente: 290),
        ahora: _ahora,
      );

      expect(e.porcentajeMinutos, -3.3);
    });

    test('sin recomendaciones previas el periodo anterior es línea base', () {
      final e = EvolucionSemanal.calcular(usos: _dosSemanas(), ahora: _ahora);

      expect(e.esLineaBase, isTrue);
      expect(e.etiquetaAnterior, 'línea base');
    });

    test('con recomendaciones dentro del periodo anterior no es línea base', () {
      final e = EvolucionSemanal.calcular(
        usos: _dosSemanas(),
        ahora: _ahora,
        primeraRecomendacion: DateTime(2026, 10, 20),
      );

      expect(e.esLineaBase, isFalse);
      expect(e.etiquetaAnterior, 'periodo anterior');
    });

    test('una recomendación posterior al periodo sí deja línea base', () {
      final e = EvolucionSemanal.calcular(
        usos: _dosSemanas(),
        ahora: _ahora,
        primeraRecomendacion: DateTime(2026, 11, 1),
      );

      expect(e.esLineaBase, isTrue);
    });
  });

  group('datos insuficientes', () {
    test('falta un día del periodo anterior', () {
      final usos = _dosSemanas()
        ..removeWhere((u) => u.fecha == DateTime(2026, 10, 25));
      final e = EvolucionSemanal.calcular(usos: usos, ahora: _ahora);

      expect(e.estado, EstadoEvolucion.insuficiente);
      expect(e.anterior.diasValidos, 6);
      expect(e.reciente.diasValidos, 7);
      // El promedio usa solo los días válidos: no inventa un 0.
      expect(e.anterior.promedioMinutosPantalla, 300);
      expect(e.diferenciaMinutos, isNull);
      expect(e.porcentajeMinutos, isNull);
      expect(e.explicacion, contains('6/7'));
      expect(e.esLineaBase, isFalse);
    });

    test('cobertura distinta entre periodos', () {
      final usos = _dosSemanas()
        ..removeRange(
            7, 9); // el periodo reciente queda con 5 días
      final e = EvolucionSemanal.calcular(usos: usos, ahora: _ahora);

      expect(e.estado, EstadoEvolucion.insuficiente);
      expect(e.reciente.diasValidos, 5);
      expect(e.anterior.diasValidos, 7);
      expect(e.explicacion, contains('5/7'));
    });

    test('sin registros: promedios nulos, no ceros', () {
      final e =
          EvolucionSemanal.calcular(usos: const [], ahora: _ahora);

      expect(e.estado, EstadoEvolucion.insuficiente);
      expect(e.anterior.diasValidos, 0);
      expect(e.reciente.diasValidos, 0);
      expect(e.anterior.promedioMinutosPantalla, isNull);
      expect(e.reciente.promedioDesbloqueos, isNull);
    });

    test('solo hay datos del día actual: queda fuera de la ventana', () {
      final e = EvolucionSemanal.calcular(
        usos: [_uso(DateTime(2026, 11, 2), minutos: 999, desbloqueos: 99)],
        ahora: _ahora,
      );

      expect(e.estado, EstadoEvolucion.insuficiente);
      expect(e.reciente.diasValidos, 0);
      expect(e.reciente.promedioMinutosPantalla, isNull);
    });
  });

  group('cero en línea base', () {
    test('hay diferencia absoluta y no porcentaje', () {
      final e = EvolucionSemanal.calcular(
        usos: _dosSemanas(
          minutosAnterior: 0,
          minutosReciente: 60,
          desbloqueosAnterior: 0,
          desbloqueosReciente: 10,
        ),
        ahora: _ahora,
      );

      expect(e.estado, EstadoEvolucion.noComparable);
      expect(e.diferenciaMinutos, 60);
      expect(e.porcentajeMinutos, isNull);
      expect(e.diferenciaDesbloqueos, 10);
      expect(e.porcentajeDesbloqueos, isNull);
    });
  });

  group('medianoche y cambio de fecha', () {
    test('a las 00:30 el día actual sigue excluido', () {
      final usos = _dosSemanas()
        ..add(_uso(DateTime(2026, 11, 2), minutos: 999, desbloqueos: 99));
      final e = EvolucionSemanal.calcular(
        usos: usos,
        ahora: DateTime(2026, 11, 2, 0, 30),
      );

      expect(e.estado, EstadoEvolucion.disponible);
      expect(e.reciente.hasta, DateTime(2026, 11, 1));
      expect(e.anterior.hasta, DateTime(2026, 10, 25));
      // El dato del día parcial no entra en ningún promedio.
      expect(e.reciente.promedioMinutosPantalla, 280);
    });

    test('la ventana cruza fin de mes sin huecos', () {
      final e = EvolucionSemanal.calcular(
        usos: _dosSemanas(),
        ahora: DateTime(2026, 12, 2, 10),
      );

      expect(e.reciente.desde, DateTime(2026, 11, 25));
      expect(e.reciente.hasta, DateTime(2026, 12, 1));
      expect(e.anterior.desde, DateTime(2026, 11, 18));
      expect(e.anterior.hasta, DateTime(2026, 11, 24));
    });
  });

  group('tendencia y mensaje para Tips', () {
    test('reducción: mensaje concreto y acción de mantener', () {
      final e = EvolucionSemanal.calcular(usos: _dosSemanas(), ahora: _ahora);

      expect(e.tendencia, TendenciaEvolucion.reduccion);
      expect(e.mensajeTips, contains('280 min/día'));
      expect(e.mensajeTips, contains('300 min/día'));
      expect(e.mensajeTips, contains('-6.7 %'));
      expect(e.mensajeTips, contains('7/7 días con registro'));
      // Nunca llama "distracción" al total de pantalla.
      expect(e.mensajeTips.toLowerCase(), isNot(contains('distractor')));
      expect(e.accionTips, contains('Mantén'));
    });

    test('aumento: mensaje y acción de revisar horarios', () {
      final e = EvolucionSemanal.calcular(
        usos: _dosSemanas(minutosAnterior: 300, minutosReciente: 400),
        ahora: _ahora,
      );

      expect(e.tendencia, TendenciaEvolucion.aumento);
      expect(e.mensajeTips, contains('400 min/día'));
      expect(e.mensajeTips, contains('300 min/día'));
      expect(e.accionTips, contains('Revisa'));
    });

    test('estabilidad dentro del umbral', () {
      final e = EvolucionSemanal.calcular(
        usos: _dosSemanas(minutosAnterior: 300, minutosReciente: 302),
        ahora: _ahora,
      );

      expect(e.tendencia, TendenciaEvolucion.estable);
      expect(e.mensajeTips, contains('similar al periodo anterior'));
      expect(e.mensajeTips, isNot(contains('%')));
      expect(e.accionTips, contains('25 minutos'));
    });

    test('justo en el umbral de 5 minutos ya no es estable', () {
      final e = EvolucionSemanal.calcular(
        usos: _dosSemanas(minutosAnterior: 300, minutosReciente: 305),
        ahora: _ahora,
      );

      expect(EvolucionSemanal.umbralEstableMinutos, 5);
      expect(e.tendencia, TendenciaEvolucion.aumento);
    });

    test('histórico incompleto: mensaje neutral', () {
      final usos = _dosSemanas()
        ..removeWhere((u) => u.fecha == DateTime(2026, 10, 25));
      final e = EvolucionSemanal.calcular(usos: usos, ahora: _ahora);

      expect(e.tendencia, TendenciaEvolucion.sinDatos);
      expect(e.mensajeTips, contains('Necesitamos más días de registro'));
      expect(e.mensajeTips, contains('6/7'));
      expect(e.accionTips, contains('Actualiza'));
    });

    test('sin datos: mensaje neutral y sin porcentaje', () {
      final e = EvolucionSemanal.calcular(usos: const [], ahora: _ahora);

      expect(e.tendencia, TendenciaEvolucion.sinDatos);
      expect(e.mensajeTips, isNot(contains('%')));
      expect(e.accionTips, contains('Actualiza'));
    });

    test('base en cero: diferencia absoluta sin porcentaje', () {
      final e = EvolucionSemanal.calcular(
        usos: _dosSemanas(minutosAnterior: 0, minutosReciente: 60),
        ahora: _ahora,
      );

      expect(e.tendencia, TendenciaEvolucion.aumento);
      expect(e.mensajeTips, contains('60 min/día'));
      expect(e.mensajeTips, contains('0 min/día'));
      expect(e.mensajeTips, isNot(contains('%')));
    });
  });
}
