import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/comparacion_diaria.dart';
import '../models/evolucion_semanal.dart';
import '../models/recomendacion.dart';
import '../database/database_helper.dart';
import '../services/motor_recomendaciones.dart';
import '../services/lectura_uso_controller.dart';
import '../widgets/estado_lectura_uso.dart';
import '../theme/app_theme.dart';
import '../services/recomendaciones_notificador.dart';
import '../services/reglas/resultado_evaluacion.dart';

class RecomendacionesScreen extends StatefulWidget {
  const RecomendacionesScreen({super.key, required this.lectura});

  final LecturaUsoController lectura;

  @override
  State<RecomendacionesScreen> createState() => _RecomendacionesScreenState();
}

class _RecomendacionesScreenState extends State<RecomendacionesScreen> {
  final _db = DatabaseHelper.instance;
  final _motor = MotorRecomendaciones();
  final _notificador = RecomendacionesNotificador();
  List<Recomendacion> _recomendaciones = [];
  EvolucionSemanal? _evolucion;
  bool _errorHistorial = false;
  bool _cargando = true;

  /// Evita lanzar el motor varias veces (p. ej. doble toque del botón).
  bool _generando = false;

  /// Última ejecución, para el inspector de desarrollo.
  ResultadoEvaluacion? _ultimoResultado;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() => _cargando = true);
    try {
      final recs = await _db.obtenerRecomendaciones();
      final ahora = DateTime.now();
      final evolucion = EvolucionSemanal.calcular(
        usos: await _db.obtenerUsoEntre(
          DateTime(ahora.year, ahora.month, ahora.day - 14),
          DateTime(ahora.year, ahora.month, ahora.day - 1),
        ),
        ahora: ahora,
        primeraRecomendacion: await _db.primeraFechaRecomendacion(),
      );
      if (!mounted) return;
      setState(() {
        _recomendaciones = recs;
        _evolucion = evolucion;
        _errorHistorial = false;
      });
    } catch (_) {
      if (mounted) setState(() => _errorHistorial = true);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _valorar(Recomendacion r, String? valoracion) async {
    if (r.id == null) return;
    try {
      await _db.valorarRecomendacion(r.id!, valoracion);
      if (mounted) await _cargar();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar la valoración.')),
        );
      }
    }
  }

  Future<void> _generarRecomendaciones() async {
    if (_generando) return;
    _generando = true;
    setState(() => _cargando = true);
    try {
      final resultado = await _motor.ejecutar();
      _ultimoResultado = resultado;

      // Notificar igual que el Dashboard y el ciclo de segundo plano: si no se
      // hace aquí, generar desde esta pantalla no avisa al usuario.
      final notificadas =
          await _notificador.notificarTodas(resultado.generadas);

      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ ${resultado.generadas.length} recomendaciones nuevas'
              '${resultado.huboDescartes ? ' · ${resultado.descartadas.length} en cooldown' : ''}'
              '${notificadas > 0 ? ' · $notificadas notificadas' : ''}',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error generando recomendaciones: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      _generando = false;
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Inspector de desarrollo: muestra el contexto, la regla activada, las
  /// reglas descartadas y el motivo de cada decisión.
  Future<void> _mostrarInspeccion() async {
    final resultado = _ultimoResultado;
    if (resultado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ejecuta el motor primero (botón ✨)')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🔍 Inspección del motor (dev)'),
        content: SingleChildScrollView(
          child: Text(
            resultado.resumen(),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  IconData _iconoTipo(String tipo) {
    switch (tipo) {
      case 'pausa':
        return Icons.pause_circle;
      case 'alerta_uso':
        return Icons.warning;
      case 'sugerencia_foco':
        return Icons.center_focus_strong;
      case 'descanso':
        return Icons.self_improvement;
      default:
        return Icons.info;
    }
  }

  Color _colorTipo(String tipo, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppTheme.colors(context);
    switch (tipo) {
      case 'pausa':
        return colors.warning;
      case 'alerta_uso':
        return scheme.error;
      case 'sugerencia_foco':
        return scheme.primary;
      case 'descanso':
        return scheme.tertiary;
      default:
        return scheme.outline;
    }
  }

  Color _colorSeveridad(String severidad, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppTheme.colors(context);
    switch (severidad) {
      case 'critica':
        return scheme.error;
      case 'advertencia':
        return colors.warning;
      case 'sugerencia':
        return scheme.primary;
      default:
        return scheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.lectura,
        builder: (context, _) => _buildTips(context),
      );

  Widget _buildTips(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recomendaciones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            onPressed: _generando || widget.lectura.actualizando
                ? null
                : _generarRecomendaciones,
            tooltip: 'Generar recomendaciones',
          ),
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.bug_report),
              onPressed: _mostrarInspeccion,
              tooltip: 'Inspeccionar la última ejecución',
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await (widget.lectura.leer(forzar: true), _cargar()).wait;
        },
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _recomendaciones.length + 1,
          itemBuilder: (ctx, i) {
            if (i == 0) {
              return Column(
                children: [
                  if (widget.lectura.estado != EstadoLecturaUso.disponible)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: EtiquetaLecturaUso(widget.lectura),
                    ),
                  if (widget.lectura.estado == EstadoLecturaUso.sinPermiso)
                    TextButton(
                      onPressed: widget.lectura.actualizar,
                      child: const Text('Abrir acceso al uso'),
                    ),
                  if (widget.lectura.comparacion?.motivo ==
                          MotivoComparacion.sinDatos &&
                      widget.lectura.comparacion?.minutosHoy != null)
                    const Text('Datos insuficientes para comparar con ayer.'),
                  if (_cargando)
                    const LinearProgressIndicator(
                        semanticsLabel: 'Cargando recomendaciones'),
                  if (_evolucion != null)
                    TarjetaEvolucionTips(
                      evolucion: _evolucion!,
                      comparacion: widget.lectura.comparacion,
                    ),
                  if (_errorHistorial)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No se pudo cargar el historial.'),
                    )
                  else if (!_cargando && _recomendaciones.isEmpty) ...[
                    Icon(Icons.lightbulb_outline,
                        size: 64, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 12),
                    const Text('No hay recomendaciones aún'),
                    FilledButton.icon(
                      onPressed: _generando || widget.lectura.actualizando
                          ? null
                          : _generarRecomendaciones,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Generar ahora'),
                    ),
                  ],
                ],
              );
            }
            final r = _recomendaciones[i - 1];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              color: r.leida
                  ? null
                  : _colorTipo(r.tipo, ctx).withValues(alpha: 0.1),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _colorTipo(r.tipo, ctx),
                  child:
                      Icon(_iconoTipo(r.tipo), color: Colors.white, size: 20),
                ),
                title: Text(r.titulo,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.reglaId != null) ...[
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _colorSeveridad(r.severidad, ctx)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${r.severidad.toUpperCase()} · Regla ${r.reglaId}',
                              style: TextStyle(
                                fontSize: 10,
                                color: _colorSeveridad(r.severidad, ctx),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(r.mensaje),
                    const SizedBox(height: 2),
                    BotonesValoracion(
                      valoracion: r.valoracion,
                      onCambio: (v) => _valorar(r, v),
                    ),
                    if (r.motivo != null && r.motivo!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        r.motivo!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(ctx)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.65),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(DateFormat('dd/MM HH:mm').format(r.fecha),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(ctx)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.55),
                        )),
                  ],
                ),
                onTap: () async {
                  if (r.id != null) {
                    await _db.marcarRecomendacionLeida(r.id!);
                    await _cargar();
                  }
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Tarjeta de tendencia para Tips. Reutiliza la comparación semanal y no
/// crea reglas ni notificaciones: es solo texto explicativo.
class TarjetaEvolucionTips extends StatelessWidget {
  const TarjetaEvolucionTips({
    super.key,
    required this.evolucion,
    this.comparacion,
  });

  final EvolucionSemanal evolucion;

  /// Comparación de hoy con ayer. Si es válida, el mensaje diario tiene
  /// prioridad; si no, se usa la evolución semanal.
  final ComparacionDiaria? comparacion;

  bool get _usarDiaria =>
      comparacion?.estado == EstadoComparacionDiaria.disponible;

  IconData get _icono {
    if (_usarDiaria) {
      final diferencia =
          comparacion!.diferenciaDistractor ?? comparacion!.diferenciaMinutos!;
      if (diferencia < -ComparacionDiaria.umbralMinutos) {
        return Icons.trending_down;
      }
      if (diferencia > ComparacionDiaria.umbralMinutos) {
        return Icons.trending_up;
      }
      return Icons.trending_flat;
    }
    return switch (evolucion.tendencia) {
      TendenciaEvolucion.reduccion => Icons.trending_down,
      TendenciaEvolucion.aumento => Icons.trending_up,
      TendenciaEvolucion.estable => Icons.trending_flat,
      TendenciaEvolucion.sinDatos => Icons.hourglass_empty,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icono, size: 18, color: Colors.blueGrey),
                const SizedBox(width: 6),
                const Text('Tu evolución',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _usarDiaria ? comparacion!.mensajeTips : evolucion.mensajeTips,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              _usarDiaria ? comparacion!.accionTips : evolucion.accionTips,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botones voluntarios de valoración. Tocar la opción activa la quita
/// (sin respuesta). No marca leída ni implica aplicación.
class BotonesValoracion extends StatelessWidget {
  const BotonesValoracion({
    super.key,
    required this.valoracion,
    required this.onCambio,
  });

  final String? valoracion;
  final ValueChanged<String?> onCambio;

  @override
  Widget build(BuildContext context) {
    Widget boton(String texto, String valor, IconData icono) {
      final activo = valoracion == valor;
      return TextButton.icon(
        onPressed: () => onCambio(activo ? null : valor),
        icon: Icon(activo ? Icons.check : icono, size: 16),
        label: Text(texto, style: const TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
          foregroundColor: activo
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return Row(
      children: [
        boton('Útil', 'util', Icons.thumb_up_alt_outlined),
        boton('No me sirvió', 'no_util', Icons.thumb_down_alt_outlined),
      ],
    );
  }
}
