# 📄 Informe — Etapa 6: Control de duplicados y frecuencia

**Rama:** `feature/Motor-Recomendaciones-Adaptado`
**Alcance:** evitar que el motor vuelva a guardar la misma recomendación en cada
ejecución, mediante una clave de equivalencia y un cooldown por regla.
**Fecha:** Agosto 2026

---

## 🎯 Objetivo

`evaluarYGenerar()` insertaba **todas** las recomendaciones generadas. Ahora,
antes de insertar, se comprueba si ya existe una equivalente dentro de su
ventana de cooldown. El historial **nunca se borra**.

---

## ✅ Cambios realizados

| # | Archivo | Cambio |
|---|---------|--------|
| 1 | `lib/services/reglas/politica_cooldown.dart` | **Nuevo**: `PoliticaCooldown` (pura) y `DescarteCooldown`. |
| 2 | `lib/services/reglas/resultado_evaluacion.dart` | **Nuevo**: `ResultadoEvaluacion` (generadas / descartadas / evaluadas). |
| 3 | `lib/services/reglas/regla_recomendacion.dart` | `AmbitoCooldown`, `ambito`, `claveEquivalencia()`, `inicioVentanaCooldown()`. |
| 4 | `lib/services/reglas/reglas_por_defecto.dart` | Ámbito asignado a cada regla. |
| 5 | `lib/models/recomendacion.dart` | Campo `clave`. |
| 6 | `lib/services/reglas/creador_recomendaciones.dart` | Sella la `clave` en cada recomendación. |
| 7 | `lib/database/database_helper.dart` | Migración **v5** (`clave`) + `obtenerRecomendacionesDesde()`. |
| 8 | `lib/services/motor_recomendaciones.dart` | Deduplicación antes de insertar, log de descartes y `ejecutar()`. |
| 9 | `test/cooldown_test.dart` | **23 pruebas nuevas**. |

### Identificación de una recomendación equivalente

Cada regla define un **ámbito** que determina qué recomendaciones suyas son
equivalentes. La clave se compone del identificador de la regla más el contexto:

```
R1|horario:2026-08-24|academico:19:00-21:00
R5|dia:2026-08-24
R3|regla
```

Como la clave incluye el `id`, **reglas distintas nunca se bloquean entre sí**.

### Los tres niveles pedidos (tarea 5)

| Ámbito | Significado | Reglas | Ventana |
|--------|-------------|--------|---------|
| `dia` | Una vez por **día natural** | R5 | inicio del día |
| `horario` | Una vez por **bloque de horario** dentro del día | R1, R2 | inicio del día (la clave ya distingue el bloque) |
| `regla` | Sujeta al **cooldown temporal** de la regla | R3, R4, R6, R7, R8 | `momento − cooldown` |

Cooldowns por regla (en `ConfiguracionMotor`): R3 90 min, R4 12 h, R6 6 h,
R7 12 h, R8 12 h. **Cada regla puede tener un cooldown diferente.**

### Flujo del motor

```
1. Contexto            → ContextoRecomendacionService
2. Evaluación          → EvaluadorReglas
3. Historial relevante → UNA consulta acotada a la ventana más antigua posible
4. Por cada regla que se cumple:
      ¿equivalente dentro de la ventana?  → descartar y registrar en log
      si no                                → crear, insertar, añadir al historial
5. ResultadoEvaluacion { generadas, descartadas, reglasEvaluadas }
```

- **Sin borrados**: no existe ninguna operación de `DELETE` sobre
  `recomendaciones`; el historial queda íntegro para la evaluación de la tesis.
- **Una sola consulta** de historial por ejecución, no una por regla.
- **Determinista**: el resultado depende solo del contexto y del historial; no
  hay aleatoriedad ni relojes ocultos.

### Log en modo desarrollo (tarea 8)

Con `kDebugMode`, cada descarte se registra con su motivo:

```
[MotorRecomendaciones] Regla R3 descartada: ya existe una recomendación
equivalente (clave "R3|regla") del 2026-08-24T09:30:00.000, dentro de la
ventana iniciada el 2026-08-24T08:30:00.000
```

### Compatibilidad

- `evaluarYGenerar()` **se conserva** con su firma original (devuelve
  `List<Recomendacion>`); ahora delega en `ejecutar()`, que devuelve el detalle.
- **Migración v5** no destructiva. Las recomendaciones anteriores tienen `clave`
  nula: se conservan en el historial pero no bloquean a las nuevas.
- **La UI no se modificó** en esta etapa.

---

## 🧪 Verificación

```
dart analyze lib test   →  No issues found!
flutter test            →  00:00 +109: All tests passed!  (23 nuevas + 86 previas)
```

`test/cooldown_test.dart` cubre los casos exigidos:

| Caso pedido | Prueba |
|-------------|--------|
| Primera ejecución | `primera ejecución: sin historial se genera` / `la primera ejecución genera y la segunda no duplica` |
| Segunda ejecución dentro del cooldown | `segunda ejecución dentro del cooldown se descarta` |
| Ejecución después del cooldown | `ejecución después del cooldown se genera` / `pasado el cooldown la misma regla vuelve a generar` |
| Reglas diferentes | `una recomendación de R4 no bloquea a R5` / `reglas distintas producen claves distintas` |
| Contextos diferentes | `un horario distinto no bloquea`, `el mismo horario en otro día no bloquea`, `al día siguiente vuelve a generarse` |

Además: límite exacto del cooldown, elección de la recomendación equivalente más
reciente, historial antiguo sin clave, inmutabilidad del historial y claves por
ámbito.

---

## ⚠️ Notas y decisiones

1. **En los ámbitos `dia` y `horario` la ventana es el día natural**, no el
   `cooldown` en minutos: la clave ya acota el periodo (así R5 no se repite de
   mañana y tarde el mismo día). El `cooldown` temporal aplica al ámbito `regla`.
   Está documentado en el propio campo.
2. **El límite del cooldown es inclusivo**: una recomendación exactamente a
   `momento − cooldown` todavía bloquea. Hay una prueba que lo fija.
3. **No se implementó deduplicación por contenido.** Dos ejecuciones con la
   misma regla, mismo ámbito pero distinto mensaje (p. ej. distinta app
   distractora) se consideran duplicadas. Es la interpretación de «equivalente»
   por regla + contexto.
4. **Las notificaciones siguen sin tocarse**, tal como se pidió.
5. **Entorno:** `dart analyze` y `flutter test` requieren acceso ampliado por el
   spawn de procesos hijos.

---

## 📌 Criterios de aceptación

- [x] Ejecutar varias veces el motor no produce duplicados innecesarios.
- [x] Cada regla puede tener cooldown diferente.
- [x] El historial permanece disponible (no hay borrados).
- [x] El comportamiento es determinista (política pura + límites explícitos).
- [x] Pruebas de primera ejecución, dentro del cooldown, después del cooldown,
      reglas diferentes y contextos diferentes.
- [x] `dart analyze` / tests correctos.

---

## ⏭️ Siguiente etapa (no iniciada)

- [ ] Deduplicación por contenido si se desea (mismo tipo/mensaje).
- [ ] Notificaciones a partir de las recomendaciones generadas.
- [ ] Probar en teléfono físico con datos reales.
