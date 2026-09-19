// Pruebas de regresión de la capa de base de datos.
//
// Cubren el bug SQLITE_MISMATCH (code 20): al actualizar una fila con el mapa
// de un modelo recién construido, el `id` viaja como `null` y SQLite rechaza
// `SET id = NULL` sobre una columna INTEGER PRIMARY KEY.

import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/database/database_helper.dart';
import 'package:prototipo_tesis/models/horario.dart';
import 'package:prototipo_tesis/models/uso_pantalla.dart';

void main() {
  group('DatabaseHelper.sinId', () {
    test('quita la clave id cuando es nula', () {
      final mapa = <String, dynamic>{
        'id': null,
        'fecha': '2026-09-19',
        'tiempoTotalMinutos': 323,
      };

      final resultado = DatabaseHelper.sinId(mapa);

      expect(resultado.containsKey('id'), isFalse);
      expect(resultado['fecha'], '2026-09-19');
      expect(resultado['tiempoTotalMinutos'], 323);
    });

    test('quita el id aunque tenga valor y no muta el mapa original', () {
      final mapa = <String, dynamic>{'id': 7, 'titulo': 'x'};

      final resultado = DatabaseHelper.sinId(mapa);

      expect(resultado, {'titulo': 'x'});
      expect(mapa.containsKey('id'), isTrue);
      expect(mapa['id'], 7);
    });

    test('un mapa sin id se devuelve equivalente', () {
      expect(DatabaseHelper.sinId({'a': 1}), {'a': 1});
    });
  });

  group('Mapas que alimentan los UPDATE', () {
    test('UsoPantalla.toMap() incluye id nulo: hay que filtrarlo', () {
      final uso = UsoPantalla(
        fecha: DateTime(2026, 9, 19),
        tiempoTotalMinutos: 323,
        numeroDesbloqueos: 0,
        appMasUsada: 'WhatsApp',
        tiempoAppMasUsada: 94,
      );

      // El modelo recién capturado no tiene id.
      expect(uso.toMap()['id'], isNull);

      // Tras filtrarlo, el mapa es seguro para un UPDATE.
      final seguro = DatabaseHelper.sinId(uso.toMap());
      expect(seguro.containsKey('id'), isFalse);
      expect(seguro['tiempoTotalMinutos'], 323);
    });

    test('Horario.toMap() también se filtra antes de actualizar', () {
      final horario = Horario(
        tipo: 'laboral',
        horaInicio: 9,
        horaFin: 17,
        minutoFin: 30,
      );

      expect(horario.toMap()['id'], isNull);
      expect(DatabaseHelper.sinId(horario.toMap()).containsKey('id'), isFalse);
    });
  });
}
