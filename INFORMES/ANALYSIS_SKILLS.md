# Análisis del Proyecto para Integración de Skills

## Resumen General

El proyecto **"prototipo_tesis"** es una aplicación Flutter para Android que monitorea el uso de pantalla, gestiona tareas y genera recomendaciones contextuales. Tiene un motor de reglas bien estructurado pero presenta varios puntos clave que deben revisarse para futuras integraciones.

---

## 1. Arquitectura Actual

### Capas bien definidas:
- **Models** (`lib/models/`)  
- **Services** (`lib/services/`)  
- **Database** (`lib/database/`)  
- **Screens** (`lib/screens/`)  

### Motor de recomendaciones (`lib/services/motor_recomendaciones.dart`)
- ✅ Muy bien estructurado: separa contexto → evaluación → cooldown → creación → persistencia
- ✅ Las reglas son **datos** (`ReglaRecomendacion`), no código disperso
- Reglas actuales: R1-R8 definidas en `reglas_por_defecto.dart`

---

## 2. Puntos Clave a Cambiar

### ⚠️ CRÍTICO: Versionamiento de base de datos inconsistente

**Archivo:** `lib/database/database_helper.dart:26`

```dart
version: 6
```

La versión actual es **6**, con migraciones hasta `oldVersion < 6`. Si agregas un nuevo campo a `Recomendacion` o cualquier tabla, debes:
1. Incrementar a **version: 7**
2. Agregar un bloque `if (oldVersion < 7)` en `_upgradeDB`

**Riesgo:** Si añades campos a modelos como `Recomendacion` o `Horario` sin migrar, la app puede crashear en dispositivos existentes.

---

### ⚠️ CRÍTICO: No hay esquema de versionamiento de skills

No existe un mecanismo para:
- Registrar skills activos
- Gestionar permisos de skills
- Habilitar/deshabilitar skills individualmente
- Definir prioridades entre skills

**Recomendación:** Crear una tabla `skills` en la base de datos:
```sql
CREATE TABLE skills (
  id TEXT PRIMARY KEY,
  nombre TEXT NOT NULL,
  habilitado INTEGER NOT NULL DEFAULT 1,
  prioridad INTEGER NOT NULL DEFAULT 0,
  categoria TEXT,
  schema_version INTEGER NOT NULL DEFAULT 1
);
```

---

### ⚠️ Alto: Acoplamiento manual en el motor de recomendaciones

**Archivo:** `lib/services/reglas/reglas_por_defecto.dart:22-34`

```dart
List<ReglaRecomendacion> crearReglasPorDefecto(...) {
  return [
    _r3(c), _r1(c), _r2(c), _r7(c), _r8(c), _r6(c), _r5(c), _r4(c),
  ];
}
```

Las reglas se agregan **manualmente** a mano. Para skills, esto debería ser **dinámico**:
- Un `SkillRegistry` que registre reglas desde skills cargados
- Cada skill proporciona su lista de reglas
- El motor itera sobre el registro en lugar de una lista fija

---

### ⚠️ Alto: No hay sistema de plugins/extensibilidad

El motor de recomendaciones es cerrado. No hay:
- Interface para registrar skills dinámicamente
- Sistema de eventos/hooks (antes/después de evaluar, al insertar, etc.)
- Mecanismo para que un skill extienda `ContextoRecomendacionService`

**Archivo clave:** `lib/services/motor_recomendaciones.dart`

El constructor acepta `reglas` como parámetro, pero no hay un registro centralizado.

---

### ⚠️ Alto: La tabla `app_uso` carece de índices y restricciones

**Archivo:** `lib/database/database_helper.dart:107-117`

```sql
CREATE TABLE app_uso (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  fecha TEXT NOT NULL,
  nombrePaquete TEXT NOT NULL,
  ...
);
```

Falta:
- `UNIQUE(fecha, nombrePaquete)` — aunque `insertarOActualizarAppUso` intenta manejarlo con query manual
- Índice en `nombrePaquete` para búsquedas rápidas

---

### ⚠️ Alto: Hardcodeo de paquetes distractores

**Archivo:** `lib/models/contexto_recomendacion.dart:22-33`

```dart
static const List<String> paquetesDistractoresPorDefecto = [
  'com.facebook',
  'com.instagram',
  'com.twitter',
  ...
];
```

Esto debería ser configurable desde un skill de configuración de distractores, no hardcodeado en el modelo.

---

### ⚠️ Medio: No hay pruebas para el motor completo con WorkManager

**Archivo:** `lib/services/monitoreo_segundo_plano_service.dart`

El `_cicloDeMonitoreo()` ejecuta el motor en background, pero:
- No hay tests que verifiquen la integración completa en background
- El catch silencioso (`catch (_) {}`) en `_cicloDeMonitoreo` esconde errores

---

### ⚠️ Medio: AndroidManifest.xml usa `requestLegacyExternalStorage="true"`

**Archivo:** `android/app/src/main/AndroidManifest.xml:28`

```xml
android:requestLegacyExternalStorage="true"
```

Esto es obsoleto en Android 11+. No bloqueará la funcionalidad actual, pero es una mala práctica.

---

### ⚠️ Medio: `numeroAperturas` siempre es 1

**Archivo:** `lib/services/uso_pantalla_service.dart:80`

```dart
apps.add(AppUso(
  ...
  numeroAperturas: 1,  // Hardcodeado
));
```

Debería usar `stat.totalTimeInForegroundMs` o contar eventos reales.

---

## 3. Oportunidades para Skills

### Entry points naturales para integración:

| Entry Point | Archivo | Propósito |
|---|---|---|
| `MotorRecomendaciones` constructor | `lib/services/motor_recomendaciones.dart:39-56` | Inyección de reglas y servicios |
| `crearReglasPorDefecto` | `lib/services/reglas/reglas_por_defecto.dart:22` | Registro de reglas |
| `ConfiguracionMotor` | `lib/services/reglas/configuracion_motor.dart:9` | Umbrales configurables |
| `DatabaseHelper` | `lib/database/database_helper.dart:8` | Persistencia de skills |
| `monitoreoCallbackDispatcher` | `lib/services/monitoreo_segundo_plano_service.dart:82` | Ejecución en background |
| `DashboardScreen` / `RecomendacionesScreen` | `lib/screens/` | UI de skills |

---

## 4. Recomendaciones de Implementación

### Paso 1: Sistema de registro de skills
Crear `lib/services/skills/skill_registry.dart`:
```dart
abstract class Skill {
  String get id;
  String get nombre;
  String get descripcion;
  List<ReglaRecomendacion> reglas(ConfiguracionMotor config);
  Future<void> inicializar();
  void dispose() {}
}

class SkillRegistry {
  final List<Skill> _skills = [];
  void registrar(Skill skill) => _skills.add(skill);
  List<ReglaRecomendacion> todasReglas(ConfiguracionMotor config) =>
    _skills.expand((s) => s.reglas(config)).toList();
}
```

### Paso 2: Tabla de skills en la base de datos
Agregar a `DatabaseHelper._createDB` y migración v7.

### Paso 3: Motor dinámico
Modificar `MotorRecomendaciones` para aceptar `SkillRegistry` en lugar de `List<ReglaRecomendacion>`.

### Paso 4: Configuración de distractores como skill
Mover `paquetesDistractoresPorDefecto` a un skill configurable.

---

## 5. Estado del Proyecto

| Aspecto | Estado |
|---|---|
| Tests unitarios | ✅ Buenos (reglas, motor, cooldown, horarios, base de datos) |
| Arquitectura | ✅ Muy bien separada (models → services → database → screens) |
| Documentación | ✅ Comentarios claros en cada archivo |
| Versionamiento DB | ⚠️ En v6, debe migrar a v7 con tabla de skills |
| Extensibilidad | ⚠️ Cerrado, requiere refactoreo para skills dinámicos |

---

## 6. Conclusión

El proyecto tiene una base sólida y bien estructurada, pero necesita:
1. Un sistema de registro de skills (`SkillRegistry`)
2. Una tabla `skills` en la base de datos (migración v7)
3. Conectar el motor al registro en lugar de a una lista fija
4. Hacer configurable la lista de paquetes distractores

Esto permitiría cargar skills de forma dinámica y extender la funcionalidad sin modificar el núcleo del motor.