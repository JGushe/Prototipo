# Fase 5 — Integración y regresión en Android

**Equipo** Moto G84 5G, Android 15, ADB inalámbrico, 6 de noviembre de 2026.
**Base** `master`, commit `2961981`, con los cambios locales de Fases 1–4.
La APK principal instalada coincidió por SHA-256 con la compilación local.
Esta fase añadió instrumentación, un script local y comprobaciones de prueba.

## Matriz

| Caso | Entrada y resultado esperado | Observado | Estado |
|---|---|---|---|
| Dashboard y Uso | Dos pestañas durante el mismo minuto y la misma lectura | 72 min en ambas. Dashboard indicó corte 01:34. | PASS |
| Bienestar Digital | Total de hoy observado dentro del mismo minuto | 66 min a las 01:34:27, frente a 72 en el prototipo. La vista nativa no expuso su instante de actualización. | NO VERIFICADO para igualdad de ventana |
| Arranque sin interfaz y pantalla apagada | Proceso previo ausente, pantalla en `Dozing`, un Worker puntual. Captura y persistencia completas | `SUCCEEDED`, `estado=ok`, un resumen, 74 min guardados y cero grupos duplicados de apps para hoy. | PASS |
| Dos workers simultáneos | Dos trabajos puntuales con inicios solapados | Ambos `SUCCEEDED`. Inicios separados por 2 ms, un resumen y cero grupos duplicados por fecha y app en el día. | PASS |
| UI y Worker periódico | Reactivar el periódico y pulsar Actualizar | La UI mostró la actualización en curso. El Worker terminó con `estado=ok` a las 01:36:46. La UI salió de carga y quedó un trabajo registrado. | PASS |
| Acceso de uso revocado | Revocar solo al prototipo. El Worker debe informar permiso ausente y preservar el resumen | `FAILED` esperado, `sin_permiso_uso`, sin reintento inmediato. El agregado siguió en 74 min y se verificó la restauración a `allow`. | PASS |
| Cruce de medianoche y bloqueo | Fixtures de eventos con sesión que cruza de fecha, bloqueo y pantalla inactiva | Los minutos se distribuyeron por hora civil. Bloqueo, apagado y reinicio impidieron extender sesiones. | PASS en pruebas automatizadas |
| Multiventana | Dos sesiones solapadas | 60 min únicos frente a 90 min por app en el fixture. | PASS en pruebas automatizadas |
| R1–R8, cooldown y fallos | Suite de reglas y ciclo con plugins simulados, y concurrencia con SQLite FFI | Pasaron los umbrales, reversión, migraciones, idempotencia y el flujo de aviso simulado. Los workers físicos instrumentados no generaron recomendaciones. | PASS local. Alerta de regla no provocada en el ensayo físico |
| Reinicio del dispositivo | Repetir arranque posterior a reinicio con la APK actual | El usuario autorizó únicamente la prueba de permiso. | NO VERIFICADO en Fase 5 |
| Energía restringida | Cuota restringida o Doze profundo | El equipo estaba conectado a corriente y la app en categoría activa. Pantalla apagada y `mWakefulness=Dozing` no prueban Doze profundo. | NO VERIFICADO |

Los 74 minutos guardados corresponden a las capturas de las 01:35. La tabla
diaria no guarda el instante de corte de la captura, por lo que ese dato
no equivale al corte de las 01:34. El prototipo une sesiones acreditadas de
primer plano. No se estableció qué filtros o instante de actualización
explican los seis minutos de diferencia con Bienestar Digital.

## Rendimiento observado

| Carga instrumentada | Duración de pared | CPU acumulada del proceso |
|---|---:|---:|
| Un Worker con pantalla apagada | 6208 ms | 7307 ms |
| Dos workers simultáneos | 6771 ms | 10055 ms |
| Un Worker con acceso revocado | 1072 ms | 1715 ms |

La CPU se midió con `Process.getElapsedCpuTime()` durante cada ejecución
instrumentada de la APK debug. Suma CPU de varios hilos y puede superar el
tiempo de pared. Incluye la sobrecarga del runner. No es una medición de
consumo de batería. La prueba de canal simulado contabilizó una consulta de
estadísticas agregadas y dos consultas de eventos por ciclo completo.

## Reproducción local

```sh
flutter --no-version-check analyze --no-pub
flutter --no-version-check test --no-pub --reporter expanded
(cd android && ./gradlew --offline :app:assembleDebug :app:assembleDebugAndroidTest)
adb install -r build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk
bash scripts/verificar_worker_android.sh -e verificarPersistencia true
bash scripts/verificar_worker_android.sh -e concurrente true -e verificarPersistencia true
```

El monitoreo debe haberse activado al menos una vez para registrar el
callback. El runner informa solo el estado, tiempos y, si se solicita,
agregados SQLite del día. Tras la instrumentación, conviene verificar
que Dashboard muestre monitoreo activo y que Android conserve un único
trabajo periódico.

**Resultados locales** Análisis sin incidencias, 278 pruebas aprobadas y
ambas APK compiladas offline.

**Comprobación del 9 de noviembre.** ADB reconoció el Moto G84 5G como
autorizado. `am start -W` devolvió `Status: ok` y confirmó el arranque en
frío de la actividad principal, que quedó en primer plano.
