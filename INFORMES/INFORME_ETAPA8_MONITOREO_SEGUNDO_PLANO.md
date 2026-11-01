# 📄 Informe — Etapa 8: Monitoreo de uso en segundo plano y cruce con horarios

**Rama:** `feature/Monitoreo-Uso-Horarios`
**Objetivo:** monitorear el uso de aplicaciones con la app cerrada y determinar
cuánto de ese uso ocurre dentro de los horarios y tareas configurados.
**Fecha:** Septiembre 2026

---

## 1. Archivos modificados

| Archivo | Cambio |
|---|---|
| `lib/models/contexto_recomendacion.dart` | Nuevo campo `usosContextuales` + getters derivados (uso en horarios, distractores en horario, uso en tareas). |
| `lib/services/contexto_recomendacion_service.dart` | Dependencia `MonitoreoUsoHorariosService`; construye el uso contextual reutilizando tareas y horarios ya leídos. |
| `lib/screens/dashboard_screen.dart` | Indicador **"Monitoreo activo / detenido"** con interruptor y solicitud explícita del permiso de uso. |
| `android/app/build.gradle.kts` | Dependencia `androidx.work:work-runtime-ktx:2.10.0`. |
| `android/app/src/main/kotlin/.../MainActivity.kt` | Canal de control del monitoreo (`iniciar`, `detener`, `estaActivo`, `ejecutarAhora`). |

## 2. Archivos nuevos

| Archivo | Contenido |
|---|---|
| `lib/models/intervalo_uso.dart` | `EventoUso`, `IntervaloUso`, `VentanaTiempo`, `UsoContextual`. |
| `lib/services/monitoreo_uso_horarios_service.dart` | Adquisición de eventos y **análisis puro** de intersecciones. |
| `lib/services/monitoreo_segundo_plano_service.dart` | Control del monitoreo y `monitoreoCallbackDispatcher` (entrypoint de fondo). |
| `android/app/src/main/kotlin/.../MonitoreoUsoWorker.kt` | Worker de WorkManager + motor Flutter headless + preferencias del callback. |
| `test/monitoreo_horarios_test.dart` | 25 pruebas (escenarios A–F, medianoche, límites, emparejado, integración). |

## 3. Arquitectura del monitoreo en segundo plano

```
Dashboard (UI) ──MethodChannel──► MainActivity
                                      │ programa/cancela
                                      ▼
                              WorkManager (Android)
                                      │ cada ~15 min (mínimo del sistema)
                                      ▼
                          MonitoreoUsoWorker (Kotlin)
                                      │ crea FlutterEngine headless
                                      ▼
                   monitoreoCallbackDispatcher (isolate Dart)
                                      │
        ┌─────────────────────────────┴───────────────────────────┐
        ▼                                                          ▼
ContextoRecomendacionService ─► EvaluadorReglas ─► PoliticaCooldown
        │                                                          │
   UsageStatsManager                                    CreadorRecomendaciones
        │                                                          ▼
MonitoreoUsoHorariosService                        RepositorioRecomendaciones (SQLite)
        │                                                          │
   Horarios + Tareas                                               ▼
                                                     RecomendacionesNotificador
```

**Mecanismo elegido: Android WorkManager + motor Dart headless.**

Motivos técnicos:
- **No usa `Timer` de Dart**: con la app cerrada, quien decide cuándo ejecutar es
  el sistema (WorkManager), respetando Doze y las restricciones de batería.
- **No duplica lógica**: el worker no reimplementa reglas ni cooldown; arranca un
  `FlutterEngine` y ejecuta el **mismo** pipeline Dart que la aplicación.
- **Supervivencia a reinicios** y trabajo único garantizado por WorkManager.
- Sin dependencias Flutter nuevas (solo `androidx.work` de Gradle).

## 4. Cómo se obtiene la información de UsageStatsManager

`MonitoreoUsoHorariosService.obtenerIntervalos(desde, hasta)`:

1. `UsageStats.queryEvents(desde, hasta)` (plugin `usage_stats` sobre
   `UsageStatsManager.queryEvents`).
2. Se filtran los eventos `ACTIVITY_RESUMED` (1) y `ACTIVITY_PAUSED` (2); se
   descartan los que no traen marca de tiempo o paquete.
3. Se convierten a `EventoUso` y se emparejan.
4. Se resuelve el nombre legible de cada paquete una sola vez (caché).
5. Cualquier error (sin permiso, sin datos) devuelve lista vacía: **no rompe el
   ciclo**.

## 5. Cómo se calculan los intervalos de uso

`emparejarEventos()` ordena los eventos por tiempo y mantiene un mapa
`paquete → RESUME abierto`:

- `RESUME` abre sesión (el más reciente gana);
- `PAUSE` cierra la sesión y produce un `IntervaloUso(inicio, fin)`;
- un `PAUSE` sin `RESUME` previo se ignora;
- las sesiones que quedan abiertas al terminar el rango se cierran en
  `cierrePorDefecto`;
- sesiones mayores que `duracionMaximaSesion` (6 h) se acotan, para no arrastrar
  un `PAUSE` perdido.

El resultado son intervalos reales `[inicio, fin]` **con fecha y hora**, que es
la unidad que permite cruzar con horarios.

## 6. Cómo se determina si el uso pertenece a un horario

Adaptador/interpreter de la lógica existente en `Horario`:

1. `ventanasDeHorario(horario, desde, hasta)` genera ventanas **concretas** con
   fecha, reutilizando `diasSemana`, `cruzaMedianoche` y `tieneDuracion` del
   modelo. Un horario 22:00–02:00 genera **una sola ventana** que termina al día
   siguiente.
2. `duracionEnHorario()` interseca el intervalo con esas ventanas.
3. `_unionDeIntersecciones()` **fusiona solapes**, de modo que si dos horarios
   coinciden no se cuenta dos veces el mismo minuto.

No se reimplementó `contieneDateTime()`: hay una **prueba de coherencia** que
recorre instantes cada 17 minutos durante 4 días y verifica que
`contieneDateTime(t)` coincide exactamente con "t está dentro de alguna ventana".

## 7. Cómo se relaciona con tareas planificadas

`duracionEnTarea(intervalo, tarea)` interseca el intervalo con la franja
`inicioPlanificado`–`finPlanificado` de la tarea (getters ya existentes en
`Tarea`, construidos desde `fechaPlanificada` + horas).

`UsoContextual` conserva **por separado** `enHorarioLaboral`,
`enHorarioAcademico`, `enHorariosConfigurados` y `duranteTareaPlanificada`, de
modo que el sistema **no convierte automáticamente** un uso durante una tarea en
distracción: aporta el contexto y deja la decisión a las reglas.

## 8. Cómo se integra con el MotorRecomendaciones

- `MotorRecomendaciones` **no se modificó**.
- `ContextoRecomendacion` incorpora `usosContextuales` (lista de `UsoContextual`)
  **sin clasificar** nada, y deriva:
  `minutosTotalesEnHorarios`, `distractoresEnHorarios`,
  `minutosDistractoresEnHorarios`, `distractorPrincipalEnHorario`,
  `minutosDistractoresEnTareas`, `usoContextualDe(paquete)`.
- La clasificación de distractores se sigue haciendo con la lista **configurable**
  existente (`paquetesDistractores`): ninguna app se considera problemática por su
  nombre.
- `ContextoRecomendacionService` reutiliza las tareas y horarios ya consultados
  (cero consultas extra a la BD) y calcula el uso contextual en un `try/catch`,
  degradando a lista vacía si no hay permiso.

Con esto el motor **ya puede** usar el contexto temporal preciso (p. ej. sustituir
el total diario de R1/R2 por los minutos reales dentro del horario). Esa
reformulación de reglas **no se hizo en esta etapa** para no alterar el
comportamiento existente ni romper las pruebas de R1/R2.

## 9. Cómo funcionan las notificaciones

- Las genera el **mismo** `RecomendacionesNotificador`, ejecutado ahora también
  desde el isolate de fondo.
- Solo se notifican severidades `advertencia` y `critica`, y **solo si hay
  permiso de notificaciones**.
- **No hay notificaciones repetidas**: la deduplicación la sigue haciendo el
  `PoliticaCooldown` del motor (no se duplicó la lógica) y el id de notificación
  es **estable por regla** (`R3` → 1003), así que una nueva notificación de la
  misma regla reemplaza la anterior en lugar de apilarse.
- El isolate de fondo inicializa el plugin de notificaciones antes de usarlo
  (el registro es por isolate).

## 10. Permisos Android

**No se añadió ningún permiso nuevo.** Ya estaban declarados y se siguen
solicitando explícitamente desde la interfaz:

| Permiso | Para qué | Estado |
|---|---|---|
| `PACKAGE_USAGE_STATS` | leer UsageStatsManager | ya declarado; se pide al iniciar y antes de activar el monitoreo |
| `POST_NOTIFICATIONS` | notificaciones (Android 13+) | ya declarado; se pide al iniciar |
| `SCHEDULE_EXACT_ALARM` | recordatorios de tareas | ya declarado |
| `RECEIVE_BOOT_COMPLETED` | reprogramar tras reinicio | ya declarado |

WorkManager **no requiere permisos adicionales** (se autoinicializa y gestiona
sus propios componentes). El interruptor del Dashboard pide el permiso de uso
**antes** de activar el monitoreo, y avisa si falta: nada se concede en silencio.

## 11. Cambios en SQLite

**Ninguno. No hubo migración ni cambio de esquema.**

Justificación: el análisis es una **función pura** de
(eventos de UsageStatsManager + horarios + tareas), por lo que es **idempotente**
y no necesita persistir nada nuevo. Reejecutarlo no genera duplicados ni requiere
una tabla de intervalos. Se conservan intactas `uso_pantalla`, `app_uso`,
`horarios`, `tareas` y `recomendaciones`, y sigue vigente el arreglo de
`SQLITE_MISMATCH` (`sinId()`), que **no se tocó**.

## 12. Pruebas ejecutadas y resultados

```
dart analyze lib test  →  No issues found!
flutter test           →  157/157 All tests passed!   (25 nuevas)
```

| Escenario | Resultado |
|---|---|
| **A** — Horario 08:00–17:00, TikTok 09:00–09:15 | **15 min** dentro del horario ✔ |
| **B** — TikTok 19:00–19:20 | **0 min** ✔ |
| **C** — Cruce del inicio: 07:50–08:10 | **10 min** ✔ |
| **D** — Cruce del final: 16:50–17:20 | **10 min** ✔ |
| **E** — Tarea 09:00–11:00, TikTok 09:30–09:45 | dentro de horario **Sí**, dentro de tarea **Sí**, 15 min ✔ |
| **F** — Uso fuera de contexto | 0 min en horario, `tieneUsoEnHorario` false ✔ |
| **G** — App cerrada | ⚠️ requiere prueba en dispositivo |
| **H** — Notificación única + cooldown | ⚠️ requiere prueba en dispositivo |

Además: límites exactos (inicio incluido, fin excluido), día no configurado,
cruce de medianoche (22:00–02:00 en tres casos), coherencia con
`contieneDateTime`, sin doble conteo con horarios solapados, emparejado de
eventos (incluido PAUSE huérfano y sesión anómala) e integración con el contexto.

## 13. Limitaciones técnicas identificadas

1. **Precisión real de UsageStatsManager**: Android entrega **eventos** de cambio
   de primer plano, no un muestreo continuo. La resolución depende de la calidad
   de esos eventos y los eventos detallados se conservan ~7 días. **No se detecta
   cada segundo de uso.**
2. **Cadencia de 15 minutos**: es el mínimo que permite WorkManager para trabajo
   periódico. El monitoreo es **periódico**, no continuo, y Android puede
   retrasarlo en Doze o con batería baja.
3. **El worker puede no ejecutarse**: en modo ahorro extremo Android puede
   posponerlo. No se usa un Foreground Service (evita una notificación
   permanente), aceptando esa contrapartida en favor de la batería.
4. **El isolate de fondo arranca de cero**: hay que reconstruir servicios y
   reinicializar plugins en cada ciclo (coste pequeño pero real).
5. **R1/R2 siguen usando el total diario**, no los minutos contextuales. El
   contexto ya los expone; reformular esas reglas es el siguiente paso natural.
6. **⚠️ El código Kotlin no pudo compilarse en mi entorno** (no hay build de
   Gradle disponible). Dart está verificado (`analyze` + 157 pruebas), pero
   `MainActivity.kt` y `MonitoreoUsoWorker.kt` requieren un `flutter run` para
   validarse; el primer build descargará `androidx.work`.
7. **`FlutterCallbackInformation.lookupCallbackInformation`** está marcada como
   deprecada en Flutter; funciona, pero conviene migrarla cuando el SDK lo exija.

---

## ⏭️ Pendiente para cerrar la etapa

- [ ] `flutter run` en el dispositivo y verificar escenarios **G** (app cerrada) y **H** (notificación + cooldown).
- [ ] Reformular R1/R2 para usar `minutosDistractoresEnHorarios` en lugar del total diario.
- [ ] Botón de diagnóstico "ejecutar ahora" en la UI (`ejecutarAhora` ya existe en el canal nativo).
