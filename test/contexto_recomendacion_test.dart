// Pruebas del modelo ContextoRecomendacion (Etapa 4).
//
// Verifican la clasificación de aplicaciones distractoras y los campos
// derivados del contexto. Son pruebas de Dart puro: no necesitan base de datos
// ni el plugin de UsageStats.

import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/models/contexto_recomendacion.dart';
import 'package:prototipo_tesis/models/horario.dart';
import 'package:prototipo_tesis/models/tarea.dart';
import 'package:prototipo_tesis/models/uso_pantalla.dart';

AppUso app(String paquete, int minutos, {String? nombre}) => AppUso(
      nombrePaquete: paquete,
      nombreApp: nombre ?? paquete,
      tiempoUsoMinutos: minutos,
      numeroAperturas: 1,
    );

void main() {
  group('Contexto vacío', () {
    final contexto = ContextoRecomendacion(momento: DateTime(2026, 8, 24, 10));

    test('sin datos el contexto es coherente', () {
      expect(contexto.tipoHorario, ContextoRecomendacion.tipoNinguno);
      expect(contexto.tipoHorarioTexto, 'Ninguno');
      expect(contexto.hayHorarioActivo, isFalse);
      expect(contexto.hayTareaActiva, isFalse);
      expect(contexto.tareasPendientesTotal, 0);
      expect(contexto.tareasAltaPrioridadTotal, 0);
      expect(contexto.tiempoTotalPantallaMinutos, 0);
      expect(contexto.hayDatosUsoPantalla, isFalse);
      expect(contexto.permisoUsoDisponible, isFalse);
      expect(contexto.hayAppsMasUtilizadas, isFalse);
    });

    test('sin aplicaciones no hay distractoras', () {
      expect(contexto.appsDistractoras, isEmpty);
      expect(contexto.minutosAppsDistractoras, 0);
      expect(contexto.appDistractoraPrincipal, isNull);
      expect(contexto.hayAppsDistractoras, isFalse);
    });
  });

  group('Clasificación de paquetes distractores', () {
    test('coincidencia exacta', () {
      expect(ContextoRecomendacion.esPaqueteDistractor('com.instagram'), isTrue);
      expect(ContextoRecomendacion.esPaqueteDistractor('com.whatsapp'), isTrue);
    });

    test('coincidencia por prefijo', () {
      expect(
        ContextoRecomendacion.esPaqueteDistractor('com.instagram.android'),
        isTrue,
      );
      expect(ContextoRecomendacion.esPaqueteDistractor('com.facebook.katana'), isTrue);
      expect(
        ContextoRecomendacion.esPaqueteDistractor('com.zhiliaoapp.musically'),
        isTrue,
      );
    });

    test('no distingue mayúsculas', () {
      expect(ContextoRecomendacion.esPaqueteDistractor('COM.INSTAGRAM'), isTrue);
    });

    test('un paquete no relacionado no es distractor', () {
      expect(ContextoRecomendacion.esPaqueteDistractor('com.android.chrome'), isFalse);
      expect(ContextoRecomendacion.esPaqueteDistractor('org.mozilla.firefox'), isFalse);
      // El prefijo debe terminar en punto: 'com.instagramx' no coincide.
      expect(ContextoRecomendacion.esPaqueteDistractor('com.instagramx'), isFalse);
    });
  });

  group('Derivados de las aplicaciones', () {
    final contexto = ContextoRecomendacion(
      momento: DateTime(2026, 8, 24, 10),
      appsMasUtilizadas: [
        app('com.android.chrome', 50, nombre: 'Chrome'),
        app('com.instagram', 40, nombre: 'Instagram'),
        app('com.whatsapp', 15, nombre: 'WhatsApp'),
        app('com.spotify.music', 10, nombre: 'Spotify'),
      ],
    );

    test('appsDistractoras solo incluye las clasificadas', () {
      final paquetes = contexto.appsDistractoras.map((a) => a.nombrePaquete).toList();
      expect(paquetes, ['com.instagram', 'com.whatsapp']);
    });

    test('minutosAppsDistractoras suma solo las distractoras', () {
      expect(contexto.minutosAppsDistractoras, 55); // 40 + 15
    });

    test('appDistractoraPrincipal es la de mayor tiempo entre las distractoras', () {
      expect(contexto.appDistractoraPrincipal?.nombrePaquete, 'com.instagram');
      expect(contexto.appDistractoraPrincipal?.tiempoUsoMinutos, 40);
      expect(contexto.hayAppsDistractoras, isTrue);
    });

    test('sin distractoras no hay principal aunque haya apps', () {
      final soloNeutras = ContextoRecomendacion(
        momento: DateTime(2026, 8, 24, 10),
        appsMasUtilizadas: [app('com.android.chrome', 50)],
      );
      expect(soloNeutras.hayAppsMasUtilizadas, isTrue);
      expect(soloNeutras.appDistractoraPrincipal, isNull);
      expect(soloNeutras.minutosAppsDistractoras, 0);
      expect(soloNeutras.hayAppsDistractoras, isFalse);
    });
  });

  group('Horario y tarea activos', () {
    test('tipoHorario refleja el horario activo', () {
      final laboral = ContextoRecomendacion(
        momento: DateTime(2026, 8, 24, 10),
        horarioActivo: Horario(tipo: 'laboral', horaInicio: 8, horaFin: 16),
      );
      expect(laboral.tipoHorario, ContextoRecomendacion.tipoLaboral);
      expect(laboral.tipoHorarioTexto, 'Laboral');
      expect(laboral.hayHorarioActivo, isTrue);

      final academico = ContextoRecomendacion(
        momento: DateTime(2026, 8, 24, 20),
        horarioActivo: Horario(tipo: 'academico', horaInicio: 19, horaFin: 21),
      );
      expect(academico.tipoHorario, ContextoRecomendacion.tipoAcademico);
      expect(academico.tipoHorarioTexto, 'Académico');
    });

    test('tareaActiva y conteos de tareas', () {
      final contexto = ContextoRecomendacion(
        momento: DateTime(2026, 8, 24, 10),
        tareaActiva: Tarea(titulo: 'Estudiar', fechaCreacion: DateTime(2026, 8, 20)),
        tareasPendientes: [
          Tarea(titulo: 'A', fechaCreacion: DateTime(2026, 8, 20)),
          Tarea(titulo: 'B', fechaCreacion: DateTime(2026, 8, 20)),
          Tarea(titulo: 'C', fechaCreacion: DateTime(2026, 8, 20), prioridad: 'alta'),
        ],
        tareasAltaPrioridadPendientes: [
          Tarea(titulo: 'C', fechaCreacion: DateTime(2026, 8, 20), prioridad: 'alta'),
        ],
      );

      expect(contexto.hayTareaActiva, isTrue);
      expect(contexto.tareaActiva?.titulo, 'Estudiar');
      expect(contexto.tareasPendientesTotal, 3);
      expect(contexto.tareasAltaPrioridadTotal, 1);
    });
  });
}
