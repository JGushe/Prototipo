import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/recomendacion.dart';
import '../database/database_helper.dart';
import '../services/motor_recomendaciones.dart';

class RecomendacionesScreen extends StatefulWidget {
  const RecomendacionesScreen({super.key});

  @override
  State<RecomendacionesScreen> createState() => _RecomendacionesScreenState();
}

class _RecomendacionesScreenState extends State<RecomendacionesScreen> {
  final _db = DatabaseHelper.instance;
  final _motor = MotorRecomendaciones();
  List<Recomendacion> _recomendaciones = [];
  bool _cargando = true;

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
    setState(() => _cargando = true);
    await _motor.evaluarYGenerar();
    await _cargar();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✓ Recomendaciones generadas')),
      );
    }
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
