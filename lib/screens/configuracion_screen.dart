import 'package:flutter/material.dart';
import '../models/horario.dart';
import '../models/perfil.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../database/database_helper.dart';

/// Configuración de horarios.
///
/// Arriba se mantienen los dos accesos rápidos (laboral / académico) y debajo
/// la lista completa de horarios, que pueden ser varios, de cualquier categoría,
/// configurados de lunes a domingo dentro de las 24 horas y activables o
/// desactivables individualmente.
class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  /// Límite prudente: cada horario añade ventanas al análisis de uso.
  static const int maxHorarios = 20;

  final _db = DatabaseHelper.instance;

  List<Horario> _horarios = [];
  Perfil? _perfil;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarHorarios();
  }

  Future<void> _cargarHorarios() async {
    setState(() => _cargando = true);
    final horarios = await _db.obtenerHorarios();
    final perfil = await _db.obtenerPerfil();
    if (!mounted) return;
    setState(() {
      _horarios = horarios;
      _perfil = perfil;
      _cargando = false;
    });
  }

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  /// Primer horario de una categoría (para los accesos rápidos).
  Horario? _primeroDeTipo(String tipo) {
    for (final horario in _horarios) {
      if (horario.tipo == tipo) return horario;
    }
    return null;
  }

  Future<void> _abrirEditor({Horario? horario, String? categoriaInicial}) async {
    if (horario == null && _horarios.length >= maxHorarios) {
      _avisar('Has alcanzado el máximo de $maxHorarios horarios');
      return;
    }

    final resultado = await _mostrarDialogoHorario(
      horario: horario,
      categoriaInicial: categoriaInicial,
    );
    if (resultado == null) return;

    await _db.guardarHorario(resultado);
    await _cargarHorarios();
    _avisar('✓ Horario "${resultado.nombreVisible}" guardado');
  }

  Future<void> _alternarActivo(Horario horario, bool activo) async {
    final id = horario.id;
    if (id == null) return;
    await _db.cambiarActivoHorario(id, activo);
    await _cargarHorarios();
    _avisar(activo
        ? '✓ "${horario.nombreVisible}" activado'
        : '"${horario.nombreVisible}" desactivado (no se usará en el análisis)');
  }

  Future<void> _eliminar(Horario horario) async {
    final id = horario.id;
    if (id == null) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar horario'),
        content: Text('¿Eliminar "${horario.nombreVisible}" '
            '(${horario.rangoTexto})?\n\nSi solo quieres pausarlo, '
            'desactívalo con el interruptor.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await _db.eliminarHorario(id);
      await _cargarHorarios();
      _avisar('Horario eliminado');
    }
  }

  // ---------------------------------------------------------------------------
  // Diálogo de creación / edición
  // ---------------------------------------------------------------------------

  Future<Horario?> _mostrarDialogoHorario({
    Horario? horario,
    String? categoriaInicial,
  }) async {
    final nombreCtrl = TextEditingController(text: horario?.nombre ?? '');
    var categoria = horario?.tipo ?? categoriaInicial ?? Horario.tipoPersonalizado;
    var horaInicio = horario?.horaInicio ?? 8;
    var minutoInicio = horario?.minutoInicio ?? 0;
    var horaFin = horario?.horaFin ?? 9;
    var minutoFin = horario?.minutoFin ?? 0;
    final dias = <int>{...(horario?.diasSemana ?? const [1, 2, 3, 4, 5])};
    String? error;

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final cruzaMedianoche = Horario(
            tipo: categoria,
            horaInicio: horaInicio,
            minutoInicio: minutoInicio,
            horaFin: horaFin,
            minutoFin: minutoFin,
          ).cruzaMedianoche;
          final sinDuracion =
              horaInicio == horaFin && minutoInicio == minutoFin;

          return AlertDialog(
            title: Text(horario == null ? 'Nuevo horario' : 'Editar horario'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nombreCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nombre (opcional)',
                      hintText: 'Ej: Turno noche, Gimnasio…',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Categoría
                  DropdownButtonFormField<String>(
                    initialValue: categoria,
                    decoration: const InputDecoration(labelText: 'Categoría'),
                    items: const [
                      DropdownMenuItem(
                        value: Horario.tipoLaboral,
                        child: Text('Laboral'),
                      ),
                      DropdownMenuItem(
                        value: Horario.tipoAcademico,
                        child: Text('Académico'),
                      ),
                      DropdownMenuItem(
                        value: Horario.tipoPersonalizado,
                        child: Text('Personalizado'),
                      ),
                    ],
                    onChanged: (valor) =>
                        setLocal(() => categoria = valor ?? categoria),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    categoria == Horario.tipoPersonalizado
                        ? 'Los horarios personalizados cuentan como contexto, '
                            'pero no activan las reglas de trabajo o estudio.'
                        : 'Esta categoría activa las reglas de '
                            '${categoria == Horario.tipoLaboral ? 'trabajo' : 'estudio'}.',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),

                  // Horas
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hora de inicio'),
                    trailing: Text(
                      _formatoHora(horaInicio, minutoInicio),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    onTap: () async {
                      final hora = await showTimePicker(
                        context: ctx,
                        initialTime:
                            TimeOfDay(hour: horaInicio, minute: minutoInicio),
                      );
                      if (hora != null) {
                        setLocal(() {
                          horaInicio = hora.hour;
                          minutoInicio = hora.minute;
                        });
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hora de fin'),
                    trailing: Text(
                      _formatoHora(horaFin, minutoFin),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    onTap: () async {
                      final hora = await showTimePicker(
                        context: ctx,
                        initialTime:
                            TimeOfDay(hour: horaFin, minute: minutoFin),
                      );
                      if (hora != null) {
                        setLocal(() {
                          horaFin = hora.hour;
                          minutoFin = hora.minute;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sinDuracion
                        ? '⚠️ La hora de inicio y la de fin no pueden ser iguales'
                        : cruzaMedianoche
                            ? 'Rango: ${_formatoHora(horaInicio, minutoInicio)} - '
                                '${_formatoHora(horaFin, minutoFin)} · '
                                'cruza la medianoche (termina al día siguiente)'
                            : 'Rango: ${_formatoHora(horaInicio, minutoInicio)} - '
                                '${_formatoHora(horaFin, minutoFin)}',
                    style: TextStyle(
                      color: sinDuracion
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                      fontSize: sinDuracion ? 12 : 13,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Días
                  const Text('Días',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var dia = 1; dia <= 7; dia++)
                        FilterChip(
                          label: Text(Horario.abreviaturasDias[dia - 1]),
                          selected: dias.contains(dia),
                          onSelected: (sel) => setLocal(() {
                            if (sel) {
                              dias.add(dia);
                            } else {
                              dias.remove(dia);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () =>
                            setLocal(() => dias..clear()..addAll([1, 2, 3, 4, 5])),
                        child: const Text('L-V'),
                      ),
                      TextButton(
                        onPressed: () => setLocal(() => dias..clear()..addAll([6, 7])),
                        child: const Text('S-D'),
                      ),
                      TextButton(
                        onPressed: () => setLocal(
                            () => dias..clear()..addAll([1, 2, 3, 4, 5, 6, 7])),
                        child: const Text('Todos'),
                      ),
                    ],
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final problema = _validar(
                    dias: dias,
                    sinDuracion: sinDuracion,
                  );
                  if (problema != null) {
                    setLocal(() => error = problema);
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );

    if (guardar != true) return null;
    final nombre = nombreCtrl.text.trim();
    return Horario(
      id: horario?.id,
      tipo: categoria,
      nombre: nombre.isEmpty ? null : nombre,
      horaInicio: horaInicio,
      minutoInicio: minutoInicio,
      horaFin: horaFin,
      minutoFin: minutoFin,
      diasSemana: (dias.toList()..sort()),
      activo: horario?.activo ?? true,
    );
  }

  String? _validar({
    required Set<int> dias,
    required bool sinDuracion,
  }) {
    if (dias.isEmpty) return 'Selecciona al menos un día';
    if (sinDuracion) {
      return 'La hora de inicio y la de fin no pueden ser iguales';
    }
    return null;
  }

  String _formatoHora(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------------------
  // Interfaz
  // ---------------------------------------------------------------------------

  IconData _icono(String tipo) {
    switch (tipo) {
      case Horario.tipoLaboral:
        return Icons.work;
      case Horario.tipoAcademico:
        return Icons.school;
      default:
        return Icons.schedule;
    }
  }

  Color _color(String tipo, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (tipo) {
      case Horario.tipoLaboral:
        return scheme.primary;
      case Horario.tipoAcademico:
        return scheme.tertiary;
      default:
        return scheme.secondary;
    }
  }

  Future<void> _abrirPerfil() async {
    final resultado = await showDialog<Perfil>(
      context: context,
      builder: (_) => const PerfilDialog(),
    );
    if (resultado != null && mounted) setState(() => _perfil = resultado);
    await AparienciaController.instance.recargarSugerencia();
  }

  Widget _buildAparienciaCard(BuildContext context) {
    final controller = AparienciaController.instance;
    final ap = controller.value;
    final clara = AppTheme.of(ap.clara).colorScheme;
    final oscura = AppTheme.of(ap.oscura).colorScheme;

    Widget swatch(String etiqueta, ColorScheme scheme) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _punto(scheme.primary),
                    const SizedBox(width: 4),
                    _punto(scheme.secondary),
                    const SizedBox(width: 4),
                    _punto(scheme.tertiary),
                  ],
                ),
                const SizedBox(height: 6),
                Text(etiqueta,
                    style: TextStyle(fontSize: 10, color: scheme.onSurface)),
              ],
            ),
          ),
        );

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Apariencia',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Modo',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6))),
            const SizedBox(height: 4),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('Claro')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Oscuro')),
                ButtonSegment(value: ThemeMode.system, label: Text('Sistema')),
              ],
              selected: {ap.modo},
              showSelectedIcon: false,
              onSelectionChanged: (seleccion) =>
                  controller.setModo(seleccion.first),
            ),
            const SizedBox(height: 12),
            Text('Paleta',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6))),
            const SizedBox(height: 4),
            SegmentedButton<FamiliaPaleta>(
              segments: const [
                ButtonSegment(value: FamiliaPaleta.cool, label: Text('Fríos')),
                ButtonSegment(value: FamiliaPaleta.warm, label: Text('Cálidos')),
                ButtonSegment(value: FamiliaPaleta.rgb, label: Text('RGB')),
              ],
              selected: {ap.familia},
              showSelectedIcon: false,
              onSelectionChanged: (seleccion) =>
                  controller.setFamilia(seleccion.first),
            ),
            const SizedBox(height: 12),
            Text('Vista previa',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6))),
            const SizedBox(height: 4),
            Row(
              children: [
                swatch('Claro', clara),
                const SizedBox(width: 8),
                swatch('Oscuro', oscura),
              ],
            ),
            if (ap.manual == null) ...[
              const SizedBox(height: 6),
              Text(
                'Paleta sugerida por tu perfil: ${_familiaTexto(ap.sugerida)}. '
                'Puedes cambiarla cuando quieras.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _punto(Color color) => Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  String _familiaTexto(FamiliaPaleta familia) => switch (familia) {
        FamiliaPaleta.cool => 'Fríos',
        FamiliaPaleta.warm => 'Cálidos',
        FamiliaPaleta.rgb => 'RGB',
      };

  Widget _buildPerfilCard() {
    final perfil = _perfil;
    final partes = <String>[
      if (perfil != null && perfil.tieneNombre) perfil.nombreVisible,
      if (perfil?.identidadVisible != null) perfil!.identidadVisible!,
    ];
    return Card(
      elevation: 2,
      child: ListTile(
        leading: const Icon(Icons.person_outline),
        title: const Text('Perfil',
            style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(partes.isEmpty ? 'Sin configurar' : partes.join(' · ')),
        trailing: TextButton(onPressed: _abrirPerfil, child: const Text('Editar')),
        onTap: _abrirPerfil,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      floatingActionButton: _cargando
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _abrirEditor(),
              icon: const Icon(Icons.add_alarm),
              label: const Text('Agregar horario'),
            ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _buildPerfilCard(),
                const SizedBox(height: 12),
                AnimatedBuilder(
                  animation: AparienciaController.instance,
                  builder: (_, __) => _buildAparienciaCard(context),
                ),
                const SizedBox(height: 24),
                const Text('Horarios',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Configura los horarios en los que quieres que la app detecte '
                  'tu uso del teléfono. Puedes tener varios, de lunes a domingo, '
                  'y activarlos o desactivarlos cuando quieras.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),

                // --- Accesos rápidos a los horarios preestablecidos ---
                _buildTarjetaHorario(
                  icono: Icons.work,
                  color: Theme.of(context).colorScheme.primary,
                  titulo: 'Horario laboral',
                  horario: _primeroDeTipo(Horario.tipoLaboral),
                  onTap: () => _abrirEditor(
                    horario: _primeroDeTipo(Horario.tipoLaboral),
                    categoriaInicial: Horario.tipoLaboral,
                  ),
                ),
                const SizedBox(height: 12),
                _buildTarjetaHorario(
                  icono: Icons.school,
                  color: Theme.of(context).colorScheme.tertiary,
                  titulo: 'Horario académico',
                  horario: _primeroDeTipo(Horario.tipoAcademico),
                  onTap: () => _abrirEditor(
                    horario: _primeroDeTipo(Horario.tipoAcademico),
                    categoriaInicial: Horario.tipoAcademico,
                  ),
                ),

                const SizedBox(height: 28),

                // --- Todos los horarios ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Todos los horarios',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('${_horarios.length}/$maxHorarios',
                        style: const TextStyle(color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 8),

                if (_horarios.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Aún no hay horarios. Usa "Agregar horario".'),
                    ),
                  )
                else
                  ..._horarios.map((h) => _buildItemHorario(h, context)),

                const SizedBox(height: 24),
                const Card(
                  color: Colors.amber,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.black87),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Los horarios activos se usan para saber si tu uso del '
                            'teléfono (y tus picos de uso) ocurren en horas de '
                            'trabajo, estudio u otras que definas, y darte '
                            'sugerencias. Los desactivados se conservan pero no '
                            'se tienen en cuenta.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTarjetaHorario({
    required IconData icono,
    required Color color,
    required String titulo,
    required Horario? horario,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icono, color: color),
        ),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          horario == null
              ? 'Sin configurar — toca para agregar'
              : '${horario.rangoTexto} · ${horario.diasTexto}'
                  '${horario.activo ? '' : ' · desactivado'}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _buildItemHorario(Horario horario, BuildContext context) {
    final color = _color(horario.tipo, context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: horario.activo ? 0.15 : 0.06),
          child: Icon(
            _icono(horario.tipo),
            color: horario.activo ? color : Colors.grey,
          ),
        ),
        title: Text(
          horario.nombreVisible,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: horario.activo ? null : Colors.grey,
          ),
        ),
        subtitle: Text(
          '${horario.tipoTexto} · ${horario.rangoTexto} · ${horario.diasTexto}'
          '${horario.cruzaMedianoche ? ' (cruza medianoche)' : ''}',
          style: TextStyle(
            fontSize: 12,
            color: horario.activo ? null : Colors.grey,
          ),
        ),
        onTap: () => _abrirEditor(horario: horario),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: horario.activo,
              onChanged: (valor) => _alternarActivo(horario, valor),
            ),
            PopupMenuButton<String>(
              onSelected: (valor) {
                if (valor == 'editar') _abrirEditor(horario: horario);
                if (valor == 'eliminar') _eliminar(horario);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'editar', child: Text('Editar')),
                PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo de perfil local. Todos los campos son opcionales y nada se envía
/// fuera del dispositivo.
class PerfilDialog extends StatefulWidget {
  const PerfilDialog({super.key, this.perfilInicial, this.alGuardar});

  /// Permite precargar sin consultar la base (pruebas de widget).
  final Perfil? perfilInicial;

  /// Sustituye la persistencia (pruebas de widget).
  final Future<void> Function(Perfil perfil)? alGuardar;

  @override
  State<PerfilDialog> createState() => _PerfilDialogState();
}

class _PerfilDialogState extends State<PerfilDialog> {
  final _nombre = TextEditingController();
  final _descripcion = TextEditingController();
  String? _identidad;
  bool _cargando = true;
  bool _guardando = false;
  String? _errorGuardado;

  @override
  void initState() {
    super.initState();
    final inicial = widget.perfilInicial;
    if (inicial != null) {
      _nombre.text = inicial.nombre ?? '';
      _identidad = inicial.identidadGenero;
      _descripcion.text = inicial.autodescripcion ?? '';
      _cargando = false;
    } else {
      _cargar();
    }
  }

  Future<void> _cargar() async {
    try {
      final perfil = await DatabaseHelper.instance.obtenerPerfil();
      if (!mounted) return;
      if (perfil != null) {
        _nombre.text = perfil.nombre ?? '';
        _identidad = perfil.identidadGenero;
        _descripcion.text = perfil.autodescripcion ?? '';
      }
    } catch (e) {
      debugPrint('Perfil no disponible: $e');
    }
    if (mounted) setState(() => _cargando = false);
  }

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    setState(() {
      _guardando = true;
      _errorGuardado = null;
    });
    final nombre = _nombre.text.trim();
    final descripcion = _descripcion.text.trim();
    final perfil = Perfil(
      nombre: nombre.isEmpty ? null : nombre,
      identidadGenero: _identidad,
      autodescripcion: _identidad == Perfil.otra && descripcion.isNotEmpty
          ? descripcion
          : null,
    );
    try {
      final guardar = widget.alGuardar;
      if (guardar != null) {
        await guardar(perfil);
      } else {
        await DatabaseHelper.instance.guardarPerfil(perfil);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _errorGuardado = 'No se pudo guardar el perfil. Intenta de nuevo.';
      });
      return;
    }
    if (mounted) Navigator.pop(context, perfil);
  }

  String _etiqueta(String valor) {
    switch (valor) {
      case Perfil.masculino:
        return 'Masculino';
      case Perfil.femenino:
        return 'Femenino';
      case Perfil.noBinario:
        return 'No binario';
      case Perfil.otra:
        return 'Otra identidad';
      default:
        return 'Prefiero no responder';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Configura tu perfil'),
      content: _cargando
          ? const SizedBox(
              height: 80, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nombre,
                    maxLength: 30,
                    decoration: const InputDecoration(
                      labelText: 'Nombre o apodo (opcional)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Identidad de género (opcional)',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final valor in Perfil.identidades)
                        ChoiceChip(
                          label: Text(_etiqueta(valor),
                              style: const TextStyle(fontSize: 12)),
                          selected: _identidad == valor,
                          onSelected: (_) => setState(() {
                            _identidad = _identidad == valor ? null : valor;
                            if (_identidad != Perfil.otra) {
                              _descripcion.clear();
                            }
                          }),
                        ),
                    ],
                  ),
                  if (_identidad == Perfil.otra) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descripcion,
                      maxLength: 60,
                      decoration: const InputDecoration(
                        labelText: 'Describe tu identidad (opcional)',
                      ),
                    ),
                  ],
                  if (_identidad != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() {
                          _identidad = null;
                          _descripcion.clear();
                        }),
                        child: const Text('Eliminar respuesta'),
                      ),
                    ),
                  const SizedBox(height: 4),
                  const Text(
                    'Este dato se guarda solo en este dispositivo y no cambia '
                    'las recomendaciones ni las métricas.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
      actions: [
        if (_errorGuardado != null)
          Text(
            _errorGuardado!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _cargando || _guardando ? null : _guardar,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
