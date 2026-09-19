# Desarrollo de un prototipo de aplicación móvil Android para la gestión de tareas y horarios, mediante el monitoreo del tiempo de pantalla y uso de aplicaciones, orientado a la reducción de distracciones digitales

Aplicación móvil Android que integra gestión de tareas/recordatorios con monitoreo de uso del dispositivo para una tesis de investigación.

## 📱 Características

- **Gestión de tareas**: Crear, editar, eliminar y listar tareas con prioridades
- **Recordatorios**: Notificaciones locales programadas para tareas con fecha de vencimiento
- **Monitoreo de uso**: Tiempo de pantalla, apps más usadas, número de desbloqueos
- **Dashboard**: Resumen con métricas y gráficos (FlChart)
- **Recomendaciones**: Motor de reglas que combina carga de tareas y patrones de uso
- **Privacidad**: Todos los datos se almacenan localmente (SQLite)

## 🛠️ Stack Técnico

| Componente | Tecnología |
|------------|------------|
| Framework | Flutter 3.47+ |
| Lenguaje | Dart 3.13+ |
| Plataforma | Android 10+ (API 29) |
| Base de datos | SQLite (sqflite) |
| Monitoreo uso | UsageStatsManager Android |
| Notificaciones | flutter_local_notifications |
| Gráficos | fl_chart |

## 📁 Estructura del Proyecto

```
lib/
├── main.dart                          # Entrada principal
├── models/
│   ├── tarea.dart                     # Modelo de tarea
│   ├── uso_pantalla.dart              # Modelo de uso
│   └── recomendacion.dart             # Modelo de recomendación
├── database/
│   └── database_helper.dart           # Helper de SQLite (CRUD)
├── services/
│   ├── uso_pantalla_service.dart      # Captura datos de UsageStats
│   ├── notificacion_service.dart      # Notificaciones locales
│   └── motor_recomendaciones.dart     # Reglas de recomendación
└── screens/
    ├── dashboard_screen.dart          # Pantalla principal con métricas
    ├── tareas_screen.dart             # CRUD de tareas
    ├── uso_screen.dart                # Detalle de uso de pantalla
    └── recomendaciones_screen.dart    # Lista de recomendaciones
```

## 🚀 Instalación y Ejecución

### 1. Clonar el repositorio (o usar este directorio)
```bash
cd prototipo_tesis
```

### 2. Instalar dependencias
```bash
flutter pub get
```

### 3. Conectar un dispositivo Android físico (recomendado)
- Habilita Opciones de desarrollador
- Activa Depuración USB
- Conecta vía USB y acepta la depuración

### 4. Ejecutar la app
```bash
flutter run
```

## 📋 Permisos Requeridos

La app solicitará automáticamente los siguientes permisos al iniciar:

1. **PACKAGE_USAGE_STATS** - Para leer estadísticas de uso (requiere activación manual en Ajustes > Aplicaciones > Acceso especial > Uso de la aplicación)
2. **POST_NOTIFICATIONS** - Para mostrar notificaciones (Android 13+)
3. **SCHEDULE_EXACT_ALARM** - Para programar recordatorios

## 🎯 Motor de Reglas

El motor de recomendaciones evalúa las siguientes condiciones:

| Regla | Condición | Recomendación |
|-------|-----------|---------------|
| Alto uso | > 4 horas de pantalla | Tomar descanso |
| Sobrecarga de tareas | > 5 tareas pendientes | Priorizar y dividir |
| Redes sociales | > 30 min en app social | Pausa de 15 min |
| Tareas urgentes | Tareas de alta prioridad | Técnica Pomodoro |
| Modo enfoque | > 3h uso + > 3 tareas | Silenciar notificaciones 1h |

## 🧪 Pruebas

Para el estudio piloto se recomienda:
- 8-12 usuarios
- 1-2 semanas de uso
- Encuesta SUS al final
- Comparativa pre/post instalación

## 📝 Notas para Tesis

- Los datos NO se comparten externamente (privacidad)
- SQLite local asegura portabilidad de datos
- Compatible con Android 10+ según especificación
- El motor de reglas es simple pero extensible
