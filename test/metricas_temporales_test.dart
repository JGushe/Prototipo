import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/models/intervalo_uso.dart';
import 'package:prototipo_tesis/services/analisis_horario_service.dart';
import 'package:prototipo_tesis/services/monitoreo_uso_horarios_service.dart';

DateTime _hora(int h, [int m = 0, int dia = 5]) =>
    DateTime(2026, 11, dia, h, m);

EventoUso _app(DateTime instante, String paquete, bool resume,
        {String? clase}) =>
    EventoUso(
      momento: instante,
      nombrePaquete: paquete,
      esResume: resume,
      clase: clase,
    );

void main() {
  test('multiventana conserva duraciones por app y fusiona el total', () {
    final traza = MonitoreoUsoHorariosService.reconstruir([
      _app(_hora(8), 'a', true),
      _app(_hora(8, 15), 'b', true),
      _app(_hora(8, 45), 'b', false),
      _app(_hora(9), 'a', false),
    ]);
    expect(traza.intervalos.map((i) => i.duracion.inMinutes), [30, 60]);
    expect(traza.minutosUnicos(VentanaTiempo(_hora(8), _hora(9))), 60);
    expect(traza.interactivos, isEmpty);
  });

  test('1131 minutos por app se reducen a 754 únicos a las 12:34', () {
    final traza = MonitoreoUsoHorariosService.reconstruir([
      _app(_hora(0), 'a', true),
      _app(_hora(6), 'a', false),
      _app(_hora(3), 'b', true),
      _app(_hora(9), 'b', false),
      _app(_hora(6, 34), 'c', true),
      _app(_hora(12, 34), 'c', false),
      _app(_hora(10), 'd', true),
      _app(_hora(10, 51), 'd', false),
    ]);
    expect(traza.intervalos.fold(0, (n, i) => n + i.duracion.inMinutes), 1131);
    expect(traza.minutosUnicos(VentanaTiempo(_hora(0), _hora(12, 34))), 754);
  });

  test('actividades solapadas del mismo paquete tampoco duplican su total', () {
    final traza = MonitoreoUsoHorariosService.reconstruir([
      _app(_hora(8), 'a', true, clase: 'A'),
      _app(_hora(8, 15), 'a', true, clase: 'B'),
      _app(_hora(8, 45), 'a', false, clase: 'A'),
      _app(_hora(9), 'a', false, clase: 'B'),
    ]);
    final app = MonitoreoUsoHorariosService.analizar(
      intervalos: traza.intervalos,
      horarios: [],
      tareas: [],
    ).single;
    expect(app.minutosTotales, 60);
  });

  test('una sesión nocturna cruza medianoche con sus horas correctas', () {
    final traza = MonitoreoUsoHorariosService.reconstruir([
      EventoUso.sistema(_hora(23, 45), TipoEventoUso.pantallaInteractiva),
      _app(_hora(23, 50), 'a', true),
      _app(_hora(0, 20, 6), 'a', false),
    ]);
    final horas = AnalisisHorarioService.repartirPorHora(
      traza.interactivos,
      VentanaTiempo(_hora(22), _hora(6, 0, 6)),
    );
    expect(horas.minutos, {23: 10, 0: 20});
    expect(horas.minutosEntre(22, 6), 30);
    expect(traza.minutosUnicos(VentanaTiempo(_hora(22), _hora(0, 0, 6))), 10);
  });

  test('cierre tras apagar no extiende una sesión ni la reactiva al encender',
      () {
    final traza = MonitoreoUsoHorariosService.reconstruir([
      EventoUso.sistema(_hora(22), TipoEventoUso.pantallaInteractiva),
      _app(_hora(22), 'a', true),
      EventoUso.sistema(_hora(22, 8), TipoEventoUso.pantallaInactiva),
      EventoUso.sistema(_hora(23), TipoEventoUso.pantallaInteractiva),
      _app(_hora(23, 30), 'a', false),
    ]);
    expect(traza.intervalos.single.duracion.inMinutes, 8);
    expect(traza.interactivos.single.duracion.inMinutes, 8);
  });

  test('pantalla bloqueada o encendida sin app no aporta tiempo nocturno', () {
    final traza = MonitoreoUsoHorariosService.reconstruir([
      EventoUso.sistema(_hora(22), TipoEventoUso.bloqueo),
      EventoUso.sistema(_hora(23), TipoEventoUso.pantallaInteractiva),
      _app(_hora(23), 'a', true),
      _app(_hora(1, 0, 6), 'a', false),
      EventoUso.sistema(_hora(5, 0, 6), TipoEventoUso.desbloqueo),
      EventoUso.sistema(_hora(6, 0, 6), TipoEventoUso.pantallaInactiva),
    ]);
    expect(traza.interactivos, isEmpty);
    expect(
        traza.minutosUnicos(VentanaTiempo(_hora(22), _hora(6, 0, 6))), isNull);
  });

  test('un reinicio impide emparejar una pausa con la sesión anterior', () {
    final traza = MonitoreoUsoHorariosService.reconstruir([
      _app(_hora(8), 'a', true),
      EventoUso.sistema(_hora(8, 10), TipoEventoUso.reinicio),
      _app(_hora(8, 20), 'a', false),
    ]);
    expect(traza.intervalos, isEmpty);
  });
}
