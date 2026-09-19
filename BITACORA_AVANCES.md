# 📓 Bitácora de Avances — Prototipo de Tesis

**Proyecto:** Desarrollo de un prototipo de aplicación móvil Android para la gestión de tareas y horarios, mediante el monitoreo del tiempo de pantalla y uso de aplicaciones, orientado a la reducción de distracciones digitales
**Autor:** [Tu nombre]
**Plataforma:** Android 10+ (API 29)
**Framework:** Flutter 3.47.1 (Dart 3.13.1)
**Inicio:** Agosto 2026

---

## 🎯 Objetivo del Prototipo

Desarrollar una aplicación móvil funcional que integre:
1. **Gestión de tareas y recordatorios**
2. **Monitoreo del uso del dispositivo** (tiempo en pantalla, apps más usadas, desbloqueos)
3. **Recomendaciones automáticas** basadas en reglas simples

Todos los datos permanecen en el dispositivo (SQLite local, sin nube).

---

## 🗓️ FASE 0 — Instalación del Entorno de Desarrollo

### Objetivo
Configurar todas las herramientas necesarias para desarrollar en Flutter.

### Herramientas instaladas

| Herramienta | Versión | Propósito |
|-------------|---------|-----------|
| Flutter SDK | 3.47.1 (stable) | Framework principal |
| Dart | 3.13.1 | Lenguaje de programación |
| Android Studio | (última) | IDE + SDK de Android |
| Android SDK | 36.0.0 | Plataforma Android |
| Java (JDK) | OpenJDK 25 | Requerido para Android |
| Git | (última) | Control de versiones |
| Python | 3.14 | Herramientas auxiliares |

### Rutas importantes

```
Flutter SDK:  C:\Users\Ushe\flutter
Android SDK:  C:\Users\Ushe\AppData\Local\Android\sdk
Git:          C:\Program Files\Git
Java (JBR):   C:\Program Files\Android\Android Studio\jbr
```

### Verificación inicial
```powershell
flutter --version    # Flutter 3.47.1
flutter doctor -v    # Diagnóstico del entorno
```

---

## 🗓️ FASE 1 — Problemas de Instalación y Compatibilidad

### ⚠️ Problema 1: Flutter no se reconocía en la terminal

**Síntoma:**
```
flutter: El término 'flutter' no se reconoce como nombre de un cmdlet
```

**Causa:** Flutter no estaba agregado a la variable de entorno `PATH`.

**Solución aplicada:**
1. Agregar `C:\Users\Ushe\flutter\bin` al `PATH` del sistema
2. Reabrir la terminal para recargar las variables de entorno

**Resultado:** ✅ `flutter` reconocido correctamente.

---

### ⚠️ Problema 2: `cmdline-tools` component missing

**Síntoma (en `flutter doctor -v`):**
```
[!] Android toolchain - develop for Android devices
    X cmdline-tools component is missing.
```

**Causa:** Android Studio no instaló las herramientas de línea de comandos del SDK.

**Solución aplicada:**
1. Abrir Android Studio → **SDK Manager**
2. Pestaña **"SDK Tools"**
3. Marcar **"Android SDK Command-line Tools (latest)"**
4. Aplicar e instalar

**Resultado:** ✅ Componente instalado en `C:\Users\Ushe\AppData\Local\Android\sdk\cmdline-tools\latest`.

---

### ⚠️ Problema 3: Android license status unknown

**Síntoma (en `flutter doctor -v`):**
```
X Android license status unknown.
  Run `flutter doctor --android-licenses` to accept the SDK licenses.
```

**Causa:** Las licencias del SDK de Android no estaban aceptadas.

**Primer intento:**
```powershell
flutter doctor --android-licenses
```
→ Produjo un aviso:
```
WARNING: The SDK Manager CLI tool (sdkmanager) is deprecated.
Android CLI will be used instead.
Warning: The --licenses option is no longer needed.
```

**Problema secundario:** El método tradicional (`sdkmanager`) quedó obsoleto en el SDK 36, y Flutter 3.47.1 aún buscaba las licencias por el método antiguo, creando una incompatibilidad.

**Resolución:** Se resolvió mediante consulta externa a ChatGPT.

📎 **Referencia de la conversación donde se resolvió:**
https://chatgpt.com/share/6a8fd9cf-7f34-83e9-b46d-4ccc30f31fd0

**Resultado:** ✅ Licencias aceptadas. `flutter doctor` mostró el Android toolchain sin errores.

---

### ⚠️ Problema 4: Git no estaba en el PATH

**Síntoma (al ejecutar Flutter):**
```
Error: Unable to find git in your PATH.
```

**Causa:** Git estaba instalado en `C:\Program Files\Git\bin` pero no en el `PATH`.

**Solución aplicada:** Agregar `C:\Program Files\Git\bin` al `PATH`.

**Resultado:** ✅ Flutter pudo acceder a Git.

---

## 🗓️ FASE 2 — Creación de la Estructura del Proyecto

### Objetivo
Crear la estructura base del proyecto Flutter con la arquitectura propuesta.

### Estructura creada

```
lib/
├── main.dart                          # Entrada principal + navegación
├── models/
│   ├── tarea.dart                     # Modelo de tarea
│   ├── uso_pantalla.dart              # Modelo de uso de pantalla
│   └── recomendacion.dart             # Modelo de recomendación
├── database/
│   └── database_helper.dart           # SQLite (CRUD)
├── services/
│   ├── uso_pantalla_service.dart      # Captura UsageStats
│   ├── notificacion_service.dart      # Notificaciones locales
│   └── motor_recomendaciones.dart     # Reglas de recomendación
└── screens/
    ├── dashboard_screen.dart          # Dashboard con métricas
    ├── tareas_screen.dart             # Gestión de tareas
    ├── uso_screen.dart                # Detalle de uso
    └── recomendaciones_screen.dart    # Lista de recomendaciones
```

### Base de datos SQLite (4 tablas)
| Tabla | Propósito |
|-------|-----------|
| `tareas` | Gestión de tareas con prioridad y vencimiento |
| `uso_pantalla` | Métrica diaria de uso (1 fila por día) |
| `app_uso` | Uso por aplicación |
| `recomendaciones` | Recomendaciones generadas por el motor de reglas |

### Paquetes iniciales elegidos
| Paquete | Propósito |
|---------|-----------|
| `sqflite` | Base de datos SQLite |
| `usage_stats` | Monitoreo de uso de pantalla |
| `flutter_local_notifications` | Recordatorios |
| `permission_handler` | Permisos en tiempo de ejecución |
| `fl_chart` | Gráficos |
| `intl` | Formato de fechas |

---

## 🗓️ FASE 3 — Resolución de Errores de Dependencias

### ⚠️ Problema 5: Versiones de paquetes incorrectas

**Síntoma (en `flutter pub get`):**
```
Because prototipo_tesis depends on device_apps ^0.2.0 which doesn't match
any versions, version solving failed.
```

**Causa:** Varias versiones de paquetes especificadas en `pubspec.yaml` no existían:

| Paquete | Versión escrita (incorrecta) | Versión real |
|---------|------------------------------|--------------|
| `usage_stats` | ^3.0.0+2 | ^2.0.1 |
| `device_apps` | ^0.2.0 | 2.2.0 (pero **descontinuado**) |
| `app_usage` | ^2.0.0 | (no se usaba) |
| `flutter_local_notifications` | ^15.1.0 | ^22.3.0 |
| `timezone` | ^0.9.2 | ^0.11.1 |
| `permission_handler` | ^11.3.0 | ^13.0.1 |
| `fl_chart` | ^0.65.0 | ^1.2.0 |

**Solución aplicada:**
1. Consultar `pub.dev` para obtener las versiones reales
2. Corregir todas las versiones en `pubspec.yaml`
3. Eliminar `device_apps` (descontinuado) → reemplazado por la API nativa `UsageStats.getAppInfo()`
4. Eliminar `app_usage` (no se usaba en el código)

**Resultado:** ✅ `flutter pub get` resolvió las dependencias correctamente.

---

### ⚠️ Problema 6: Cambio de API en flutter_local_notifications v22

**Síntoma (en `flutter analyze`):**
```
error - The named parameter 'settings' is required, but there's no corresponding argument.
error - Too many positional arguments: 0 expected, but 5 found.
```

**Causa:** La versión 22 del paquete cambió su API de **parámetros posicionales** a **parámetros nombrados**.

**Antes (v15):**
```dart
await _plugin.initialize(initSettings);
await _plugin.zonedSchedule(id, titulo, cuerpo, fecha, detalles, ...);
await _plugin.show(id, titulo, mensaje, detalles);
await _plugin.cancel(id);
```

**Después (v22):**
```dart
await _plugin.initialize(settings: initSettings);
await _plugin.zonedSchedule(id: id, title: titulo, body: cuerpo, ...);
await _plugin.show(id: id, title: titulo, body: mensaje, ...);
await _plugin.cancel(id: id);
```

**Resultado:** ✅ Código adaptado a la nueva API.

---

### ⚠️ Problema 7: permission_handler requiere compileSdk 37

**Síntoma (al compilar el APK):**
```
Dependency ':permission_handler_android' requires libraries and applications
that depend on it to compile against version 37 or later of the Android APIs.
:app is currently compiled against android-36.
```

**Causa:** `permission_handler 13.0.1` depende de `permission_handler_android 14.0.0`, que requiere `compileSdk 37`. Pero el Android Gradle Plugin (AGP 9.1.0) solo soporta oficialmente hasta `compileSdk 36`.

**Solución aplicada:**
1. **Bajar** `permission_handler` de `^13.0.1` a `^12.0.3`
2. La versión 12.0.3 usa `permission_handler_android 13.0.1` (compatible con SDK 36)

**Resultado:** ✅ Compatibilidad resuelta sin actualizar AGP.

---

### ⚠️ Problema 8: flutter_local_notifications requiere desugaring

**Síntoma (al compilar el APK):**
```
Dependency ':flutter_local_notifications' requires core library desugaring
to be enabled for :app.
```

**Causa:** El paquete usa APIs de Java 8+ que requieren "desugaring" para funcionar en versiones antiguas de Android.

**Solución aplicada** en `android/app/build.gradle.kts`:
```kotlin
compileOptions {
    isCoreLibraryDesugaringEnabled = true
    // ...
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

**Resultado:** ✅ Desugaring habilitado correctamente.

---

### ⚠️ Problema 9: Conflicto de archivos Gradle (Groovy vs Kotlin DSL)

**Síntoma:** Al ejecutar `flutter create .` se generaron archivos en formato nuevo (`.kts`) que entraban en conflicto con los archivos manuales en formato antiguo (`.gradle`).

**Causa:** La estructura manual inicial usaba Groovy (`.gradle`), pero Flutter 3.47.1 genera Kotlin DSL (`.kts`).

**Solución aplicada:**
1. Eliminar los archivos Groovy antiguos: `build.gradle`, `settings.gradle`, `app/build.gradle`
2. Conservar los nuevos Kotlin DSL: `build.gradle.kts`, `settings.gradle.kts`, `app/build.gradle.kts`
3. Actualizar `minSdk = 29` (requisito Android 10+)

**Resultado:** ✅ Estructura Gradle unificada y consistente.

---

## 🗓️ FASE 4 — Primera Compilación Exitosa

### Resultado
```
√ Built build\app\outputs\flutter-apk\app-debug.apk
```

| Dato | Valor |
|------|-------|
| Archivo | `app-debug.apk` |
| Tamaño | 154 MB (debug) |
| Estado | ✅ Compilación exitosa |

### Warnings restantes (no bloqueantes)
- `usage_stats` usa Kotlin Gradle Plugin (KGP) antiguo → advertencia para futuras versiones de Flutter
- Avisos cosméticos de `cmdline-tools` y Java

---

## 🗓️ FASE 5 — Prueba en Emulador

### Configuración
- Emulador: `sdk gphone64 x86 64`
- Sistema: Android 15 (API 35)

### Verificación de datos (via `adb` + SQLite)

Se accedió a la base de datos en tiempo real y se confirmó:

| Tabla | Estado | Contenido |
|-------|--------|-----------|
| `tareas` | ✅ Funciona | 1 tarea de prueba creada correctamente |
| `uso_pantalla` | ✅ Funciona | Detectó 4 min y "Pixel Launcher" |
| `app_uso` | ⚠️ Vacía | Las apps se generan en memoria pero no se persisten |
| `recomendaciones` | ⚠️ Vacía | Requiere tocar el botón de generar |

### Hallazgos importantes
1. El emulador SÍ captura datos básicos de uso, pero mínimos (solo el launcher)
2. Para datos reales (WhatsApp, Instagram) se requiere **teléfono físico**
3. Detectado un bug pendiente: `app_uso` no se persiste en la BD

---

## 🗓️ FASE 6 — Decisiones Técnicas Clave

### Decisiones de arquitectura documentadas

| Decisión | Razón | Alternativa descartada |
|----------|-------|------------------------|
| **Flutter** sobre Kotlin nativo | Prototipo rápido, UI multiplataforma | Kotlin/Java nativo |
| **SQLite (sqflite)** | Local, sin nube (requisito de privacidad) | Firebase/cloud |
| **usage_stats** | API nativa de UsageStatsManager | device_apps (descontinuado) |
| **permission_handler 12.x** | Compatible con SDK 36 | 13.x (requiere SDK 37) |
| **Material 3** | Diseño moderno estándar de Google | Material 2 |

### Descubrimientos técnicos relevantes para la tesis

1. **Android retiene meses de datos de uso agregado** (no solo desde la instalación de la app)
2. **Los eventos detallados duran ~7 días** (limita el análisis por hora)
3. **El permiso PACKAGE_USAGE_STATS es manual** (no se pide con diálogo normal)
4. **El desglose por hora es posible** mediante `queryEvents`

---

## 📎 Referencias Externas

| Recurso | Enlace | Uso |
|---------|--------|-----|
| **ChatGPT (resolución de licencias)** | https://chatgpt.com/share/6a8fd9cf-7f34-83e9-b46d-4ccc30f31fd0 | Resolución del problema de licencias del SDK Android |
| Flutter docs | https://docs.flutter.dev | Documentación oficial |
| Android Developers | https://developer.android.com | Documentación de Android |
| pub.dev | https://pub.dev | Registro de paquetes Dart |

---

## 🎯 Pendientes / Próximos Pasos

### Inmediatos
- [ ] Corregir bug: persistir `app_uso` en la base de datos
- [ ] Implementar backfill de 7 días al abrir la app
- [ ] Probar en teléfono físico con datos reales

### Fase 2 (planificada)
- [ ] Ventana de configuración de horarios laborales/académicos
- [ ] Análisis de uso por hora del día
- [ ] Servicio en segundo plano para recolección diaria

### Fase 3 (plan de mejora del usuario)
- [ ] Métrica de mejora: comparar uso semana a semana
- [ ] Línea base "pre" vs "post" intervención

---

## 📝 Notas de la Bitácora

- **Formato de fecha:** Las fechas usan el formato local del sistema (agosto 2026)
- **Comandos:** Los comandos de terminal están documentados en PowerShell
- **Estilo:** Los problemas se documentan con: Síntoma → Causa → Solución → Resultado

---

*Última actualización: Agosto 2026*
