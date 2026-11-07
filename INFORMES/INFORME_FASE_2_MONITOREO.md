# Fase 2 — Monitoreo Android en segundo plano

**Base local** `master`, commit `2961981`, con los cambios locales de la Fase 1.
**Dispositivo de prueba** Android 15 por ADB inalámbrico, usuario Android principal.

## Cambios

- El ciclo compartido por Dashboard y WorkManager captura y confirma el resumen y
  el detalle en SQLite antes de evaluar R1–R8. El contexto reutiliza esa muestra
  y evita una segunda consulta de estadísticas agregadas. La captura estricta
  conserva el resumen previo cuando falta permiso o la consulta vuelve vacía.
- El Worker crea, ejecuta y destruye el `FlutterEngine` en el hilo principal.
  Espera el resultado Dart con una corrutina. La primera compilación de prueba
  falló al interpretar el nombre del callback como biblioteca. La compilación
  final usa `DartExecutor.DartCallback` con el handle registrado por Flutter.
  El ciclo natural tras el reinicio reveló un segundo fallo. En un proceso
  nuevo, la búsqueda del handle llamaba a JNI antes de cargar Flutter. La
  búsqueda ahora se hace después de crear el motor.
- El puente distingue éxito, cancelación, permiso ausente, datos ausentes y
  fallos. Los errores transitorios del ciclo o del motor y el timeout tienen
  hasta dos reintentos. La inicialización headless no solicita permisos.
- El alta y la baja esperan la operación de WorkManager. La baja cancela los
  trabajos del Worker. El periódico conserva su nombre único y usa `KEEP`
  para preservar un trabajo activo y admitir una nueva programación cuando
  el anterior ya terminó. `UPDATE` omitía la actualización del trabajo
  finalizado por el error JNI. Se mantiene el cooldown transaccional de la
  Fase 1.

SQLite conserva el esquema v9. Las APK se instalaron con `adb install -r`.
No se borraron datos, no se migró el esquema ni se extrajeron registros de uso.
Las pruebas físicas generaron capturas normales del prototipo.

## Protocolo físico

1. Compilar offline y actualizar la instalación existente.

   ```sh
   (cd android && ./gradlew --offline :app:assembleDebug)
   adb install -r build/app/outputs/apk/debug/app-debug.apk
   ```

2. Abrir Dashboard y verificar que la tarjeta de monitoreo está activa. Para
   comprobar el alta y la baja, desactivarla y activarla una vez. Dejar el
   acceso de uso concedido y evitar el botón Recargar.
3. Observar el ciclo inicial con Dashboard visible. En otra activación,
   enviar la app a Inicio y apagar la pantalla. Comprobar que el Worker
   registra el final con `estado=ok`.

   ```sh
   adb logcat -d -s PrototipoMonitoreo:I '*:S'
   adb shell dumpsys jobscheduler |
     awk '/^ *JOB .*com\.prototipo\.prototipo_tesis\/androidx\.work/'
   ```

4. Con autorización, revocar solo el acceso de uso de este paquete durante
   un ciclo y restaurarlo al terminar. Esperar `sin_permiso_uso`, seguido
   de la confirmación de que el acceso vuelve a estar concedido.
5. Con autorización, reiniciar, desbloquear Android y recuperar ADB
   inalámbrico. No abrir el prototipo. Comprobar que se reprograma un único
   trabajo y esperar su ejecución natural. JobScheduler puede aceptar
   `run -f` antes de tiempo mientras WorkManager pospone el ciclo.
6. Usar **Probar notificación** para comprobar la publicación en Android.
   Para validar una alerta del Worker, esperar una recomendación nueva de
   severidad notificable y fuera del cooldown. Comparar el contador
   `notificadas` con la publicación del sistema.
7. Para repetir el arranque en frío de forma controlada, compilar e instalar
   la APK de instrumentación. Después de actualizar la APK principal y sin
   abrir Dashboard, ejecutar el runner. El monitoreo debe haberse activado al
   menos una vez para que exista un handle guardado.

   ```sh
   (cd android && ./gradlew --offline :app:assembleDebugAndroidTest)
   adb install -r build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk
   adb shell am instrument -w \
     com.prototipo.prototipo_tesis.test/com.prototipo.prototipo_tesis.MonitoreoEnFrioTest
   ```

   Al terminar la instrumentación, abrir Dashboard y comprobar que el
   periódico siga activo. En este dispositivo fue necesario reactivarlo.

## Resultados observados

| Escenario | Resultado |
|---|---|
| Alta y baja | Al detener desapareció el trabajo. Al activar reapareció uno. |
| UI visible | El Worker confirmó la captura y terminó con `estado=ok`. |
| App en Inicio y pantalla apagada | El Worker confirmó la captura y terminó con `estado=ok`. |
| Acceso de uso revocado | `estado=sin_permiso_uso`, sin reintento inmediato. Acceso restaurado y verificado en `allow`. |
| Reinicio | El receptor recibió `BOOT_COMPLETED` y reapareció un único trabajo sin abrir el prototipo. El ciclo natural arrancó a las 00:25:41 y reprodujo el fallo JNI corregido en la compilación final. |
| Arranque en frío con la compilación final | Instrumentación `SUCCEEDED`. El Worker comenzó a las 00:28:53, cargó Flutter en ese proceso y confirmó la captura a las 00:29:01 sin interfaz visible. |
| Notificación de prueba | Android registró la notificación de prueba 9001. |
| Alerta real de una regla | El arranque en frío final generó una recomendación y notificó una vez. Android registró la alerta del prototipo. |
| Repetición dentro del cooldown | Una segunda ejecución instrumentada confirmó la captura con `generadas=0` y `notificadas=0`. |
| Reactivación tras un trabajo finalizado | Con la política `KEEP`, el interruptor volvió a mostrar monitoreo activo y Android registró un único trabajo. El nuevo ciclo terminó con `estado=ok` a las 00:37:04. |
| Restricción de batería | Se observó el estado normal del dispositivo. La pantalla apagada no acredita una prueba de Doze profundo ni de batería restringida. |

`flutter --no-version-check analyze --no-pub` pasó sin incidencias.
`flutter --no-version-check test --no-pub --reporter expanded` pasó con
**263 pruebas**. `./gradlew --offline :app:assembleDebug :app:assembleDebugAndroidTest`
terminó correctamente.

WorkManager decide la hora efectiva del ciclo periódico. Si la publicación
falla después del commit, el historial conserva la recomendación y el
Worker informa `error_notificacion`. El ciclo no reenvía una recomendación
ya guardada.
