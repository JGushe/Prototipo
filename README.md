<p align="center">
  <img src="Iconos%20y%20datos/dopalytics_logo.png" alt="Dopalytics" width="140">
</p>

# Dopalytics

**Comprende tus hábitos. Decide sobre tu tiempo.**  
*Understand your habits. Own your time.*

Aplicación Android desarrollada en Flutter como prototipo académico. Integra gestión de tareas, planificación de horarios y análisis del uso de aplicaciones para ayudar a reconocer hábitos digitales y administrar el tiempo dedicado al teléfono.

> **Título de la investigación:** Desarrollo de un prototipo de aplicación móvil Android para la gestión de tareas y horarios, mediante el monitoreo del tiempo de pantalla y uso de aplicaciones, orientado a la reducción de distracciones digitales.

## Identidad y objetivos

Dopalytics combina los términos ingleses *dopamine* y *analytics*. La primera parte alude a los procesos de motivación y recompensa vinculados con los hábitos; la segunda representa el análisis de los patrones de uso del dispositivo. Es una relación conceptual: la aplicación analiza comportamiento digital, sin medir dopamina ni realizar evaluaciones clínicas.

La identidad se centra en la autonomía del usuario, la responsabilidad personal y la claridad de la información. Las estadísticas y recomendaciones buscan ayudar a reconocer posibles distracciones y tomar decisiones acordes con las actividades planificadas, con un lenguaje directo y respetuoso que no culpabiliza por usar el teléfono.

La identidad visual usa un icono minimalista y una paleta de azul profundo, blanco y acentos turquesa.

**Objetivo general:** apoyar la gestión consciente del tiempo y la autorregulación digital mediante la integración de tareas, horarios y estadísticas de uso del dispositivo Android, con recomendaciones basadas en reglas orientadas a reducir posibles distracciones durante actividades académicas y laborales.

**Objetivos específicos:**

1. Facilitar la organización de responsabilidades con tareas, prioridades y horarios.
2. Presentar estadísticas de uso que permitan reconocer la distribución del tiempo en el dispositivo, considerando los límites de los datos de Android.
3. Identificar posibles distracciones al cruzar el uso de aplicaciones con tareas y horarios planificados.
4. Proporcionar recomendaciones contextualizadas y notificaciones, con mecanismos que limiten mensajes equivalentes repetidos.
5. Facilitar el seguimiento de hábitos digitales mediante registros de uso y recomendaciones.

La contribución efectiva a la reducción de distracciones y a la productividad debe comprobarse con validación de usuarios; este repositorio no la declara demostrada.

## Contexto y propósito

La distracción digital sostenida afecta la concentración y la planificación del estudio o del trabajo. El prototipo explora si una aplicación local puede:

- organizar tareas, prioridades, vencimientos y bloques de trabajo;
- medir el uso real del teléfono mediante APIs de Android;
- generar recomendaciones explicables a partir de reglas contextuales;
- mostrar la evolución del uso sin atribuir causalidad a las recomendaciones.

Es un prototipo funcional, no un producto clínico ni una herramienta de diagnóstico. Todos los datos se almacenan en el dispositivo.

## Características principales

| Módulo | Funcionalidad implementada |
|---|---|
| Tareas | CRUD completo, prioridad alta/media/baja, estado pendiente/completada, fecha de vencimiento, planificación por día y franja horaria |
| Recordatorios | Notificación local 30 minutos antes del vencimiento, reprogramable y cancelable |
| Uso de pantalla | Tiempo total diario, detalle por aplicación, desbloqueos reales, uso por hora |
| Monitoreo en segundo plano | Ciclo periódico con WorkManager cada ~15 minutos y ejecución headless |
| Recomendaciones | Motor de reglas R1–R8, contexto unificado, severidad, cooldown y explicación del motivo |
| Dashboard | Métricas del día, dona de distractor, comparación Hoy/Ayer, evolución de 7 días, valoraciones y lectura compartida |
| Perfil | Nombre o apodo, identidad de género opcional, apariencia persistida, sin autenticación externa |
| Apariencia | Modo claro/oscuro/sistema y paletas Cool, Warm y RGB con Material 3 |

## Arquitectura

```text
Flutter (Dart)                         Android (Kotlin)
┌───────────────────────────┐          ┌────────────────────────────┐
│ Pantallas y tema           │          │ MainActivity               │
│ Servicios de análisis      │          │ MonitoreoUsoWorker         │
│ Motor de reglas R1–R8      │◄────────►│ UsageStatsManager          │
│ SQLite (sqflite)           │ canales  │ WorkManager (15 min)       │
│ Notificaciones locales     │          │ Notificaciones programadas │
└───────────────────────────┘          └────────────────────────────┘
```

### Capas en `lib/`

- `models/`: entidades y cálculos puros (tarea, horario, uso, recomendación, evolución, comparación diaria, perfil).
- `services/`: adquisición de uso, análisis por horarios, contexto, motor de reglas, cooldown, notificaciones y monitoreo en segundo plano.
- `services/reglas/`: reglas como datos, evaluador, creador de recomendaciones, política de cooldown y repositorio.
- `database/`: una sola clase `DatabaseHelper` con esquema, migraciones y CRUD.
- `screens/`: Dashboard, Tareas, Uso, Tips (recomendaciones) y Configuración.
- `widgets/`: piezas de interfaz reutilizables, como la etiqueta de estado de lectura de uso.
- `theme/`: tokens primitivos, seis paletas, `ThemeData` y controlador de apariencia.

### Flujo de una ejecución

1. Se construye el contexto: horarios activos, tareas planificadas, uso por aplicación, uso por hora, uso nocturno y permiso de UsageStats.
2. El evaluador comprueba las condiciones de cada regla.
3. La política de cooldown descarta recomendaciones equivalentes dentro de su ventana.
4. Las recomendaciones nuevas se guardan en SQLite con regla, severidad y motivo.
5. Solo las severidades `advertencia` y `critica` se notifican, con un identificador estable por regla.
6. El Dashboard y Tips leen el histórico; la valoración de utilidad se guarda por recomendación.

### Ciclo de monitoreo y lectura compartida

- `CicloMonitoreoService` ejecuta la misma secuencia (captura, contexto, reglas, notificación) tanto desde la actualización manual como desde WorkManager.
- `LecturaUsoController` centraliza la lectura de uso de la interfaz: una sola consulta por sesión, reutilizada al cambiar de pestaña, con vigencia de 5 minutos.
- El estado de la lectura distingue `leyendo`, `actualizando`, `sinPermiso`, `sinDatos`, `disponible`, `antigua` y `error`. Cambiar de pestaña no escribe en SQLite.
- Si falla el envío de notificaciones después de guardar recomendaciones, el ciclo informa el fallo; las recomendaciones ya persistidas quedan en cooldown y no se duplican al reintentar.

### Integración nativa

- `MainActivity.kt` registra el canal `prototipo_tesis/monitoreo` y programa el trabajo periódico con `PeriodicWorkRequestBuilder<MonitoreoUsoWorker>(15, TimeUnit.MINUTES)`.
- `MonitoreoUsoWorker.kt` arranca un `FlutterEngine` headless y ejecuta el mismo punto de entrada Dart que la interfaz. El isolate avisa por el canal `prototipo_tesis/monitoreo_completado`.
- La lectura de estadísticas se realiza con el plugin `usage_stats` sobre `UsageStatsManager` y `PackageManager`.

## Tecnologías

| Componente | Versión o configuración |
|---|---|
| Flutter | 3.47.2 (verificado en el entorno de desarrollo) |
| Dart | restricción `>=3.2.0 <4.0.0` en `pubspec.yaml` |
| Android mínimo | `minSdk = 29` (Android 10) |
| Compilación | `compileSdk` y `targetSdk` tomados de Flutter; Java/Kotlin 17 |
| Base de datos | SQLite con `sqflite`, esquema versión 9 |
| Trabajo periódico | WorkManager, intervalo mínimo de 15 minutos |
| Gráficos | `fl_chart` |

### Dependencias directas

| Paquete | Uso |
|---|---|
| `sqflite`, `path` | Persistencia local y rutas de base de datos |
| `usage_stats` | `UsageStatsManager` y metadatos de aplicaciones |
| `flutter_local_notifications`, `timezone` | Recordatorios y alertas locales |
| `permission_handler` | Permiso de notificaciones |
| `fl_chart` | Dona, barras y línea de tendencia |
| `intl` | Formato de fechas |

Dependencias de desarrollo: `flutter_test`, `flutter_lints` y `sqflite_common_ffi` (pruebas SQLite reales en escritorio).

## Estructura del repositorio

```text
lib/
├── main.dart                    # MaterialApp, navegación y tema activo
├── database/database_helper.dart
├── models/                      # tarea, horario, uso, recomendación, evolución, perfil
├── screens/                     # dashboard, tareas, uso, recomendaciones, configuración
├── services/
│   ├── reglas/                  # R1–R8, evaluador, cooldown, repositorio
│   ├── analisis_horario_service.dart
│   ├── ciclo_monitoreo_service.dart
│   ├── lectura_uso_controller.dart
│   ├── monitoreo_uso_horarios_service.dart
│   ├── monitoreo_segundo_plano_service.dart
│   ├── motor_recomendaciones.dart
│   └── notificacion_service.dart
├── widgets/                     # componentes de interfaz reutilizables
├── theme/                       # tokens, paletas, ThemeData y controlador
android/app/src/main/kotlin/com/prototipo/prototipo_tesis/
├── MainActivity.kt
└── MonitoreoUsoWorker.kt
android/app/src/androidTest/     # prueba de instrumentación del worker
test/                            # pruebas unitarias, SQLite y de widgets
INFORMES/                        # informes por etapa y por fase de refactorización
```

## Instalación y ejecución

Requisitos: Flutter estable, Android SDK, un teléfono Android con depuración USB o ADB inalámbrico.

```bash
git clone https://github.com/JGushe/Prototipo.git
cd Prototipo
flutter pub get
adb devices
flutter run -d <device_id>
```

Si las dependencias ya están en caché local, `flutter pub get --offline` evita descargas.

No se requieren servicios externos ni credenciales. Para actualizar una instalación existente sin perder datos se usa el mismo `flutter run`; no es necesario desinstalar la aplicación. La actualización requiere una firma compatible con la instalación previa.

## Permisos Android

| Permiso | Uso real | Concesión |
|---|---|---|
| `PACKAGE_USAGE_STATS` | Leer tiempo de pantalla, uso por app, eventos y desbloqueos | Acceso especial: Ajustes > Aplicaciones > Acceso especial > Uso de la aplicación |
| `POST_NOTIFICATIONS` | Recordatorios y alertas (Android 13+) | Diálogo del sistema |
| `SCHEDULE_EXACT_ALARM` | Programar recordatorios exactos | Se solicita al iniciar; si no está concedido, la app usa alarma inexacta |
| `QUERY_ALL_PACKAGES` | Resolver nombres e iconos de aplicaciones monitorizadas | Concedido en instalación |
| `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK` | Mantener el trabajo periódico tras reinicios y en reposo | Concedidos en instalación |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Declarado para entornos de prueba; la app no lo solicita actualmente | Sin solicitud desde la app |

El manifiesto también declara permisos de servicio en primer plano, aunque el ciclo periódico implementado usa WorkManager, no un servicio en primer plano.

## Tareas y horarios

- Cada tarea admite prioridad, descripción, vencimiento y planificación opcional (`fechaPlanificada`, hora de inicio y fin).
- Una franja puede cruzar la medianoche; la lógica lo contempla al detectar la tarea activa.
- Los horarios tienen categoría (laboral, académico o personalizado), rango horario, días de la semana, nombre visible y activación individual. Se admiten hasta 20 horarios.
- El contexto usa solo horarios activos. Si varios se solapan, se prioriza laboral/académico y luego la hora de inicio.
- El título es obligatorio y la fecha de vencimiento se limita a un año desde hoy.
- Los recordatorios se cancelan y reprograman al editar, completar o eliminar una tarea.

## Motor de recomendaciones

Cada regla es un dato con identificador, prioridad, condiciones explicables, severidad y ventana de cooldown. Añadir una regla no requiere modificar el motor.

| Regla | Condición | Severidad | Cooldown |
|---|---|---|---|
| R1 | Horario académico activo y más de 30 min en apps distractoras dentro del horario | Advertencia | 90 min (ámbito horario) |
| R2 | Horario laboral activo y una app distractora supera 30 min dentro del horario | Advertencia | 90 min (ámbito horario) |
| R3 | Tarea planificada activa de prioridad alta y uso distractor en el mismo periodo | Advertencia | 90 min |
| R4 | Más de 5 tareas pendientes | Sugerencia | 12 h |
| R5 | Más de 240 min de pantalla en el día, con datos disponibles | Advertencia | 6 h (ámbito día) |
| R6 | Más de 3 tareas pendientes y más de 180 min de pantalla | Advertencia | 6 h |
| R7 | Más de 60 min nocturnos por día acumulados en 7 días (420 min entre 22:00 y 06:00) | Advertencia | 12 h |
| R8 | Pico de uso horario que cae dentro de un horario configurado | Sugerencia | 12 h |

- Las claves de equivalencia combinan regla, fecha y, cuando corresponde, horario activo.
- El historial nunca se borra; solo se descarta la generación de duplicados.
- Cada recomendación guarda `reglaId`, `severidad` y `motivo` para poder explicar la decisión.
- Las reglas son datos; el comportamiento está cubierto por pruebas de condiciones, prioridad y cooldown.

## Evolución digital

### Comparación diaria

- Compara hoy con ayer usando la misma hora de corte.
- El corte se reconstruye con eventos de `UsageStats`, porque los resúmenes diarios no guardan la hora de captura.
- Calcula minutos de pantalla, minutos en apps distractoras, diferencia absoluta y variación porcentual.
- Si no hay permiso o fallan los eventos, devuelve `insuficiente`; no convierte la ausencia en cero.
- El porcentaje solo se calcula si el día anterior tiene minutos mayores que cero.

### Comparación de 7 días

- Ventanas de 7 días completos: reciente y anterior. El día actual parcial queda excluido.
- El resumen reciente muestra los registros disponibles en las siete fechas locales anteriores a hoy, indicando fechas y cobertura. No exige una semana anterior completa.
- Los promedios usan solo días registrados; los ausentes quedan como huecos en el gráfico, sin convertirse en cero.
- La comparación entre semanas requiere cobertura completa de ambos periodos; si falta, se explica el motivo sin ocultar el resumen reciente.
- Un registro diario acredita una captura, no que se haya observado todo el día: el esquema no conserva la hora de captura histórica.
- La etiqueta `línea base` solo se usa si el periodo anterior está completo y no existen recomendaciones anteriores a su fin. En caso contrario se denomina `periodo anterior`.
- La tendencia de uso de pantalla es descriptiva: no se interpreta como mejora de productividad.

### Valoración de Tips

- Cada recomendación puede valorarse como `Útil` o `No me sirvió`; también puede quedar sin respuesta o eliminarse.
- Se guarda una sola valoración actual por recomendación.
- El Dashboard muestra total valorado y porcentaje de utilidad solo con al menos 5 valoraciones; con menos indica `muestra insuficiente`.
- La valoración mide utilidad percibida; no demuestra que el Tip causara un cambio.

### Historial de Tips

- Las 50 recomendaciones más recientes se agrupan por fecha local, con encabezados Hoy, Ayer o fecha completa y contadores por grupo.
- Los grupos pueden expandirse o contraerse. «Fechas visibles» conserva la selección; las fechas nuevas aparecen visibles por defecto.
- «Ver archivo» permite consultar recomendaciones anteriores por bloques, sin borrar ni mover registros. Su filtro es independiente de las fechas ocultas en recientes.
- Las tarjetas se construyen bajo demanda. Tips conserva su estado al alternar pestañas; lectura y valoración actualizan los elementos afectados.
- La conservación del diseño y estas reducciones de trabajo no constituyen por sí solas una mejora de rendimiento medida.

## Perfil y apariencia

- Perfil local con nombre o apodo, identidad de género opcional (Masculino, Femenino, No binario, Otra identidad con autodescripción, Prefiero no responder) y autodescripción.
- El diálogo de perfil aparece en el primer arranque si no existe perfil. Todos los campos son opcionales.
- No hay Google Sign-In, cuentas ni autenticación externa.
- La identidad solo puede sugerir una paleta inicial (Fríos, Cálidos o RGB). La selección manual siempre tiene prioridad.
- La apariencia se guarda en la misma base local: modo (`light`, `dark`, `system`) y paleta (`cool`, `warm`, `rgb`).

### Temas disponibles

| Paleta | Claro | Oscuro |
|---|---|---|
| Cool | Light Cool | Dark Cool |
| Warm | Light Warm | Dark Warm |
| RGB | Light RGB | Dark RGB |

El sistema define tokens primitivos, semánticos y de componente sobre `ColorScheme` y un `ThemeExtension`. Las pruebas de tema comprueban las seis combinaciones y el contraste de textos sobre acentos y superficies.

## Privacidad

- Los datos permanecen en SQLite dentro del dispositivo.
- No hay analítica de terceros, servicios remotos ni envío del perfil.
- El nombre, la identidad de género y la apariencia son opcionales.
- La identidad de género no interviene en reglas, métricas, productividad ni recomendaciones.

## Pruebas

```bash
flutter analyze
flutter test
```

Última validación: **11 de noviembre de 2026**, sobre el estado local posterior a las correcciones de Dashboard y pruebas de Tips.

| Comprobación | Resultado |
|---|---|
| Suite automatizada completa | **321 aprobadas, 0 fallidas** |
| `flutter analyze` | Sin problemas |

Los resultados corresponden al árbol de trabajo local validado. El número de pruebas aprobadas no representa un porcentaje de cobertura de código.

| Área | Archivos representativos |
|---|---|
| Reglas y contexto | `test/reglas_test.dart`, `test/contexto_recomendacion_test.dart`, `test/integracion_motor_test.dart` |
| Cooldown y duplicados | `test/cooldown_test.dart` |
| Tareas y horarios | `test/tarea_planificacion_test.dart`, `test/horario_test.dart`, `test/horarios_multiples_test.dart` |
| Uso y desbloqueos | `test/uso_pantalla_service_test.dart`, `test/monitoreo_horarios_test.dart` |
| SQLite y migraciones | `test/database_transacciones_test.dart`, `test/valoracion_migracion_test.dart`, `test/perfil_test.dart` |
| Evolución y comparación diaria | `test/evolucion_semanal_test.dart`, `test/comparacion_diaria_test.dart` |
| Tema y apariencia | `test/theme_test.dart`, `test/apariencia_test.dart` |
| Lectura compartida y métricas | `test/lectura_uso_compartida_test.dart`, `test/metricas_temporales_test.dart`, `test/monitoreo_segundo_plano_test.dart` |
| Interfaz | `test/widget_test.dart`, `test/dashboard_evolucion_test.dart`, `test/tarjeta_evolucion_tips_test.dart`, `test/tareas_pantalla_test.dart` |
| Historial y navegación de Tips | `test/historial_tips_test.dart`, `test/tips_historial_pantalla_test.dart` |

Las pruebas de SQLite usan `sqflite_common_ffi` en escritorio. La última validación física se realizó en un Motorola moto g84 5G conectado mediante ADB inalámbrico. Se actualizó la APK debug con `adb install -r`, sin desinstalar ni borrar datos, y se ejecutó correctamente.

Se observaron Dashboard y Tips, y se comprobó que un grupo de Tips permanece contraído al ir al Dashboard y volver. El desbordamiento del texto de comparación insuficiente se corrigió con ajuste de línea y se verificó mediante widgets; ese estado no se forzó en el teléfono. También se reforzó la comprobación visual del contador «49 sin leer» en pruebas.

Los logs de la ejecución están en `build/`; son artefactos locales de compilación, no documentación permanente.

## Alcance y limitaciones

- **Prototipo académico:** no sustituye atención profesional ni constituye una evaluación clínica.
- **Datos locales:** no hay sincronización entre dispositivos ni respaldo automático.
- **Retención de eventos:** Android conserva eventos detallados de uso durante aproximadamente 7 días. Las comparaciones que dependen de eventos fuera de esa ventana quedan como datos insuficientes.
- **Aperturas de aplicaciones:** no existe un conteo real de aperturas; el campo `numeroAperturas` se registra con valor fijo y no debe interpretarse como métrica.
- **Desbloqueos:** se cuentan eventos `KEYGUARD_HIDDEN`; dependen de que el equipo tenga bloqueo de pantalla activo.
- **Alarmas exactas:** en Android 14+ el permiso puede estar denegado por defecto; la app cae a una alarma inexacta para no perder el recordatorio.
- **Distractor:** las reglas R1/R2 usan uso dentro de horarios; el Dashboard muestra el total diario en apps clasificadas como distractoras, que no es lo mismo.
- **Cumplimiento de tareas:** no se calcula una tasa histórica porque el modelo no guarda la fecha de finalización.
- **Causalidad:** ninguna comparación demuestra que las recomendaciones causaron un cambio de comportamiento.
- **Onboarding:** si el diálogo inicial se cancela, vuelve a aparecer en el siguiente arranque hasta guardar un perfil.
- **Cobertura visual:** los seis temas están cubiertos por pruebas de contraste; la validación visual se realizó en un dispositivo físico con tema oscuro.
- **Rendimiento pendiente:** esta validación es debug. Falta comparar el mismo recorrido antes y después en profile; faltaban dependencias locales para compilar ese modo sin descargas. Las 321 pruebas aprobadas no certifican fluidez ni preparación para distribución.

## Documentación complementaria

- [Motor de reglas y explicabilidad](INFORMES/INFORME_ETAPA5_MOTOR_REGLAS.md)
- [Control de duplicados y cooldown](INFORMES/INFORME_ETAPA6_CONTROL_DUPLICADOS.md)
- [Monitoreo en segundo plano](INFORMES/INFORME_ETAPA8_MONITOREO_SEGUNDO_PLANO.md)
- [Horarios múltiples](INFORMES/INFORME_ETAPA9_HORARIOS_MULTIPLES.md)
- [Refactorización: monitoreo](INFORMES/INFORME_FASE_2_MONITOREO.md)
- [Refactorización: métricas](INFORMES/INFORME_FASE_3_METRICAS.md)
- [Refactorización: interfaz](INFORMES/INFORME_FASE_4_INTERFAZ.md)
- [Refactorización: integración](INFORMES/INFORME_FASE_5_INTEGRACION.md)
- [Reporte técnico](INFORMES/REPORTE_TECNICO.txt)
- [Bitácora de avances](INFORMES/BITACORA_AVANCES.md)
