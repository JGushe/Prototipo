# 📄 Informe — Etapa 7: Integración final y preparación de la evaluación

**Rama:** `feature/Motor-Recomendaciones-Adaptado`
**Alcance:** cerrar el ciclo datos → reglas → recomendaciones → interfaz, y
preparar la evidencia para la evaluación de la tesis.
**Fecha:** Agosto 2026

---

## ✅ Cambios realizados

| # | Archivo | Cambio |
|---|---------|--------|
| 1 | `lib/services/reglas/repositorio_recomendaciones.dart` | **Nuevo**: abstracción del almacén de recomendaciones + adaptador SQLite. |
| 2 | `lib/services/reglas/resultado_evaluacion.dart` | Resultado ampliado: contexto, `EvaluacionRegla` por regla y `resumen()` legible. |
| 3 | `lib/services/reglas/evaluador_reglas.dart` | `detallar()`: estado y explicación de **cada** regla. |
| 4 | `lib/services/motor_recomendaciones.dart` | Repositorio inyectable, guarda anti-concurrencia y log del resumen en desarrollo. |
| 5 | `lib/services/notificacion_service.dart` | `tienePermisoNotificaciones()`, `notificarRecomendacion()` e id estable por regla. |
| 6 | `lib/services/recomendaciones_notificador.dart` | **Nuevo**: decide qué se notifica (solo `advertencia`/`critica`) y respeta permisos. |
| 7 | `lib/screens/dashboard_screen.dart` | Integración del ciclo completo con guarda, notificaciones y resumen. |
| 8 | `lib/screens/recomendaciones_screen.dart` | Presentación clara (severidad + regla) e **inspector de desarrollo**. |
| 9 | `test/integracion_motor_test.dart` | **12 pruebas** de integración (escenarios A–J + motor). |
| 10 | `test/notificador_test.dart` | **6 pruebas** del notificador y del id estable. |

### Dónde se ejecuta el motor (tarea 1)

- **Dashboard** (flujo real): botón actualizar → `capturarUsoDelDia()` →
  `motor.ejecutar()` → notificaciones → resumen visible.
- **Recomendaciones** (flujo manual): botón generar → `motor.ejecutar()`.
- Guardas en ambas pantallas (`_actualizando` / `_generando`) y **dentro del
  motor**: las llamadas simultáneas reutilizan la ejecución en curso, así el
  motor nunca corre dos veces a la vez (tarea 2). El cooldown evita además que
  dos ejecuciones seguidas dupliquen recomendaciones.

### Ciclo asegurado (tarea 3)

```
captura de uso → ContextoRecomendacionService (contexto)
→ EvaluadorReglas.detallar()/evaluar() (reglas)
→ PoliticaCooldown (descartar duplicados)
→ CreadorRecomendaciones + RepositorioRecomendaciones (solo válidas)
```

### Presentación (tarea 4)

Cada tarjeta muestra ahora el chip `SEVERIDAD · Regla R#`, el mensaje, el
**motivo** (por qué se generó) y la fecha. El Dashboard muestra una tarjeta con
el resultado del último ciclo (`N nuevas · M en cooldown`) y un SnackBar con el
mismo dato.

### Notificaciones (tareas 5 y 6)

Solo se notifican recomendaciones con severidad `advertencia` o `critica`
(`RecomendacionesNotificador`). Se respeta el permiso de notificaciones de
Android 13+ (`tienePermisoNotificaciones()`). El id de notificación es **estable
por regla** (`R3` → 1003): una nueva notificación de la misma regla reemplaza a
la anterior en lugar de apilarse, y como el motor ya aplica cooldown antes de
crear la recomendación, **no hay notificaciones repetidas**.

### Inspección en desarrollo (tarea 7)

- `MotorRecomendaciones.ejecutar()` devuelve `ResultadoEvaluacion` con:
  contexto utilizado, evaluación de todas las reglas (aplicable / fallidas /
  descartadas), generadas, descartadas y motivos.
- En `kDebugMode` se imprime el `resumen()` completo en la consola.
- En la app, un botón 🐞 (solo visible en `kDebugMode`) abre el diálogo
  **"Inspección del motor"** con ese resumen: contexto, `[OK]` regla generada,
  `[COOLDOWN]` regla descartada y `[--]` regla no aplicable con las condiciones
  fallidas.

---

## 🏗️ Arquitectura resultante

```
Android (UsageStats / permisos)
        │
        ▼
ContextoRecomendacionService ──(usa DatabaseHelper, UsoPantallaService,
   │                               AnalisisHorarioService, ConfiguracionMotor)
   ▼
ContextoRecomendacion  (datos inmutables, derivados como getters)
        │
        ▼
MotorRecomendaciones
   ├─ EvaluadorReglas         → ResultadoRegla / EvaluacionRegla (detalle)
   ├─ PoliticaCooldown        → DescarteCooldown (clave + ventana por ámbito)
   ├─ CreadorRecomendaciones  → Recomendacion (reglaId, severidad, motivo, clave)
   └─ RepositorioRecomendaciones (SQLite) → historial intacto
        │
        ▼
RecomendacionesNotificador (solo severidades que corresponden, con permiso)
        │
        ▼
UI: Dashboard (resumen) · Recomendaciones (tarjetas + inspector dev)
```

## 📋 Reglas implementadas

| ID | Regla | Contexto que usa | Ámbito cooldown |
|----|-------|------------------|-----------------|
| R1 | Distractor durante el estudio | horario académico activo + distractoras | horario |
| R2 | Distractor durante el trabajo | horario laboral activo + distractora | horario |
| R3 | Tarea prioritaria + distracción | tarea planificada activa alta + distractor | regla (90 min) |
| R4 | Exceso de tareas pendientes | conteo de pendientes | regla (12 h) |
| R5 | Alto uso acumulado | pantalla del día | día |
| R6 | Carga combinada | tareas + pantalla | regla (6 h) |
| R7 | Uso nocturno | minutos nocturnos | regla (12 h) |
| R8 | Pico dentro del horario | pico + horarios | regla (12 h) |

Umbrales centralizados en `ConfiguracionMotor`; clasificación de distractoras
configurable en el contexto.

## 🧪 Escenarios cubiertos (`test/integracion_motor_test.dart`)

| Escenario | Entrada | Regla(s) esperada(s) | ✔ |
|-----------|---------|----------------------|---|
| A | sin horario + uso elevado (300 min) | R5 | ✔ |
| B | académico activo + Instagram 45 min | R1 | ✔ |
| C | laboral activo + Instagram 45 min | R2 | ✔ |
| D | tarea alta activa + distractor | R3 | ✔ |
| E | 8 tareas pendientes | R4 | ✔ |
| F | 90 min nocturnos | R7 | ✔ |
| G | laboral + distractor + 8 tareas + 300 min + 90 nocturnos | R2, R4, R5, R6, R7 en orden de prioridad | ✔ |
| H | misma condición 2 veces | 1ª genera; 2ª descartada por cooldown | ✔ |
| I | sin permiso UsageStats | sin reglas de apps (R5 sí) | ✔ |
| J | sin tareas planificadas | sin R3 | ✔ |

Para cada escenario se verifica: **entrada → contexto → regla →
recomendación esperada** (reglaId, tipo, severidad, mensaje y motivo), que solo
se almacenan las recomendaciones válidas y que el contexto se construye una
única vez. También se prueban la ejecución concurrente (se reutiliza la misma) y
el `resumen()` como evidencia documentable.

## 🧪 Verificación

```
dart analyze lib test   →  No issues found!
flutter test            →  00:00 +127: All tests passed!  (18 nuevas + 109 previas)
```

---

## ⚠️ Limitaciones encontradas

1. **«Mismo periodo» en R3 es una aproximación diaria.** El contexto agrega el
   uso distractor del día, no por intervalo horario; R3 exige que la tarea esté
   activa en el momento y que exista uso distractor. Precisarlo requiere
   consultar `queryEvents` por ventana (futuro).
2. **La ventana de aplicaciones es el top 5.** Para no cambiar el comportamiento
   del motor previo; ampliable con `topApps`.
3. **El cooldown de los ámbitos `dia`/`horario` es el día natural** (la clave
   acota el periodo); el `cooldown` en minutos aplica al ámbito `regla`.
4. **Las pruebas de integración sustituyen el almacén por un doble en memoria**;
   la adquisición real (SQLite + UsageStats) se verifica en el dispositivo. No
   se añadió `sqflite_common_ffi` para mantener las dependencias intactas.
5. **Notificaciones**: no se probaron con el plugin real en las pruebas
   automatizadas (se probó la política con un doble). El id estable por regla
   mitiga la repetición; el envío real depende del permiso de Android.
6. **R3 usa `permisoUsoDisponible` solo informativamente**: las reglas dependen
   de los datos del contexto (que ya caen a la BD cuando no hay permiso).
7. **Entorno de desarrollo**: `dart analyze` y `flutter test` requieren acceso
   ampliado por el spawn de procesos hijos; en la máquina del usuario funcionan
   con normalidad.

## 📌 Criterios de aceptación

- [x] El motor funciona desde el flujo real de la aplicación (Dashboard).
- [x] Las recomendaciones no se duplican (cooldown + guarda de concurrencia).
- [x] Los escenarios definidos pueden reproducirse (10 pruebas de integración).
- [x] Las pruebas permiten obtener evidencia (resumen imprimible + inspector dev).
- [x] `dart analyze` / tests correctos.

## ⏭️ Siguientes pasos sugeridos (fuera de esta etapa)

- [ ] Probar en teléfono físico y capturar el `resumen()` como evidencia.
- [ ] Uso por ventana horaria para precisar R3.
- [ ] Notificaciones con prueba de integración sobre el plugin real.
