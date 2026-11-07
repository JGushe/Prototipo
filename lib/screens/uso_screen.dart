import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/lectura_uso_controller.dart';
import '../widgets/estado_lectura_uso.dart';
import '../theme/app_theme.dart';
import '../models/uso_pantalla.dart';

class UsoScreen extends StatelessWidget {
  const UsoScreen({super.key, required this.lectura});

  final LecturaUsoController lectura;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: lectura,
        builder: (context, _) => FutureBuilder<DetalleLecturaUso>(
          future: lectura.detalle(),
          builder: _buildUso,
        ),
      );

  Widget _buildUso(
      BuildContext context, AsyncSnapshot<DetalleLecturaUso> detalle) {
    final comparacion = lectura.comparacion;
    final minutos = comparacion?.minutosHoy;
    final desbloqueos = comparacion?.desbloqueosHoy;
    final distractor = comparacion?.distractorHoy;
    final actual =
        detalle.connectionState == ConnectionState.done ? detalle.data : null;
    final apps = actual?.apps ?? const <AppUso>[];
    final analisis = actual?.analisis;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = AppTheme.colors(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Uso de Pantalla'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar datos',
            onPressed: lectura.actualizando ? null : lectura.actualizar,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Resumen del día
            Card(
              color: scheme.primary.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Resumen de hoy',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(
                        'Tiempo único de pantalla: ${minutos == null ? '—' : formatearMinutosUso(minutos)}',
                        style: const TextStyle(fontSize: 18)),
                    EtiquetaLecturaUso(lectura),
                    const SizedBox(height: 6),
                    Text('Desbloqueos: ${desbloqueos ?? '—'}'),
                    if (distractor != null)
                      Text(
                          'En apps distractoras: ${formatearMinutosUso(distractor)}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Top apps (gráfico circular)
            const Text('Top aplicaciones (hoy)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (detalle.connectionState == ConnectionState.done &&
                detalle.hasError)
              const Text('No se pudo cargar el detalle de uso.')
            else if (detalle.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator(
                  semanticsLabel: 'Consultando detalle de uso')
            else if (apps.isEmpty)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Sin datos por aplicación.')))
            else
              SizedBox(
                height: 220,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 40,
                    sections: apps.map((app) {
                      final color = colors.chartColors[
                          apps.indexOf(app) % colors.chartColors.length];
                      return PieChartSectionData(
                        value: app.tiempoUsoMinutos.toDouble(),
                        title: '${app.tiempoUsoMinutos}m',
                        color: color,
                        radius: 60,
                        titleStyle: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      );
                    }).toList(),
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Lista detallada
            ...apps.map((app) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colors.chartColors[
                              apps.indexOf(app) % colors.chartColors.length]
                          .withValues(alpha: 0.18),
                      child: Text('${apps.indexOf(app) + 1}',
                          style: TextStyle(
                              color: colors.chartColors[apps.indexOf(app) %
                                  colors.chartColors.length])),
                    ),
                    title: Text(app.nombreApp),
                    subtitle: Text(app.nombrePaquete,
                        style: const TextStyle(fontSize: 11)),
                    trailing: Text(formatearMinutosUso(app.tiempoUsoMinutos),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                )),
            const SizedBox(height: 32),

            // Momentos de mayor uso (análisis por hora)
            const Text('Momentos de mayor uso del día',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Uso de pantalla por hora (últimos 7 días). Toca Config para '
              'definir tus horarios laborales y académicos.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),

            if (analisis != null) ...[
              if (analisis.usoPorHora.isNotEmpty)
                SizedBox(
                  height: 200,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: (analisis.usoPorHora.values.fold<int>(
                              0, (max, v) => v > max ? v : max)).toDouble() +
                          10,
                      barGroups: analisis.usoPorHora.entries.map((entry) {
                        final esPico = entry.key == analisis.horaPico;
                        return BarChartGroupData(
                          x: entry.key,
                          barRods: [
                            BarChartRodData(
                              toY: entry.value.toDouble(),
                              color:
                                  esPico ? scheme.error : colors.chartColors[0],
                              width: 6,
                              borderRadius: BorderRadius.circular(2),
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
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: scheme.onSurface
                                          .withValues(alpha: 0.6)));
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 3,
                            getTitlesWidget: (value, meta) {
                              final h = value.toInt();
                              if (h % 3 != 0) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('$h',
                                    style: const TextStyle(fontSize: 9)),
                              );
                            },
                          ),
                        ),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: FlGridData(
                        show: true,
                        getDrawingHorizontalLine: (_) =>
                            FlLine(color: colors.chartGrid, strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Tarjeta con el pico y sugerencias
              Card(
                color: analisis.minutosPico == 0
                    ? scheme.surfaceContainerHighest.withValues(alpha: 0.4)
                    : colors.warning.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            analisis.minutosPico == 0
                                ? Icons.hourglass_empty
                                : Icons.local_fire_department,
                            color: analisis.minutosPico == 0
                                ? scheme.outline
                                : colors.warning,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              analisis.minutosPico == 0
                                  ? 'Aún sin datos de uso'
                                  : 'Tu pico de uso: ${analisis.picoTexto} '
                                      '(${analisis.minutosPico} min)',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...analisis.sugerencias.map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text('• $s',
                                style: const TextStyle(fontSize: 14)),
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
