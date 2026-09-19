import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/tarea.dart';
import '../models/uso_pantalla.dart';
import '../models/recomendacion.dart';
import '../models/horario.dart';

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
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE horarios (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tipo TEXT NOT NULL,
          horaInicio INTEGER NOT NULL,
          minutoInicio INTEGER NOT NULL DEFAULT 0,
          horaFin INTEGER NOT NULL,
          minutoFin INTEGER NOT NULL DEFAULT 0,
          diasSemana TEXT NOT NULL DEFAULT '1,2,3,4,5'
        )
      ''');
    }
    if (oldVersion < 3) {
      // Contexto temporal de las tareas (columnas opcionales).
      // Las tareas existentes quedan con planificación nula.
      await db.execute('ALTER TABLE tareas ADD COLUMN fechaPlanificada TEXT');
      await db.execute(
          'ALTER TABLE tareas ADD COLUMN horaInicioPlanificada TEXT');
      await db.execute('ALTER TABLE tareas ADD COLUMN horaFinPlanificada TEXT');
    }
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
        prioridad TEXT NOT NULL DEFAULT 'media',
        fechaPlanificada TEXT,
        horaInicioPlanificada TEXT,
        horaFinPlanificada TEXT
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

    // Tabla de horarios (laboral/académico)
    await db.execute('''
      CREATE TABLE horarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo TEXT NOT NULL,
        horaInicio INTEGER NOT NULL,
        minutoInicio INTEGER NOT NULL DEFAULT 0,
        horaFin INTEGER NOT NULL,
        minutoFin INTEGER NOT NULL DEFAULT 0,
        diasSemana TEXT NOT NULL DEFAULT '1,2,3,4,5'
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

  /// Tareas planificadas para el día [fecha] (según `fechaPlanificada`).
  /// Las tareas antiguas sin planificación no se incluyen.
  Future<List<Tarea>> obtenerTareasPlanificadasDelDia(
    DateTime fecha, {
    bool? completada,
  }) async {
    final db = await database;
    final where = StringBuffer('fechaPlanificada = ?');
    final args = <Object?>[_soloFecha(fecha)];
    if (completada != null) {
      where.write(' AND completada = ?');
      args.add(completada ? 1 : 0);
    }
    final result = await db.query(
      'tareas',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'horaInicioPlanificada ASC',
    );
    return result.map((map) => Tarea.fromMap(map)).toList();
  }

  /// Tareas planificadas que están activas en [momento].
  ///
  /// Se consultan el día de [momento] y el día anterior para contemplar el
  /// caso especial de franjas que cruzan la medianoche; el filtro final lo
  /// aplica [Tarea.estaPlanificadaEn].
  Future<List<Tarea>> obtenerTareasPlanificadasEn(
    DateTime momento, {
    bool? completada,
  }) async {
    final db = await database;
    final where = StringBuffer('fechaPlanificada IN (?, ?)');
    final args = <Object?>[
      _soloFecha(momento.subtract(const Duration(days: 1))),
      _soloFecha(momento),
    ];
    if (completada != null) {
      where.write(' AND completada = ?');
      args.add(completada ? 1 : 0);
    }
    final result = await db.query(
      'tareas',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'horaInicioPlanificada ASC',
    );
    return result
        .map((map) => Tarea.fromMap(map))
        .where((t) => t.estaPlanificadaEn(momento))
        .toList();
  }

  /// Primera tarea planificada activa en [momento], o null si no hay ninguna.
  Future<Tarea?> obtenerTareaPlanificadaEn(DateTime momento) async {
    final tareas = await obtenerTareasPlanificadasEn(momento);
    return tareas.isEmpty ? null : tareas.first;
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

  /// Uso de pantalla registrado para una fecha concreta, o null si no existe.
  Future<UsoPantalla?> obtenerUsoPorFecha(DateTime fecha) async {
    final db = await database;
    final result = await db.query(
      'uso_pantalla',
      where: 'fecha = ?',
      whereArgs: [_soloFecha(fecha)],
    );
    if (result.isEmpty) return null;
    return UsoPantalla.fromMap(result.first);
  }

  Future<UsoPantalla?> obtenerUsoHoy() => obtenerUsoPorFecha(DateTime.now());

  // --- CRUD Uso por aplicación ---
  /// Inserta o actualiza el uso de una aplicación para una fecha y paquete dados.
  /// Evita duplicados: si ya existe un registro para la misma fecha y paquete,
  /// actualiza sus valores en lugar de insertar uno nuevo. La fecha se normaliza
  /// a 'yyyy-MM-dd' para que coincida con el resto del esquema.
  Future<int> insertarOActualizarAppUso(AppUso app, {DateTime? fecha}) async {
    final db = await database;
    final fechaStr =
        (fecha ?? DateTime.now()).toIso8601String().substring(0, 10);
    final valores = {...app.toMap(), 'fecha': fechaStr};

    final existing = await db.query(
      'app_uso',
      where: 'fecha = ? AND nombrePaquete = ?',
      whereArgs: [fechaStr, app.nombrePaquete],
    );
    if (existing.isEmpty) {
      return await db.insert('app_uso', valores);
    } else {
      return await db.update(
        'app_uso',
        valores,
        where: 'fecha = ? AND nombrePaquete = ?',
        whereArgs: [fechaStr, app.nombrePaquete],
      );
    }
  }

  /// Obtiene el detalle de uso por aplicación de una fecha (por defecto hoy),
  /// ordenado de mayor a menor tiempo de uso.
  Future<List<AppUso>> obtenerAppsUsoDelDia({DateTime? fecha, int? top}) async {
    final db = await database;
    final fechaStr =
        (fecha ?? DateTime.now()).toIso8601String().substring(0, 10);
    final result = await db.query(
      'app_uso',
      where: 'fecha = ?',
      whereArgs: [fechaStr],
      orderBy: 'tiempoUsoMinutos DESC',
    );
    final apps = result.map((map) => AppUso.fromMap(map)).toList();
    if (top == null || top >= apps.length) return apps;
    return apps.take(top).toList();
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

  // --- CRUD Horarios ---
  Future<int> guardarHorario(Horario horario) async {
    final db = await database;
    // Si ya existe un horario del mismo tipo, lo actualiza
    final existing = await db.query(
      'horarios',
      where: 'tipo = ?',
      whereArgs: [horario.tipo],
    );
    if (existing.isEmpty) {
      return await db.insert('horarios', horario.toMap());
    } else {
      return await db.update(
        'horarios',
        horario.toMap(),
        where: 'tipo = ?',
        whereArgs: [horario.tipo],
      );
    }
  }

  Future<List<Horario>> obtenerHorarios() async {
    final db = await database;
    final result = await db.query('horarios', orderBy: 'tipo ASC');
    return result.map((map) => Horario.fromMap(map)).toList();
  }

  Future<Horario?> obtenerHorarioPorTipo(String tipo) async {
    final db = await database;
    final result = await db.query(
      'horarios',
      where: 'tipo = ?',
      whereArgs: [tipo],
    );
    if (result.isEmpty) return null;
    return Horario.fromMap(result.first);
  }

  Future<int> eliminarHorario(int id) async {
    final db = await database;
    return await db.delete('horarios', where: 'id = ?', whereArgs: [id]);
  }

  // --- Utilidades ---
  /// Normaliza una fecha a 'yyyy-MM-dd', formato usado en las columnas de fecha.
  static String _soloFecha(DateTime fecha) =>
      fecha.toIso8601String().substring(0, 10);

  // --- Cerrar base de datos ---
  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
