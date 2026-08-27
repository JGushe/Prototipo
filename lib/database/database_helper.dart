import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/tarea.dart';
import '../models/uso_pantalla.dart';
import '../models/recomendacion.dart';

class DatabaseHelper {
  // Singleton: una única instancia de la base de datos
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('prototipo_tesis.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Tabla de tareas
    await db.execute('''
      CREATE TABLE tareas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        titulo TEXT NOT NULL,
        descripcion TEXT,
        fechaCreacion TEXT NOT NULL,
        fechaVencimiento TEXT,
        completada INTEGER NOT NULL DEFAULT 0,
        prioridad TEXT NOT NULL DEFAULT 'media'
      )
    ''');

    // Tabla de uso de pantalla diario
    await db.execute('''
      CREATE TABLE uso_pantalla (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT NOT NULL UNIQUE,
        tiempoTotalMinutos INTEGER NOT NULL DEFAULT 0,
        numeroDesbloqueos INTEGER NOT NULL DEFAULT 0,
        appMasUsada TEXT,
        tiempoAppMasUsada INTEGER DEFAULT 0
      )
    ''');

    // Tabla de uso por aplicación
    await db.execute('''
      CREATE TABLE app_uso (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT NOT NULL,
        nombrePaquete TEXT NOT NULL,
        nombreApp TEXT NOT NULL,
        tiempoUsoMinutos INTEGER NOT NULL,
        numeroAperturas INTEGER NOT NULL
      )
    ''');

    // Tabla de recomendaciones
    await db.execute('''
      CREATE TABLE recomendaciones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT NOT NULL,
        tipo TEXT NOT NULL,
        titulo TEXT NOT NULL,
        mensaje TEXT NOT NULL,
        leida INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  // --- CRUD Tareas ---
  Future<int> insertarTarea(Tarea tarea) async {
    final db = await database;
    return await db.insert('tareas', tarea.toMap());
  }

  Future<List<Tarea>> obtenerTareas({bool? completada}) async {
    final db = await database;
    if (completada == null) {
      final result = await db.query('tareas', orderBy: 'fechaCreacion DESC');
      return result.map((map) => Tarea.fromMap(map)).toList();
    } else {
      final result = await db.query(
        'tareas',
        where: 'completada = ?',
        whereArgs: [completada ? 1 : 0],
        orderBy: 'fechaCreacion DESC',
      );
      return result.map((map) => Tarea.fromMap(map)).toList();
    }
  }

  Future<int> actualizarTarea(Tarea tarea) async {
    final db = await database;
    if (tarea.id == null) return 0;
    return await db.update('tareas', tarea.toMap(), where: 'id = ?', whereArgs: [tarea.id]);
  }

  Future<int> eliminarTarea(int id) async {
    final db = await database;
    return await db.delete('tareas', where: 'id = ?', whereArgs: [id]);
  }

  // --- CRUD Uso de Pantalla ---
  Future<int> insertarOActualizarUsoPantalla(UsoPantalla uso) async {
    final db = await database;
    final fechaStr = uso.fecha.toIso8601String().substring(0, 10);
    final existing = await db.query('uso_pantalla', where: 'fecha = ?', whereArgs: [fechaStr]);
    if (existing.isEmpty) {
      return await db.insert('uso_pantalla', {...uso.toMap(), 'fecha': fechaStr});
    } else {
      return await db.update('uso_pantalla', {...uso.toMap()}, where: 'fecha = ?', whereArgs: [fechaStr]);
    }
  }

  Future<List<UsoPantalla>> obtenerUsoSemanal() async {
    final db = await database;
    final result = await db.query('uso_pantalla', orderBy: 'fecha DESC', limit: 7);
    return result.map((map) => UsoPantalla.fromMap(map)).toList();
  }

  Future<UsoPantalla?> obtenerUsoHoy() async {
    final db = await database;
    final fechaStr = DateTime.now().toIso8601String().substring(0, 10);
    final result = await db.query('uso_pantalla', where: 'fecha = ?', whereArgs: [fechaStr]);
    if (result.isEmpty) return null;
    return UsoPantalla.fromMap(result.first);
  }

  // --- CRUD Recomendaciones ---
  Future<int> insertarRecomendacion(Recomendacion rec) async {
    final db = await database;
    return await db.insert('recomendaciones', rec.toMap());
  }

  Future<List<Recomendacion>> obtenerRecomendaciones({bool soloNoLeidas = false}) async {
    final db = await database;
    if (soloNoLeidas) {
      final result = await db.query(
        'recomendaciones',
        where: 'leida = ?',
        whereArgs: [0],
        orderBy: 'fecha DESC',
        limit: 50,
      );
      return result.map((map) => Recomendacion.fromMap(map)).toList();
    } else {
      final result = await db.query('recomendaciones', orderBy: 'fecha DESC', limit: 50);
      return result.map((map) => Recomendacion.fromMap(map)).toList();
    }
  }

  Future<int> marcarRecomendacionLeida(int id) async {
    final db = await database;
    return await db.update('recomendaciones', {'leida': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // --- Cerrar base de datos ---
  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
