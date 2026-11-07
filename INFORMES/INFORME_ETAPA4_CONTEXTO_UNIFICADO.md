# 📄 Informe — Etapa 4: Contexto unificado para las recomendaciones

**Rama:** `feature/Motor-Recomendaciones-Adaptado`
**Alcance:** construir una capa de contexto única para el motor, separando la
adquisición de datos de la lógica de decisión.
**Fecha:** Agosto 2026

---

## 🎯 Objetivo

Evitar que `MotorRecomendaciones` consulte directamente varias fuentes y mezcle
acceso a datos con reglas, reuniendo el estado relevante del usuario en un solo
objeto: `ContextoRecomendacion`.

---

## ✅ Cambios realizados

| # | Archivo | Cambio |
|---|---------|--------|
| 1 | `lib/models/contexto_recomendacion.dart` | **Nuevo**: modelo del contexto + clasificación de apps distractoras. |
| 2 | `lib/services/contexto_recomendacion_service.dart` | **Nuevo**: construye el contexto centralizando las consultas. |
| 3 | `lib/services/motor_recomendaciones.dart` | Consume el contexto; se eliminó el acceso directo a `DatabaseHelper`/`UsoPantallaService` para datos. |
| 4 | `lib/database/database_helper.dart` | `obtenerUsoPorFecha(DateTime)`; `obtenerUsoHoy()` delega en él. |
| 5 | `lib/services/uso_pantalla_service.dart` | `tienePermisoUso()` (comprueba sin solicitar); `solicitarPermisoUso()` lo reutiliza. |
| 6 | `test/contexto_recomendacion_test.dart` | **12 pruebas nuevas** del modelo y la clasificación. |

### Modelo `ContextoRecomendacion`

Contenedor **inmutable de datos**, sin reglas de negocio. Campos:

| Campo | Tipo |
|-------|------|
| `momento` | `DateTime` |
| `horarios` | `List<Horario>` (todos los configurados) |
| `horarioActivo` | `Horario?` |
| `tareaActiva` | `Tarea?` |
| `tareasPendientes` | `List<Tarea>` |
| `tareasAltaPrioridadPendientes` | `List<Tarea>` |
| `tiempoTotalPantallaMinutos` | `int` |
| `hayDatosUsoPantalla` | `bool` |
| `permisoUsoDisponible` | `bool` |
| `appsMasUtilizadas` | `List<AppUso>` |

Derivados como **getters** (no pueden quedar inconsistentes): `tipoHorario`
(`laboral` / `academico` / `ninguno`), `tipoHorarioTexto`, `hayHorarioActivo`,
`hayTareaActiva`, `tareasPendientesTotal`, `tareasAltaPrioridadTotal`,
`appsDistractoras`, `minutosAppsDistractoras`, `appDistractoraPrincipal`,
`hayAppsDistractoras`.

La clasificación vive en `static bool esPaqueteDistractor(String)` con una lista
`paquetesDistractores` configurable, comparando **por prefijo** (`com.instagram`
clasifica también `com.instagram.android`).

### `ContextoRecomendacionService`

Responsabilidad única: **adquirir y normalizar**. Una sola consulta por fuente
(punto 9):

| Fuente | Consulta | Derivados en memoria |
|--------|----------|----------------------|
| `DatabaseHelper` | `obtenerTareas(completada: false)` | pendientes, alta prioridad, tarea activa |
| `DatabaseHelper` | `obtenerHorarios()` | horario activo (`contieneDateTime`) |
| `DatabaseHelper` | `obtenerUsoPorFecha(momento)` | total de pantalla |
| `UsoPantallaService` | `obtenerTopAppsDelDia(top)` | apps y distractoras |

**Permisos UsageStats:** primero se comprueba con `tienePermisoUso()` (sin abrir
Ajustes). Si no hay permiso, o si la consulta falla, el contexto **no lanza
excepción**: usa como respaldo los datos ya persistidos
(`obtenerAppsUsoDelDia`) y, si tampoco hay, deja la lista vacía. El estado se
refleja en `permisoUsoDisponible`.

**Sin reglas:** el servicio no decide nada; no genera recomendaciones.

### Motor

`evaluarYGenerar({ContextoRecomendacion? contexto})` — si recibe un contexto lo
reutiliza; si no, lo construye con el servicio. Las **6 reglas se mantienen
idénticas**:

| Regla | Antes | Ahora |
|-------|-------|-------|
| 1 | `usoHoy != null && usoHoy.tiempoTotalMinutos > 240` | `minutosUsoHoy != null && minutosUsoHoy > 240` |
| 2 | `tareas.length > 5` | `ctx.tareasPendientes.length > 5` |
| 3 | `for (app in usoService.obtenerTopAppsDelDia())` | `for (app in ctx.appsMasUtilizadas)` |
| 4 | `tareas.where(prioridad alta && !completada)` | `ctx.tareasAltaPrioridadPendientes` |
| 5 | `usoHoy != null && ... > 180 && tareas.length > 3` | igual, con `minutosUsoHoy` |
| 6 | `await _db.obtenerHorarios()` | `ctx.horarios` |

La lista `redesSociales` de la Regla 3 se mantiene **igual** dentro del motor
(la clasificación del contexto es una capacidad nueva, no un cambio de regla).
El motor conserva `_db` solo para `insertarRecomendacion`.

---

## 🧪 Verificación

```
dart analyze lib test   →  No issues found!
flutter test            →  00:00 +48: All tests passed!  (12 nuevas + 36 previas)
```

Cubre: contexto vacío coherente, coincidencia exacta/por prefijo/insensible a
mayúsculas, no-falsos-positivos (`com.instagramx`), suma de minutos
distractores, app distractora principal, ausencia de distractoras, tipo de
horario laboral/académico/ninguno y conteos de tareas.

---

## ⚠️ Notas

1. **Ventana de apps = 5.** El contexto pide las 5 principales por defecto para
   **reproducir exactamente** el comportamiento previo del motor. Es
   parametrizable (`topApps`), pero ampliarlo cambiaría cuándo se dispara la
   Regla 3; eso corresponde a la etapa de la matriz definitiva de reglas.
2. **Dependencia restante del motor:** la Regla 6 sigue usando
   `AnalisisHorarioService.analizar()` para el pico horario, porque ese análisis
   no forma parte del contexto especificado. Es la única fuente que el motor
   todavía consulta directamente.
3. **Consulta duplicada menor:** `AnalisisHorarioService.analizar()` vuelve a
   leer los horarios internamente. Es previo a esta etapa y se puede eliminar
   cuando la Regla 6 se reformule.
4. **Tarea activa:** se calcula sobre tareas **pendientes** (una tarea completada
   no se considera "activa"). Evita una consulta adicional.
5. **Entorno:** `dart analyze` y `flutter test` necesitan lanzar procesos hijos,
   denegados por el sandbox → ejecutados con acceso ampliado.
6. El aviso `databaseFactory not initialized` del `widget_test` es preexistente.

---

## 📌 Criterios de aceptación

- [x] Un único objeto representa el estado contextual del usuario.
- [x] El contexto puede indicar horario activo.
- [x] El contexto puede indicar tarea activa.
- [x] Incluye las aplicaciones utilizadas.
- [x] No mezcla adquisición de datos con reglas de decisión.
- [x] `dart analyze` / tests correctos.

---

## ⏭️ Siguiente etapa (no iniciada)

- [ ] Definir la matriz definitiva de reglas sobre el contexto.
- [ ] Incorporar el pico horario al contexto para eliminar la última consulta
      directa del motor.
- [ ] Probar en teléfono físico con datos reales.
