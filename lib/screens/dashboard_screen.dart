import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../database/database_helper.dart';
import '../models/comparacion_diaria.dart';
import '../models/perfil.dart';
import '../models/evolucion_semanal.dart';
import '../models/recomendacion.dart';
import '../services/notificacion_service.dart';
import '../services/uso_pantalla_service.dart';
import '../services/lectura_uso_controller.dart';
import '../widgets/estado_lectura_uso.dart';
import '../services/monitoreo_segundo_plano_service.dart';
import '../services/reglas/resultado_evaluacion.dart';
import '../theme/app_theme.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.lectura});

  final LecturaUsoController lectura;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _db = DatabaseHelper.instance;
  final _usoService = UsoPantallaService();
  final _monitoreo = MonitoreoSegundoPlanoService();

  Map<String, dynamic> _stats = {};
  EvolucionSemanal? _evolucion;
  ComparacionDiaria? get _comparacion => widget.lectura.comparacion;
  Perfil? _perfil;
  ModoEvolucion _modoEvolucion = ModoEvolucion.diario;
  ResumenValoraciones? _resumenHoy;
  ResumenValoraciones? _resumenSemana;
  bool _cargando = true;
  Future<void>? _carga;
  bool _recargarAlTerminar = false;
  ComparacionDiaria? _lecturaVista;
  bool _capturando = false;

  ResultadoEvaluacion? get _ultimoResultado => widget.lectura.ultimaEvaluacion;

  /// Estado del monitoreo en segundo plano (WorkManager).
  bool _monitoreoActivo = false;
  bool _cambiandoMonitoreo = false;

  @override
  void initState() {
    super.initState();
    _lecturaVista = _comparacion;
    _capturando = widget.lectura.actualizando;
    widget.lectura.addListener(_alCambiarLectura);
    _cargarDatos();
    _consultarMonitoreo();
  }

  @override
  void dispose() {
    widget.lectura.removeListener(_alCambiarLectura);
    super.dispose();
  }

  void _alCambiarLectura() {
    final lectura = _comparacion;
    final capturaTerminada = _capturando && !widget.lectura.actualizando;
    _capturando = widget.lectura.actualizando;
    if (_capturando || widget.lectura.estado == EstadoLecturaUso.leyendo) {
      return;
    }
    if (!identical(lectura, _lecturaVista) || capturaTerminada) {
      _lecturaVista = lectura;
      _cargarDatos();
    }
  }

  Future<void> _cargarDatos() {
    if (_carga case final pendiente?) {
      _recargarAlTerminar = true;
      return pendiente;
    }
    final carga = Future<void>.microtask(() async {
      do {
        _recargarAlTerminar = false;
        await _consultarDatos();
      } while (mounted && _recargarAlTerminar);
    }).whenComplete(() => _carga = null);
    _carga = carga;
    return carga;
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

  Future<void> _consultarDatos() async {
    if (!mounted) return;
    setState(() => _cargando = true);
    try {
      final tareas = await _db.obtenerTareas();
      final tareasPendientes = tareas.where((t) => !t.completada).length;
      final usoHoy = await _db.obtenerUsoHoy();
      final perfil = await _db.obtenerPerfil();

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

      if (!mounted || _recargarAlTerminar) return;
      if (!DateUtils.isSameDay(ahora, DateTime.now())) {
        _recargarAlTerminar = true;
        return;
      }
      setState(() {
        _stats = {
          'tareasTotal': tareas.length,
          'tareasPendientes': tareasPendientes,
          'appMasUsada': usoHoy?.appMasUsada ?? 'Sin datos',
        };
        _evolucion = evolucion;
        _perfil = perfil;
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
    final resultado = await widget.lectura.actualizar();
    if (!mounted || resultado == null) return;
    await _carga;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('${resultado.generadas.length} recomendaciones nuevas')),
    );
  }

  Future<void> _refrescarPanel() async {
    await widget.lectura.leer(forzar: true);
    await (_carga ?? _cargarDatos());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.lectura,
        builder: (context, _) => _buildPanel(context),
      );

  Widget _buildPanel(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppTheme.colors(context);

    return Scaffold(
      body: SafeArea(
        child: _cargando && _evolucion == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _refrescarPanel,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    if (_cargando) const LinearProgressIndicator(),
                    _buildHeader(theme),
                    const SizedBox(height: 16),
                    _buildHero(theme, colors),
                    const SizedBox(height: 12),
                    _buildMetricsGrid(theme, colors),
                    const SizedBox(height: 12),
                    _buildMonitoringCard(theme),
                    if (_ultimoResultado != null) ...[
                      const SizedBox(height: 12),
                      _buildMotorCard(theme),
                    ],
                    const SizedBox(height: 16),
                    if (_evolucion != null) ...[
                      SeccionEvolucionDigital(
                        evolucion: _evolucion!,
                        comparacion: _comparacion,
                        resumenDiario: _resumenHoy,
                        resumenSemanal: _resumenSemana,
                        modo: _modoEvolucion,
                        onCambioModo: (m) {
                          setState(() => _modoEvolucion = m);
                          if (m == ModoEvolucion.sieteDias) _cargarDatos();
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _probarNotificacion,
                        icon: const Icon(Icons.notifications_active_outlined,
                            size: 18),
                        label: const Text('Probar notificación'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hola, ${_perfil?.nombreVisible ?? 'Usuario'}',
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: 2),
              Text('Tu resumen de bienestar digital',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.65))),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: widget.lectura.actualizando ? null : _actualizarUso,
          tooltip: 'Actualizar datos',
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _buildHero(ThemeData theme, AppThemeColors colors) {
    final minutos = _comparacion?.minutosHoy;
    final distractor = _comparacion?.distractorHoy;
    final porcentaje = porcentajeDistractor(minutos, distractor);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: colors.gradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('HOY',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            theme.colorScheme.onPrimary.withValues(alpha: 0.8),
                        letterSpacing: 1.2)),
                const SizedBox(height: 4),
                Text(minutos == null ? '—' : formatearMinutosUso(minutos),
                    style: theme.textTheme.displaySmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontSize: 36,
                        height: 1)),
                Text('Tiempo único de pantalla',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onPrimary)),
                EtiquetaLecturaUso(
                  widget.lectura,
                  color: theme.colorScheme.onPrimary,
                  mostrarCorte: true,
                ),
                if (distractor != null) ...[
                  const SizedBox(height: 8),
                  Text(
                      'En apps distractoras: ${formatearMinutosUso(distractor)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimary
                              .withValues(alpha: 0.85))),
                ],
                if (porcentaje != null)
                  Text('Porcentaje del uso de apps clasificadas.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onPrimary)),
              ],
            ),
          ),
          if (porcentaje != null)
            _buildDonut(
                theme, colors, distractor!, minutos! - distractor, porcentaje),
        ],
      ),
    );
  }

  Widget _buildDonut(ThemeData theme, AppThemeColors colors, int distractor,
      int resto, int porcentaje) {
    return Semantics(
      label:
          '$porcentaje por ciento del tiempo único en apps distractoras. Describe el uso de apps clasificadas.',
      excludeSemantics: true,
      child: SizedBox(
        width: 96,
        height: 96,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 30,
                startDegreeOffset: -90,
                sections: [
                  PieChartSectionData(
                    value: distractor.toDouble(),
                    color: colors.chartColors.length > 3
                        ? colors.chartColors[3]
                        : colors.warning,
                    radius: 14,
                    showTitle: false,
                  ),
                  PieChartSectionData(
                    value: resto.toDouble(),
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.35),
                    radius: 14,
                    showTitle: false,
                  ),
                ],
              ),
            ),
            Text('$porcentaje%',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.onPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsGrid(ThemeData theme, AppThemeColors colors) {
    final scheme = theme.colorScheme;
    final distractor = _comparacion?.distractorHoy;
    final desbloqueos = _comparacion?.desbloqueosHoy;

    return Column(
      children: [
        Row(
          children: [
            _statCard(
              theme,
              etiqueta: 'Tareas pendientes',
              valor: '${_stats['tareasPendientes'] ?? 0}',
              icono: Icons.task_alt,
              color: scheme.primary,
            ),
            const SizedBox(width: 12),
            _statCard(
              theme,
              etiqueta: 'Desbloqueos hoy',
              valor: desbloqueos == null ? '—' : '$desbloqueos',
              icono: Icons.lock_open,
              color: scheme.secondary,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _statCard(
              theme,
              etiqueta: 'App más usada',
              valor: '${_stats['appMasUsada'] ?? 'Sin datos'}',
              icono: Icons.star_outline,
              color: scheme.tertiary,
            ),
            const SizedBox(width: 12),
            _statCard(
              theme,
              etiqueta: 'Distractor del día',
              valor: distractor == null ? '—' : '$distractor min',
              icono: Icons.do_not_disturb_on_outlined,
              color: colors.warning,
            ),
          ],
        ),
      ],
    );
  }

  Widget _statCard(
    ThemeData theme, {
    required String etiqueta,
    required String valor,
    required IconData icono,
    required Color color,
  }) {
    final scheme = theme.colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icono, size: 18, color: color),
            ),
            const SizedBox(height: 8),
            Text(valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(etiqueta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.6))),
          ],
        ),
      ),
    );
  }

  Widget _buildMonitoringCard(ThemeData theme) {
    final scheme = theme.colorScheme;
    final color = _monitoreoActivo ? scheme.primary : scheme.outline;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(
            _monitoreoActivo ? Icons.shield_moon : Icons.shield_outlined,
            color: color,
            size: 20,
          ),
        ),
        title: Text(
          _monitoreoActivo ? 'Monitoreo activo' : 'Monitoreo detenido',
          style: theme.textTheme.titleMedium,
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
    );
  }

  Widget _buildMotorCard(ThemeData theme) {
    final contexto = _ultimoResultado!.contexto;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_ultimoResultado!.generadas.length} nuevas · '
              '${_ultimoResultado!.descartadas.length} en cooldown'
              '${contexto.horarioActivo != null && contexto.usosBloqueActivo.isNotEmpty ? '\nDistractor en el bloque evaluado: ${formatearMinutosUso(contexto.minutosDistractoresBloqueActivo)}' : ''}',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
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
            ButtonSegment(
                value: ModoEvolucion.sieteDias, label: Text('7 días')),
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
                ? _construirDiario(context)
                : _construirSemana(context),
          ),
        ),
      ],
    );
  }

  Widget _construirDiario(BuildContext context) {
    final c = comparacion;
    if (c == null || c.estado == EstadoComparacionDiaria.insuficiente) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.grey),
              SizedBox(width: 6),
              Expanded(
                child: Text('Datos insuficientes para comparar',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
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
            : (
                Icons.trending_flat,
                Colors.blueGrey,
                'Sin cambio significativo'
              );

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
        Text(c.explicacion,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        _lineaValoraciones(resumenDiario, 'hoy'),
        const SizedBox(height: 8),
        Semantics(
          label: 'Ayer ${c.minutosAyer} minutos; hoy ${c.minutosHoy} minutos '
              'hasta las ${c.corte!.hour}:${c.corte!.minute.toString().padLeft(2, '0')}',
          child: SizedBox(
            height: 140,
            child: _graficoBarras(
              context,
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

  Widget _periodoDiario(
          String titulo, DateTime dia, int? minutos, int? distractor) =>
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
            Text(
                distractor == null
                    ? 'Sin dato distractor'
                    : 'Distractor $distractor min',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      );

  Widget _construirSemana(BuildContext context) {
    final reciente = evolucion.reciente;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_fecha(reciente.desde)} – ${_fecha(reciente.hasta)}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        Text('${reciente.diasValidos}/7 días con registro'),
        if (reciente.diasValidos == 0)
          const Text('Sin registros de uso en estos siete días.')
        else ...[
          Text('${reciente.promedioMinutosPantalla!.round()} min/día',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Text(
              'Promedio de los días con registro. — indica un día sin registro.',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 8),
          Semantics(
            label: [
              for (var i = 0; i < 7; i++)
                '${_fecha(DateTime(reciente.desde.year, reciente.desde.month, reciente.desde.day + i))}: '
                    '${evolucion.diasRecientes[i]?.tiempoTotalMinutos == null ? 'sin registro' : '${evolucion.diasRecientes[i]!.tiempoTotalMinutos} minutos'}',
            ].join('; '),
            child: SizedBox(height: 160, child: _graficoLinea(context)),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
            'Las capturas pueden ser parciales; tener registro no garantiza medir todo el día.',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
        _lineaValoraciones(resumenSemanal, 'en 7 días'),
        const Divider(height: 20),
        if (evolucion.estado == EstadoEvolucion.insuficiente)
          Text('Comparación no disponible. ${evolucion.explicacion}',
              style: const TextStyle(fontSize: 12, color: Colors.grey))
        else
          _construirComparacion(context),
      ],
    );
  }

  Widget _construirComparacion(BuildContext context) {
    final anterior = evolucion.anterior;
    final reciente = evolucion.reciente;
    final diferencia = evolucion.diferenciaMinutos;
    final porcentaje = evolucion.porcentajeMinutos;
    final noComparable = evolucion.estado == EstadoEvolucion.noComparable;

    final (IconData icono, String texto) = switch (evolucion.tendencia) {
      TendenciaEvolucion.reduccion => (
          Icons.trending_down,
          'Reducción observada'
        ),
      TendenciaEvolucion.aumento => (Icons.trending_up, 'Aumento observado'),
      TendenciaEvolucion.estable => (
          Icons.trending_flat,
          'Sin cambio relevante'
        ),
      TendenciaEvolucion.sinDatos => (
          Icons.trending_flat,
          'Sin datos suficientes'
        ),
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
        const Text('Tendencia de distractor semanal: sin datos por periodo',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
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
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('${periodo.diasValidos}/${periodo.diasEsperados} días',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      );

  Widget _graficoBarras(
    BuildContext context, {
    required double valorA,
    required double valorB,
    required String etiquetaA,
    required String etiquetaB,
  }) {
    final theme = Theme.of(context);
    final colors = AppTheme.colors(context);
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
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: colors.chartGrid, strokeWidth: 1),
        ),
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
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.7))),
              ),
            ),
          ),
        ),
        barGroups: [
          BarChartGroupData(x: 0, barRods: [
            barra(valorA, colors.chartColors[1].withValues(alpha: 0.6))
          ]),
          BarChartGroupData(
              x: 1, barRods: [barra(valorB, colors.chartColors[0])]),
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

  Widget _graficoLinea(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppTheme.colors(context);
    final puntos = evolucion.diasRecientes;
    final mayor = puntos.fold<int>(
        0,
        (max, uso) => (uso?.tiempoTotalMinutos ?? 0) > max
            ? uso!.tiempoTotalMinutos
            : max);
    final maxY = mayor == 0 ? 60.0 : mayor * 1.2 + 20;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 6,
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: colors.chartGrid, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) => Text('${value.toInt()}',
                  style: TextStyle(
                      fontSize: 10,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 38,
              getTitlesWidget: (value, meta) {
                final indice = value.toInt();
                if (indice < 0 || indice >= puntos.length) {
                  return const SizedBox.shrink();
                }
                final inicio = evolucion.reciente.desde;
                final fecha =
                    DateTime(inicio.year, inicio.month, inicio.day + indice);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      '${_fecha(fecha)}${puntos[indice] == null ? '\n—' : ''}',
                      style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6))),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < puntos.length; i++)
                puntos[i] == null
                    ? FlSpot.nullSpot
                    : FlSpot(
                        i.toDouble(), puntos[i]!.tiempoTotalMinutos.toDouble()),
            ],
            isCurved: false,
            barWidth: 3,
            color: colors.chartColors[0],
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: false,
              color: colors.chartColors[0].withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }

  static String _fecha(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/'
      '${fecha.month.toString().padLeft(2, '0')}';
}
