# 📄 Informe — Etapa 2: Contexto temporal de las tareas

**Rama:** `feature/Motor-Recomendaciones-Adaptado`
**Alcance:** incorporar planificación temporal a las tareas para que el motor
pueda relacionar una recomendación con una actividad planificada.
**Fecha:** Agosto 2026

---

## 🎯 Objetivo

Añadir a `Tarea` la información necesaria para saber **qué actividad estaba
planificada durante un periodo concreto**, sin tocar todavía el comportamiento
del motor de recomendaciones.

---

## ✅ Cambios realizados

| # | Archivo | Cambio |
|---|---------|--------|
| 1 | `lib/models/tarea.dart` | Campos opcionales `fechaPlanificada`, `horaInicioPlanificada`, `horaFinPlanificada` + `toMap`/`fromMap`/`copyWith`, getters de consulta y validación. |
| 2 | `lib/database/database_helper.dart` | Migración a **v3**, columnas nuevas en `_createDB` y 3 métodos de consulta. |
| 3 | `lib/screens/tareas_screen.dart` | El diálogo permite definir fecha, hora de inicio y hora de fin, con validación; la lista muestra el plan. |
| 4 | `test/tarea_planificacion_test.dart` | 16 pruebas nuevas de la lógica de planificación. |

### Modelo `Tarea`

- `fechaPlanificada` (`DateTime?`) — día planificado.
- `horaInicioPlanificada` / `horaFinPlanificada` (`String?`, formato `'HH:mm'`).
  Se eligió texto `HH:mm` (y no `DateTime`) porque el modelo es Dart puro —sin
  importar Flutter— y porque el formato con ceros a la izquierda permite
  comparar horas directamente en SQLite.
- **`fechaVencimiento` se mantiene como concepto independiente**: sigue siendo
  el recordatorio de entrega y lo usa `NotificacionService` sin cambios.
- Getters: `inicioPlanificado`, `finPlanificado`, `tieneFechaPlanificada`,
  `tieneRangoHorario`, `cruzaMedianoche`.
- `estaPlanificadaEn(DateTime momento)` concentra la lógica temporal:
  sin fecha → nunca activa; solo fecha → todo el día; con franja → `[inicio, fin)`;
  si cruza medianoche, el fin se desplaza al día siguiente.
- `Tarea.rangoHorarioValido(...)` valida `horaInicio < horaFin`. El caso especial
  de franja que cruza la medianoche es **opt-in** (`permitirCruceMedianoche`).

### Migración SQLite (v2 → v3)

```sql
ALTER TABLE tareas ADD COLUMN fechaPlanificada TEXT;
ALTER TABLE tareas ADD COLUMN horaInicioPlanificada TEXT;
ALTER TABLE tareas ADD COLUMN horaFinPlanificada TEXT;
```

Las tareas existentes quedan con planificación `NULL`, por lo que **siguen
funcionando igual**. La migración solo añade columnas: no se pierden datos.

### Consultas añadidas a `DatabaseHelper`

- `obtenerTareasPlanificadasDelDia(DateTime, {completada})` — plan del día.
- `obtenerTareasPlanificadasEn(DateTime, {completada})` — tareas activas en un
  instante. Consulta el día indicado **y el anterior** para cubrir las franjas
  que cruzan medianoche, y filtra con `estaPlanificadaEn`.
- `obtenerTareaPlanificadaEn(DateTime)` — la primera activa, o `null`.

### Interfaz

El diálogo de creación/edición incorpora una sección **"Planificación
(opcional)"** con fecha, hora de inicio y hora de fin (con opción de quitar la
planificación). Validaciones mostradas en el propio diálogo:

- horario sin fecha → *"Selecciona una fecha planificada para el horario."*
- solo una de las dos horas → *"Define la hora de inicio y la hora de fin."*
- `inicio >= fin` → *"La hora de inicio debe ser anterior a la hora de fin."*

La tarjeta de cada tarea muestra `Plan: dd/MM · HH:mm–HH:mm` cuando existe.

---

## 🧪 Verificación

```
dart analyze lib test   →  No issues found!
flutter test            →  00:00 +17: All tests passed!  (16 nuevas + 1 existente)
```

Las pruebas cubren: compatibilidad con filas antiguas sin planificación,
serialización `toMap`/`fromMap`, `copyWith`, validación de franja, y
`estaPlanificadaEn` (franja normal, solo fecha, cruce de medianoche y tarea sin
planificación).

---

## ⚠️ Notas

1. **Entorno:** `dart analyze` y `flutter test` necesitan lanzar procesos hijos
   (servidor de análisis / `flutter_tester`); el sandbox confinado los deniega,
   por lo que se ejecutaron con acceso ampliado.
2. **Cruce de medianoche:** el modelo y la base de datos lo soportan, pero la
   interfaz todavía valida el caso estricto (`inicio < fin`); exponerlo en la UI
   no era parte de esta etapa.
3. **`copyWith`** conserva el patrón `??` del resto de campos: no permite volver
   un campo a `null`. El diálogo construye `Tarea` directamente, así que quitar
   la planificación sí la borra en la base de datos.
4. El aviso `databaseFactory not initialized` del `widget_test` es preexistente
   y no afecta al resultado.

---

## 📌 Criterios de aceptación

- [x] Una tarea puede tener un periodo planificado.
- [x] Las tareas antiguas siguen funcionando.
- [x] SQLite se actualiza correctamente (v3 con migración no destructiva).
- [x] Es posible consultar qué tarea está planificada para un `DateTime`.
- [x] La aplicación compila (`dart analyze` sin issues) y las pruebas pasan.

---

## ⏭️ Siguiente etapa (no iniciada)

- [ ] Usar la tarea planificada como contexto de las reglas del motor.
- [ ] Exponer en la interfaz el caso especial de franja que cruza medianoche.
- [ ] Probar en teléfono físico con datos reales.
