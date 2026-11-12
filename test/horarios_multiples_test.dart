// Pruebas de horarios múltiples: nombre, activación, categorías y precedencia.
//
// Son pruebas de Dart puro (modelo y análisis); el CRUD real contra SQLite se
// verifica en el dispositivo, ya que requiere el plugin de base de datos.

import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/models/horario.dart';
import 'package:prototipo_tesis/models/intervalo_uso.dart';
import 'package:prototipo_tesis/services/contexto_recomendacion_service.dart';
import 'package:prototipo_tesis/services/monitoreo_uso_horarios_service.dart';

const _todosLosDias = [1, 2, 3, 4, 5, 6, 7];
final _lunes = DateTime(2026, 8, 24);

IntervaloUso _uso(int h1, int m1, int h2, int m2) => IntervaloUso(
      nombrePaquete: 'com.zhiliaoapp.musically',
      nombreApp: 'TikTok',
      inicio: DateTime(_lunes.year, _lunes.month, _lunes.day, h1, m1),
      fin: DateTime(_lunes.year, _lunes.month, _lunes.day, h2, m2),
    );

void main() {
  group('Modelo Horario con nombre y activación', () {
    test('serializa y reconstruye nombre y activo', () {
      final horario = Horario(
        tipo: Horario.tipoPersonalizado,
        nombre: 'Gimnasio',
        horaInicio: 6,
        horaFin: 7,
        diasSemana: const [1, 3, 5],
        activo: false,
      );

      final copia = Horario.fromMap(horario.toMap());

      expect(copia.nombre, 'Gimnasio');
      expect(copia.activo, isFalse);
      expect(copia.tipo, Horario.tipoPersonalizado);
      expect(copia.diasSemana, [1, 3, 5]);
    });

    test('una fila anterior a la migración v6 queda sin nombre y activa', () {
      // Columnas antiguas: sin 'nombre' ni 'activo'.
      final filaAntigua = <String, dynamic>{
        'id': 1,
        'tipo': 'laboral',
        'horaInicio': 9,
        'minutoInicio': 0,
        'horaFin': 17,
        'minutoFin': 30,
        'diasSemana': '1,2,3,4,5',
      };

      final horario = Horario.fromMap(filaAntigua);

      expect(horario.nombre, isNull);
      expect(horario.activo, isTrue, reason: 'no debe perder funcionalidad');
      expect(horario.nombreVisible, 'Laboral');
      expect(horario.rangoTexto, '09:00 - 17:30');
    });

    test('nombreVisible usa el nombre o, si no hay, la categoría', () {
      expect(
        Horario(tipo: 'laboral', horaInicio: 8, horaFin: 9, nombre: 'Turno A')
            .nombreVisible,
        'Turno A',
      );
      expect(
        Horario(tipo: 'academico', horaInicio: 8, horaFin: 9).nombreVisible,
        'Académico',
      );
      expect(
        Horario(tipo: 'personalizado', horaInicio: 8, horaFin: 9, nombre: '   ')
            .nombreVisible,
        'Personalizado',
      );
    });

    test('tipoTexto cubre las tres categorías', () {
      expect(Horario(tipo: 'laboral', horaInicio: 8, horaFin: 9).tipoTexto,
          'Laboral');
      expect(Horario(tipo: 'academico', horaInicio: 8, horaFin: 9).tipoTexto,
          'Académico');
      expect(
          Horario(tipo: 'personalizado', horaInicio: 8, horaFin: 9).tipoTexto,
          'Personalizado');
      expect(Horario(tipo: 'otra', horaInicio: 8, horaFin: 9).tipoTexto,
          'Personalizado');
    });

    test('diasTexto resume los días configurados', () {
      expect(
        Horario(tipo: 'laboral', horaInicio: 8, horaFin: 9, diasSemana: const [1, 2, 3, 4, 5])
            .diasTexto,
        'L-V',
      );
      expect(
        Horario(tipo: 'laboral', horaInicio: 8, horaFin: 9, diasSemana: const [6, 7])
            .diasTexto,
        'S-D',
      );
      expect(
        Horario(tipo: 'laboral', horaInicio: 8, horaFin: 9, diasSemana: _todosLosDias)
            .diasTexto,
        'Todos los días',
      );
      expect(
        Horario(tipo: 'laboral', horaInicio: 8, horaFin: 9, diasSemana: const [5, 1, 3])
            .diasTexto,
        'L, X, V',
      );
    });

    test('copyWith permite activar y desactivar sin perder datos', () {
      final horario = Horario(
        id: 7,
        tipo: 'laboral',
        nombre: 'Oficina',
        horaInicio: 9,
        horaFin: 18,
        diasSemana: const [1, 2, 3, 4, 5],
      );

      final desactivado = horario.copyWith(activo: false);

      expect(desactivado.activo, isFalse);
      expect(desactivado.id, 7);
      expect(desactivado.nombre, 'Oficina');
      expect(desactivado.horaFin, 18);
      expect(desactivado.diasSemana, [1, 2, 3, 4, 5]);
    });
  });

  group('Precedencia cuando hay varios horarios', () {
    test('laboral y académico tienen prioridad sobre personalizado', () {
      final personalizado =
          Horario(tipo: 'personalizado', horaInicio: 7, horaFin: 8, id: 1);
      final laboral = Horario(tipo: 'laboral', horaInicio: 9, horaFin: 17, id: 2);

      final orden = ContextoRecomendacionService.ordenarPorPrecedencia(
          [personalizado, laboral]);

      expect(orden.first.tipo, 'laboral');
    });

    test('dentro de la misma categoría gana la hora de inicio más temprana', () {
      final tarde =
          Horario(tipo: 'personalizado', horaInicio: 18, horaFin: 20, id: 5);
      final temprano =
          Horario(tipo: 'personalizado', horaInicio: 6, horaFin: 8, id: 9);

      final orden = ContextoRecomendacionService.ordenarPorPrecedencia(
          [tarde, temprano]);

      expect(orden.first.horaInicio, 6);
    });

    test('ante empate total el orden es determinista por id', () {
      final a = Horario(tipo: 'personalizado', horaInicio: 8, horaFin: 9, id: 2);
      final b = Horario(tipo: 'personalizado', horaInicio: 8, horaFin: 9, id: 1);

      final orden =
          ContextoRecomendacionService.ordenarPorPrecedencia([a, b]);

      expect(orden.map((h) => h.id), [1, 2]);
    });
  });

  group('Categorías en el análisis de uso', () {
    test('un horario personalizado cuenta como contexto, no como laboral', () {
      final personalizado = Horario(
        tipo: Horario.tipoPersonalizado,
        nombre: 'Gimnasio',
        horaInicio: 8,
        horaFin: 17,
        diasSemana: _todosLosDias,
      );

      final analisis = MonitoreoUsoHorariosService.analizar(
        intervalos: [_uso(9, 0, 9, 30)],
        horarios: [personalizado],
        tareas: const [],
      ).single;

      expect(analisis.minutosEnHorarios, 30);
      expect(analisis.enHorarioLaboral.inMinutes, 0);
      expect(analisis.enHorarioAcademico.inMinutes, 0);
    });

    test('un horario laboral sí suma a enHorarioLaboral', () {
      final laboral = Horario(
        tipo: Horario.tipoLaboral,
        horaInicio: 8,
        horaFin: 17,
        diasSemana: _todosLosDias,
      );

      final analisis = MonitoreoUsoHorariosService.analizar(
        intervalos: [_uso(9, 0, 9, 30)],
        horarios: [laboral],
        tareas: const [],
      ).single;

      expect(analisis.minutosEnHorarios, 30);
      expect(analisis.enHorarioLaboral.inMinutes, 30);
    });

    test('varios horarios de la misma categoría no duplican minutos', () {
      final manana = Horario(
        tipo: Horario.tipoLaboral,
        horaInicio: 8,
        horaFin: 12,
        diasSemana: _todosLosDias,
      );
      final tarde = Horario(
        tipo: Horario.tipoLaboral,
        horaInicio: 8,
        horaFin: 17,
        diasSemana: _todosLosDias,
      );

      final analisis = MonitoreoUsoHorariosService.analizar(
        intervalos: [_uso(9, 0, 10, 0)],
        horarios: [manana, tarde],
        tareas: const [],
      ).single;

      expect(analisis.minutosEnHorarios, 60);
      expect(analisis.duracionTotal.inMinutes, 60);
    });
  });
}
