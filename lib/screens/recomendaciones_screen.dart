import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/recomendacion.dart';
import '../database/database_helper.dart';
import '../services/motor_recomendaciones.dart';
import '../services/recomendaciones_notificador.dart';
import '../services/reglas/resultado_evaluacion.dart';

class RecomendacionesScreen extends StatefulWidget {
  const RecomendacionesScreen({super.key});

  @override
  State<RecomendacionesScreen> createState() => _RecomendacionesScreenState();
}

class _RecomendacionesScreenState extends State<RecomendacionesScreen> {
  final _db = DatabaseHelper.instance;
  final _motor = MotorRecomendaciones();
  final _notificador = RecomendacionesNotificador();
  List<Recomendacion> _recomendaciones = [];
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
    setState(() => _cargando = true);
    final recs = await _db.obtenerRecomendaciones();
    setState(() {
      _recomendaciones = recs;
      _cargando = false;
    });
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
      final notificadas = await _notificador.notificarTodas(resultado.generadas);

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
      case 'pausa': return Icons.pause_circle;
      case 'alerta_uso': return Icons.warning;
      case 'sugerencia_foco': return Icons.center_focus_strong;
      case 'descanso': return Icons.self_improvement;
      default: return Icons.info;
    }
  }

  Color _colorTipo(String tipo) {
    switch (tipo) {
      case 'pausa': return Colors.orange;
      case 'alerta_uso': return Colors.red;
      case 'sugerencia_foco': return Colors.blue;
      case 'descanso': return Colors.purple;
      default: return Colors.grey;
    }
  }

  Color _colorSeveridad(String severidad) {
    switch (severidad) {
      case 'critica': return Colors.red;
      case 'advertencia': return Colors.orange;
      case 'sugerencia': return Colors.blue;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recomendaciones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            onPressed: _generarRecomendaciones,
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
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _recomendaciones.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lightbulb_outline, size: 80, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('No hay recomendaciones aún'),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _generarRecomendaciones,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Generar ahora'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    itemCount: _recomendaciones.length,
                    itemBuilder: (ctx, i) {
                      final r = _recomendaciones[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        color: r.leida ? null : _colorTipo(r.tipo).withValues(alpha: 0.1),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _colorTipo(r.tipo),
                            child: Icon(_iconoTipo(r.tipo), color: Colors.white, size: 20),
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
                                        color: _colorSeveridad(r.severidad)
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${r.severidad.toUpperCase()} · Regla ${r.reglaId}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: _colorSeveridad(r.severidad),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                              ],
                              Text(r.mensaje),
                              if (r.motivo != null && r.motivo!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  r.motivo!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.blueGrey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(DateFormat('dd/MM HH:mm').format(r.fecha),
                                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
