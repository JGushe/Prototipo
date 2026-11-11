import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/comparacion_diaria.dart';
import '../models/evolucion_semanal.dart';
import '../models/recomendacion.dart';
import '../database/database_helper.dart';
import '../services/motor_recomendaciones.dart';
import '../services/lectura_uso_controller.dart';
import '../services/historial_tips_controller.dart';
import '../widgets/estado_lectura_uso.dart';
import '../theme/app_theme.dart';
import '../services/recomendaciones_notificador.dart';
import '../services/reglas/resultado_evaluacion.dart';

class RecomendacionesScreen extends StatefulWidget {
  const RecomendacionesScreen(
      {super.key, required this.lectura, this.historial, this.activa = true});

  final LecturaUsoController lectura;
  final HistorialTipsController? historial;
  final bool activa;

  @override
  State<RecomendacionesScreen> createState() => _RecomendacionesScreenState();
}

class _RecomendacionesScreenState extends State<RecomendacionesScreen>
    with WidgetsBindingObserver {
  final _db = DatabaseHelper.instance;
  final _motor = MotorRecomendaciones();
  final _notificador = RecomendacionesNotificador();
  late final _historial = widget.historial ?? HistorialTipsController();
  final _fechasAbiertas = <String, ValueNotifier<bool>>{};
  final _formatoHora = DateFormat('HH:mm');
  final _formatoFecha = DateFormat('dd/MM/yyyy');
  List<Recomendacion> get _recomendaciones =>
      _historial.viendoArchivo ? _historial.archivo : _historial.recientes;
  bool _capturando = false;
  Future<void>? _carga;
  Future<void>? _comprobacion;
  Timer? _medianoche;
  bool get _cargando => _cargandoResumen || _historial.cargando;
  EvolucionSemanal? _evolucion;
  bool _errorHistorial = false;
  bool _cargandoResumen = true;

  /// Evita lanzar el motor varias veces (p. ej. doble toque del botón).
  bool _generando = false;

  /// Última ejecución, para el inspector de desarrollo.
  ResultadoEvaluacion? _ultimoResultado;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _capturando = widget.lectura.actualizando;
    widget.lectura.addListener(_alCambiarLectura);
    _cargar();
    _programarMedianoche();
  }

  @override
  void didUpdateWidget(covariant RecomendacionesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activa && !oldWidget.activa) _verificarVigencia();
  }

  void _programarMedianoche() {
    _medianoche?.cancel();
    final ahora = _historial.ahora;
    final siguiente = DateTime(ahora.year, ahora.month, ahora.day + 1);
    _medianoche = Timer(siguiente.difference(ahora), () {
      if (!mounted) return;
      if (widget.activa) _verificarVigencia();
      _programarMedianoche();
    });
  }

  Future<void> _verificarVigencia() {
    if (!mounted || !widget.activa) return Future.value();
    if (_carga case final pendiente?) return pendiente;
    if (_comprobacion case final pendiente?) return pendiente;
    final tarea = Future<void>.microtask(() async {
      if (await _historial.comprobarCambios() && mounted) {
        await _cargarResumen();
      }
    }).whenComplete(() => _comprobacion = null);
    _comprobacion = tarea;
    return tarea;
  }

  @override
  void dispose() {
    _medianoche?.cancel();
    for (final apertura in _fechasAbiertas.values) {
      apertura.dispose();
    }
    WidgetsBinding.instance.removeObserver(this);
    widget.lectura.removeListener(_alCambiarLectura);
    if (widget.historial == null) _historial.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.activa) {
      _verificarVigencia();
      _programarMedianoche();
    }
  }

  void _alCambiarLectura() {
    final termino = _capturando && !widget.lectura.actualizando;
    _capturando = widget.lectura.actualizando;
    if (termino && widget.activa) _verificarVigencia();
  }

  Future<void> _cargar() {
    if (_carga case final pendiente?) return pendiente;
    final carga = Future<void>.microtask(() async {
      await (_historial.cargar(), _cargarResumen()).wait;
    }).whenComplete(() => _carga = null);
    _carga = carga;
    return carga;
  }

  Future<void> _cargarResumen({bool reintentar = true}) async {
    if (!mounted) return;
    setState(() => _cargandoResumen = true);
    try {
      final ahora = _historial.ahora;
      final usos = await _db.obtenerUsoEntre(
        DateTime(ahora.year, ahora.month, ahora.day - 14),
        DateTime(ahora.year, ahora.month, ahora.day - 1),
      );
      if (!mounted) return;
      final evolucion = EvolucionSemanal.calcular(
        usos: usos,
        ahora: ahora,
        primeraRecomendacion: await _db.primeraFechaRecomendacion(),
      );
      if (!mounted) return;
      if (!DateUtils.isSameDay(ahora, _historial.ahora)) {
        if (reintentar) await _cargarResumen(reintentar: false);
        return;
      }
      setState(() {
        _evolucion = evolucion;
        _errorHistorial = false;
      });
    } catch (_) {
      if (mounted) setState(() => _errorHistorial = true);
    } finally {
      if (mounted) setState(() => _cargandoResumen = false);
    }
  }

  Future<void> _valorar(Recomendacion r, String? valoracion) async {
    if (r.id == null) return;
    try {
      await _historial.actualizarRecomendacion(r, valoracion: valoracion);
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
    setState(() => _cargandoResumen = true);
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
      if (mounted) setState(() => _cargandoResumen = false);
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
        listenable: _historial,
        builder: (context, _) => _buildTips(context),
      );

  Widget _buildTips(BuildContext context) {
    final grupos = _historial.grupos.entries.toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_historial.viendoArchivo
            ? 'Archivo de recomendaciones'
            : 'Recomendaciones'),
        actions: [
          ListenableBuilder(
              listenable: widget.lectura,
              builder: (_, __) => IconButton(
                    icon: const Icon(Icons.auto_awesome),
                    onPressed: _generando || widget.lectura.actualizando
                        ? null
                        : _generarRecomendaciones,
                    tooltip: 'Generar recomendaciones',
                  )),
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
        child: CustomScrollView(
          key: const PageStorageKey('tips-desplazamiento'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
                child: Column(
              children: [
                _cabeceraTips(context),
                ListenableBuilder(
                    listenable: widget.lectura,
                    builder: (context, _) => Column(
                          children: [
                            if (widget.lectura.estado !=
                                EstadoLecturaUso.disponible)
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: EtiquetaLecturaUso(widget.lectura),
                              ),
                            if (widget.lectura.estado ==
                                EstadoLecturaUso.sinPermiso)
                              TextButton(
                                onPressed: widget.lectura.actualizar,
                                child: const Text('Abrir acceso al uso'),
                              ),
                            if (widget.lectura.comparacion?.motivo ==
                                    MotivoComparacion.sinDatos &&
                                widget.lectura.comparacion?.minutosHoy != null)
                              const Text(
                                  'Datos insuficientes para comparar con ayer.'),
                            if (_cargando)
                              const LinearProgressIndicator(
                                  semanticsLabel: 'Cargando recomendaciones'),
                            if (_evolucion != null)
                              TarjetaEvolucionTips(
                                evolucion: _evolucion!,
                                comparacion: widget.lectura.comparacion,
                              ),
                          ],
                        )),
                _controlesHistorial(),
                if (_historial.errorPreferencias)
                  const Text('No se pudo recuperar el filtro de fechas.'),
                if (_errorHistorial || _historial.error)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextButton(
                        onPressed: _cargar,
                        child: const Text(
                            'No se pudo cargar el historial. Reintentar')),
                  )
                else if (!_cargando && _recomendaciones.isEmpty) ...[
                  Icon(Icons.lightbulb_outline,
                      size: 64, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  Text(_historial.viendoArchivo
                      ? 'No hay recomendaciones archivadas'
                      : 'No hay recomendaciones aún'),
                  if (!_historial.viendoArchivo)
                    FilledButton.icon(
                      onPressed: _generando || widget.lectura.actualizando
                          ? null
                          : _generarRecomendaciones,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Generar ahora'),
                    ),
                ],
                if (!_cargando && _recomendaciones.isNotEmpty && grupos.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'No hay recomendaciones para las fechas seleccionadas')),
              ],
            )),
            for (final grupo in grupos) _grupoFecha(grupo, context),
            SliverToBoxAdapter(
                child: _historial.viendoArchivo && _historial.hayMas
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: OutlinedButton(
                            onPressed: _cargando ? null : _historial.cargarMas,
                            child: const Text('Cargar más')))
                    : const SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _grupoFecha(
      MapEntry<String, List<Recomendacion>> grupo, BuildContext ctx) {
    final scheme = Theme.of(ctx).colorScheme;
    final fecha = DateTime.parse(grupo.key);
    final clave = '${_historial.viendoArchivo}-${grupo.key}';
    final apertura = _fechasAbiertas.putIfAbsent(
        clave,
        () => ValueNotifier(
            grupo.key == HistorialTipsController.dia(_historial.ahora)));
    final compartida = _historial.fechaCompartida(grupo.key);
    return ValueListenableBuilder<bool>(
        key: ValueKey('apertura-$clave'),
        valueListenable: apertura,
        builder: (_, abierta, __) => SliverPadding(
              key: ValueKey('fecha-$clave'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: DecoratedSliver(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.6)),
                  boxShadow: [
                    BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.12),
                        blurRadius: 4,
                        offset: const Offset(0, 2))
                  ],
                ),
                sliver: SliverMainAxisGroup(slivers: [
                  SliverToBoxAdapter(
                      child: Semantics(
                    expanded: abierta,
                    child: Material(
                        color: Colors.transparent,
                        child: ListTile(
                          onTap: () => apertura.value = !abierta,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                          minTileHeight: 104,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          leading: ExcludeSemantics(
                              child: Container(
                                  width: 52,
                                  height: 56,
                                  decoration: BoxDecoration(
                                      color: scheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(14)),
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.calendar_today_outlined,
                                            size: 16,
                                            color: scheme.onPrimaryContainer),
                                        Flexible(
                                            child: FittedBox(
                                                child: Text('${fecha.day}',
                                                    style: TextStyle(
                                                        fontSize: 22,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: scheme
                                                            .onPrimaryContainer)))),
                                      ]))),
                          title: Text(_etiquetaDia(grupo.key),
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface)),
                          subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${grupo.value.length} recomendaciones mostradas',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant)),
                                    ValueListenableBuilder<int>(
                                        valueListenable:
                                            _historial.sinLeer(grupo.key),
                                        builder: (_, sinLeer, __) => sinLeer ==
                                                0
                                            ? const SizedBox.shrink()
                                            : Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 4),
                                                child: Text('$sinLeer sin leer',
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color: scheme.primary,
                                                        fontWeight:
                                                            FontWeight.w600)))),
                                  ])),
                          trailing: AnimatedRotation(
                              turns: abierta ? 0.5 : 0,
                              duration: MediaQuery.disableAnimationsOf(ctx)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 200),
                              child: Icon(Icons.expand_more,
                                  color: abierta
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant)),
                        )),
                  )),
                  if (abierta) ...[
                    if (compartida)
                      SliverToBoxAdapter(
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(_historial.viendoArchivo
                                  ? 'También hay recomendaciones de esta fecha en recientes.'
                                  : 'Más recomendaciones de esta fecha en el archivo.'))),
                    SliverPadding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                        sliver: SliverList.builder(
                          itemCount: grupo.value.length,
                          findChildIndexCallback: (key) {
                            final indice = grupo.value.indexWhere(
                                (r) => ValueKey('tip-${r.id}') == key);
                            return indice < 0 ? null : indice;
                          },
                          itemBuilder: (_, indice) =>
                              _tarjetaRecomendacion(grupo.value[indice], ctx),
                        )),
                  ],
                ]),
              ),
            ));
  }

  Widget _cabeceraTips(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primaryContainer,
              Color.alphaBlend(
                  scheme.onPrimaryContainer.withValues(alpha: 0.06),
                  scheme.primaryContainer),
            ]),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ExcludeSemantics(
              child: Icon(
                  _historial.viendoArchivo
                      ? Icons.inventory_2_outlined
                      : Icons.lightbulb_outline_rounded,
                  color: scheme.onPrimaryContainer,
                  size: 24)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
                  _historial.viendoArchivo ? 'TU ARCHIVO' : 'IDEAS PARA TU DÍA',
                  style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer))),
        ]),
        const SizedBox(height: 14),
        Text(
            _historial.viendoArchivo
                ? 'Consejos que puedes\nvolver a consultar.'
                : 'Tu bienestar,\ndía a día.',
            style: TextStyle(
                fontSize: 28,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: scheme.onPrimaryContainer,
                letterSpacing: -0.6)),
        const SizedBox(height: 12),
        Text(
            _historial.viendoArchivo
                ? 'Tu historial sigue aquí, organizado por fecha.'
                : 'Explora tus recomendaciones y valora lo que te ayuda.',
            style: TextStyle(
                fontSize: 14, height: 1.45, color: scheme.onPrimaryContainer)),
      ]),
    );
  }

  Future<void> _marcarLeida(Recomendacion r) async {
    if (r.id == null) return;
    try {
      await _historial.actualizarRecomendacion(r, leer: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo marcar como leída.')));
      }
    }
  }

  Widget _tarjetaRecomendacion(Recomendacion r, BuildContext ctx) =>
      ValueListenableBuilder<Recomendacion>(
        key: ValueKey('tip-${r.id}'),
        valueListenable: _historial.tarjeta(r),
        builder: (_, actual, __) => _contenidoTarjeta(actual, ctx),
      );

  Widget _contenidoTarjeta(Recomendacion r, BuildContext ctx) {
    final scheme = Theme.of(ctx).colorScheme;
    final acento = _colorSeveridad(r.severidad, ctx);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      elevation: 0,
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: r.leida
                  ? scheme.outlineVariant
                  : acento.withValues(alpha: 0.45))),
      child: InkWell(
        onTap: () => _marcarLeida(r),
        child: Container(
          decoration: BoxDecoration(
              border: Border(left: BorderSide(color: acento, width: 4))),
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ExcludeSemantics(
                  child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: _colorTipo(r.tipo, ctx).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(_iconoTipo(r.tipo),
                    color: _colorTipo(r.tipo, ctx), size: 22),
              )),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        r.severidad == 'critica'
                            ? 'Atención prioritaria'
                            : r.severidad == 'advertencia'
                                ? 'Para tener en cuenta'
                                : r.severidad == 'sugerencia'
                                    ? 'Una idea para ti'
                                    : 'Tu consejo',
                        style: TextStyle(
                            fontSize: 12,
                            color: acento,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(_formatoHora.format(r.fecha.toLocal()),
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ])),
              if (!r.leida)
                Tooltip(
                    excludeFromSemantics: true,
                    message: 'Recomendación sin leer',
                    child: Icon(Icons.circle,
                        size: 10,
                        color: scheme.primary,
                        semanticLabel: 'Sin leer')),
            ]),
            const SizedBox(height: 14),
            Text(r.titulo,
                style: TextStyle(
                    fontSize: 17,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface)),
            const SizedBox(height: 8),
            Text(r.mensaje,
                style: TextStyle(
                    fontSize: 14, height: 1.5, color: scheme.onSurfaceVariant)),
            if (r.motivo != null && r.motivo!.isNotEmpty)
              Theme(
                  data:
                      Theme.of(ctx).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    key: PageStorageKey('tips-motivo-${r.id}'),
                    expansionAnimationStyle: MediaQuery.disableAnimationsOf(ctx)
                        ? AnimationStyle.noAnimation
                        : null,
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 12),
                    title: Text('Por qué este consejo',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary)),
                    children: [
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Text(r.motivo!,
                              style: TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                  color: scheme.onSurfaceVariant)))
                    ],
                  )),
            const SizedBox(height: 8),
            Divider(
                height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
            BotonesValoracion(
                valoracion: r.valoracion, onCambio: (v) => _valorar(r, v)),
          ]),
        ),
      ),
    );
  }

  String _etiquetaDia(String fecha) {
    final hoy = _historial.ahora;
    if (fecha == HistorialTipsController.dia(hoy)) return 'Hoy';
    if (fecha ==
        HistorialTipsController.dia(
            DateTime(hoy.year, hoy.month, hoy.day - 1))) {
      return 'Ayer';
    }
    return _formatoFecha.format(DateTime.parse(fecha));
  }

  Widget _controlesHistorial() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            _historial.viendoArchivo
                ? 'Historial archivado'
                : 'Tus recomendaciones',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface)),
        const SizedBox(height: 4),
        Text(
            _historial.viendoArchivo
                ? 'Consulta tus consejos anteriores.'
                : 'Hasta 50 recientes · agrupadas por fecha',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(
            onPressed: _cargando
                ? null
                : () => _historial.mostrarArchivo(!_historial.viendoArchivo),
            icon: Icon(
                _historial.viendoArchivo
                    ? Icons.arrow_back
                    : Icons.archive_outlined,
                size: 20),
            label: Text(_historial.viendoArchivo
                ? 'Volver a recientes'
                : 'Ver archivo'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          ),
          if (!_historial.viendoArchivo) ...[
            OutlinedButton.icon(
              onPressed:
                  _cargando || _historial.guardando ? null : _fechasVisibles,
              icon: const Icon(Icons.tune_rounded, size: 20),
              label: const Text('Fechas visibles'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            ),
            if (_historial.ocultas.isNotEmpty)
              TextButton(
                  onPressed:
                      _historial.guardando ? null : () => _guardarFechas({}),
                  child: const Text('Restaurar todas las fechas')),
          ],
        ]),
      ]),
    );
  }

  Future<void> _guardarFechas(Set<String> fechas) async {
    try {
      await _historial.guardarOcultas(fechas);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo guardar el filtro de fechas.')));
      }
    }
  }

  Future<void> _fechasVisibles() async {
    final ocultas = Set<String>.of(_historial.ocultas);
    final fechas = _historial.recientes
        .map((r) => HistorialTipsController.dia(r.fecha))
        .toSet()
        .toList();
    final seleccion = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, cambiar) => AlertDialog(
                title: const Text('Fechas visibles'),
                content: SizedBox(
                    width: double.maxFinite,
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final fecha in fechas)
                          CheckboxListTile(
                              title: Text(_etiquetaDia(fecha)),
                              value: !ocultas.contains(fecha),
                              onChanged: (visible) => cambiar(() {
                                    if (visible == true) {
                                      ocultas.remove(fecha);
                                    } else {
                                      ocultas.add(fecha);
                                    }
                                  })),
                      ],
                    )),
                actions: [
                  TextButton(
                      onPressed: () => cambiar(ocultas.clear),
                      child: const Text('Restablecer')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, ocultas),
                      child: const Text('Guardar')),
                ],
              )),
    );
    if (mounted && seleccion != null) await _guardarFechas(seleccion);
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
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ExcludeSemantics(
                child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(_icono,
                        size: 20, color: scheme.onSecondaryContainer))),
            const SizedBox(width: 10),
            Expanded(
                child: Text('Tu evolución',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface))),
          ]),
          const SizedBox(height: 12),
          Text(_usarDiaria ? comparacion!.mensajeTips : evolucion.mensajeTips,
              style: TextStyle(
                  fontSize: 14, height: 1.45, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          Text(_usarDiaria ? comparacion!.accionTips : evolucion.accionTips,
              style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary)),
        ]),
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
          minimumSize: const Size(0, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return Wrap(
      children: [
        boton('Útil', 'util', Icons.thumb_up_alt_outlined),
        boton('No me sirvió', 'no_util', Icons.thumb_down_alt_outlined),
      ],
    );
  }
}
