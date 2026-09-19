import '../../database/database_helper.dart';
import '../../models/recomendacion.dart';

/// Almacén de recomendaciones que necesita el motor.
///
/// Abstraer esta dependencia permite sustituir SQLite por un doble en memoria
/// en las pruebas de integración, sin tocar el motor. El historial nunca se
/// borra desde esta interfaz: solo hay lectura acotada e inserción.
abstract class RepositorioRecomendaciones {
  Future<int> insertar(Recomendacion recomendacion);

  /// Recomendaciones con fecha igual o posterior a [desde].
  Future<List<Recomendacion>> obtenerDesde(DateTime desde);
}

/// Implementación real sobre SQLite a través de [DatabaseHelper].
class RepositorioRecomendacionesSqlite implements RepositorioRecomendaciones {
  final DatabaseHelper _db;

  RepositorioRecomendacionesSqlite([DatabaseHelper? db])
      : _db = db ?? DatabaseHelper.instance;

  @override
  Future<int> insertar(Recomendacion recomendacion) =>
      _db.insertarRecomendacion(recomendacion);

  @override
  Future<List<Recomendacion>> obtenerDesde(DateTime desde) =>
      _db.obtenerRecomendacionesDesde(desde);
}
