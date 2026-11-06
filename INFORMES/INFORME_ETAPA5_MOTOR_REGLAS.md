# 📄 Informe — Etapa 5: Motor de reglas contextualizadas

**Rama:** `feature/Motor-Recomendaciones-Adaptado`
**Alcance:** convertir `MotorRecomendaciones` en un motor de reglas declarativas
que relaciona actividad planificada, horario, tarea, uso de aplicación y tiempo.
**Fecha:** Agosto 2026

---

## 🎯 Objetivo

Sustituir la colección de `if/else` globales por una **estructura explicable**:
reglas declarativas con identificador, prioridad, condiciones, severidad y
cooldown, y una separación estricta entre adquirir datos, decidir y crear
recomendaciones.

---

## ✅ Cambios realizados

| # | Archivo | Cambio |
|---|---------|--------|
| 1 | `lib/services/reglas/configuracion_motor.dart` | **Nuevo**: configuración centralizada de umbrales y ventanas de datos. |
| 2 | `lib/services/reglas/regla_recomendacion.dart` | **Nuevo**: `ReglaRecomendacion`, `CondicionRegla`, `SeveridadRecomendacion`. |
| 3 | `lib/services/reglas/evaluador_reglas.dart` | **Nuevo**: `EvaluadorReglas`, `ResultadoRegla`. |
| 4 | `lib/services/reglas/creador_recomendaciones.dart` | **Nuevo**: materializa la decisión en `Recomendacion`. |
| 5 | `lib/services/reglas/reglas_por_defecto.dart` | **Nuevo**: R1–R8. |
| 6 | `lib/services/motor_recomendaciones.dart` | Rediseñado como orquestador de 4 etapas. |
| 7 | `lib/models/recomendacion.dart` | `reglaId`, `severidad`, `motivo`. |
| 8 | `lib/models/contexto_recomendacion.dart` | `usoPorHora`, `minutosUsoNocturno`, clasificación configurable, `horaPico`/`minutosPico`/`horarioDelPico`. |
| 9 | `lib/services/contexto_recomendacion_service.dart` | Usa la configuración y el análisis por hora. |
| 10 | `lib/database/database_helper.dart` | Migración **v4** (trazabilidad de recomendaciones). |
| 11 | `lib/screens/recomendaciones_screen.dart` | Muestra el `motivo` de cada recomendación. |
| 12 | `test/reglas_test.dart` + `test/contexto_recomendacion_test.dart` | Pruebas por regla. |

### Representación de una regla

`ReglaRecomendacion` es **datos**, no código: `id`, `nombre`, `prioridad`,
`condiciones` (lista de `CondicionRegla`, todas deben cumplirse), `tipo`,
`titulo`, `mensaje`, `severidad`, `cooldown` y `habilitada`. Incluye `copyWith`
para habilitar/deshabilitar una regla sin borrarla.

`CondicionRegla` sabe **explicarse**: además del predicado lleva una
`descripcion` y un `detalle` que devuelve el texto con datos concretos
(p. ej. «Tiempo en distractoras: 45 min (umbral 30 min)»).

### Arquitectura en tres responsabilidades (punto 2)

```
ContextoRecomendacionService  →  adquiere y normaliza datos
        ↓  ContextoRecomendacion
EvaluadorReglas               →  decide qué reglas aplican (y por qué)
        ↓  List<ResultadoRegla>
CreadorRecomendaciones        →  materializa Recomendacion
        ↓  List<Recomendacion>
MotorRecomendaciones          →  persiste y orquesta
```

Añadir una regla nueva (punto 1) es añadir otra `ReglaRecomendacion` a
`crearReglasPorDefecto()`: ni el evaluador ni el motor cambian.

### Reglas implementadas

| ID | Regla | Tipo | Se cumple cuando |
|----|-------|------|------------------|
| **R1** | Uso distractor durante el estudio | `pausa` | horario **académico** activo + hay distractoras + total distractor > umbral |
| **R2** | Uso distractor durante el trabajo | `pausa` | horario **laboral** activo + **una** distractora supera el umbral |
| **R3** | Tarea prioritaria en distracción | `sugerencia_foco` | **tarea planificada activa de prioridad alta** + uso distractor en el periodo |
| **R4** | Exceso de tareas pendientes | `sugerencia_foco` | pendientes > límite (5) |
| **R5** | Alto uso acumulado | `alerta_uso` | uso de pantalla del día > umbral (240) |
| **R6** | Carga combinada | `descanso` | tareas > 3 **y** uso > 180 |
| **R7** | Uso nocturno | `descanso` | uso en el rango nocturno > umbral (60) |
| **R8** | Pico dentro de un horario | `sugerencia_foco` | pico de uso dentro de un horario configurado |

R1, R2 y R3 usan realmente contexto temporal (`horarioActivo`, `tipoHorario`,
`tareaActiva`) y la actividad planificada.

**Sobre R8:** la lista pedida era R1–R7; R8 se añadió porque el motor anterior ya
tenía una regla de «pico de uso dentro del horario» y el enunciado pide **no
eliminar funcionalidades existentes**. Queda integrada en el mismo diseño y
puede retirarse borrando una línea si no se desea.

### Umbrales centralizados (punto 3)

Todos en `ConfiguracionMotor` (30, 5, 240, 180, 3, 22, 6, 60, ventana de 7 días
y la lista de paquetes distractores). Ninguna regla contiene números sueltos.

### Clasificación configurable

`ContextoRecomendacion.paquetesDistractores` es sustituible; por defecto usa
`paquetesDistractoresPorDefecto`. La comparación es por **prefijo** y no asume
que toda aplicación sea distractora.

### Trazabilidad y explicabilidad (puntos 3 y 4)

Cada recomendación guarda `reglaId`, `severidad` y `motivo`, p. ej.:

```
Regla R1 (Uso distractor durante el estudio): Horario académico activo (19:00 - 21:00);
App distractora principal: Instagram; Tiempo en distractoras: 45 min (umbral 30 min)
```

Migración **v4** (no destructiva): `ALTER TABLE recomendaciones ADD COLUMN`
para `reglaId`, `severidad` (`DEFAULT 'info'`) y `motivo`. Las recomendaciones
antiguas siguen leyéndose. La pantalla muestra el `motivo` bajo el mensaje.

---

## 🧪 Verificación

```
dart analyze lib test   →  No issues found!
flutter test            →  00:00 +86: All tests passed!  (38 nuevas + 48 previas)
```

`test/reglas_test.dart` incluye casos **positivos y negativos** para cada regla
principal, verificación de los umbrales por defecto, prueba de que cambiar la
configuración cambia el resultado, orden por prioridad, regla deshabilitada,
IDs únicos, y que la recomendación resultante identifica su regla y explica el
motivo con datos concretos.

---

## ⚠️ Notas y decisiones

1. **Cooldown no aplicado todavía.** El campo existe en la representación (la
   configuración define un valor por familia de reglas), pero el motor **no** lo
   evalúa: el enunciado pide no implementar todavía deduplicación avanzada.
   Falta consultar la última recomendación por `reglaId`.
2. **«Mismo periodo» en R3 es una aproximación.** El contexto agrega el uso
   distractor del día, no por ventana horaria. R3 exige que la tarea esté activa
   *ahora* y que exista uso distractor; para precisarlo haría falta uso por
   intervalo dentro de la ventana de la tarea.
3. **R2 vs R1 (intencional).** R2 exige que *una* aplicación supere el umbral;
   R1 usa el *total* distractor. Hay una prueba que fija esta diferencia.
4. **R7 usa `usoPorHora`** de `AnalisisHorarioService.obtenerUsoPorHora()`; así
   el motor deja de depender del servicio de análisis (se resolvió la nota
   pendiente de la etapa 4) y no se duplica la consulta de horarios.
5. **`Regla 3` del motor anterior** (redes sociales > 30 min) se sustituye por
   R1/R2, que son contextuales. La lista `redesSociales` del motor desaparece:
   la clasificación vive ahora en el contexto/configuración.
6. **Cambio de interfaz mínimo:** se añade el `motivo` a la tarjeta existente;
   no se eliminó ningún elemento.
7. **Entorno:** `dart analyze` y `flutter test` requieren acceso ampliado por el
   spawn de procesos hijos (`flutter_tester`, servidor de análisis).

---

## 📌 Criterios de aceptación

- [x] R1, R2 y R3 usan contexto temporal y actividad planificada.
- [x] Las reglas globales existentes quedan organizadas en el nuevo diseño.
- [x] Los umbrales están centralizados en `ConfiguracionMotor`.
- [x] Las recomendaciones explican por qué fueron generadas (`motivo`).
- [x] Existen pruebas para cada regla principal (positivas y negativas).
- [x] `dart analyze` / tests correctos.

---

## ⏭️ Siguiente etapa (no iniciada)

- [ ] Aplicar el cooldown por regla (consulta de la última recomendación).
- [ ] Uso por ventana horaria para precisar el «mismo periodo» de R3.
- [ ] Deduplicación y notificaciones.
- [ ] Probar en teléfono físico con datos reales.
