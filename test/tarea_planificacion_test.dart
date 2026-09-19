// Pruebas de la planificación temporal de las tareas (Etapa 2).
//
// Son pruebas de Dart puro sobre el modelo: no requieren base de datos,
// emulador ni dependencias adicionales.

import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/models/tarea.dart';

void main() {
  group('Compatibilidad con tareas antiguas', () {
    test('fromMap acepta filas sin columnas de planificación', () {
      // Fila tal como existía antes de la migración v3.
      final mapAntiguo = <String, dynamic>{
        'id': 1,
        'titulo': 'Tarea antigua',
        'descripcion': null,
        'fechaCreacion': '2026-08-01T10:00:00.000',
        'fechaVencimiento': null,
        'completada': 0,
        'prioridad': 'media',
      };

      final tarea = Tarea.fromMap(mapAntiguo);

      expect(tarea.fechaPlanificada, isNull);
      expect(tarea.horaInicioPlanificada, isNull);
      expect(tarea.horaFinPlanificada, isNull);
      expect(tarea.tieneFechaPlanificada, isFalse);
      expect(tarea.tieneRangoHorario, isFalse);
      expect(tarea.estaPlanificadaEn(DateTime(2026, 8, 1, 10, 0)), isFalse);
    });

    test('toMap de una tarea sin planificación deja los campos en null', () {
      final tarea = Tarea(
        titulo: 'Sin plan',
        fechaCreacion: DateTime(2026, 8, 1),
      );

      final map = tarea.toMap();

      expect(map['fechaPlanificada'], isNull);
      expect(map['horaInicioPlanificada'], isNull);
      expect(map['horaFinPlanificada'], isNull);
    });
  });

  group('Serialización con planificación', () {
    final tarea = Tarea(
      id: 7,
      titulo: 'Estudiar',
      fechaCreacion: DateTime(2026, 8, 20),
      fechaVencimiento: DateTime(2026, 8, 30, 18, 0),
      prioridad: 'alta',
      fechaPlanificada: DateTime(2026, 8, 27),
      horaInicioPlanificada: '09:00',
      horaFinPlanificada: '11:30',
    );

    test('toMap guarda la fecha como yyyy-MM-dd y las horas como HH:mm', () {
      final map = tarea.toMap();

      expect(map['fechaPlanificada'], '2026-08-27');
      expect(map['horaInicioPlanificada'], '09:00');
      expect(map['horaFinPlanificada'], '11:30');
      // El vencimiento sigue siendo un concepto independiente.
      expect(map['fechaVencimiento'], isNotNull);
      expect(map['fechaVencimiento'], isNot(equals(map['fechaPlanificada'])));
    });

    test('fromMap reconstruye la planificación', () {
      final copia = Tarea.fromMap(tarea.toMap());

      expect(copia.fechaPlanificada, DateTime(2026, 8, 27));
      expect(copia.horaInicioPlanificada, '09:00');
      expect(copia.horaFinPlanificada, '11:30');
      expect(copia.fechaVencimiento, DateTime(2026, 8, 30, 18, 0));
    });

    test('inicioPlanificado y finPlanificado combinan fecha y hora', () {
      expect(tarea.inicioPlanificado, DateTime(2026, 8, 27, 9, 0));
      expect(tarea.finPlanificado, DateTime(2026, 8, 27, 11, 30));
      expect(tarea.cruzaMedianoche, isFalse);
    });

    test('copyWith conserva y actualiza la planificación', () {
      final sinCambios = tarea.copyWith(titulo: 'Estudiar más');
      expect(sinCambios.fechaPlanificada, tarea.fechaPlanificada);
      expect(sinCambios.horaInicioPlanificada, '09:00');

      final cambiada = tarea.copyWith(horaFinPlanificada: '12:00');
      expect(cambiada.horaInicioPlanificada, '09:00');
      expect(cambiada.horaFinPlanificada, '12:00');
    });
  });

  group('Validación de la franja horaria', () {
    test('sin horas es válido (planificación vacía)', () {
      expect(Tarea.rangoHorarioValido(null, null), isTrue);
    });

    test('inicio anterior a fin es válido', () {
      expect(Tarea.rangoHorarioValido('09:00', '11:00'), isTrue);
    });

    test('inicio igual o posterior a fin es inválido', () {
      expect(Tarea.rangoHorarioValido('09:00', '09:00'), isFalse);
      expect(Tarea.rangoHorarioValido('11:00', '09:00'), isFalse);
    });

    test('rango incompleto o con formato inválido es inválido', () {
      expect(Tarea.rangoHorarioValido('09:00', null), isFalse);
      expect(Tarea.rangoHorarioValido(null, '11:00'), isFalse);
      expect(Tarea.rangoHorarioValido('25:00', '26:00'), isFalse);
      expect(Tarea.rangoHorarioValido('9', '11:00'), isFalse);
    });

    test('el caso especial de cruce de medianoche es opt-in', () {
      expect(Tarea.rangoHorarioValido('23:00', '01:00'), isFalse);
      expect(
        Tarea.rangoHorarioValido('23:00', '01:00',
            permitirCruceMedianoche: true),
        isTrue,
      );
    });

    test('formatearHora normaliza a dos dígitos', () {
      expect(Tarea.formatearHora(9, 5), '09:05');
      expect(Tarea.formatearHora(23, 59), '23:59');
      expect(Tarea.formatearHora(24, 0), isNull);
      expect(Tarea.formatearHora(0, 60), isNull);
    });
  });

  group('estaPlanificadaEn', () {
    test('activa dentro de la franja (fin exclusivo)', () {
      final tarea = Tarea(
        titulo: 'Clase',
        fechaCreacion: DateTime(2026, 8, 20),
        fechaPlanificada: DateTime(2026, 8, 27),
        horaInicioPlanificada: '09:00',
        horaFinPlanificada: '11:00',
      );

      expect(tarea.estaPlanificadaEn(DateTime(2026, 8, 27, 10, 0)), isTrue);
      expect(tarea.estaPlanificadaEn(DateTime(2026, 8, 27, 9, 0)), isTrue);
      expect(tarea.estaPlanificadaEn(DateTime(2026, 8, 27, 8, 59)), isFalse);
      expect(tarea.estaPlanificadaEn(DateTime(2026, 8, 27, 11, 0)), isFalse);
      expect(tarea.estaPlanificadaEn(DateTime(2026, 8, 28, 10, 0)), isFalse);
    });

    test('con solo fecha está activa todo el día', () {
      final tarea = Tarea(
        titulo: 'Repasar',
        fechaCreacion: DateTime(2026, 8, 20),
        fechaPlanificada: DateTime(2026, 8, 27),
      );

      expect(tarea.estaPlanificadaEn(DateTime(2026, 8, 27, 0, 0)), isTrue);
      expect(tarea.estaPlanificadaEn(DateTime(2026, 8, 27, 23, 59)), isTrue);
      expect(tarea.estaPlanificadaEn(DateTime(2026, 8, 28, 0, 0)), isFalse);
    });

    test('franja que cruza la medianoche cubre el día siguiente', () {
      final tarea = Tarea(
        titulo: 'Turno noche',
        fechaCreacion: DateTime(2026, 8, 20),
        fechaPlanificada: DateTime(2026, 8, 27),
        horaInicioPlanificada: '23:00',
        horaFinPlanificada: '01:00',
      );

      expect(tarea.cruzaMedianoche, isTrue);
      expect(tarea.estaPlanificadaEn(DateTime(2026, 8, 27, 23, 30)), isTrue);
      expect(tarea.estaPlanificadaEn(DateTime(2026, 8, 28, 0, 30)), isTrue);
      expect(tarea.estaPlanificadaEn(DateTime(2026, 8, 27, 22, 0)), isFalse);
      expect(tarea.estaPlanificadaEn(DateTime(2026, 8, 28, 2, 0)), isFalse);
    });

    test('una tarea sin planificación nunca está activa', () {
      final tarea = Tarea(
        titulo: 'Sin plan',
        fechaCreacion: DateTime(2026, 8, 20),
        fechaVencimiento: DateTime(2026, 8, 27, 10, 0),
      );

      expect(tarea.estaPlanificadaEn(DateTime(2026, 8, 27, 10, 0)), isFalse);
    });
  });
}
