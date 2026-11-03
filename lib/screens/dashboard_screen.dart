import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/comparacion_diaria.dart';
import '../models/evolucion_semanal.dart';
import '../models/recomendacion.dart';
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
  EvolucionSemanal? _evolucion;
  ComparacionDiaria? _comparacion;
  ModoEvolucion _modoEvolucion = ModoEvolucion.diario;
  ResumenValoraciones? _resumenHoy;
  ResumenValoraciones? _resumenSemana;
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

      // Dos semanas completas: el día actual queda fuera por parcial.
      final ahora = DateTime.now();
      final usosEvolucion = await _db.obtenerUsoEntre(
        DateTime(ahora.year, ahora.month, ahora.day - 14),
        DateTime(ahora.year, ahora.month, ahora.day - 1),
      );
      final evolucion = EvolucionSemanal.calcular(
        usos: usosEvolucion,
        ahora: ahora,
        primeraRecomendacion: await _db.primeraFechaRecomendacion(),
      );
      final inicioHoy = DateTime(ahora.year, ahora.month, ahora.day);
      final resumenHoy =
          await _db.obtenerResumenValoracionesEntre(inicioHoy, inicioHoy);
      final resumenSemana = await _db.obtenerResumenValoracionesEntre(
        evolucion.reciente.desde,
        evolucion.reciente.hasta,
      );

      // La comparación diaria depende de eventos de uso; si falla, la pantalla
      // sigue funcionando y ese modo muestra "datos insuficientes".
      ComparacionDiaria? comparacion;
      try {
        comparacion = await _usoService.compararHoyAyer();
      } catch (e) {
        debugPrint('Error comparando hoy con ayer: $e');
      }

      if (!mounted) return;
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
        _evolucion = evolucion;
        _comparacion = comparacion;
        _resumenHoy = resumenHoy;
        _resumenSemana = resumenSemana;
      });
    } catch (e) {
      debugPrint('Error cargando datos: $e');
    }
    if (mounted) setState(() => _cargando = false);
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

                  // Evolución: dos semanas completas, sin tocar el gráfico
                  // semanal existente.
                  if (_evolucion != null) ...[
                    SeccionEvolucionDigital(
                      evolucion: _evolucion!,
                      comparacion: _comparacion,
                      resumenDiario: _resumenHoy,
                      resumenSemanal: _resumenSemana,
                      modo: _modoEvolucion,
                      onCambioModo: (m) => setState(() => _modoEvolucion = m),
                    ),
                    const SizedBox(height: 12),
                  ],

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

/// Sección "Tu evolución digital": compara dos semanas completas.
///
/// Muestra el total diario de pantalla como indicador descriptivo. No usa
/// "distracción" ni atribuye el cambio a las recomendaciones: la distracción
/// contextual no tiene historial persistido.
enum ModoEvolucion { diario, sieteDias }

class SeccionEvolucionDigital extends StatelessWidget {
  const SeccionEvolucionDigital({
    super.key,
    required this.evolucion,
    required this.modo,
    required this.onCambioModo,
    this.comparacion,
    this.resumenDiario,
    this.resumenSemanal,
  });

  final EvolucionSemanal evolucion;
  final ModoEvolucion modo;
  final ValueChanged<ModoEvolucion> onCambioModo;
  final ComparacionDiaria? comparacion;
  final ResumenValoraciones? resumenDiario;
  final ResumenValoraciones? resumenSemanal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tu evolución digital',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Uso total de pantalla por día. Indicador descriptivo: no mide '
          'distracción ni atribuye cambios a los consejos.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 2),
        const Text(
          'La valoración mide utilidad percibida; no demuestra que el Tip '
          'causara el cambio.',
          style: TextStyle(fontSize: 10, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        SegmentedButton<ModoEvolucion>(
          segments: const [
            ButtonSegment(value: ModoEvolucion.diario, label: Text('Diario')),
            ButtonSegment(value: ModoEvolucion.sieteDias, label: Text('7 días')),
          ],
          selected: {modo},
          onSelectionChanged: (seleccion) => onCambioModo(seleccion.first),
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: modo == ModoEvolucion.diario
                ? _construirDiario()
                : (evolucion.estado == EstadoEvolucion.insuficiente
                    ? _construirInsuficiente()
                    : _construirComparacion(context)),
          ),
        ),
      ],
    );
  }

  Widget _construirDiario() {
    final c = comparacion;
    if (c == null || c.estado == EstadoComparacionDiaria.insuficiente) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.grey),
              SizedBox(width: 6),
              Text('Datos insuficientes para comparar',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          if (c != null) ...[
            const SizedBox(height: 6),
            Text(c.explicacion,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ],
      );
    }

    final diferencia = c.diferenciaMinutos!;
    final (IconData icono, Color color, String texto) = diferencia < -5
        ? (Icons.trending_down, Colors.green, 'Menos uso que ayer')
        : diferencia > 5
            ? (Icons.trending_up, Colors.orange, 'Más uso que ayer')
            : (Icons.trending_flat, Colors.blueGrey, 'Sin cambio significativo');

    final distractorHoy = c.distractorHoy;
    final distractorAyer = c.distractorAyer;
    final distractorComparable =
        distractorHoy != null && distractorAyer != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _periodoDiario('Ayer', c.diaAyer, c.minutosAyer, c.distractorAyer),
            const SizedBox(width: 8),
            _periodoDiario('Hoy', c.diaHoy, c.minutosHoy, c.distractorHoy),
          ],
        ),
        const Divider(height: 20),
        Row(
          children: [
            Icon(icono, size: 20, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                [
                  texto,
                  '${diferencia >= 0 ? '+' : ''}$diferencia min',
                  if (c.porcentaje != null)
                    '(${c.porcentaje! >= 0 ? '+' : ''}'
                        '${c.porcentaje!.toStringAsFixed(1)}%)',
                ].join(' · '),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          distractorComparable
              ? 'Distractor: $distractorHoy min hoy · $distractorAyer min ayer'
              : 'Distractor: no disponible para ambos días',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 2),
        Text(c.explicacion, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        _lineaValoraciones(resumenDiario, 'hoy'),
        const SizedBox(height: 8),
        Semantics(
          label: 'Ayer ${c.minutosAyer} minutos; hoy ${c.minutosHoy} minutos '
              'hasta las ${c.corte!.hour}:${c.corte!.minute.toString().padLeft(2, '0')}',
          child: SizedBox(
            height: 140,
            child: _graficoBarras(
              valorA: c.minutosAyer!.toDouble(),
              valorB: c.minutosHoy!.toDouble(),
              etiquetaA: 'Ayer',
              etiquetaB: 'Hoy',
            ),
          ),
        ),
      ],
    );
  }

  Widget _periodoDiario(String titulo, DateTime dia, int? minutos, int? distractor) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$titulo · ${_fecha(dia)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(minutos == null ? '—' : '$minutos min',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(distractor == null ? 'Sin dato distractor' : 'Distractor $distractor min',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      );

  Widget _construirInsuficiente() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.grey),
              SizedBox(width: 6),
              Text('Sin datos suficientes',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Text(evolucion.explicacion,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          Row(
            children: [
              _periodoCobertura(evolucion.anterior, 'Periodo anterior'),
              _periodoCobertura(evolucion.reciente, 'Periodo reciente'),
            ],
          ),
          _lineaValoraciones(resumenSemanal, 'en 7 días'),
        ],
      );

  Widget _periodoCobertura(ResumenPeriodo periodo, String titulo) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text('${periodo.diasValidos}/${periodo.diasEsperados} días',
                style: const TextStyle(fontSize: 13)),
          ],
        ),
      );

  Widget _construirComparacion(BuildContext context) {
    final anterior = evolucion.anterior;
    final reciente = evolucion.reciente;
    final diferencia = evolucion.diferenciaMinutos;
    final porcentaje = evolucion.porcentajeMinutos;
    final noComparable = evolucion.estado == EstadoEvolucion.noComparable;

    final (IconData icono, String texto) = switch (evolucion.tendencia) {
      TendenciaEvolucion.reduccion => (Icons.trending_down, 'Reducción observada'),
      TendenciaEvolucion.aumento => (Icons.trending_up, 'Aumento observado'),
      TendenciaEvolucion.estable => (Icons.trending_flat, 'Sin cambio relevante'),
      TendenciaEvolucion.sinDatos =>
        (Icons.trending_flat, 'Sin datos suficientes'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _periodoResumen(anterior, evolucion.etiquetaAnterior),
            const SizedBox(width: 8),
            _periodoResumen(reciente, 'Periodo reciente'),
          ],
        ),
        const Divider(height: 20),
        Row(
          children: [
            Icon(icono, size: 20, color: Colors.blueGrey),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                [
                  texto,
                  if (diferencia != null)
                    '${diferencia >= 0 ? '+' : ''}${diferencia.round()} min/día'
                        '${porcentaje == null ? '' : ' (${porcentaje >= 0 ? '+' : ''}'
                            '${porcentaje.toStringAsFixed(1)}%)'}',
                ].join(' · '),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        if (noComparable) ...[
          const SizedBox(height: 4),
          const Text(
            'El periodo anterior promedia 0 minutos: solo hay diferencia '
            'absoluta, sin porcentaje.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
        _lineaValoraciones(resumenSemanal, 'en 7 días'),
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Text('Tendencia de distractor semanal: sin datos por periodo',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: 'Promedio diario anterior '
              '${anterior.promedioMinutosPantalla!.round()} minutos; '
              'reciente ${reciente.promedioMinutosPantalla!.round()} minutos',
          child: SizedBox(
            height: 140,
            child: _graficoBarras(
              valorA: anterior.promedioMinutosPantalla!,
              valorB: reciente.promedioMinutosPantalla!,
              etiquetaA: 'Anterior',
              etiquetaB: 'Reciente',
            ),
          ),
        ),
      ],
    );
  }

  Widget _periodoResumen(ResumenPeriodo periodo, String titulo) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 2),
            Text('${_fecha(periodo.desde)} – ${_fecha(periodo.hasta)}',
                style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 4),
            Text('${periodo.promedioMinutosPantalla!.round()} min/día',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            Text('${periodo.diasValidos}/${periodo.diasEsperados} días',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      );

  Widget _graficoBarras({
    required double valorA,
    required double valorB,
    required String etiquetaA,
    required String etiquetaB,
  }) {
    final mayor = valorA > valorB ? valorA : valorB;
    final maxY = mayor == 0 ? 60.0 : mayor * 1.25 + 10;

    BarChartRodData barra(double valor, Color color) => BarChartRodData(
          toY: valor,
          color: color,
          width: 28,
          borderRadius: BorderRadius.circular(4),
        );

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(value == 0 ? etiquetaA : etiquetaB,
                    style: const TextStyle(fontSize: 11)),
              ),
            ),
          ),
        ),
        barGroups: [
          BarChartGroupData(
              x: 0, barRods: [barra(valorA, Colors.grey.shade400)]),
          BarChartGroupData(
              x: 1, barRods: [barra(valorB, Colors.blue)]),
        ],
      ),
    );
  }

  Widget _lineaValoraciones(ResumenValoraciones? resumen, String periodo) =>
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          _textoValoraciones(resumen, periodo),
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      );

  String _textoValoraciones(ResumenValoraciones? resumen, String periodo) {
    if (resumen == null) return 'Recomendaciones $periodo: sin datos';
    if (resumen.generadas == 0) return 'Sin recomendaciones $periodo';
    final base = 'Recomendaciones $periodo: ${resumen.generadas} · '
        'valoradas ${resumen.total}';
    if (resumen.total == 0) return '$base · sin valorar';
    if (!resumen.muestraSuficiente) return '$base · muestra insuficiente';
    return '$base · ${resumen.porcentajeUtil!.toStringAsFixed(0)} % útiles';
  }

  static String _fecha(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/'
      '${fecha.month.toString().padLeft(2, '0')}';
}
