import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/tarea.dart';
import '../theme/app_theme.dart';
import '../database/database_helper.dart';
import '../services/notificacion_service.dart';

class TareasScreen extends StatefulWidget {
  const TareasScreen({super.key, this.database});

  final DatabaseHelper? database;

  @override
  State<TareasScreen> createState() => _TareasScreenState();
}

class _TareasScreenState extends State<TareasScreen> {
  late final _db = widget.database ?? DatabaseHelper.instance;
  final _notif = NotificacionService();
  List<Tarea> _tareas = [];
  bool _cargando = true;
  String _filtro = 'todas'; // 'todas', 'pendientes', 'completadas'

  @override
  void initState() {
    super.initState();
    _cargarTareas();
  }

  Future<void> _cargarTareas() async {
    if (!mounted) return;
    setState(() => _cargando = true);
    bool? completada;
    if (_filtro == 'pendientes') completada = false;
    if (_filtro == 'completadas') completada = true;
    final tareas = await _db.obtenerTareas(completada: completada);
    if (!mounted) return;
    setState(() {
      _tareas = tareas;
      _cargando = false;
    });
  }

  Future<void> _mostrarDialogoTarea({Tarea? tarea}) async {
    final tituloCtrl = TextEditingController(text: tarea?.titulo ?? '');
    final descCtrl = TextEditingController(text: tarea?.descripcion ?? '');
    String prioridad = tarea?.prioridad ?? 'media';
    DateTime? fechaVencimiento = tarea?.fechaVencimiento;
    DateTime? fechaPlanificada = tarea?.fechaPlanificada;
    TimeOfDay? horaInicio = _parseHora(tarea?.horaInicioPlanificada);
    TimeOfDay? horaFin = _parseHora(tarea?.horaFinPlanificada);
    String? errorPlanificacion;
    String? errorTitulo;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: Text(tarea == null ? 'Nueva tarea' : 'Editar tarea'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tituloCtrl,
                  decoration: InputDecoration(
                    labelText: 'Título *',
                    errorText: errorTitulo,
                  ),
                  onChanged: (texto) {
                    if (errorTitulo != null && texto.trim().isNotEmpty) {
                      setLocal(() => errorTitulo = null);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: prioridad,
                  decoration: const InputDecoration(labelText: 'Prioridad'),
                  items: const [
                    DropdownMenuItem(value: 'alta', child: Text('Alta')),
                    DropdownMenuItem(value: 'media', child: Text('Media')),
                    DropdownMenuItem(value: 'baja', child: Text('Baja')),
                  ],
                  onChanged: (v) => setLocal(() => prioridad = v!),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(fechaVencimiento == null
                      ? 'Sin fecha de vencimiento'
                      : 'Vence: ${DateFormat('dd/MM/yyyy HH:mm').format(fechaVencimiento!)}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final ahora = DateTime.now();
                    final hoy = DateUtils.dateOnly(ahora);
                    final limite = DateTime(hoy.year, hoy.month, hoy.day + 365);
                    final candidata = fechaVencimiento == null
                        ? DateTime(hoy.year, hoy.month, hoy.day + 1)
                        : DateUtils.dateOnly(fechaVencimiento!);
                    var inicial = candidata;
                    if (inicial.isBefore(hoy)) inicial = hoy;
                    if (inicial.isAfter(limite)) inicial = limite;
                    final fecha = await showDatePicker(
                      context: ctx,
                      initialDate: inicial,
                      firstDate: hoy,
                      lastDate: limite,
                    );
                    if (fecha != null && ctx.mounted) {
                      final hora = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(fechaVencimiento ?? ahora.add(const Duration(hours: 1))),
                      );
                      if (hora == null || !ctx.mounted) return;
                      setLocal(() {
                        fechaVencimiento = DateTime(
                          fecha.year, fecha.month, fecha.day,
                          hora.hour, hora.minute,
                        );
                      });
                    }
                  },
                ),
                const Divider(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Planificación (opcional)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(fechaPlanificada == null
                      ? 'Sin fecha planificada'
                      : 'Fecha: ${DateFormat('dd/MM/yyyy').format(fechaPlanificada!)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (fechaPlanificada != null)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: 'Quitar planificación',
                          onPressed: () => setLocal(() {
                            fechaPlanificada = null;
                            errorPlanificacion = null;
                          }),
                        ),
                      const Icon(Icons.event),
                    ],
                  ),
                  onTap: () async {
                    final fecha = await showDatePicker(
                      context: ctx,
                      initialDate: fechaPlanificada ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (fecha != null && ctx.mounted) {
                      setLocal(() {
                        fechaPlanificada =
                            DateTime(fecha.year, fecha.month, fecha.day);
                        errorPlanificacion = null;
                      });
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(horaInicio == null
                      ? 'Hora de inicio'
                      : 'Inicio: ${_formatearHora(horaInicio!)}'),
                  trailing: const Icon(Icons.schedule),
                  onTap: () async {
                    final hora = await showTimePicker(
                      context: ctx,
                      initialTime: horaInicio ?? const TimeOfDay(hour: 9, minute: 0),
                    );
                    if (hora != null && ctx.mounted) {
                      setLocal(() {
                        horaInicio = hora;
                        errorPlanificacion = null;
                      });
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(horaFin == null
                      ? 'Hora de fin'
                      : 'Fin: ${_formatearHora(horaFin!)}'),
                  trailing: const Icon(Icons.schedule_outlined),
                  onTap: () async {
                    final hora = await showTimePicker(
                      context: ctx,
                      initialTime: horaFin ?? const TimeOfDay(hour: 10, minute: 0),
                    );
                    if (hora != null && ctx.mounted) {
                      setLocal(() {
                        horaFin = hora;
                        errorPlanificacion = null;
                      });
                    }
                  },
                ),
                if (errorPlanificacion != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(errorPlanificacion!,
                          style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (tituloCtrl.text.trim().isEmpty) {
                  setLocal(() => errorTitulo = 'Ingresa un título.');
                  return;
                }
                final error = _validarPlanificacion(
                    fechaPlanificada, horaInicio, horaFin);
                if (error != null) {
                  setLocal(() => errorPlanificacion = error);
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      }),
    );

    if (result == true && mounted) {
      final nuevaTarea = Tarea(
        id: tarea?.id,
        titulo: tituloCtrl.text.trim(),
        descripcion: descCtrl.text.isEmpty ? null : descCtrl.text,
        fechaCreacion: tarea?.fechaCreacion ?? DateTime.now(),
        fechaVencimiento: fechaVencimiento,
        completada: tarea?.completada ?? false,
        prioridad: prioridad,
        fechaPlanificada: fechaPlanificada,
        horaInicioPlanificada:
            horaInicio == null ? null : _formatearHora(horaInicio!),
        horaFinPlanificada: horaFin == null ? null : _formatearHora(horaFin!),
      );

      if (tarea == null) {
        final id = await _db.insertarTarea(nuevaTarea);
        final tareaConId = nuevaTarea.copyWith(id: id);
        await _notif.programarNotificacionTarea(tareaConId);
      } else {
        await _db.actualizarTarea(nuevaTarea);
        if (nuevaTarea.id != null) {
          await _notif.cancelarNotificacionTarea(nuevaTarea.id!);
          await _notif.programarNotificacionTarea(nuevaTarea);
        }
      }
      await _cargarTareas();
    }
  }

  Future<void> _toggleCompletada(Tarea tarea) async {
    final actualizada = tarea.copyWith(completada: !tarea.completada);
    await _db.actualizarTarea(actualizada);
    if (actualizada.completada && tarea.id != null) {
      await _notif.cancelarNotificacionTarea(tarea.id!);
    } else if (!actualizada.completada && tarea.id != null) {
      await _notif.programarNotificacionTarea(actualizada);
    }
    await _cargarTareas();
  }

  Future<void> _eliminarTarea(Tarea tarea) async {
    if (tarea.id == null) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar tarea'),
        content: Text('¿Eliminar "${tarea.titulo}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar == true) {
      await _db.eliminarTarea(tarea.id!);
      await _notif.cancelarNotificacionTarea(tarea.id!);
      await _cargarTareas();
    }
  }

  /// Convierte 'HH:mm' a TimeOfDay, o null si falta o es inválido.
  static TimeOfDay? _parseHora(String? hhmm) {
    if (hhmm == null) return null;
    final partes = hhmm.split(':');
    if (partes.length != 2) return null;
    final h = int.tryParse(partes[0]);
    final m = int.tryParse(partes[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String _formatearHora(TimeOfDay hora) =>
      Tarea.formatearHora(hora.hour, hora.minute) ?? '';

  /// Valida la planificación temporal antes de guardar la tarea.
  /// Devuelve null si es válida; en caso contrario, el mensaje de error.
  static String? _validarPlanificacion(
      DateTime? fecha, TimeOfDay? inicio, TimeOfDay? fin) {
    if (fecha == null && (inicio != null || fin != null)) {
      return 'Selecciona una fecha planificada para el horario.';
    }
    if (inicio == null && fin == null) return null;
    if (inicio == null || fin == null) {
      return 'Define la hora de inicio y la hora de fin.';
    }
    if (!Tarea.rangoHorarioValido(_formatearHora(inicio), _formatearHora(fin))) {
      return 'La hora de inicio debe ser anterior a la hora de fin.';
    }
    return null;
  }

  Color _colorPrioridad(String p, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppTheme.colors(context);
    switch (p) {
      case 'alta':
        return scheme.error;
      case 'media':
        return colors.warning;
      case 'baja':
        return colors.success;
      default:
        return scheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tareas'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'todas', label: Text('Todas')),
                ButtonSegment(value: 'pendientes', label: Text('Pendientes')),
                ButtonSegment(value: 'completadas', label: Text('Hechas')),
              ],
              selected: {_filtro},
              onSelectionChanged: (s) {
                setState(() => _filtro = s.first);
                _cargarTareas();
              },
            ),
          ),
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _tareas.isEmpty
              ? const Center(child: Text('No hay tareas. ¡Crea la primera!'))
              : ListView.builder(
                  itemCount: _tareas.length,
                  itemBuilder: (ctx, i) {
                    final t = _tareas[i];
                    final scheme = Theme.of(context).colorScheme;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      color: t.completada
                          ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
                          : null,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        leading: Checkbox(
                          value: t.completada,
                          onChanged: (_) => _toggleCompletada(t),
                        ),
                        title: Text(
                          t.titulo,
                          style: TextStyle(
                            decoration: t.completada ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (t.descripcion != null && t.descripcion!.isNotEmpty)
                              Text(t.descripcion!),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _colorPrioridad(t.prioridad, context).withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(t.prioridad,
                                      style: TextStyle(fontSize: 10, color: _colorPrioridad(t.prioridad, context))),
                                ),
                                if (t.fechaVencimiento != null) ...[
                                  const SizedBox(width: 8),
                                  Icon(Icons.schedule, size: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
                                  const SizedBox(width: 2),
                                  Text(DateFormat('dd/MM HH:mm').format(t.fechaVencimiento!),
                                      style: const TextStyle(fontSize: 11)),
                                ],
                              ],
                            ),
                            if (t.fechaPlanificada != null) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(Icons.event_note,
                                      size: 12,
                                      color: scheme.onSurface
                                          .withValues(alpha: 0.5)),
                                  const SizedBox(width: 2),
                                  Text(
                                    t.tieneRangoHorario
                                        ? 'Plan: ${DateFormat('dd/MM').format(t.fechaPlanificada!)} · '
                                            '${t.horaInicioPlanificada}–${t.horaFinPlanificada}'
                                        : 'Plan: ${DateFormat('dd/MM').format(t.fechaPlanificada!)}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: scheme.onSurface
                                            .withValues(alpha: 0.7)),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        trailing: PopupMenuButton(
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'edit', child: Text('Editar')),
                            const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                          ],
                          onSelected: (v) {
                            if (v == 'edit') _mostrarDialogoTarea(tarea: t);
                            if (v == 'delete') _eliminarTarea(t);
                          },
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _mostrarDialogoTarea(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
