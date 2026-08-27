import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../database/database_helper.dart';
import '../services/uso_pantalla_service.dart';
import '../models/uso_pantalla.dart';

class UsoScreen extends StatefulWidget {
  const UsoScreen({super.key});

  @override
  State<UsoScreen> createState() => _UsoScreenState();
}

class _UsoScreenState extends State<UsoScreen> {
  final _db = DatabaseHelper.instance;
  final _usoService = UsoPantallaService();

  UsoPantalla? _usoHoy;
  List<AppUso> _topApps = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    final uso = await _db.obtenerUsoHoy();
    final apps = await _usoService.obtenerTopAppsDelDia(top: 5);
    setState(() {
      _usoHoy = uso;
      _topApps = apps;
      _cargando = false;
    });
  }

  Future<void> _actualizarDatos() async {
    final tienePermiso = await _usoService.solicitarPermisoUso();
    if (!tienePermiso) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Permiso requerido'),
            content: const Text('Para capturar datos de uso, activa el permiso de '
                'Uso de la aplicación en Ajustes > Aplicaciones > Acceso especial.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
      return;
    }
    await _usoService.capturarUsoDelDia();
    await _cargarDatos();
  }

  String _formatearTiempo(int minutos) {
    final h = minutos ~/ 60;
    final m = minutos % 60;
    return h > 0 ? '${h}h ${m}min' : '${m}min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Uso de Pantalla'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _actualizarDatos),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Resumen del día
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Resumen de hoy',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Text('⏱️ Tiempo total: ${_formatearTiempo(_usoHoy?.tiempoTotalMinutos ?? 0)}',
                              style: const TextStyle(fontSize: 18)),
                          const SizedBox(height: 6),
                          Text('🔓 Desbloqueos: ${_usoHoy?.numeroDesbloqueos ?? 0}'),
                          if (_usoHoy?.appMasUsada != null) ...[
                            const SizedBox(height: 6),
                            Text('⭐ App más usada: ${_usoHoy!.appMasUsada} '
                                '(${_formatearTiempo(_usoHoy!.tiempoAppMasUsada)})'),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Top apps (gráfico circular)
                  const Text('Top aplicaciones (hoy)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _topApps.isEmpty
                      ? const Center(child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('Sin datos. Presiona actualizar para capturar.')))
                      : SizedBox(
                          height: 220,
                          child: PieChart(
                            PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 40,
                              sections: _topApps.map((app) {
                                final color = Colors.primaries[_topApps.indexOf(app) % Colors.primaries.length];
                                return PieChartSectionData(
                                  value: app.tiempoUsoMinutos.toDouble(),
                                  title: '${app.tiempoUsoMinutos}m',
                                  color: color,
                                  radius: 60,
                                  titleStyle: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                  const SizedBox(height: 16),

                  // Lista detallada
                  ..._topApps.map((app) => Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.primaries[_topApps.indexOf(app) % Colors.primaries.length].shade100,
                            child: Text('${_topApps.indexOf(app) + 1}'),
                          ),
                          title: Text(app.nombreApp),
                          subtitle: Text(app.nombrePaquete, style: const TextStyle(fontSize: 11)),
                          trailing: Text(_formatearTiempo(app.tiempoUsoMinutos),
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      )),
                ],
              ),
            ),
    );
  }
}
