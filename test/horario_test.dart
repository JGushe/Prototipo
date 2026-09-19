// Pruebas del modelo Horario (Etapa 3).
//
// Verifican que un DateTime concreto se clasifique correctamente según día de
// la semana, hora y minutos, incluyendo horarios que cruzan medianoche.
// Son pruebas de Dart puro: no requieren base de datos ni emulador.

import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/models/horario.dart';

void main() {
  // Fechas de referencia: el lunes 24/08/2026 (weekday == 1).
  DateTime lunes(int hora, [int minuto = 0]) =>
      DateTime(2026, 8, 24, hora, minuto);
  DateTime martes(int hora, [int minuto = 0]) =>
      DateTime(2026, 8, 25, hora, minuto);
  DateTime miercoles(int hora, [int minuto = 0]) =>
      DateTime(2026, 8, 26, hora, minuto);
  DateTime sabado(int hora, [int minuto = 0]) =>
      DateTime(2026, 8, 29, hora, minuto);
  DateTime domingo(int hora, [int minuto = 0]) =>
      DateTime(2026, 8, 30, hora, minuto);

  group('Fixtures de fecha', () {
    test('las fechas de referencia tienen el día de semana esperado', () {
      expect(lunes(0).weekday, DateTime.monday);
      expect(martes(0).weekday, DateTime.tuesday);
      expect(miercoles(0).weekday, DateTime.wednesday);
      expect(sabado(0).weekday, DateTime.saturday);
      expect(domingo(0).weekday, DateTime.sunday);
    });
  });

  group('Horario laboral 08:00-16:00 (lunes a viernes)', () {
    final laboral = Horario(
      tipo: 'laboral',
      horaInicio: 8,
      horaFin: 16,
      diasSemana: const [1, 2, 3, 4, 5],
    );

    test('lunes dentro del horario', () {
      expect(laboral.contieneDateTime(lunes(10)), isTrue);
      expect(laboral.contieneDateTime(lunes(15, 59)), isTrue);
    });

    test('lunes fuera del horario', () {
      expect(laboral.contieneDateTime(lunes(7, 59)), isFalse);
      expect(laboral.contieneDateTime(lunes(20)), isFalse);
      expect(laboral.contieneDateTime(lunes(3)), isFalse);
    });

    test('día no configurado (sábado)', () {
      // La hora cae dentro del rango, pero el día no está configurado.
      expect(laboral.contieneDateTime(sabado(10)), isFalse);
      expect(laboral.contieneDateTime(domingo(10)), isFalse);
      // Con la comprobación heredada (solo hora) sí coincidiría.
      expect(laboral.contieneHora(10), isTrue);
    });

    test('límite inferior: 08:00 pertenece, 07:59 no', () {
      expect(laboral.contieneDateTime(lunes(8, 0)), isTrue);
      expect(laboral.contieneDateTime(lunes(7, 59)), isFalse);
    });

    test('límite superior: 16:00 queda fuera, 15:59 dentro', () {
      expect(laboral.contieneDateTime(lunes(16, 0)), isFalse);
      expect(laboral.contieneDateTime(lunes(15, 59)), isTrue);
    });

    test('getters de rango en minutos', () {
      expect(laboral.minutosInicio, 8 * 60);
      expect(laboral.minutosFin, 16 * 60);
      expect(laboral.cruzaMedianoche, isFalse);
      expect(laboral.tieneDuracion, isTrue);
    });
  });

  group('Rango con minutos 08:30-16:45', () {
    final horario = Horario(
      tipo: 'academico',
      horaInicio: 8,
      minutoInicio: 30,
      horaFin: 16,
      minutoFin: 45,
      diasSemana: const [1],
    );

    test('los minutos se consideran en ambos extremos', () {
      expect(horario.contieneDateTime(lunes(8, 29)), isFalse);
      expect(horario.contieneDateTime(lunes(8, 30)), isTrue);
      expect(horario.contieneDateTime(lunes(16, 44)), isTrue);
      expect(horario.contieneDateTime(lunes(16, 45)), isFalse);
    });

    test('minutosDesdeMedianoche convierte hora y minuto', () {
      expect(Horario.minutosDesdeMedianoche(8, 30), 510);
      expect(Horario.minutosDesdeMedianoche(0, 0), 0);
      expect(Horario.minutosDesdeMedianoche(23, 59), 1439);
      expect(horario.minutosInicio, 510);
      expect(horario.minutosFin, 1005);
    });
  });

  group('Horario que cruza medianoche 22:00-02:00 (lunes)', () {
    final nocturno = Horario(
      tipo: 'laboral',
      horaInicio: 22,
      horaFin: 2,
      diasSemana: const [1],
    );

    test('cruzaMedianoche es verdadero', () {
      expect(nocturno.cruzaMedianoche, isTrue);
      expect(nocturno.minutosInicio, 22 * 60);
      expect(nocturno.minutosFin, 2 * 60);
    });

    test('lunes por la noche pertenece al bloque', () {
      expect(nocturno.contieneDateTime(lunes(22, 0)), isTrue); // límite inferior
      expect(nocturno.contieneDateTime(lunes(23, 59)), isTrue);
      expect(nocturno.contieneDateTime(lunes(21, 59)), isFalse);
    });

    test('madrugada del martes pertenece al bloque del lunes', () {
      expect(nocturno.contieneDateTime(martes(0, 0)), isTrue);
      expect(nocturno.contieneDateTime(martes(1, 59)), isTrue);
      expect(nocturno.contieneDateTime(martes(2, 0)), isFalse); // límite superior
    });

    test('la madrugada del miércoles ya no pertenece', () {
      // El día anterior (martes) no está configurado.
      expect(nocturno.contieneDateTime(miercoles(1, 0)), isFalse);
    });

    test('un día no configurado por la noche tampoco pertenece', () {
      expect(nocturno.contieneDateTime(martes(23, 0)), isFalse);
    });

    test('contieneHora se conserva para compatibilidad', () {
      // La comprobación heredada ignora días y minutos.
      expect(nocturno.contieneHora(22), isTrue);
      expect(nocturno.contieneHora(23), isTrue);
      expect(nocturno.contieneHora(1), isTrue);
      expect(nocturno.contieneHora(2), isFalse);
      expect(nocturno.contieneHora(3), isFalse);
      expect(nocturno.contieneHora(21), isFalse);
    });
  });

  group('Cruce de medianoche con otros días configurados', () {
    test('domingo 22:00-02:00 alcanza la madrugada del lunes', () {
      final horario = Horario(
        tipo: 'laboral',
        horaInicio: 22,
        horaFin: 2,
        diasSemana: const [7], // domingo
      );

      expect(horario.contieneDateTime(domingo(23, 0)), isTrue);
      // El lunes es el día siguiente al domingo configurado.
      expect(horario.contieneDateTime(lunes(1, 0)), isTrue);
      // El martes ya no.
      expect(horario.contieneDateTime(martes(1, 0)), isFalse);
    });

    test('martes 22:00-02:00 no alcanza la madrugada del martes', () {
      final horario = Horario(
        tipo: 'academico',
        horaInicio: 22,
        horaFin: 2,
        diasSemana: const [2], // martes
      );

      // 01:00 del martes pertenece al bloque del lunes, que no está configurado.
      expect(horario.contieneDateTime(martes(1, 0)), isFalse);
      expect(horario.contieneDateTime(martes(23, 0)), isTrue);
      // 01:00 del miércoles sí pertenece al bloque del martes.
      expect(horario.contieneDateTime(miercoles(1, 0)), isTrue);
    });
  });

  group('Casos degenerados', () {
    test('inicio igual a fin no cubre ningún minuto', () {
      final horario = Horario(
        tipo: 'laboral',
        horaInicio: 8,
        horaFin: 8,
        diasSemana: const [1],
      );

      expect(horario.tieneDuracion, isFalse);
      expect(horario.contieneDateTime(lunes(8, 0)), isFalse);
      expect(horario.contieneDateTime(lunes(10, 0)), isFalse);
    });

    test('diasSemana vacío nunca contiene un DateTime', () {
      final horario = Horario(
        tipo: 'laboral',
        horaInicio: 8,
        horaFin: 16,
        diasSemana: const [],
      );

      expect(horario.contieneDateTime(lunes(10)), isFalse);
    });
  });
}
