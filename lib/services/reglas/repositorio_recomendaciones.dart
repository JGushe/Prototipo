import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';
import '../../models/recomendacion.dart';

/// Almacén de recomendaciones que necesita el motor.
///
/// Abstraer esta dependencia permite sustituir SQLite por un doble en memoria
/// en las pruebas de integración, sin tocar el motor. El historial nunca se
/// borra desde esta interfaz: solo hay lectura acotada e inserción.
abstract class RepositorioRecomendaciones {
  /// Serializa la lectura de cooldown y las escrituras que dependen de ella.
  Future<T> enTransaccion<T>(
    Future<T> Function(RepositorioRecomendaciones repositorio) operacion,
  );

  Future<int> insertar(Recomendacion recomendacion);

  /// Recomendaciones con fecha igual o posterior a [desde].
  Future<List<Recomendacion>> obtenerDesde(DateTime desde);
}

/// Implementación real sobre SQLite a través de [DatabaseHelper].
class RepositorioRecomendacionesSqlite implements RepositorioRecomendaciones {
  final DatabaseHelper _db;
  final Transaction? _transaccion;

  RepositorioRecomendacionesSqlite([DatabaseHelper? db])
      : this._(db ?? DatabaseHelper.instance, null);

  RepositorioRecomendacionesSqlite._(this._db, this._transaccion);

  @override
  Future<T> enTransaccion<T>(
    Future<T> Function(RepositorioRecomendaciones repositorio) operacion,
  ) async {
    if (_transaccion != null) return operacion(this);
    final db = await _db.database;
    return db.transaction(
      (txn) => operacion(RepositorioRecomendacionesSqlite._(_db, txn)),
    );
  }

  @override
  Future<int> insertar(Recomendacion recomendacion) =>
      _db.insertarRecomendacion(recomendacion, executor: _transaccion);

  @override
  Future<List<Recomendacion>> obtenerDesde(DateTime desde) =>
      _db.obtenerRecomendacionesDesde(desde, executor: _transaccion);
}
