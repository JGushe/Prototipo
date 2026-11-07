# PROMPT MAESTRO PARA CODEX — Auditoría y refactorización local del prototipo Android

> **Directorio de trabajo único:** `/home/ushe/Documentos/Proyecto-Android/Prototipo`  
> **Directorio de skills:** `/home/ushe/.dsh/skills`  
> **Contexto:** tesis sobre productividad, bienestar digital, tareas y horarios en Android.  
> **Modalidad:** trabajo exclusivamente local, fase por fase, con diagnóstico y pruebas.  
> **Fecha de preparación:** 5 de noviembre de 2026.  
> **Advertencia:** los hallazgos históricos descritos aquí son puntos de partida para la investigación. El contenido real del directorio local es la única autoridad sobre la implementación actual.

## INSTRUCCIÓN MAESTRA — PRIORIDAD MÁXIMA

**Eres Codex actuando como ingeniero senior de Flutter/Dart, Kotlin, Android (UsageStatsManager y WorkManager), SQLite, depuración ADB y pruebas de software.** Tu tarea es auditar y posteriormente corregir en fases el proyecto de tesis ubicado en:

```text
/home/ushe/Documentos/Proyecto-Android/Prototipo
```

**Restricciones innegociables:**

1. **Fuente única del proyecto: el directorio local indicado.** Lee sus archivos, configuración, tests, documentación y modificaciones actuales. **No consultes ni compares con GitHub**, otras ramas remotas, repositorios online, o copias externas. No utilices `git fetch`, `git pull`, `git clone`, `git ls-remote`, `gh`, APIs remotas de repositorio ni enlaces web al repositorio para contrastar versiones. No invoques agentes o procesos externos que sincronicen el proyecto.
2. **Todo cambio debe permanecer local.** **PROHIBIDO `git push`, crear PR, publicar ramas, subir archivos, crear releases, sincronizar remotos o enviar código/datos a GitHub o a otros servicios.** Puedes consultar `git status`/`git diff` locales únicamente para proteger trabajo preexistente; nunca uses `git reset --hard`, `git clean -fd`, `git checkout -- .` ni `git restore` sobre cambios ajenos. No hagas commits automáticos sin autorización expresa.
3. **Skills:** inspecciona primero `/home/ushe/.dsh/skills`; identifica el catálogo disponible y lee las instrucciones de las skills aplicables antes de intervenir en cada fase. Usa **Ponytail** y **Caveman** cuando realmente existan y sean pertinentes; nunca inventes su disponibilidad o sintaxis. Da prioridad a las instrucciones específicas de cada skill sin dejar que anulen las restricciones de privacidad, trabajo local, protección de datos o seguridad aquí establecidas. Documenta cuáles usaste y con qué propósito.
4. **Empieza únicamente con Fase 0, auditoría no destructiva.** No alteres lógica de producción, base de datos del dispositivo ni configuración del usuario en esa fase. Presenta evidencia y plan antes de realizar parches. Luego ejecuta cada fase de forma independiente cuando el usuario la solicite.
5. **Protege la información:** no desinstales la app, no borres almacenamiento, no elimines registros históricos ni modifiques migraciones sin respaldo y autorización. Solicita permiso para extracciones de datos privados, instalaciones en el dispositivo, cambios de permisos y operaciones potencialmente destructivas. Sanitiza logs y elimina identificadores personales del informe.
6. **No simules ejecuciones:** no afirmes que probaste el dispositivo, corriste pruebas, consultaste Bienestar Digital o solucionaste un error si no existe evidencia concreta. Diferencia hechos observados, hallazgos del código, hipótesis y resultados efectivamente comprobados.
7. **Conserva el alcance académico:** no conviertas el prototipo en servicio de vigilancia continua, no prometas notificaciones instantáneas con WorkManager y no hagas cambios de arquitectura importantes sin justificarlos y medir su costo de batería.

**Al comenzar, comprueba que el directorio existe (`pwd`, `ls`) y que dispones de acceso a las skills. Si no existe alguna ruta, reporta la limitación y no sustituyas el proyecto por otra fuente.**

---

## 0A. Protocolo obligatorio de skills locales

Antes de leer o editar lógica del proyecto, inspecciona **solamente el directorio local** de habilidades:

```bash
find /home/ushe/.dsh/skills -maxdepth 3 -type f \( -iname 'SKILL.md' -o -iname 'skill.md' \) -print | sort
```

Lee las instrucciones y archivos de referencia de las skills útiles para análisis, Flutter/Dart, Kotlin/Android, SQLite, pruebas, refactorización y depuración. Prioriza Ponytail/Caveman **si están realmente presentes** y asigna una tarea adecuada a cada una. Si no existen o no son aplicables, dilo expresamente y continúa con buenas prácticas sin inventar funciones ni capacidades. No ejecutes scripts desconocidos de una skill sin inspeccionarlos primero. En cada informe de fase indica: `skill utilizada → objetivo → resultado`.

---

## 1. Contexto y arquitectura funcional

Aplicación móvil Android desarrollada con **Flutter/Dart**, componentes nativos **Kotlin**, almacenamiento local **SQLite (`sqflite`)** y estadísticas proporcionadas por **`UsageStatsManager`** a través del paquete `usage_stats`. Integra:

- Gestión de tareas y horarios laborales/académicos.
- Captura de tiempo de uso por aplicación y desbloqueos.
- Detección contextual de posibles distracciones al cruzar apps, horarios y tareas.
- Motor de reglas **R1–R8**, recomendaciones, severidad, prioridades, historial, control de duplicados y cooldown.
- Pantallas **Dashboard**, **Uso**, **Tareas**, **Tips/Recomendaciones** y configuración.
- Monitoreo periódico en segundo plano con **WorkManager** y un `FlutterEngine` headless.
- Indicadores de comparación **hoy/ayer a la misma hora de corte** y evolución semanal.

**Dispositivo de validación:** Motorola G84 con Android 15 (según contexto proporcionado por el usuario). Se contempla conexión autorizada mediante ADB (USB inicialmente, inalámbrica si funciona con estabilidad). No se ha realizado en esta conversación ninguna extracción del dispositivo, ni se ha verificado la conexión ADB.

### Principales rutas de código identificadas

| Subsistema | Ruta relativa |
|---|---|
| Panel general | `lib/screens/dashboard_screen.dart` |
| Pantalla Uso | `lib/screens/uso_screen.dart` |
| Captura y comparación | `lib/services/uso_pantalla_service.dart` |
| Comparación diaria | `lib/models/comparacion_diaria.dart` |
| Sesiones/contexto temporal | `lib/services/monitoreo_uso_horarios_service.dart` |
| Eventos/modelos temporales | `lib/models/intervalo_uso.dart` |
| Análisis por horas/nocturno | `lib/services/analisis_horario_service.dart` |
| Construcción de contexto | `lib/services/contexto_recomendacion_service.dart` |
| Clasificación por paquete | `lib/models/contexto_recomendacion.dart` |
| Umbrales de reglas | `lib/services/reglas/configuracion_motor.dart` |
| Definiciones R1–R8 | `lib/services/reglas/reglas_por_defecto.dart` |
| Orquestación del motor | `lib/services/motor_recomendaciones.dart` |
| Background Dart | `lib/services/monitoreo_segundo_plano_service.dart` |
| Worker Kotlin | `android/app/src/main/kotlin/com/prototipo/prototipo_tesis/MonitoreoUsoWorker.kt` |
| Canal y programación nativa | `android/app/src/main/kotlin/com/prototipo/prototipo_tesis/MainActivity.kt` |
| SQLite | `lib/database/database_helper.dart` |
| Documentación técnica | `README.md`, `INFORMES/` |

**Nota histórica (verificar localmente):** La ruta Kotlin incluye `com/prototipo/prototipo_tesis` (no `com/example/prototipo_tesis`). Confirmar de nuevo en la copia local.

---

## 2. Evidencia real reportada por el usuario

### Caso A: Dashboard — 4 de noviembre de 2026, 12:34

La aplicación mostró:

- **Hoy: 1131 minutos de pantalla** (18 h 51 min).
- Etiqueta: **«hasta las 12:34»**.
- **«Distractor hoy: 25 min»**.
- **2 %** en el gráfico circular.

Desde las 00:00 hasta las 12:34 transcurren **754 minutos**. La cifra presentada excede el tiempo calendario disponible en **377 minutos**, por lo que **no puede ser válida como uso de pantalla real no duplicado**.

El porcentaje del gráfico circular sí es aritméticamente consistente con los valores que recibe: `25 / 1131 × 100 = 2,21 %`, redondeado a **2 %**. El problema está en la calidad del total y posiblemente también en la clasificación/detección del numerador.

### Caso B: pantalla Uso — 4 de noviembre de 2026, 12:42

La aplicación mostró:

- **Tiempo total: 7 h 6 min = 426 min**.
- **Desbloqueos: 32**.
- **App más usada: TikTok, 2 h 3 min = 123 min**.

A las 12:42 habían transcurrido **762 minutos** desde medianoche. **426 min es físicamente posible**, pero **no está validado** contra Bienestar Digital ni contra una muestra diagnóstica de ADB. Ambas pantallas se consultaron con ocho minutos de diferencia, por lo que una pequeña discrepancia temporal es normal; **705 min** de diferencia entre 1131 y 426 **no es normal**.

Si TikTok tuvo realmente 123 min de uso y forma parte de los distractores predeterminados, mostrar solo 25 min distractores requiere explicación. La comparación no es estrictamente simultánea y usa vías diferentes; podría haber datos parciales, sesiones reconstruidas erróneamente o diferencias de identificación de paquete. **No concluir aún que los 123 min deban aparecer exactamente como 123 min distractores** sin alinear fuente, intervalo y corte.

### Caso C: comportamiento funcional reportado

- Si la aplicación **no está abierta**, el usuario indica que **no recibe notificaciones por uso del teléfono**.
- Si no pulsa el botón de **recargar**, tampoco observa el monitoreo/notificación esperado.
- La **regla R7 de uso nocturno** ha reportado tiempo entre **22:00 y 06:00** en períodos en los que el usuario indica que estaba durmiendo, sin utilizar conscientemente el teléfono.

Estos son síntomas observados. **Falta evidencia de logs, eventos y ejecución física** para determinar las causas exactas.

---

## 3. Hallazgos técnicos confirmados y sospechas pendientes

### H1 — Dos rutas incompatibles de cálculo de tiempo de pantalla (**confirmado por código**)

**Dashboard** (`dashboard_screen.dart`): en `_cargarDatos()` llama a `UsoPantallaService.compararHoyAyer()`. En el encabezado usa preferentemente `comparacion.minutosHoy`; solo si falta recurre al resumen SQLite `usoHoyMinutos`.

**Uso** (`uso_screen.dart`): en `_cargarDatos()` usa `DatabaseHelper.obtenerUsoHoy()` para el resumen, mientras consulta las top apps actuales mediante `obtenerTopAppsDelDia(top: 5)`. El botón actualizar llama `capturarUsoDelDia()` antes de recargar.

**Consecuencia:** dos pantallas pueden combinar capturas de horas diferentes y metodologías distintas; la pantalla Uso puede presentar un resumen SQLite anterior aunque sus top apps sean recientes.

**Decisión de diseño propuesta:** establecer un **servicio canónico de métricas** con fuente explícita, fecha de captura, ventana consultada y calidad del dato. Reservar estadísticas agregadas de Android para el uso por aplicación, y eventos temporalmente reconstruidos para contexto; reconciliar ambos cuando sea posible. El total no duplicado de pantalla requiere semántica propia y validación, no simplemente sumar todas las actividades.

### H2 — Reconstrucción de sesiones susceptible a solapamientos (**confirmado por código; causalidad exacta pendiente**)

`MonitoreoUsoHorariosService.emparejarEventos()`:

- Ordena eventos y mantiene un mapa `abiertos` por nombre de paquete.
- Un evento `ACTIVITY_RESUMED` abre/reemplaza la sesión del paquete correspondiente.
- Un `ACTIVITY_PAUSED` cierra solo la sesión de **ese mismo paquete**.
- Cuando faltan pausas, varias aplicaciones pueden permanecer abiertas a la vez y cerrarse en `cierrePorDefecto`.
- Limita cada sesión anómala a **6 horas**, pero **no elimina intervalos superpuestos entre paquetes**.

`UsoPantallaService._minutosEn()` recorta cada intervalo al rango solicitado, **suma sus segundos directamente** y convierte con `segundos ~/ 60`; no fusiona los intervalos de aplicaciones distintas. Este defecto **puede explicar** un total mayor que los minutos físicamente transcurridos, aunque no existe aún traza que pruebe que fue la causa exacta del valor 1131.

**Importante:** Android permite escenarios como pantalla dividida/multiventana. Una corrección no debe asumir que solo puede existir una aplicación en primer plano en cualquier circunstancia: diferenciar **tiempo por aplicación** de **tiempo único del dispositivo**, y fusionar la unión temporal donde corresponda. No parchear con `clamp(0, minutosTranscurridos)` como solución definitiva: eso **oculta** el error.

### H3 — Diferencias de redondeo y procedencia (**confirmado por código**)

- `capturarUsoDelDia()` usa `UsageStats.queryUsageStats(inicioDelDia, finDelDia)`; para cada app convierte `totalTimeInForegroundMs` mediante `(ms / 60000).round()` y **después suma** los minutos de todas las apps.
- `compararHoyAyer()` consulta eventos `UsageStats.queryEvents(inicioAyer, momento)`; forma intervalos y convierte los **segundos acumulados** con `~/ 60`.
- El valor **«hasta las HH:mm»** es la hora de corte de la lectura/comparación hoy-ayer, **no** la última hora en que se usó el teléfono.
- La variación hoy/ayer = `(minutosHoy - minutosAyer) / minutosAyer × 100`; si ayer = 0, devuelve porcentaje no disponible.

Las cifras pueden diferir por redondeo, sesiones, ventana y actualización, pero **no es aceptable** un total de pantalla superior al tiempo calendario disponible si se presenta como tiempo único de pantalla.

### H4 — El 2 % del donut no es productividad (**confirmado por código**)

El donut calcula `round(100 × distractorHoy / minutosHoy)`. `distractorHoy` suma los paquetes clasificados como distractores; el resto es **uso no clasificado como distractor**, no necesariamente uso productivo. Tampoco equivale al tiempo de distracción **dentro de horarios laborales/académicos**, que requiere contexto adicional de las reglas R1/R2/R3.

### H5 — Clasificación inconsistente de paquetes (**confirmado por código; efecto concreto pendiente**)

En la comparación de `UsoPantallaService._minutosEn(..., soloDistractores: true)` se usa `paquetesDistractoresPorDefecto.contains(intervalo.nombrePaquete)`, esto es, **coincidencia exacta**.

La lista por defecto incluye prefijos/paquetes como `com.facebook`, `com.instagram`, `com.twitter`, `com.x`, `com.whatsapp`, `com.tiktok`, `com.zhiliaoapp.musically`, `com.snapchat`. **YouTube no aparece** en esa lista. En otros puntos existe clasificación por **prefijo** (`ContextoRecomendacion.clasificarDistractor`). Por tanto, algunas variantes de paquetes (p. ej., paquetes con sufijos) pueden no contarse igual entre módulos. Auditar la fuente real de configuración y homogeneizar el criterio; **no imponer categorías sin considerar personalización y usos legítimos**.

### H6 — Regla R7: actividad nocturna atribuida potencialmente de forma indebida (**hallazgo de diseño confirmado; eventos reales pendientes**)

Configuración actual en `ConfiguracionMotor`:

- Ventana nocturna **22:00–06:00** (cruza medianoche).
- **60 min/día** como umbral base.
- **7 días** de análisis.
- Regla **R7** se activa si el acumulado de 7 días supera **420 min** (`60 × 7`); cooldown **12 h**.

**Importante: hay otro criterio diferente** en `AnalisisHorarioService.analizar()`, que muestra una sugerencia nocturna si el acumulado construido para su ventana de análisis supera **60 min**. **Son mecanismos distintos** y sus umbrales no deben confundirse.

`AnalisisHorarioService._calcularUsoPorHora()` reconstruye eventos `RESUME/PAUSE` y asigna **la duración de la sesión completa a la hora en que comenzó**, sin distribuirla proporcionalmente entre las horas atravesadas. La obtención se basa en eventos de aplicación, **sin comprobación explícita de estado de pantalla interactiva/bloqueo** en ese cálculo; las sesiones abiertas/incompletas y los eventos perdidos requieren análisis. Los períodos 22–06 no son automáticamente tiempo efectivo de uso ni prueban insomnio.

**Corrección deseada:** contar exclusivamente la intersección de **actividad realmente acreditada** + **pantalla interactiva (si la evidencia de Android lo permite)** + **ventana nocturna**; dividir sesiones que cruzan medianoche y horas; manejar incertidumbre sin inventar actividad. Probar días completos, noches parciales, suspensión/bloqueo, sesiones sin PAUSE, cambios de fecha y multitarea. Distinguir evento desconocido de cero minutos.

### H7 — Background existe, pero debe comprobarse de extremo a extremo (**código confirmado; fallo físico por diagnosticar**)

- `MainActivity.kt` programa trabajo periódico único con `WorkManager` a intervalo nominal de **15 minutos**; no garantiza ejecución exacta ni instantánea.
- `MonitoreoUsoWorker.kt` construye `FlutterEngine` headless y espera un mensaje Dart de completado mediante `CompletableFuture` (timeout de 4 min); ante excepción usa `Result.retry()`.
- `monitoreoCallbackDispatcher()` inicializa plugins y llama `_cicloDeMonitoreo()`; esta función inicializa SQLite/notificaciones y ejecuta `MotorRecomendaciones().ejecutar()` seguido de `RecomendacionesNotificador().notificarTodas(...)`.
- **Se confirma que `_cicloDeMonitoreo()` no llama expresamente `capturarUsoDelDia()`**. El contexto del motor consulta `uso_pantalla` de SQLite; **reglas que dependen del resumen diario (como R5/R6) pueden evaluar información obsoleta** si el usuario no pulsa recargar y no existe otro proceso que actualice esa tabla.
- El ciclo Dart tiene captura de errores y su callback **puede notificar «completado» al Worker incluso si internamente registró una excepción**. Esto dificulta distinguir éxito de fallo real.
- Es necesario verificar registro de plugins en headless, canal, permisos, política de reintentos, `Result` real, estado de trabajos, condiciones de batería/Doze en Motorola, concurrencia con interfaz, y el comportamiento tras cerrar la UI, expulsar la tarea o reiniciar. **Forzar detención («Forzar cierre») tiene restricciones de Android diferentes a cerrar la UI**.

**Flujo objetivo verificable:** permisos/estado → **captura o lectura actualizada** → persistencia consistente → construcción de contexto → motor R1–R8 → cooldown/duplicados → persistencia de recomendaciones → notificación permitida. Que **no dependa del botón recargar**. Sin prometer precisión de 15 minutos o tiempo real bajo Doze.

### H8 — SQLite: proteger integridad y reparar carreras (**confirmado parcialmente; verificar datos locales**)

- El archivo SQLite es `prototipo_tesis.db`; el esquema observado usa **versión 9**.
- Ya existe `guardarUsoDelDia()` con **transacción** para resumen diario y detalle por app: **preservarla**.
- `uso_pantalla.fecha` tiene restricción `UNIQUE`.
- `app_uso` **no declara `UNIQUE(fecha, nombrePaquete)`**; el `insertarOActualizarAppUso()` realiza consulta previa y luego `insert/update`. Esto **puede ser vulnerable a carreras** si varios ejecutores escriben al mismo tiempo. Revisar duplicados reales y migración no destructiva con clave compuesta o índice cuando proceda.
- `DatabaseHelper.database` inicializa su singleton asíncronamente sin compartir explícitamente un `Future` de apertura en la sección revisada; **investigar** riesgo de aperturas concurrentes entre consumidores/isolate (no afirmar todavía que explique los síntomas).
- Hay antecedente del error `SQLITE_MISMATCH` al intentar actualizar un `id` nulo; el código actual aplica `sinId(uso.toMap())` para evitar `SET id = NULL`. **No revertir esta corrección**.
- Las recomendaciones ya cuentan con claves/cooldown. Preservar idempotencia e historial; validar generación simultánea UI/Worker y evitar recomendaciones/notificaciones duplicadas.

### H9 — Campos de métricas que no deben presentarse como mediciones reales (**confirmado por código**)

- `numeroDesbloqueos` se obtiene contando eventos `KEYGUARD_HIDDEN` (tipo 18), deduplicados por instante; se observó **32**. Puede diferir de la semántica del fabricante.
- `numeroAperturas` de cada `AppUso` se fija actualmente en **1**; no constituye conteo real de aperturas. Dejar claramente marcado como provisional/no disponible hasta implementar medición basada en eventos con pruebas.

### H10 — Bienestar Digital es referencia de contraste, no base consultada por la app

**Bienestar Digital y controles parentales** y la aplicación consultan información del sistema Android, pero el prototipo **no lee directamente los números de la interfaz de Bienestar Digital**. Usa `UsageStatsManager` y aplica su propio procesamiento. Contrastar **tiempo total, TikTok, desbloqueos y hora de corte** con Bienestar Digital, y documentar que diferencias de definición/ventana/fabricante pueden persistir; no exigir igualdad exacta sin comprobar semánticas.

---

## 3A. Hallazgo adicional: alertas distractoras, comprobaciones y cooldown

**Escenario reportado para analizar:** usuario con **42 minutos de TikTok**. No presupongas que se enviará un aviso inmediatamente al minuto 30 o al minuto 42.

- La configuración histórica de R1/R2 utiliza un umbral de **más de 30 minutos** (`> 30`, no `>= 30`) dentro de condiciones contextuales. **R1** consideraba el acumulado de apps distractoras dentro de horarios; **R2**, los minutos de la aplicación distractora principal dentro de horario laboral. Verifica estas condiciones de nuevo en la copia local.
- El ciclo en segundo plano estaba programado mediante WorkManager con período solicitado de **15 minutos**. Esto **no** constituye una alarma exacta ni garantiza ejecución en cada marca de 15 minutos; Doze, políticas de batería y restricciones del fabricante pueden retrasarla.
- El cooldown por defecto de distractores era de **90 minutos** y la comparación de duplicados dependía de regla, clave de equivalencia, día/horario y fecha de la recomendación. La alerta puede repetirse **solo si** sigue cumpliéndose la condición y el cooldown lo permite. No asumas repetición por cada revisión de Worker.
- Las notificaciones se filtraban por severidad (`advertencia`, `critica`) y permiso de Android. Generar una recomendación en SQLite **no prueba** que aparezca una notificación.
- Posible defecto semántico: una regla basada en acumulado histórico puede avisar **después de que TikTok dejó de estar abierta**, porque no verifica necesariamente que esa app siga en primer plano en el instante de evaluación. Diseña tests para alertas oportunas y evitar falsos positivos, sin imponer detección instantánea de forma no viable.
- **R3:** una tarea prioritaria activa con distracción puede activar una advertencia antes del umbral de 30 min de R1/R2. La selección/prioridad y cooldown por regla requieren pruebas específicas.
- Confronta siempre: (a) tiempo acumulado por app, (b) uso distractor solapado con horario, (c) sesión activa actual, (d) actualización de contexto, (e) ejecución efectiva del Worker, (f) inserción de recomendación, (g) canal y permiso de notificación, (h) entrega visible.

**Criterios específicos de validación:** testear 29, 30, 31 y 42 minutos; horario académico/laboral/sin horario; una sola y varias apps; pantalla bloqueada; app cerrada; permiso concedido/denegado; Worker diferido; alerta emitida y cooldown activo/expirado. El resultado debe explicar *por qué* se notificó o se omitió.

---

## 4. Prioridades consolidadas

| Prioridad | Asunto | Motivo | Fases |
|---|---|---|---|
| **P0** | Integridad de muestras, transacciones, duplicados y carreras | Riesgo de corrupción, muestras falsas o recomendaciones repetidas | F0, F1, F5 |
| **P0** | Monitoreo/background sin intervención del usuario | Funcionalidad esencial reportada como fallida | F0, F2, F5 |
| **P0** | Tiempo de pantalla imposible: 1131 min a las 12:34 | Invalida Dashboard, porcentajes y evaluaciones derivadas | F0, F3, F4, F5 |
| **P1** | R7 nocturna / pantalla apagada / horas mal imputadas | Genera recomendaciones potencialmente falsas | F3, F5 |
| **P1** | TikTok 123 min frente a 25 min distractores; clasificación | Riesgo de inconsistencias entre reglas, pantallas y métricas | F3, F4 |
| **P1** | Manejo de fallas, permisos y éxito real del Worker | Diagnóstico de notificaciones ausentes | F2, F5 |
| **P2** | Pulido de UI, estados sin datos y evolución | Claridad de información sin ocultar fallas | F4 |
| **P2** | Documentación y evidencia para tesis | Reproducibilidad de resultados | F6 |

**Orden recomendado:** F0 → F1 → F2 → F3 → F4 → F5 → F6. Cada fase requiere resultado local verificable; no ejecutar la siguiente automáticamente. Los defectos de medición constituyen P0 y deben investigarse **desde F0**, aunque su corrección estructural pertenezca a F3.

---

## 5. Plan de refactorización: siete fases independientes

> Los siguientes son **siete encargos autónomos** para Codex, no un solo pedido de implementar todo. Cada fase debe cerrarse con cambios acotados, pruebas y un informe. Los nombres y objetivos F0–F6 recuperan el plan de la conversación anterior y se enriquecen con el diagnóstico de métricas de este chat.

### Fase 0 — Auditoría, línea base y pruebas de regresión (SIN cambiar lógica)

**Prompt para Codex — F0:**

```text
Trabaja exclusivamente sobre /home/ushe/Documentos/Proyecto-Android/Prototipo. Realiza SOLO la FASE 0: diagnóstico y línea base, sin modificar lógica de negocio, migrar datos ni reinstalar la app.

1. Identifica rama/commit, cambios locales, estado Flutter/Dart/Gradle/Android, manifest, permisos y configuración del dispositivo ADB.
2. Traza todas las rutas de captura, cálculo, persistencia y presentación de métricas (Dashboard, Uso, reglas, background). Confirma cómo se obtienen minutos, porcentajes, desbloqueos, distractores y hora de corte.
3. Usa como escenario de referencia: 12:34 Dashboard 1131 min / 25 min distractores / 2 %; 12:42 Uso 426 min / 32 desbloqueos / TikTok 123 min. Es evidencia reportada, no datos que debas inventar ni resultados actuales.
4. Analiza sin alterar los datos las sesiones superpuestas, duraciones nocturnas, discrepancia de paquetes, estados de WorkManager, fallos ocultos y carreras SQLite.
5. Si ADB funciona, recoge SOLO evidencias necesarias de modo privado, minimizado y de lectura; coteja con Bienestar Digital. No hagas dumps públicos de hábitos/paquetes.
6. Ejecuta flutter analyze y las pruebas existentes; registra qué pasa y qué falla. Incorpora únicamente tests/fixtures aislados si se autoriza mantenerlos en F0, sin cambiar producción.
7. Produce un informe de línea base con reproducciones, hipótesis, rutas, funciones, comandos, resultados, riesgos y plan de parches.

Descubre y lee primero las skills disponibles en /home/ushe/.dsh/skills; utiliza Ponytail y Caveman si existen y son pertinentes; cita las skills aplicadas en el reporte.

Aceptación: diagnóstico reproducible y trazable; archivos locales intactos salvo artefactos de reporte/tests expresamente aprobados; sin pérdida de datos; inventario claro de prioridades P0/P1/P2.
```

**Archivos a inspeccionar:** todos los de la tabla de rutas, `test/`, manifiesto, Gradle, documentación técnica y estado del dispositivo.  
**Pruebas:** `flutter analyze`, `flutter test`, revisión de WorkManager/ADB y comparación de métricas.  
**Salida:** reporte antes/después base, sin afirmar correcciones.

### Fase 1 — Integridad de SQLite, transacciones e idempotencia

**Prompt para Codex — F1:**

```text
Implementa SOLO la FASE 1 después de cerrar la auditoría F0 y proteger los datos existentes.

Objetivo: robustecer SQLite frente a concurrencia, duplicados, upserts no atómicos y aperturas simultáneas, sin borrar ni alterar semánticamente el historial.

Revisa DatabaseHelper, uso_pantalla, app_uso, recomendaciones y sus consumidores UI/background. Conserva guardarUsoDelDia() y su transacción; conserva la solución sinId() contra SQLITE_MISMATCH. Comprueba duplicados reales en app_uso, las claves de cooldown y cómo compiten distintos isolates/procesos. Decide y justifica índices/restricciones UNIQUE, deduplicación previa y migraciones incrementales; no supongas que version: 9 sigue siendo la última en la copia local. Si hay migración, debe ser reversible mediante respaldo y probada contra base antigua.

Añade pruebas de SQLite con sqflite_common_ffi para: inserción repetida, simultaneidad, rollbacks, datos históricos, versiones previas y preservación de recomendaciones/valoraciones. No modifiques reglas R1–R8 ni interfaz en esta fase.

Entrega diff acotado, pruebas ejecutadas y evidencia de que dos capturas/recomendaciones concurrentes no duplican filas ni corrompen el estado.
```

**Archivos prioritarios:** `lib/database/database_helper.dart`, modelos persistidos, repositorio de reglas/cooldown, `test/database_transacciones_test.dart` y pruebas de migración.  
**Aceptación:** upsert idempotente, transacción íntegra, historial preservado, pruebas de migración y concurrencia verdes.

### Fase 2 — WorkManager, ejecución headless y notificaciones sin recargar

**Prompt para Codex — F2:**

```text
Implementa SOLO la FASE 2: reparar y verificar el monitoreo de uso cuando la aplicación está cerrada, sin requerir el botón recargar.

Audita MainActivity.kt, MonitoreoUsoWorker.kt, monitoreo_segundo_plano_service.dart, canales MethodChannel, DartPluginRegistrant, inicialización de FlutterEngine y dependencias. Observa Doze, permisos UsageStats y notificaciones, restricciones de batería del Motorola, WorkManager, reintentos, timeouts, errores reales, y posibles conflictos con una ejecución manual en UI.

Comprueba explícitamente si el ciclo background captura estadísticas actualizadas y las persiste ANTES de evaluar reglas que consumen uso_pantalla de SQLite. El código revisado llama MotorRecomendaciones().ejecutar() sin capturarUsoDelDia() de forma explícita. Corrige el flujo sin consultas innecesarias y evita duplicar lógica con el Dashboard.

No informes Result.success cuando el ciclo Dart haya fallado realmente; propaga/registrar un estado verificable de éxito, error o cancelación sin datos sensibles. Asegura comportamiento correcto de inicio/parada, trabajo único, reintentos con límites y ausencia de alertas duplicadas mediante cooldown. No prometas latencia exacta de 15 minutos.

Valida con ADB y logs minimizados: UI visible, app en segundo plano, UI cerrada, pantalla apagada, reinicio, restricciones de batería y permiso revocado. Distingue cerrar interfaz de forzar detención.

No cambies umbrales R1–R8 ni la presentación del Dashboard. Entrega pruebas automatizadas donde sea viable, más protocolo físico reproducible y resultados observados.
```

**Archivos prioritarios:** `MainActivity.kt`, `MonitoreoUsoWorker.kt`, `monitoreo_segundo_plano_service.dart`, `contexto_recomendacion_service.dart`, `motor_recomendaciones.dart` y pruebas nativas/Dart.  
**Aceptación:** tareas programadas verificables, captura/contexto frescos, estado de error propagado, notificaciones permitidas sin tocar recarga, sin duplicados bajo concurrencia y con limitaciones Android documentadas.

### Fase 3 — Métricas temporales, clasificación y motor R1–R8 (incluida R7)

**Prompt para Codex — F3:**

```text
Implementa SOLO la FASE 3: corregir la semántica del tiempo de pantalla, uso contextual y motor de reglas R1–R8, usando el diagnóstico de F0 y la integridad de F1/F2.

1. Introduce una fuente/capa común de intervalos con pruebas, manteniendo por separado (a) tiempo por app y (b) tiempo único de pantalla sin solapamientos. Maneja RESUME/PAUSE, eventos perdidos, cambios de foreground, pausas, pantalla apagada, sesiones sin cierre, multiventana y cortes de medianoche, sin inventar uso en períodos desconocidos.
2. Corrige el conteo que permitió mostrar 1131 minutos a las 12:34 (754 min transcurridos). La unión temporal del uso real no debe superar su ventana consultada. No lo soluciones con un clamp cosmético.
3. Distribuye cada sesión por la hora/calendario correctos, en lugar de asignar toda su duración a la hora de inicio. Unifica ventanas de hoy/ayer y manejo de datos insuficientes.
4. Para R7, contabiliza solo actividad acreditada dentro de 22:00–06:00 y, cuando la API lo permita, pantalla interactiva. No clasifiques horas de sueño o pantalla apagada como uso sin evidencia. Verifica el umbral 60 min/día × 7 días = 420 min para R7 y el criterio separado de sugerencia nocturna (>60 min del agregado); decide si es coherente y documenta cualquier cambio de criterio antes de hacerlo.
5. Unifica el clasificador de paquetes: la comparación usa contains exacto y otros módulos clasifican por prefijo. Incluye com.zhiliaoapp.musically (TikTok) y respeta configuración del usuario. Distingue minuto distractor diario de distractor en horarios/tareas.
6. Conserva prioridad, cooldown, severidad, claves de equivalencia e historial R1–R8. Evita recomendaciones falsas por datos parciales o errores de permisos.

Pruebas obligatorias: solapamientos, split-screen, RESUME sin PAUSE, PAUSE huérfano, 23:50–00:20, 22:00–06:00 bloqueado, pantalla encendida sin app acreditada, comparación hoy/ayer, paquetes con prefijo/sufijo, datos sin permiso, umbrales exactos, cooldown y reglas R1–R8.

Entrega explicación causal, invariantes matemáticas, pruebas unitarias y evidencia de valores consistentes en el dispositivo.
```

**Archivos prioritarios:** `monitoreo_uso_horarios_service.dart`, `intervalo_uso.dart`, `uso_pantalla_service.dart`, `analisis_horario_service.dart`, `contexto_recomendacion_service.dart`, `contexto_recomendacion.dart`, `reglas_por_defecto.dart`, `configuracion_motor.dart`, `comparacion_diaria.dart`, pruebas temporales/reglas.  
**Aceptación:** ningún tiempo único supera el intervalo real; R7 no inventa actividad con pantalla bloqueada; clasificación y comparaciones coherentes; motor y cooldown sin regresiones.

### Fase 4 — Consistencia visual y actualización de Flutter

**Prompt para Codex — F4:**

```text
Implementa SOLO la FASE 4: adaptar las pantallas Dashboard, Uso y Tips a las métricas canónicas corregidas, sin reescribir el motor ni volver a cambiar SQLite sin necesidad.

El Dashboard mostraba 1131 min y Uso 426 min para casi la misma hora: deben compartir la misma definición de tiempo, hora de corte, estado de actualización y etiqueta de procedencia. Define un estado claro para sin permiso, datos insuficientes, captura antigua, captura en curso y error. Diferencia tiempo total, minutos en apps distractoras y distractor contextual de horarios. Mantén el donut matemáticamente seguro y deja claro que el porcentaje distractor NO representa productividad.

Evita recapturas duplicadas al alternar pestañas, setState tras dispose, múltiples workers por pulsar actualizar y consultas innecesarias; la actualización manual no debe ser requisito para que exista monitoreo programado. Conserva las vistas de comparación diaria y evolución de siete días, sin inventar ceros ni implicar causalidad de las recomendaciones.

Ejecuta tests de widgets, navegación, estados vacíos, formatos 7h6min, porcentajes y accesibilidad; prueba con tema claro/oscuro y datos reales/simulados trazables.
```

**Archivos prioritarios:** `lib/screens/dashboard_screen.dart`, `lib/screens/uso_screen.dart`, `lib/screens/recomendaciones_screen.dart`, modelos de comparación/evolución, pruebas de widgets.  
**Aceptación:** Dashboard y Uso consistentes a la misma hora de corte, estados comprensibles, sin refrescos o escrituras redundantes y pruebas visuales/funcionales verdes.

### Fase 5 — Integración Android real, rendimiento y regresión

**Prompt para Codex — F5:**

```text
Implementa SOLO la FASE 5: pruebas de integración, confiabilidad y rendimiento después de las correcciones F1–F4.

Usa un Motorola G84 Android 15 conectado mediante ADB y, cuando sea viable, escenarios de automatización. Verifica el ciclo completo: permiso → lectura → captura → persistencia → contexto → reglas → cooldown → notificación → visualización. Contrasta time windows idénticas entre Dashboard, Uso, registros y Bienestar Digital nativo, explicitando diferencias legítimas de definición.

Prueba escenarios con app abierta/cerrada, usuario que nunca pulsa recargar, pantalla bloqueada de noche, cambios de fecha, alternancia de aplicaciones, split-screen, cortes del sistema, restricciones de energía, reinicio, revocación de permisos y trabajos concurrentes UI/background.

Mide overhead razonable de batería/CPU/lecturas y comprueba ausencia de pérdida de datos, locks, duplicados, notificaciones en tormenta, manejo fallido de FlutterEngine y regresiones R1–R8. No garantices periodicidad exacta de WorkManager; documenta los límites de Android.

Produce matriz de prueba con dispositivo/versión, caso, input, output esperado, output observado, logs mínimos, estado PASS/FAIL y riesgos residuales. Ejecuta flutter analyze, flutter test y compilación Android.
```

**Archivos prioritarios:** tests de integración, scripts reproducibles, manifiesto, rutas background, servicios y `INFORMES/`.  
**Aceptación:** métricas razonables y consistentes, notificaciones verificadas dentro de las restricciones del SO, pruebas automatizadas y manuales documentadas, sin regresiones ni pérdida de datos.

### Fase 6 — Documentación técnica, trazabilidad y cierre académico

**Prompt para Codex — F6:**

```text
Implementa SOLO la FASE 6: cierre documental y entrega de la refactorización, basándote exclusivamente en cambios realmente implementados y pruebas realmente ejecutadas.

Actualiza README e informes del proyecto, arquitectura de captura y background, diagramas de flujo si los existentes están desactualizados, diccionario de métricas, clasificación de distractores, especificación R1–R8/R7, límites de UsageStats/WorkManager, esquema SQLite/migraciones y controles de privacidad.

Elabora una tabla hallazgo → causa confirmada → archivo/cambio → prueba → evidencia → riesgo residual. Diferencia hipótesis previas de errores demostrados. Documenta cómo reproducir los casos 1131/426/25/123 y cómo se verificó su resolución (o por qué quedan pendientes).

Prepara texto técnico reutilizable en la tesis, sin aseverar mejoras de productividad no demostradas ni atribuir causalidad a recomendaciones. Adjunta resultados de flutter analyze/test/build y matriz de pruebas físicas. Revisa que la documentación no contradiga el estado final del repositorio.

Entrega changelog, decisiones arquitectónicas, recomendaciones para mantenimiento y lista explícita de pendientes no resueltos.
```

**Archivos prioritarios:** `README.md`, `INFORMES/`, documentación metodológica, pruebas y registro de cambios.  
**Aceptación:** documentación exacta respecto a la implementación final, resultados verificables y límites científicos/técnicos explicitados.

---

## 6. Matriz de validación mínima para las correcciones

| ID | Escenario | Resultado exigido |
|---|---|---|
| T01 | Desde 00:00 hasta 12:34 | Tiempo **único** de pantalla ≤ 754 min; si no se puede calcular, mostrar insuficiente, no inventar |
| T02 | App A 08:00–09:00 y app B 08:15–08:45 | Por app conservar sus duraciones; **tiempo único** = 60 min, no 90 |
| T03 | Inicio de actividad 23:50, cierre 00:20 | Distribución correcta 10 min antes y 20 min después de medianoche |
| T04 | Intervalo 23:00–05:00 con pantalla bloqueada/no interactiva | No adjudicar automáticamente 360 min nocturnos de uso activo |
| T05 | RESUME sin PAUSE; PAUSE sin RESUME | No extender uso ficticio sin evidencia; indicar incertidumbre y límites |
| T06 | TikTok `com.zhiliaoapp.musically` y paquetes con sufijos | Clasificador consistente en Dashboard, contexto y reglas, respetando configuración |
| T07 | Hoy/ayer consultados hasta 12:34 | Comparar ventanas equivalentes; porcentaje nulo con denominador cero |
| T08 | Múltiples refrescos y worker simultáneos | Un único resumen por fecha y paquete, recomendaciones idempotentes |
| T09 | App fuera de primer plano, sin tocar recargar | Trabajo programado y ciclo de datos/recomendación/notificación verificables, sujetos a Android |
| T10 | R7 justo en umbral de 420 min/7 días | Respetar `>` frente a `>=` actual, salvo cambio deliberado documentado |
| T11 | Error de plugin o permiso denegado | No mostrar éxito engañoso, ni cero falso; error/insuficiente recuperable |
| T12 | Migración desde BD anterior | Preservar tareas, horarios, uso, recomendaciones y valoraciones |
| T13 | Repetición del mismo ciclo background | Sin duplicados dentro del cooldown; errores distinguibles de éxito |
| T14 | Comparación contra Bienestar Digital | Comparar a igual ventana y documentar diferencia de semántica o fabricación |

**Advertencia metodológica:** T02 representa la unión temporal de intervalos, no la suma del uso por aplicación. Distintos indicadores admiten definiciones diferentes, pero deben llevar nombres precisos.

---

## 7. Preparación segura de entorno Codex + Android

### Verificación no destructiva inicial

```bash
pwd
git status --short --branch  # SOLO LOCAL; no consultar remotos
flutter doctor -v
flutter devices
adb devices -l
flutter analyze
flutter test
```

**Acceso al teléfono:** habilitar opciones de desarrollador y depuración autorizada; comprobar que el identificador figure como `device`. Si se utiliza ADB inalámbrico, realizar emparejamiento seguro; no exponer el puerto de depuración a redes no confiables.

**Lectura diagnóstica sujeta a permisos y versión de Android:**

```bash
adb shell dumpsys usagestats
adb shell dumpsys jobscheduler
```

Esas salidas pueden ser extensas, contener información privada o estar restringidas. Filtrar a la aplicación y al período del ensayo, sanitizar antes de compartir, y no subirlas al repositorio. Para SQLite, intentar acceso **solo si la compilación es depurable y `run-as` lo permite**; el paquete real (`applicationId`) y la ruta deberán descubrirse, no inventarse. Evitar comandos de borrado o reinstalación antes del respaldo.

**Reglas de interpretación para ADB:**
- Una tarea WorkManager **programada** no equivale a una tarea **ejecutada correctamente**.
- Una recomendación **generada** no equivale a una notificación **entregada/mostrada**.
- Pantalla **encendida** no implica necesariamente **uso consciente**; evento RESUME aislado no prueba uso continuo.
- No se puede inferir que el usuario durmió o estuvo despierto únicamente desde una franja horaria.
- La app de Codex y esta conversación web **no comparten automáticamente acceso al directorio ni al móvil**; el agente local necesita permisos y conexión en su propia sesión.

---

## 8. Contratos que deben preservarse

1. **No perder datos locales ni historial**: tareas, horarios, recomendaciones, valoraciones, muestras y preferencias.
2. **No romper el motor R1–R8** ni sus prioridades, ámbitos de cooldown y claves de equivalencia.
3. **No convertir los valores desconocidos en ceros** cuando faltan permisos/eventos/días.
4. **No confundir categorías**: uso total ≠ uso distractor ≠ uso distractor dentro de horarios ≠ productividad.
5. **No atribuir causalidad**: disminución de minutos no demuestra que las recomendaciones produjeron el cambio.
6. **No camuflar errores** con límites visuales; corregir la fuente y establecer invariantes.
7. **No prometer tiempo real** si el mecanismo depende de periodicidad diferida por WorkManager/Doze.
8. **No añadir servicios persistentes o permisos invasivos** sin justificar beneficio, riesgos y compatibilidad Android 13–15.
9. **No hardcodear conclusiones sobre paquetes** sin inspeccionar su identificación en el dispositivo; mantener configurable la clasificación cuando proceda.
10. **No presentar `numeroAperturas = 1` como un conteo real**.

---

## 9. Formato de reporte exigido a Codex al terminar cada fase

```text
Fase ejecutada:
Rama/commit base:
Archivos examinados:
Problema(s) reproducido(s):
Causa(s) confirmada(s), con evidencia:
Hipótesis aún no confirmadas:
Cambio(s) realizados y motivo:
Migraciones / impacto en datos:
Pruebas ejecutadas, comando y resultado real:
Validación física / ADB, si ocurrió:
Riesgos y límites de Android:
Pendientes:
Criterios de aceptación: PASS / FAIL / NO VERIFICADO:
Siguiente fase sugerida:
```

**Definición de «corregido»:** existe una causa identificada, modificación que la atiende, una prueba que fallaba antes y pasa después o evidencia equivalente de comportamiento físico, sin regresiones observadas. No basta con cambiar el código o que deje de aparecer el síntoma una vez.

---

## 10. Referencias exclusivamente locales y antecedentes

- **Proyecto:** `/home/ushe/Documentos/Proyecto-Android/Prototipo`.
- **Skills:** `/home/ushe/.dsh/skills`.
- **Código, tests y documentación:** inspeccionar dentro del proyecto (`lib/`, `android/`, `test/`, `INFORMES/`, `README.md`, `pubspec.yaml`, configuración Gradle y manifiestos), sin asumir que todas las rutas antiguas todavía existen.
- **Antecedentes conversacionales:** «Plan de refactorización por fases» y el análisis de discrepancias entre Dashboard/Uso, R7, notificaciones y uso en segundo plano. Son evidencia histórica y objetivos a validar, **no prueba del estado actual del directorio local**.

---

## 11. Mensaje de ejecución inicial (copiar en Codex)

```text
Inspecciona exclusivamente /home/ushe/Documentos/Proyecto-Android/Prototipo.
Primero descubre y lee las skills pertinentes dentro de /home/ushe/.dsh/skills, incluidas Ponytail y Caveman si existen. No consultes ni compares GitHub; no hagas fetch, pull, push, PR ni ninguna sincronización. Todos los archivos, reportes, pruebas y cambios deben permanecer locales.

Lee este documento completo y comienza SOLO la Fase 0, una auditoría no destructiva. Inventaría las rutas reales, el estado local, las pruebas, los permisos, y la conexión ADB si está disponible. Identifica el origen de los valores históricos 1131 min a las 12:34 en Dashboard frente a 426 min a las 12:42 en Uso, TikTok 123 min frente a 25 distractores, la posible imputación falsa de R7, y las notificaciones que no llegan sin actualizar. Revisa también el comportamiento de R1/R2, la frecuencia de WorkManager y el cooldown.

Distingue evidencia histórica de lo actualmente reproducido. Entrega un informe de F0 con causas confirmadas, hipótesis, pruebas ejecutadas, estado de datos, riesgos y plan de cambios locales. No modifiques código de producción ni datos sin autorización para pasar a la siguiente fase.
```

**Fin del prompt maestro.**
