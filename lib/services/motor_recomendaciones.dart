import 'package:flutter/foundation.dart';

import '../models/contexto_recomendacion.dart';
import '../models/recomendacion.dart';
import '../database/database_helper.dart';
import 'contexto_recomendacion_service.dart';
import 'reglas/configuracion_motor.dart';
import 'reglas/creador_recomendaciones.dart';
import 'reglas/evaluador_reglas.dart';
import 'reglas/politica_cooldown.dart';
import 'reglas/regla_recomendacion.dart';
import 'reglas/reglas_por_defecto.dart';
import 'reglas/resultado_evaluacion.dart';

/// Motor de recomendaciones: orquesta el ciclo completo separando cada etapa.
///
/// 1. **Adquisición del contexto** → [ContextoRecomendacionService]
/// 2. **Evaluación de las reglas** → [EvaluadorReglas]
/// 3. **Control de duplicados** → [PoliticaCooldown]
/// 4. **Creación de recomendaciones** → [CreadorRecomendaciones]
/// 5. **Persistencia**
///
/// Las reglas son datos ([ReglaRecomendacion]); añadir una nueva no requiere
/// modificar esta clase. Cada recomendación conserva qué regla la generó y por
/// qué, y las que se descartan por cooldown se registran sin borrar nunca el
/// historial.
class MotorRecomendaciones {
  final DatabaseHelper _db;
  final ContextoRecomendacionService _contextoService;
  final EvaluadorReglas _evaluador;
  final PoliticaCooldown _politica;
  final CreadorRecomendaciones _creador;
  final ConfiguracionMotor _config;

  MotorRecomendaciones({
    DatabaseHelper? db,
    ContextoRecomendacionService? contextoService,
    ConfiguracionMotor? configuracion,
    List<ReglaRecomendacion>? reglas,
    PoliticaCooldown? politica,
    CreadorRecomendaciones? creador,
  })  : _db = db ?? DatabaseHelper.instance,
        _config = _resolverConfiguracion(configuracion),
        _contextoService = contextoService ??
            ContextoRecomendacionService(
              config: _resolverConfiguracion(configuracion),
            ),
        _evaluador = EvaluadorReglas(
          reglas ?? crearReglasPorDefecto(_resolverConfiguracion(configuracion)),
        ),
        _politica = politica ?? const PoliticaCooldown(),
        _creador = creador ?? const CreadorRecomendaciones();

  static ConfiguracionMotor _resolverConfiguracion(ConfiguracionMotor? c) =>
      c ?? ConfiguracionMotor.porDefecto;

  /// Configuración de umbrales y cooldowns en uso.
  ConfiguracionMotor get configuracion => _config;

  /// Reglas registradas en el motor.
  List<ReglaRecomendacion> get reglas => _evaluador.reglas;

  /// Ejecuta el motor y devuelve el detalle de la decisión.
  ///
  /// Si se recibe [contexto] ya construido se reutiliza y no se vuelven a
  /// consultar las fuentes. Solo se insertan las recomendaciones que no son
  /// duplicados dentro de su cooldown; el historial nunca se borra.
  Future<ResultadoEvaluacion> ejecutar({ContextoRecomendacion? contexto}) async {
    // 1. Contexto
    final ctx = contexto ?? await _contextoService.construir();

    // 2. Evaluación de reglas
    final resultados = _evaluador.evaluar(ctx);

    // 3. Historial relevante: una sola consulta, acotada a la ventana más
    //    antigua que podría bloquear alguna regla.
    final historial = await _db.obtenerRecomendacionesDesde(_inicioHistorial(ctx));

    // 4. Control de duplicados, creación y persistencia
    final generadas = <Recomendacion>[];
    final descartadas = <DescarteCooldown>[];

    for (final resultado in resultados) {
      final descarte = _politica.evaluar(
        regla: resultado.regla,
        contexto: ctx,
        historial: historial,
      );
      if (descarte != null) {
        descartadas.add(descarte);
        _registrarDescarte(descarte);
        continue;
      }

      final recomendacion = _creador.crear(resultado, ctx);
      await _db.insertarRecomendacion(recomendacion);
      generadas.add(recomendacion);
      // Evita que dos reglas equivalentes se inserten en la misma ejecución.
      historial.add(recomendacion);
    }

    return ResultadoEvaluacion(
      generadas: generadas,
      descartadas: descartadas,
      reglasEvaluadas: resultados.length,
    );
  }

  /// Ejecuta el motor y devuelve solo las recomendaciones nuevas.
  Future<List<Recomendacion>> evaluarYGenerar({
    ContextoRecomendacion? contexto,
  }) async =>
      (await ejecutar(contexto: contexto)).generadas;

  /// Inicio del historial que podría bloquear alguna regla: el más antiguo
  /// entre el inicio del día y `momento - cooldown` de cada regla.
  DateTime _inicioHistorial(ContextoRecomendacion contexto) {
    var inicio = DateTime(
      contexto.momento.year,
      contexto.momento.month,
      contexto.momento.day,
    );
    for (final regla in _evaluador.reglas) {
      final desde = regla.inicioVentanaCooldown(contexto);
      if (desde.isBefore(inicio)) inicio = desde;
    }
    return inicio;
  }

  void _registrarDescarte(DescarteCooldown descarte) {
    if (kDebugMode) {
      debugPrint('[MotorRecomendaciones] ${descarte.motivo}');
    }
  }
}
