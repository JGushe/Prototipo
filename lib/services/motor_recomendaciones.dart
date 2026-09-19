import 'package:flutter/foundation.dart';

import '../models/contexto_recomendacion.dart';
import '../models/recomendacion.dart';
import 'contexto_recomendacion_service.dart';
import 'reglas/configuracion_motor.dart';
import 'reglas/creador_recomendaciones.dart';
import 'reglas/evaluador_reglas.dart';
import 'reglas/politica_cooldown.dart';
import 'reglas/regla_recomendacion.dart';
import 'reglas/reglas_por_defecto.dart';
import 'reglas/repositorio_recomendaciones.dart';
import 'reglas/resultado_evaluacion.dart';

/// Motor de recomendaciones: orquesta el ciclo completo separando cada etapa.
///
/// 1. **Adquisición del contexto** → [ContextoRecomendacionService]
/// 2. **Evaluación de las reglas** → [EvaluadorReglas]
/// 3. **Control de duplicados** → [PoliticaCooldown]
/// 4. **Creación de recomendaciones** → [CreadorRecomendaciones]
/// 5. **Persistencia** → [RepositorioRecomendaciones]
///
/// Las reglas son datos ([ReglaRecomendacion]); añadir una nueva no requiere
/// modificar esta clase. Cada ejecución devuelve un [ResultadoEvaluacion] con
/// el contexto, el detalle de cada regla y los descartes, para poder inspeccionar
/// y documentar el comportamiento.
class MotorRecomendaciones {
  final ContextoRecomendacionService _contextoService;
  final EvaluadorReglas _evaluador;
  final PoliticaCooldown _politica;
  final CreadorRecomendaciones _creador;
  final RepositorioRecomendaciones _repositorio;
  final ConfiguracionMotor _config;

  /// Ejecución en curso: las llamadas simultáneas la reutilizan en lugar de
  /// lanzar el motor varias veces.
  Future<ResultadoEvaluacion>? _enCurso;

  MotorRecomendaciones({
    ContextoRecomendacionService? contextoService,
    ConfiguracionMotor? configuracion,
    List<ReglaRecomendacion>? reglas,
    PoliticaCooldown? politica,
    CreadorRecomendaciones? creador,
    RepositorioRecomendaciones? repositorio,
  })  : _config = _resolverConfiguracion(configuracion),
        _contextoService = contextoService ??
            ContextoRecomendacionService(
              config: _resolverConfiguracion(configuracion),
            ),
        _evaluador = EvaluadorReglas(
          reglas ?? crearReglasPorDefecto(_resolverConfiguracion(configuracion)),
        ),
        _politica = politica ?? const PoliticaCooldown(),
        _creador = creador ?? const CreadorRecomendaciones(),
        _repositorio = repositorio ?? RepositorioRecomendacionesSqlite();

  static ConfiguracionMotor _resolverConfiguracion(ConfiguracionMotor? c) =>
      c ?? ConfiguracionMotor.porDefecto;

  /// Configuración de umbrales y cooldowns en uso.
  ConfiguracionMotor get configuracion => _config;

  /// Reglas registradas en el motor.
  List<ReglaRecomendacion> get reglas => _evaluador.reglas;

  /// Ejecuta el motor y devuelve el detalle de la decisión.
  ///
  /// Si ya hay una ejecución en curso, se devuelve la misma: el motor nunca se
  /// ejecuta dos veces simultáneamente. Si se recibe [contexto] ya construido
  /// se reutiliza y no se vuelven a consultar las fuentes. Solo se insertan las
  /// recomendaciones que no son duplicados dentro de su cooldown; el historial
  /// nunca se borra.
  Future<ResultadoEvaluacion> ejecutar({ContextoRecomendacion? contexto}) {
    final enCurso = _enCurso;
    if (enCurso != null) return enCurso;

    final ejecucion = _ejecutarInterno(contexto: contexto);
    _enCurso = ejecucion;
    ejecucion.whenComplete(() {
      if (identical(_enCurso, ejecucion)) _enCurso = null;
    });
    return ejecucion;
  }

  /// Ejecuta el motor y devuelve solo las recomendaciones nuevas.
  Future<List<Recomendacion>> evaluarYGenerar({
    ContextoRecomendacion? contexto,
  }) async =>
      (await ejecutar(contexto: contexto)).generadas;

  Future<ResultadoEvaluacion> _ejecutarInterno({
    ContextoRecomendacion? contexto,
  }) async {
    // 1. Contexto
    final ctx = contexto ?? await _contextoService.construir();

    // 2. Evaluación detallada de todas las reglas
    final evaluaciones = _evaluador.detallar(ctx);
    final resultados = _evaluador.evaluar(ctx);

    // 3. Historial relevante: una sola consulta, acotada a la ventana más
    //    antigua que podría bloquear alguna regla.
    final historial = await _repositorio.obtenerDesde(_inicioHistorial(ctx));

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
        _marcarEvaluacion(
          evaluaciones,
          resultado.regla.id,
          ResultadoReglaEjecucion.descartadaPorCooldown,
          motivo: descarte.motivo,
        );
        _registrarDescarte(descarte);
        continue;
      }

      final recomendacion = _creador.crear(resultado, ctx);
      await _repositorio.insertar(recomendacion);
      generadas.add(recomendacion);
      _marcarEvaluacion(
        evaluaciones,
        resultado.regla.id,
        ResultadoReglaEjecucion.generada,
      );
      // Evita que dos reglas equivalentes se inserten en la misma ejecución.
      historial.add(recomendacion);
    }

    final resultadoFinal = ResultadoEvaluacion(
      contexto: ctx,
      evaluaciones: evaluaciones,
      generadas: generadas,
      descartadas: descartadas,
      reglasEvaluadas: resultados.length,
    );

    // Inspección en modo desarrollo.
    if (kDebugMode) {
      debugPrint(resultadoFinal.resumen());
    }

    return resultadoFinal;
  }

  /// Anota en el detalle de una regla qué ocurrió con ella.
  void _marcarEvaluacion(
    List<EvaluacionRegla> evaluaciones,
    String reglaId,
    ResultadoReglaEjecucion resultado, {
    String? motivo,
  }) {
    final indice = evaluaciones.indexWhere((e) => e.reglaId == reglaId);
    if (indice < 0) return;
    final anterior = evaluaciones[indice];
    evaluaciones[indice] = EvaluacionRegla(
      reglaId: anterior.reglaId,
      nombre: anterior.nombre,
      prioridad: anterior.prioridad,
      aplica: anterior.aplica,
      explicaciones: anterior.explicaciones,
      condicionesFallidas: anterior.condicionesFallidas,
      resultado: resultado,
      motivoDescarte: motivo,
    );
  }

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
