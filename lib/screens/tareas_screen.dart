import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/tarea.dart';
import '../database/database_helper.dart';
import '../services/notificacion_service.dart';

class TareasScreen extends StatefulWidget {
  const TareasScreen({super.key});

  @override
  State<TareasScreen> createState() => _TareasScreenState();
}

class _TareasScreenState extends State<TareasScreen> {
  final _db = DatabaseHelper.instance;
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
    setState(() => _cargando = true);
    bool? completada;
    if (_filtro == 'pendientes') completada = false;
    if (_filtro == 'completadas') completada = true;
    final tareas = await _db.obtenerTareas(completada: completada);
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
                  decoration: const InputDecoration(labelText: 'Título *'),
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
                    final fecha = await showDatePicker(
                      context: ctx,
                      initialDate: fechaVencimiento ?? DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (fecha != null && ctx.mounted) {
                      final hora = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(fechaVencimiento ?? DateTime.now().add(const Duration(hours: 1))),
                      );
                      setLocal(() {
                        fechaVencimiento = DateTime(
                          fecha.year, fecha.month, fecha.day,
                          hora?.hour ?? 9, hora?.minute ?? 0,
                        );
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        );
      }),
    );

    if (result == true && tituloCtrl.text.isNotEmpty) {
      final nuevaTarea = Tarea(
        id: tarea?.id,
        titulo: tituloCtrl.text,
        descripcion: descCtrl.text.isEmpty ? null : descCtrl.text,
        fechaCreacion: tarea?.fechaCreacion ?? DateTime.now(),
        fechaVencimiento: fechaVencimiento,
        completada: tarea?.completada ?? false,
        prioridad: prioridad,
      );

      if (tarea == null) {
        final id = await _db.insertarTarea(nuevaTarea);
        final tareaConId = nuevaTarea.copyWith(id: id);
        await _notif.programarNotificacionTarea(tareaConId);
      } else {
        await _db.actualizarTarea(nuevaTarea);
        if (nuevaTarea.id != null) {
          await _notif.cancelarNotificacion(nuevaTarea.id!);
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
      await _notif.cancelarNotificacion(tarea.id!);
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar == true) {
      await _db.eliminarTarea(tarea.id!);
      await _notif.cancelarNotificacion(tarea.id!);
      await _cargarTareas();
    }
  }

  Color _colorPrioridad(String p) {
    switch (p) {
      case 'alta': return Colors.red;
      case 'media': return Colors.orange;
      case 'baja': return Colors.green;
      default: return Colors.grey;
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
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
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
                                    color: _colorPrioridad(t.prioridad).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(t.prioridad,
                                      style: TextStyle(fontSize: 10, color: _colorPrioridad(t.prioridad))),
                                ),
                                if (t.fechaVencimiento != null) ...[
                                  const SizedBox(width: 8),
                                  Icon(Icons.schedule, size: 12, color: Colors.grey[600]),
                                  const SizedBox(width: 2),
                                  Text(DateFormat('dd/MM HH:mm').format(t.fechaVencimiento!),
                                      style: const TextStyle(fontSize: 11)),
                                ],
                              ],
                            ),
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
