import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/tarea.dart';
import '../models/uso_pantalla.dart';
import '../models/recomendacion.dart';
import '../models/horario.dart';
import '../models/perfil.dart';

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
      version: 9,
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
    if (oldVersion < 4) {
      // Trazabilidad de las recomendaciones: qué regla las generó y por qué.
      // Las recomendaciones existentes quedan con severidad 'info'.
      await db.execute('ALTER TABLE recomendaciones ADD COLUMN reglaId TEXT');
      await db.execute(
          "ALTER TABLE recomendaciones ADD COLUMN severidad TEXT NOT NULL DEFAULT 'info'");
      await db.execute('ALTER TABLE recomendaciones ADD COLUMN motivo TEXT');
    }
    if (oldVersion < 5) {
      // Clave de equivalencia para el control de duplicados y cooldown.
      // Las recomendaciones anteriores quedan con clave nula: se conservan en
      // el historial pero no bloquean a las nuevas.
      await db.execute('ALTER TABLE recomendaciones ADD COLUMN clave TEXT');
    }
    if (oldVersion < 6) {
      // Horarios múltiples: etiqueta visible y activación individual.
      // Los horarios existentes quedan sin nombre (se usa su categoría) y
      // ACTIVOS, para no perder funcionalidad.
      await db.execute('ALTER TABLE horarios ADD COLUMN nombre TEXT');
      await db.execute(
          'ALTER TABLE horarios ADD COLUMN activo INTEGER NOT NULL DEFAULT 1');
    }
    if (oldVersion < 7) {
      // Valoración voluntaria de la recomendación ('util' / 'no_util').
      // Las recomendaciones existentes quedan sin valorar (NULL): no se
      // inventan respuestas ni se toca ningún otro campo.
      await db.execute(
          'ALTER TABLE recomendaciones ADD COLUMN valoracion TEXT');
    }
    if (oldVersion < 8) {
      // Perfil local opcional. Sin filas previas: los usuarios existentes
      // quedan sin perfil y la app funciona igual.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS perfil (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          nombre TEXT,
          identidadGenero TEXT,
          autodescripcion TEXT
        )
      ''');
    }
    if (oldVersion < 9) {
      // Preferencias de apariencia en el mismo perfil local. Null = sin
      // preferencia manual (modo sistema y paleta sugerida).
      await db.execute('ALTER TABLE perfil ADD COLUMN temaModo TEXT');
      await db.execute('ALTER TABLE perfil ADD COLUMN paleta TEXT');
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
        leida INTEGER NOT NULL DEFAULT 0,
        reglaId TEXT,
        severidad TEXT NOT NULL DEFAULT 'info',
        motivo TEXT,
        clave TEXT,
        valoracion TEXT
      )
    ''');

    // Tabla de horarios (categoría laboral/académico/personalizado)
    await db.execute('''
      CREATE TABLE horarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo TEXT NOT NULL,
        horaInicio INTEGER NOT NULL,
        minutoInicio INTEGER NOT NULL DEFAULT 0,
        horaFin INTEGER NOT NULL,
        minutoFin INTEGER NOT NULL DEFAULT 0,
        diasSemana TEXT NOT NULL DEFAULT '1,2,3,4,5',
        nombre TEXT,
        activo INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Perfil local opcional (una sola fila).
    await db.execute('''
      CREATE TABLE perfil (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        nombre TEXT,
        identidadGenero TEXT,
        autodescripcion TEXT,
        temaModo TEXT,
        paleta TEXT
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
    return await db.update('tareas', sinId(tarea.toMap()), where: 'id = ?', whereArgs: [tarea.id]);
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
  /// Inserta o actualiza el resumen de uso del día.
  ///
  /// [executor] permite reutilizar la operación dentro de una transacción.
  Future<int> insertarOActualizarUsoPantalla(
    UsoPantalla uso, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    final fechaStr = _soloFecha(uso.fecha);
    // Se quita el `id`: enviarlo nulo (el modelo recién construido no lo tiene)
    // haría `SET id = NULL` sobre una columna INTEGER PRIMARY KEY y SQLite
    // devolvería SQLITE_MISMATCH (code 20).
    final valores = sinId(uso.toMap())..['fecha'] = fechaStr;
    final existing = await db.query(
      'uso_pantalla',
      where: 'fecha = ?',
      whereArgs: [fechaStr],
    );
    if (existing.isEmpty) {
      return await db.insert('uso_pantalla', valores);
    }
    return await db.update(
      'uso_pantalla',
      valores,
      where: 'fecha = ?',
      whereArgs: [fechaStr],
    );
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

  /// Uso registrado entre dos fechas locales, ambas incluidas. Solo devuelve
  /// días con captura: los días ausentes no aparecen como ceros.
  Future<List<UsoPantalla>> obtenerUsoEntre(
    DateTime desde,
    DateTime hasta,
  ) async {
    final db = await database;
    final result = await db.query(
      'uso_pantalla',
      where: 'fecha BETWEEN ? AND ?',
      whereArgs: [_soloFecha(desde), _soloFecha(hasta)],
      orderBy: 'fecha ASC',
    );
    return result.map((map) => UsoPantalla.fromMap(map)).toList();
  }

  /// Fecha de la primera recomendación generada, o null si aún no hay ninguna.
  ///
  /// Sirve para verificar si un periodo es realmente línea base: si hay
  /// recomendaciones antes de su fin, el periodo ya es posterior.
  Future<DateTime?> primeraFechaRecomendacion() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT MIN(fecha) AS primera FROM recomendaciones');
    final primera = result.first['primera'] as String?;
    return primera == null ? null : DateTime.tryParse(primera);
  }

  // --- CRUD Uso por aplicación ---
  /// Inserta o actualiza el uso de una aplicación para una fecha y paquete dados.
  /// Evita duplicados: si ya existe un registro para la misma fecha y paquete,
  /// actualiza sus valores en lugar de insertar uno nuevo. La fecha se normaliza
  /// a 'yyyy-MM-dd' para que coincida con el resto del esquema.
  ///
  /// [executor] permite reutilizar la operación dentro de una transacción.
  Future<int> insertarOActualizarAppUso(
    AppUso app, {
    DateTime? fecha,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
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

  /// Persiste el resumen del día y el detalle por aplicación en una sola
  /// transacción: si falla cualquier escritura no queda un resumen parcial.
  Future<void> guardarUsoDelDia(UsoPantalla uso, List<AppUso> apps) async {
    final db = await database;
    await db.transaction((txn) async {
      await insertarOActualizarUsoPantalla(uso, executor: txn);
      for (final app in apps) {
        await insertarOActualizarAppUso(app, fecha: uso.fecha, executor: txn);
      }
    });
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

  /// Recomendaciones con fecha igual o posterior a [desde], de la más reciente
  /// a la más antigua.
  ///
  /// Se usa para el control de duplicados: solo se consulta la ventana de
  /// historial potencialmente relevante, nunca se borra nada.
  Future<List<Recomendacion>> obtenerRecomendacionesDesde(DateTime desde) async {
    final db = await database;
    final result = await db.query(
      'recomendaciones',
      where: 'fecha >= ?',
      whereArgs: [desde.toIso8601String()],
      orderBy: 'fecha DESC',
    );
    return result.map((map) => Recomendacion.fromMap(map)).toList();
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

  /// Guarda o rectifica la valoración de una recomendación.
  ///
  /// [valoracion] es 'util', 'no_util' o null (sin respuesta). Es un UPDATE
  /// sobre el id existente: nunca crea una segunda valoración.
  Future<int> valorarRecomendacion(int id, String? valoracion) async {
    final db = await database;
    return await db.update(
      'recomendaciones',
      {'valoracion': valoracion},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Conteo de valoraciones de todo el historial.
  Future<ResumenValoraciones> obtenerResumenValoraciones() =>
      obtenerResumenValoracionesEntre(DateTime(1970), DateTime(2100));

  /// Resumen de recomendaciones generadas y valoradas en [desde, hasta]
  /// (días locales, ambos incluidos).
  ///
  /// La valoración se cuenta en el periodo en que se generó la recomendación:
  /// no existe fecha de valoración separada.
  Future<ResumenValoraciones> obtenerResumenValoracionesEntre(
    DateTime desde,
    DateTime hasta,
  ) async {
    final db = await database;
    final fin = DateTime(hasta.year, hasta.month, hasta.day + 1);
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS generadas, "
      "SUM(CASE WHEN valoracion IS NOT NULL THEN 1 ELSE 0 END) AS total, "
      "SUM(CASE WHEN valoracion = 'util' THEN 1 ELSE 0 END) AS utiles "
      'FROM recomendaciones WHERE fecha >= ? AND fecha < ?',
      [_soloFecha(desde), _soloFecha(fin)],
    );
    final fila = result.first;
    final total = (fila['total'] as int?) ?? 0;
    final utiles = (fila['utiles'] as int?) ?? 0;
    return ResumenValoraciones(
      total: total,
      utiles: utiles,
      noUtiles: total - utiles,
      generadas: (fila['generadas'] as int?) ?? 0,
    );
  }

  // --- CRUD Horarios ---
  /// Inserta un horario nuevo (sin `id`) o actualiza el existente por su `id`.
  ///
  /// Ya **no** se agrupa por `tipo`: pueden coexistir varios horarios de la
  /// misma categoría (p. ej. dos turnos laborales distintos).
  Future<int> guardarHorario(Horario horario) async {
    final db = await database;
    final valores = sinId(horario.toMap());
    final id = horario.id;
    if (id == null) {
      return await db.insert('horarios', valores);
    }
    return await db.update('horarios', valores, where: 'id = ?', whereArgs: [id]);
  }

  /// Horarios configurados, ordenados por hora de inicio.
  ///
  /// Con [soloActivos] se excluyen los desactivados: es lo que deben usar el
  /// análisis y el motor de recomendaciones.
  Future<List<Horario>> obtenerHorarios({bool soloActivos = false}) async {
    final db = await database;
    final result = await db.query(
      'horarios',
      where: soloActivos ? 'activo = 1' : null,
      orderBy: 'horaInicio ASC, minutoInicio ASC, id ASC',
    );
    return result.map((map) => Horario.fromMap(map)).toList();
  }

  /// Primer horario de la categoría [tipo] (compatibilidad con los presets).
  Future<Horario?> obtenerHorarioPorTipo(
    String tipo, {
    bool soloActivos = false,
  }) async {
    final db = await database;
    final result = await db.query(
      'horarios',
      where: soloActivos ? 'tipo = ? AND activo = 1' : 'tipo = ?',
      whereArgs: [tipo],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return Horario.fromMap(result.first);
  }

  /// Activa o desactiva un horario sin borrarlo del historial.
  Future<int> cambiarActivoHorario(int id, bool activo) async {
    final db = await database;
    return await db.update(
      'horarios',
      {'activo': activo ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> eliminarHorario(int id) async {
    final db = await database;
    return await db.delete('horarios', where: 'id = ?', whereArgs: [id]);
  }

  // --- Perfil local ---
  /// Perfil guardado, o null si el usuario aún no configuró nada.
  Future<Perfil?> obtenerPerfil() async {
    final db = await database;
    final result = await db.query('perfil', where: 'id = 1');
    if (result.isEmpty) return null;
    return Perfil.fromMap(result.first);
  }

  /// Guarda o reemplaza el perfil único. No crea filas duplicadas.
  Future<int> guardarPerfil(Perfil perfil) async {
    final db = await database;
    final valores = perfil.toMap();
    final existing = await db.query('perfil', where: 'id = 1');
    if (existing.isEmpty) {
      return await db.insert('perfil', {'id': 1, ...valores});
    }
    return await db.update('perfil', valores, where: 'id = 1');
  }

  /// Preferencias de apariencia guardadas, o (null, null) si no hay.
  Future<({String? modo, String? paleta})> obtenerApariencia() async {
    final db = await database;
    final result = await db.query('perfil',
        columns: ['temaModo', 'paleta'], where: 'id = 1');
    if (result.isEmpty) return (modo: null, paleta: null);
    return (
      modo: result.first['temaModo'] as String?,
      paleta: result.first['paleta'] as String?,
    );
  }

  /// Guarda solo las preferencias de apariencia sin tocar nombre, identidad
  /// ni autodescripción. Crea la fila si aún no existe.
  Future<void> guardarApariencia({String? modo, String? paleta}) async {
    final db = await database;
    await db.insert('perfil', {'id': 1},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.update(
      'perfil',
      {'temaModo': modo, 'paleta': paleta},
      where: 'id = 1',
    );
  }

  // --- Utilidades ---
  /// Normaliza una fecha a 'yyyy-MM-dd', formato usado en las columnas de fecha.
  static String _soloFecha(DateTime fecha) =>
      fecha.toIso8601String().substring(0, 10);

  /// Devuelve una copia de [mapa] sin la clave `id` (el original no se modifica).
  ///
  /// Es necesario en todo `UPDATE` que parta de un `toMap()` de un modelo
  /// recién construido: al no tener `id`, el mapa lo envía como `null` y
  /// `SET id = NULL` sobre una columna `INTEGER PRIMARY KEY` hace que SQLite
  /// devuelva `SQLITE_MISMATCH (code 20)`.
  static Map<String, dynamic> sinId(Map<String, dynamic> mapa) {
    final copia = Map<String, dynamic>.from(mapa);
    copia.remove('id');
    return copia;
  }

  // --- Cerrar base de datos ---
  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
