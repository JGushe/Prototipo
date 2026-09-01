import 'package:flutter/material.dart';
import '../models/horario.dart';
import '../database/database_helper.dart';

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  final _db = DatabaseHelper.instance;

  Horario? _horarioLaboral;
  Horario? _horarioAcademico;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarHorarios();
  }

  Future<void> _cargarHorarios() async {
    setState(() => _cargando = true);
    final laboral = await _db.obtenerHorarioPorTipo('laboral');
    final academico = await _db.obtenerHorarioPorTipo('academico');
    setState(() {
      _horarioLaboral = laboral;
      _horarioAcademico = academico;
      _cargando = false;
    });
  }

  Future<void> _editarHorario(String tipo, Horario? actual) async {
    final resultado = await _mostrarDialogoHorario(tipo, actual);
    if (resultado != null) {
      await _db.guardarHorario(resultado);
      await _cargarHorarios();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ Horario ${resultado.tipoTexto.toLowerCase()} guardado')),
        );
      }
    }
  }

  Future<Horario?> _mostrarDialogoHorario(String tipo, Horario? actual) async {
    var horaInicio = actual?.horaInicio ?? (tipo == 'laboral' ? 8 : 18);
    var minutoInicio = actual?.minutoInicio ?? 0;
    var horaFin = actual?.horaFin ?? (tipo == 'laboral' ? 16 : 20);
    var minutoFin = actual?.minutoFin ?? 0;

    final titulo = tipo == 'laboral' ? 'Horario laboral' : 'Horario académico';

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text(titulo),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Hora de inicio
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hora de inicio'),
                    trailing: Text(
                      _formatoHora(horaInicio, minutoInicio),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    onTap: () async {
                      final hora = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay(hour: horaInicio, minute: minutoInicio),
                      );
                      if (hora != null) {
                        setLocal(() {
                          horaInicio = hora.hour;
                          minutoInicio = hora.minute;
                        });
                      }
                    },
                  ),
                  // Hora de fin
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hora de fin'),
                    trailing: Text(
                      _formatoHora(horaFin, minutoFin),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    onTap: () async {
                      final hora = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay(hour: horaFin, minute: minutoFin),
                      );
                      if (hora != null) {
                        setLocal(() {
                          horaFin = hora.hour;
                          minutoFin = hora.minute;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Rango: ${_formatoHora(horaInicio, minutoInicio)} - '
                    '${_formatoHora(horaFin, minutoFin)}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );

    if (guardar == true) {
      return Horario(
        id: actual?.id,
        tipo: tipo,
        horaInicio: horaInicio,
        minutoInicio: minutoInicio,
        horaFin: horaFin,
        minutoFin: minutoFin,
        diasSemana: actual?.diasSemana ?? const [1, 2, 3, 4, 5],
      );
    }
    return null;
  }

  String _formatoHora(int h, int m) {
    final hh = h.toString().padLeft(2, '0');
    final mm = m.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Horarios',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Configura tus horarios laborales y académicos para que la app '
                  'detecte si usas el teléfono en esos momentos y te sugiera mejoras.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),

                // Horario laboral
                _buildTarjetaHorario(
                  icono: Icons.work,
                  color: Colors.blue,
                  titulo: 'Horario laboral',
                  horario: _horarioLaboral,
                  onTap: () => _editarHorario('laboral', _horarioLaboral),
                ),
                const SizedBox(height: 16),

                // Horario académico
                _buildTarjetaHorario(
                  icono: Icons.school,
                  color: Colors.green,
                  titulo: 'Horario académico',
                  horario: _horarioAcademico,
                  onTap: () => _editarHorario('academico', _horarioAcademico),
                ),
                const SizedBox(height: 32),

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
                            'Los horarios se usan para detectar si tus picos de uso '
                            'de pantalla coinciden con tus horas de trabajo o estudio, '
                            'y darte sugerencias de mejora.',
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
              : '${horario.rangoTexto} (${horario.diasSemana.length} días/semana)',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
