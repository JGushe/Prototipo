import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../services/notificacion_service.dart';
import '../services/uso_pantalla_service.dart';
import '../services/motor_recomendaciones.dart';
import '../services/monitoreo_segundo_plano_service.dart';
import '../services/recomendaciones_notificador.dart';
import '../services/reglas/resultado_evaluacion.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _db = DatabaseHelper.instance;
  final _usoService = UsoPantallaService();
  final _motor = MotorRecomendaciones();
  final _notificador = RecomendacionesNotificador();
  final _monitoreo = MonitoreoSegundoPlanoService();

  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _usoSemanal = [];
  bool _cargando = true;

  /// Evita lanzar el motor varias veces (p. ej. doble toque del botón).
  bool _actualizando = false;

  /// Resultado de la última ejecución, para mostrar el resumen.
  ResultadoEvaluacion? _ultimoResultado;

  /// Estado del monitoreo en segundo plano (WorkManager).
  bool _monitoreoActivo = false;
  bool _cambiandoMonitoreo = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _consultarMonitoreo();
  }

  Future<void> _consultarMonitoreo() async {
    final activo = await _monitoreo.estaActivo();
    if (mounted) setState(() => _monitoreoActivo = activo);
  }

  Future<void> _alternarMonitoreo() async {
    if (_cambiandoMonitoreo) return;
    setState(() => _cambiandoMonitoreo = true);
    try {
      if (_monitoreoActivo) {
        await _monitoreo.detener();
      } else {
        // El monitoreo sin acceso al uso no aporta datos: se pide antes.
        final permiso = await _usoService.solicitarPermisoUso();
        if (!permiso) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Se requiere el permiso de uso para monitorear'),
              ),
            );
          }
          return;
        }
        await _monitoreo.iniciar();
      }
      await _consultarMonitoreo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_monitoreoActivo
                ? '✓ Monitoreo en segundo plano activado'
                : 'Monitoreo en segundo plano detenido'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cambiandoMonitoreo = false);
    }
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      final tareas = await _db.obtenerTareas();
      final tareasPendientes = tareas.where((t) => !t.completada).length;
      final usoHoy = await _db.obtenerUsoHoy();
      final usoSemanal = await _db.obtenerUsoSemanal();

      setState(() {
        _stats = {
          'tareasTotal': tareas.length,
          'tareasPendientes': tareasPendientes,
          'usoHoyMinutos': usoHoy?.tiempoTotalMinutos ?? 0,
          'appMasUsada': usoHoy?.appMasUsada ?? 'Sin datos',
        };
        _usoSemanal = usoSemanal
            .map((u) => {
                  'fecha': u.fecha,
                  'minutos': u.tiempoTotalMinutos,
                })
            .toList()
            .reversed
            .toList();
      });
    } catch (e) {
      debugPrint('Error cargando datos: $e');
    }
    setState(() => _cargando = false);
  }

  /// Envía una notificación de prueba: permite comprobar que el canal funciona
  /// sin esperar a que una regla se dispare (y sin chocar con el cooldown).
  Future<void> _probarNotificacion() async {
    final servicio = NotificacionService();
    try {
      await servicio.init();
      final permiso = await servicio.tienePermisoNotificaciones() ||
          await servicio.solicitarPermisoNotificaciones();
      if (!permiso) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Las notificaciones están bloqueadas para la app: '
                  'actívalas en Ajustes > Aplicaciones > Prototipo Tesis'),
            ),
          );
        }
        return;
      }
      await servicio.enviarNotificacionDePrueba();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🔔 Notificación de prueba enviada')),
        );
      }
    } catch (e) {
      debugPrint('Error enviando notificación de prueba: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo notificar: $e')),
        );
      }
    }
  }

  Future<void> _actualizarUso() async {
    if (_actualizando) return; // el motor no se ejecuta dos veces a la vez
    _actualizando = true;
    try {
      final tienePermiso = await _usoService.solicitarPermisoUso();
      if (!tienePermiso) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Se requiere permiso de uso para capturar datos')),
          );
        }
        return;
      }

      await _usoService.capturarUsoDelDia();

      // Ciclo completo: contexto -> reglas -> cooldown -> almacenamiento.
      final resultado = await _motor.ejecutar();

      // Notificar solo las recomendaciones que correspondan (y con permiso).
      await _notificador.notificarTodas(resultado.generadas);

      await _cargarDatos();
      if (mounted) {
        setState(() => _ultimoResultado = resultado);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ ${resultado.generadas.length} recomendaciones nuevas'
              '${resultado.huboDescartes ? ' · ${resultado.descartadas.length} en cooldown' : ''}',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error actualizando uso: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar: $e')),
        );
      }
    } finally {
      _actualizando = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _actualizarUso,
            tooltip: 'Actualizar datos',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargarDatos,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Tarjetas de métricas
                  Row(
                    children: [
                      Expanded(child: _buildCard(
                        'Tareas Pendientes',
                        _stats['tareasPendientes'].toString(),
                        Icons.task_alt,
                        Colors.blue,
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: _buildCard(
                        'Uso Hoy (min)',
                        _stats['usoHoyMinutos'].toString(),
                        Icons.timer,
                        Colors.orange,
                      )),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildCard(
                    'App más usada',
                    _stats['appMasUsada'].toString(),
                    Icons.star,
                    Colors.purple,
                    fullWidth: true,
                  ),
                  if (_ultimoResultado != null) ...[
                    const SizedBox(height: 12),
                    _buildCard(
                      'Motor de recomendaciones',
                      '${_ultimoResultado!.generadas.length} nuevas · '
                          '${_ultimoResultado!.descartadas.length} en cooldown',
                      Icons.auto_awesome,
                      Colors.teal,
                      fullWidth: true,
                    ),
                  ],
                  const SizedBox(height: 12),

                  // Estado y control del monitoreo en segundo plano.
                  Card(
                    elevation: 2,
                    color: _monitoreoActivo
                        ? Colors.green.withValues(alpha: 0.08)
                        : null,
                    child: ListTile(
                      leading: Icon(
                        _monitoreoActivo
                            ? Icons.shield_moon
                            : Icons.shield_outlined,
                        color: _monitoreoActivo ? Colors.green : Colors.grey,
                      ),
                      title: Text(
                        _monitoreoActivo ? 'Monitoreo activo' : 'Monitoreo detenido',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Comprueba el uso cada ~15 min aunque cierres la app',
                        style: TextStyle(fontSize: 11),
                      ),
                      trailing: _cambiandoMonitoreo
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Switch(
                              value: _monitoreoActivo,
                              onChanged: (_) => _alternarMonitoreo(),
                            ),
                      onTap: _alternarMonitoreo,
                    ),
                  ),

                  // Verificación del canal de notificaciones.
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _probarNotificacion,
                      icon: const Icon(Icons.notifications_active_outlined,
                          size: 18),
                      label: const Text('Probar notificación'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Gráfico de uso semanal
                  const Text('Uso de pantalla (últimos 7 días)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 220,
                    child: _usoSemanal.isEmpty
                        ? const Center(child: Text('Sin datos aún. Presiona actualizar.'))
                        : BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: _usoSemanal.fold<int>(0, (max, e) =>
                                      e['minutos'] > max ? e['minutos'] : max).toDouble() + 60,
                              barGroups: _usoSemanal.asMap().entries.map((entry) {
                                return BarChartGroupData(
                                  x: entry.key,
                                  barRods: [
                                    BarChartRodData(
                                      toY: entry.value['minutos'].toDouble(),
                                      color: Colors.blue,
                                      width: 22,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ],
                                );
                              }).toList(),
                              titlesData: FlTitlesData(
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 30,
                                    getTitlesWidget: (value, meta) {
                                      return Text('${value.toInt()}',
                                          style: const TextStyle(fontSize: 10));
                                    },
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      final idx = value.toInt();
                                      if (idx < 0 || idx >= _usoSemanal.length) {
                                        return const SizedBox.shrink();
                                      }
                                      final fecha = _usoSemanal[idx]['fecha'] as DateTime;
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          DateFormat('E').format(fecha),
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              gridData: const FlGridData(show: true),
                              borderData: FlBorderData(show: false),
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCard(String titulo, String valor, IconData icono, Color color, {bool fullWidth = false}) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(titulo,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(valor,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
