import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../database/database_helper.dart';
import '../models/recomendacion.dart';

/// Archivo visual de una instantánea. Actualizar reinicia las páginas cargadas.
class HistorialTipsController extends ChangeNotifier {
  HistorialTipsController({DateTime Function()? reloj})
      : _ahora = reloj ?? DateTime.now;
  final DateTime Function() _ahora;
  DateTime get ahora => _ahora();
  String? _cargadoEn;
  Future<bool>? _comprobacion;
  static const preferencias =
      MethodChannel('prototipo_tesis/preferencias_tips');
  final _db = DatabaseHelper.instance;
  List<Recomendacion> recientes = [];
  List<Recomendacion> archivo = [];
  Set<String> ocultas = {};
  bool viendoArchivo = false;
  bool hayMas = false;
  bool cargando = false;
  bool guardando = false;
  bool error = false;
  bool errorPreferencias = false;
  bool _preferenciasLeidas = false;
  bool _cerrado = false;
  int _limiteId = 0;
  int _version = 0;
  Future<void>? _recarga;
  Future<void>? _pagina;

  static final _formatoDia = DateFormat('yyyy-MM-dd');
  static String dia(DateTime fecha) => _formatoDia.format(fecha.toLocal());
  final _tarjetas = <int, ValueNotifier<Recomendacion>>{};
  final _sinLeer = <String, ValueNotifier<int>>{};
  Map<String, List<Recomendacion>> _grupos = {};
  String _calendario = '';

  ValueListenable<Recomendacion> tarjeta(Recomendacion rec) =>
      _tarjetas.putIfAbsent(rec.id!, () => ValueNotifier(rec));

  ValueListenable<int> sinLeer(String fecha) => _sinLeer.putIfAbsent(
      '$viendoArchivo-$fecha',
      () => ValueNotifier(_contarSinLeer(fecha, viendoArchivo)));

  int _contarSinLeer(String fecha, bool enArchivo) =>
      (enArchivo ? archivo : recientes)
          .where((r) => dia(r.fecha) == fecha && !r.leida)
          .length;

  String get _calendarioActual {
    final ahora = _ahora();
    return '${dia(ahora)}:${ahora.timeZoneOffset.inMinutes}';
  }

  void _prepararGrupos() {
    _calendario = _calendarioActual;
    final grupos = <String, List<Recomendacion>>{};
    for (final rec in viendoArchivo ? archivo : recientes) {
      final fecha = dia(rec.fecha);
      if (!viendoArchivo && ocultas.contains(fecha)) continue;
      (grupos[fecha] ??= []).add(rec);
    }
    _grupos = Map.unmodifiable(grupos.map(
        (dia, recs) => MapEntry(dia, List<Recomendacion>.unmodifiable(recs))));
    final todos = [...recientes, ...archivo];
    final porId = {for (final rec in todos) rec.id: rec};
    for (final id in _tarjetas.keys.toList()) {
      final rec = porId[id];
      if (rec == null) {
        _tarjetas.remove(id)!.dispose();
      } else {
        _tarjetas[id]!.value = rec;
      }
    }
    for (final entrada in _sinLeer.entries) {
      final archivo = entrada.key.startsWith('true-');
      final fecha = entrada.key.substring(archivo ? 5 : 6);
      entrada.value.value = _contarSinLeer(fecha, archivo);
    }
  }

  Map<String, List<Recomendacion>> get grupos {
    if (_calendario != _calendarioActual) _prepararGrupos();
    return _grupos;
  }

  bool fechaCompartida(String fecha) =>
      recientes.isNotEmpty &&
      archivo.isNotEmpty &&
      dia(recientes.last.fecha) == fecha &&
      dia(archivo.first.fecha) == fecha;

  Future<void> cargar() {
    if (_cerrado) return Future.value();
    if (_recarga case final pendiente?) return pendiente;
    final version = ++_version;
    cargando = true;
    final tarea = Future<void>.microtask(() async {
      try {
        if (!_preferenciasLeidas) {
          try {
            final fechas = await preferencias
                .invokeListMethod<String>('leerFechasOcultas');
            if (_cerrado) return;
            ocultas = (fechas ?? []).toSet();
            _preferenciasLeidas = true;
            errorPreferencias = false;
          } catch (_) {
            errorPreferencias = true;
          }
        }
        final datos = await _db.iniciarHistorialTips();
        if (_cerrado || version != _version) return;
        recientes = datos.recientes;
        archivo = datos.archivo;
        _limiteId = datos.limiteId;
        _cargadoEn = _calendarioActual;
        hayMas = datos.hayMas;
        _prepararGrupos();
        error = false;
      } catch (_) {
        if (!_cerrado && version == _version) error = true;
      } finally {
        if (!_cerrado && version == _version) {
          cargando = false;
          _avisar();
        }
      }
    }).whenComplete(() => _recarga = null);
    _recarga = tarea;
    _avisar();
    return tarea;
  }

  /// El motor inserta nuevas filas; MAX(id) detecta novedades sin recargar páginas.
  Future<bool> comprobarCambios() {
    if (_cerrado) return Future.value(false);
    if (_comprobacion case final pendiente?) return pendiente;
    if (_recarga case final pendiente?) return pendiente.then((_) => true);
    final version = _version;
    final tarea = Future<bool>.microtask(() async {
      try {
        final db = await _db.database;
        final filas =
            await db.rawQuery('SELECT MAX(id) AS ultimo FROM recomendaciones');
        if (_cerrado || version != _version) return false;
        final limite = (filas.first['ultimo'] as int?) ?? 0;
        if (error || limite != _limiteId || _cargadoEn != _calendarioActual) {
          await cargar();
          return !error;
        }
        return false;
      } catch (_) {
        if (!_cerrado && version == _version) {
          error = true;
          _avisar();
        }
        return false;
      }
    }).whenComplete(() => _comprobacion = null);
    _comprobacion = tarea;
    return tarea;
  }

  Future<void> cargarMas() {
    if (_cerrado || !hayMas || archivo.isEmpty) return Future.value();
    if (_recarga case final pendiente?) return pendiente;
    if (_pagina case final pendiente?) return pendiente;
    final version = _version;
    cargando = true;
    final tarea = Future<void>.microtask(() async {
      try {
        final pagina = await _db.paginaArchivoTips(
          limiteId: _limiteId,
          despuesDe: archivo.last,
        );
        if (_cerrado || version != _version) return;
        archivo = [...archivo, ...pagina.registros];
        hayMas = pagina.hayMas;
        _prepararGrupos();
        error = false;
      } catch (_) {
        if (!_cerrado && version == _version) error = true;
      } finally {
        if (!_cerrado && version == _version) {
          cargando = false;
          _avisar();
        }
      }
    }).whenComplete(() => _pagina = null);
    _pagina = tarea;
    _avisar();
    return tarea;
  }

  void mostrarArchivo(bool mostrar) {
    if (viendoArchivo == mostrar) return;
    viendoArchivo = mostrar;
    _prepararGrupos();
    _avisar();
  }

  Future<void> guardarOcultas(Set<String> fechas) async {
    if (_cerrado || guardando) return;
    guardando = true;
    _avisar();
    try {
      await preferencias.invokeMethod<void>(
          'guardarFechasOcultas', fechas.toList()..sort());
      if (_cerrado) return;
      ocultas = Set.of(fechas);
      _prepararGrupos();
      _preferenciasLeidas = true;
      errorPreferencias = false;
    } finally {
      guardando = false;
      _avisar();
    }
  }

  /// Lectura/valoración no cambian el orden ni reinician la paginación.
  Future<void> actualizarRecomendacion(Recomendacion rec,
      {String? valoracion, bool leer = false}) async {
    if (rec.id == null) return;
    if (leer) {
      await _db.marcarRecomendacionLeida(rec.id!);
    } else {
      await _db.valorarRecomendacion(rec.id!, valoracion);
    }
    if (_cerrado) return;
    Recomendacion actualizar(Recomendacion actual) => actual.id != rec.id
        ? actual
        : Recomendacion.fromMap({
            ...actual.toMap(),
            if (leer) 'leida': 1 else 'valoracion': valoracion,
          });
    recientes = recientes.map(actualizar).toList();
    archivo = archivo.map(actualizar).toList();
    final actual =
        [...recientes, ...archivo].where((r) => r.id == rec.id).firstOrNull;
    if (actual != null) _tarjetas[rec.id]?.value = actual;
    final fecha = dia(rec.fecha);
    if (_grupos.containsKey(fecha)) {
      _grupos = Map.unmodifiable({
        ..._grupos,
        fecha:
            List<Recomendacion>.unmodifiable(_grupos[fecha]!.map(actualizar)),
      });
    }
    for (final enArchivo in [false, true]) {
      _sinLeer['$enArchivo-$fecha']?.value = _contarSinLeer(fecha, enArchivo);
    }
  }

  void _avisar() {
    if (!_cerrado) notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    _version++;
    for (final tarjeta in _tarjetas.values) {
      tarjeta.dispose();
    }
    for (final contador in _sinLeer.values) {
      contador.dispose();
    }
    super.dispose();
  }
}
