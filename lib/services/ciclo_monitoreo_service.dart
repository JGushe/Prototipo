import 'contexto_recomendacion_service.dart';
import 'motor_recomendaciones.dart';
import 'recomendaciones_notificador.dart';
import 'reglas/resultado_evaluacion.dart';
import 'uso_pantalla_service.dart';

class FalloNotificacionMonitoreo implements Exception {
  final Object causa;

  const FalloNotificacionMonitoreo(this.causa);

  @override
  String toString() => 'Error al enviar las notificaciones de monitoreo';
}

/// Ejecuta el mismo ciclo desde la actualización manual y WorkManager.
class CicloMonitoreoService {
  final UsoPantallaService _uso;
  final ContextoRecomendacionService _contexto;
  final MotorRecomendaciones _motor;
  final RecomendacionesNotificador _notificador;

  CicloMonitoreoService({
    UsoPantallaService? uso,
    ContextoRecomendacionService? contexto,
    MotorRecomendaciones? motor,
    RecomendacionesNotificador? notificador,
  })  : _uso = uso ?? UsoPantallaService(),
        _contexto = contexto ?? ContextoRecomendacionService(),
        _motor = motor ?? MotorRecomendaciones(registrarDetalle: false),
        _notificador = notificador ?? RecomendacionesNotificador();

  Future<({ResultadoEvaluacion resultado, int notificadas})> ejecutar() async {
    final muestra = await _uso.capturarMuestraDelDia();
    final contexto = await _contexto.construirDesdeMuestra(muestra);
    final resultado = await _motor.ejecutar(contexto: contexto);
    try {
      final notificadas = await _notificador.notificarTodas(resultado.generadas);
      return (resultado: resultado, notificadas: notificadas);
    } catch (e) {
      // La transacción del motor ya confirmó el historial. Repetir el ciclo
      // no reenvía estas recomendaciones porque ahora están en cooldown.
      throw FalloNotificacionMonitoreo(e);
    }
  }
}
