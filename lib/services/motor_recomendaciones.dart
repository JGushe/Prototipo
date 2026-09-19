import '../models/contexto_recomendacion.dart';
import '../models/recomendacion.dart';
import '../database/database_helper.dart';
import 'contexto_recomendacion_service.dart';
import 'reglas/configuracion_motor.dart';
import 'reglas/creador_recomendaciones.dart';
import 'reglas/evaluador_reglas.dart';
import 'reglas/regla_recomendacion.dart';
import 'reglas/reglas_por_defecto.dart';

/// Motor de recomendaciones: orquesta el ciclo completo separando cada etapa.
///
/// 1. **Adquisición del contexto** → [ContextoRecomendacionService]
/// 2. **Evaluación de las reglas** → [EvaluadorReglas]
/// 3. **Creación de recomendaciones** → [CreadorRecomendaciones]
/// 4. **Persistencia**
///
/// Las reglas son datos ([ReglaRecomendacion]); añadir una nueva no requiere
/// modificar esta clase. Cada recomendación conserva qué regla la generó y por
/// qué, de modo que el resultado es explicable.
class MotorRecomendaciones {
  final DatabaseHelper _db;
  final ContextoRecomendacionService _contextoService;
  final EvaluadorReglas _evaluador;
  final CreadorRecomendaciones _creador;
  final ConfiguracionMotor _config;

  MotorRecomendaciones({
    DatabaseHelper? db,
    ContextoRecomendacionService? contextoService,
    ConfiguracionMotor? configuracion,
    List<ReglaRecomendacion>? reglas,
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
        _creador = creador ?? const CreadorRecomendaciones();

  static ConfiguracionMotor _resolverConfiguracion(ConfiguracionMotor? c) =>
      c ?? ConfiguracionMotor.porDefecto;

  /// Configuración de umbrales en uso.
  ConfiguracionMotor get configuracion => _config;

  /// Reglas registradas en el motor.
  List<ReglaRecomendacion> get reglas => _evaluador.reglas;

  /// Evalúa las reglas sobre el contexto y genera las recomendaciones.
  ///
  /// Si se recibe [contexto] ya construido se reutiliza y no se vuelven a
  /// consultar las fuentes. Las recomendaciones se guardan y se devuelven
  /// ordenadas por prioridad de la regla que las originó.
  Future<List<Recomendacion>> evaluarYGenerar({
    ContextoRecomendacion? contexto,
  }) async {
    // 1. Contexto
    final ctx = contexto ?? await _contextoService.construir();

    // 2. Evaluación de reglas
    final resultados = _evaluador.evaluar(ctx);

    // 3. Creación de recomendaciones
    final recomendaciones = _creador.crearTodos(resultados, ctx);

    // 4. Persistencia
    for (final recomendacion in recomendaciones) {
      await _db.insertarRecomendacion(recomendacion);
    }

    return recomendaciones;
  }
}
