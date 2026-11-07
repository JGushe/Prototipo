import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/lectura_uso_controller.dart';

String formatearMinutosUso(int minutos) =>
    minutos >= 60 ? '${minutos ~/ 60} h ${minutos % 60} min' : '$minutos min';

int? porcentajeDistractor(int? total, int? distractor) {
  if (total == null ||
      total <= 0 ||
      distractor == null ||
      distractor < 0 ||
      distractor > total) {
    return null;
  }
  return (100 * distractor / total).round();
}

class EtiquetaLecturaUso extends StatelessWidget {
  const EtiquetaLecturaUso(
    this.lectura, {
    super.key,
    this.color,
    this.mostrarCorte = false,
  });

  final LecturaUsoController lectura;
  final Color? color;
  final bool mostrarCorte;

  @override
  Widget build(BuildContext context) {
    final estado = switch (lectura.estado) {
      EstadoLecturaUso.leyendo => 'Consultando uso…',
      EstadoLecturaUso.actualizando => 'Actualizando captura…',
      EstadoLecturaUso.sinPermiso => 'Acceso al uso desactivado',
      EstadoLecturaUso.sinDatos => 'Datos insuficientes',
      EstadoLecturaUso.disponible => null,
      EstadoLecturaUso.antigua => 'Captura antigua',
      EstadoLecturaUso.error => 'No se pudo actualizar la lectura',
    };
    final corte = mostrarCorte ? lectura.comparacion?.corte : null;
    final lineas = [
      if (estado != null) estado,
      if (corte != null) 'Corte ${DateFormat.Hm().format(corte)}',
    ];
    if (lineas.isEmpty) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Text(
        lineas.join('\n'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}
