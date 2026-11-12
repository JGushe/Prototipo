# 📄 Informe — Etapa 9: Horarios múltiples con categoría y activación

**Rama:** `feature/Monitoreo-Uso-Horarios`
**Objetivo:** permitir crear tantos horarios como se necesiten (además de los
preestablecidos), configurarlos de lunes a domingo dentro de las 24 horas y
activarlos o desactivarlos individualmente.
**Fecha:** Septiembre 2026

---

## 1. Archivos modificados

| Archivo | Cambio |
|---|---|
| `lib/models/horario.dart` | Campos `nombre` y `activo`; constantes de categoría; `copyWith`; `nombreVisible`; `diasTexto`; `tipoTexto` cubre 3 categorías; `fromMap` tolera filas antiguas. |
| `lib/database/database_helper.dart` | **Migración v6**; `guardarHorario` por `id`; `obtenerHorarios({soloActivos})`; `cambiarActivoHorario()`; `obtenerHorarioPorTipo(..., soloActivos)`. |
| `lib/services/contexto_recomendacion_service.dart` | Solo horarios **activos**; nuevo `ordenarPorPrecedencia()`. |
| `lib/services/analisis_horario_service.dart` | `horarioActivoEn()` y `analizar()` usan solo horarios activos. |
| `lib/services/reglas/reglas_por_defecto.dart` | R8 usa `nombreVisible` y distingue la categoría personalizada. |
| `lib/screens/configuracion_screen.dart` | Reescrita: presets + lista completa, añadir, editar, activar/desactivar, eliminar, selector de días. |
| `test/horarios_multiples_test.dart` | **Nuevo**: 12 pruebas. |

## 2. El problema que se resolvió

`guardarHorario()` hacía *upsert* **por `tipo`**:

```sql
SELECT * FROM horarios WHERE tipo = 'laboral'   -- si existía…
UPDATE horarios SET ... WHERE tipo = 'laboral'  -- …sobrescribía
```

Es decir, **solo podía existir un horario por categoría**: un segundo horario
laboral pisaba al primero y `obtenerHorarioPorTipo()` devolvía solo uno. Ahora el
guardado es **por `id`** (insert si no hay id, update por id si lo hay), de modo
que pueden coexistir varios horarios de la misma categoría.

## 3. Compatibilidad y migración

**Migración v6, aditiva y no destructiva:**

```sql
ALTER TABLE horarios ADD COLUMN nombre TEXT;
ALTER TABLE horarios ADD COLUMN activo INTEGER NOT NULL DEFAULT 1;
```

- Los horarios existentes quedan **sin nombre** (se muestra su categoría) y
  **activos** → no se pierde funcionalidad ni se cambia el comportamiento actual.
- `fromMap` asume `activo = 1` cuando la columna no existe, así que los mapas
  antiguos siguen funcionando.
- No se borra ni se recrea ninguna tabla. El teléfono (v5) migrará solo al
  abrir la app actualizada.
- `obtenerHorarioPorTipo()` se conserva (compatibilidad con los presets).

## 4. Cómo funciona ahora

**Modelo.** `tipo` es la **categoría** (`laboral` | `academico` | `personalizado`)
y `nombre` es la etiqueta visible ("Turno noche", "Gimnasio"). `activo=false`
significa que el horario se conserva pero **no participa en nada**.

**Interfaz (Configuración).**
- Arriba, los dos accesos rápidos de siempre: *Horario laboral* y *Horario
  académico*.
- Debajo, **"Todos los horarios"** con contador `n/20`, y por cada horario:
  icono y color por categoría, `nombreVisible`, `categoría · rango · días`,
  **interruptor activo/inactivo** y menú *Editar / Eliminar* (con confirmación).
- Botón flotante **"Agregar horario"**.

**Diálogo de alta/edición.**
- Nombre opcional, **categoría** seleccionable y una nota que explica el efecto:
  las categorías laboral/académico activan las reglas de trabajo/estudio; la
  personalizada solo aporta contexto.
- Hora de inicio y de fin con selector de 24 h.
- **Días de lunes a domingo** con chips (L M X J V S D) y atajos **L-V**, **S-D**,
  **Todos**.
- Validaciones: al menos un día y hora de inicio ≠ hora de fin.
- Aviso informativo (no bloqueante) cuando el fin es anterior al inicio:
  *"cruza la medianoche (termina al día siguiente)"*.
- Límite de **20 horarios** para no degradar el análisis.

**Motor y análisis.**
- `ContextoRecomendacionService` pide **solo horarios activos**; los desactivados
  no entran en el contexto, ni en R8, ni en el cálculo de uso en horarios.
- Cuando varios horarios activos se solapan, `ordenarPorPrecedencia()` decide
  cuál es `horarioActivo`: primero laboral/académico, después la hora de inicio
  más temprana y, ante empate, el `id` (determinista).
- Las categorías **laboral** y **académico** (incluidas las creadas por el
  usuario) siguen alimentando `enHorarioLaboral` / `enHorarioAcademico` y las
  reglas R1/R2. La categoría **personalizada** suma a `enHorariosConfigurados`
  (contexto) sin disparar esas reglas.

## 5. Verificación

```
dart analyze lib test   →  No issues found!
flutter test            →  00:00 +169: All tests passed!   (12 nuevas)
```

Las 12 pruebas nuevas cubren: serialización de `nombre`/`activo`, fila anterior a
la migración (queda activa), `nombreVisible`, `tipoTexto` para las 3 categorías,
`diasTexto` (L-V, S-D, todos, días sueltos), `copyWith`, precedencia de horarios
(tres casos), horario personalizado que cuenta como contexto pero no como
laboral, horario laboral que sí suma, y varios horarios de la misma categoría sin
duplicar minutos.

**Sin regresiones**: las 157 pruebas anteriores siguen pasando.

## 6. Limitaciones y pendientes

1. **El CRUD real contra SQLite no se pudo probar aquí**: requiere el plugin de
   base de datos, así que la migración v6 y el guardado por `id` se verifican al
   ejecutar en el dispositivo.
2. **Nada impide dos horarios solapados** de la misma categoría: se permiten a
   propósito (turnos rotativos). La precedencia resuelve cuál se considera activo
   y el análisis **no duplica** minutos (unión de intervalos).
3. **Sin reordenación manual ni prioridad explícita** (Opción C del análisis): la
   precedencia es automática. Si más adelante hace falta control fino, se puede
   añadir un campo `prioridad` sin romper nada.
4. **Tareas planificadas fuera de horario** siguen contando en
   `duranteTareaPlanificada`, independientemente de los horarios creados.

## ⏭️ Sugerencias para después

- [ ] Probar en el dispositivo: migración v5→v6, crear 2 horarios "laboral",
      desactivar uno y comprobar que el análisis lo ignora.
- [ ] Indicar en la lista de horarios cuánto uso cae dentro de cada uno (ya está
      disponible en `usosContextuales`).
- [ ] Añadir prioridad manual si se necesitan reglas de solape más finas.
