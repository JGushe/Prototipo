import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/comparacion_diaria.dart';
import '../models/uso_pantalla.dart';
import 'analisis_horario_service.dart';
import 'ciclo_monitoreo_service.dart';
import 'reglas/resultado_evaluacion.dart';
import 'uso_pantalla_service.dart';

enum EstadoLecturaUso {
  leyendo,
  actualizando,
  sinPermiso,
  sinDatos,
  disponible,
  antigua,
  error,
}

typedef DetalleLecturaUso = ({List<AppUso> apps, AnalisisHorario analisis});

/// Una lectura por sesión de interfaz. Cambiar de pestaña no escribe en SQLite.
class LecturaUsoController extends ChangeNotifier {
  static const vigencia = Duration(minutes: 5);

  LecturaUsoController({
    UsoPantallaService? uso,
    CicloMonitoreoService? ciclo,
    AnalisisHorarioService? analisis,
    DateTime Function()? reloj,
  })  : _uso = uso ?? UsoPantallaService(),
        _ciclo = ciclo ?? CicloMonitoreoService(),
        _analisis = analisis ?? AnalisisHorarioService(),
        _ahora = reloj ?? DateTime.now;

  final UsoPantallaService _uso;
  final CicloMonitoreoService _ciclo;
  final AnalisisHorarioService _analisis;
  final DateTime Function() _ahora;
  ComparacionDiaria? _comparacion;
  MotivoComparacion? _motivo;
  DateTime? _ultimaLectura;
  Future<void>? _lectura;
  Future<ResultadoEvaluacion?>? _actualizacion;
  ResultadoEvaluacion? _ultimaEvaluacion;
  Future<DetalleLecturaUso>? _detalle;
  Timer? _avisoCaducidad;
  bool _cerrado = false;

  bool get actualizando => _actualizacion != null;
  ResultadoEvaluacion? get ultimaEvaluacion {
    final momento = _ultimaEvaluacion?.contexto.momento;
    final ahora = _ahora();
    return momento != null &&
            DateTime(momento.year, momento.month, momento.day) ==
                DateTime(ahora.year, ahora.month, ahora.day)
        ? _ultimaEvaluacion
        : null;
  }

  ComparacionDiaria? get comparacion {
    final ahora = _ahora();
    return _comparacion?.diaHoy == DateTime(ahora.year, ahora.month, ahora.day)
        ? _comparacion
        : null;
  }

  bool get _caducada {
    final instante = _comparacion?.corte ?? _ultimaLectura;
    return instante != null &&
        (comparacion == null && _comparacion != null ||
            _ahora().difference(instante) >= vigencia);
  }

  EstadoLecturaUso get estado {
    if (actualizando) return EstadoLecturaUso.actualizando;
    if (_lectura != null || _ultimaLectura == null) {
      return EstadoLecturaUso.leyendo;
    }
    if (_motivo == MotivoComparacion.sinPermiso) {
      return EstadoLecturaUso.sinPermiso;
    }
    if (_motivo == MotivoComparacion.error) return EstadoLecturaUso.error;
    if (_caducada) return EstadoLecturaUso.antigua;
    return comparacion?.minutosHoy == null
        ? EstadoLecturaUso.sinDatos
        : EstadoLecturaUso.disponible;
  }

  Future<void> leer({bool forzar = false}) {
    if (_actualizacion case final enCurso?) return enCurso.then((_) {});
    if (_lectura case final enCurso?) return enCurso;
    final ultima = _ultimaLectura;
    if (!forzar &&
        ultima != null &&
        _ahora().difference(ultima) < vigencia &&
        (comparacion != null || _comparacion == null)) {
      return Future.value();
    }

    final lectura = Future<void>.microtask(_consultar).whenComplete(() {
      _lectura = null;
      _notificar();
    });
    _lectura = lectura;
    _notificar();
    return lectura;
  }

  Future<ResultadoEvaluacion?> actualizar() {
    if (_actualizacion case final enCurso?) return enCurso;

    final actualizacion = Future<ResultadoEvaluacion?>.microtask(() async {
      await _lectura;
      ResultadoEvaluacion? resultado;
      MotivoComparacion? motivo;
      try {
        if (await _uso.solicitarPermisoUso()) {
          resultado = (await _ciclo.ejecutar()).resultado;
        } else {
          motivo = MotivoComparacion.sinPermiso;
        }
      } on CapturaUsoNoDisponible catch (error) {
        if (error == CapturaUsoNoDisponible.sinPermiso) {
          motivo = MotivoComparacion.sinPermiso;
        }
        // Una lectura puede conservar el lado conocido de la comparación.
      } catch (_) {
        motivo = MotivoComparacion.error;
      }

      if (motivo == MotivoComparacion.sinPermiso) {
        _guardar(ComparacionDiaria.insuficiente(
          ahora: _ahora(),
          explicacion: 'Concede acceso al uso para consultar estas métricas.',
          motivo: MotivoComparacion.sinPermiso,
        ));
      } else {
        await _consultar();
        if (motivo != null && _motivo != MotivoComparacion.sinPermiso) {
          _motivo = motivo;
        }
      }
      if (!_cerrado && resultado != null) _ultimaEvaluacion = resultado;
      return resultado;
    }).whenComplete(() {
      _actualizacion = null;
      _notificar();
    });
    _actualizacion = actualizacion;
    _notificar();
    return actualizacion;
  }

  Future<void> _consultar() async {
    final ahora = _ahora();
    try {
      _guardar(await _uso.compararHoyAyer(ahora: ahora));
    } catch (_) {
      _guardar(ComparacionDiaria.insuficiente(
        ahora: ahora,
        explicacion: 'No se pudo leer el uso.',
        motivo: MotivoComparacion.error,
      ));
    }
  }

  void _guardar(ComparacionDiaria lectura) {
    if (_cerrado) return;
    _ultimaLectura = _ahora();
    _motivo = lectura.motivo;
    if (_motivo != MotivoComparacion.error || comparacion == null) {
      _comparacion = lectura;
      _detalle = null;
    }
    _avisoCaducidad?.cancel();
    _avisarAlCaducar();
  }

  void _avisarAlCaducar() {
    final corte = _comparacion?.corte;
    if (corte == null) return;
    final ahora = _ahora();
    final caducidad = corte.add(vigencia);
    final medianoche = DateTime(ahora.year, ahora.month, ahora.day + 1);
    final siguiente = caducidad.isAfter(ahora) && caducidad.isBefore(medianoche)
        ? caducidad
        : medianoche;
    _avisoCaducidad = Timer(siguiente.difference(ahora), () {
      _notificar();
      if (siguiente != medianoche && !_cerrado) {
        _avisoCaducidad = Timer(medianoche.difference(_ahora()), _notificar);
      }
    });
  }

  Future<DetalleLecturaUso>? detalle() {
    final corte = comparacion?.corte;
    if (corte == null || _motivo == MotivoComparacion.sinPermiso) return null;
    return _detalle ??= _cargarDetalle(corte);
  }

  Future<DetalleLecturaUso> _cargarDetalle(DateTime corte) async {
    final (apps, analisis) = await (
      _uso.obtenerTopAppsDelDia(ahora: corte),
      _analisis.analizar(ahora: corte),
    ).wait;
    return (apps: apps, analisis: analisis);
  }

  void _notificar() {
    if (!_cerrado) notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    _avisoCaducidad?.cancel();
    super.dispose();
  }
}
