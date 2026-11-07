# Fase 3 — Métricas temporales y reglas

**Base local** `master`, commit `2961981`, con los cambios locales de las Fases 1 y 2.

## Cálculo

- La reconstrucción empareja eventos de primer plano por paquete y clase de
  actividad. Un cambio a otra app permite solapes de multiventana. Un inicio
  sin cierre, una pausa huérfana y un par anómalo de más de seis horas no
  acreditan uso. El bloqueo o apagado recorta un par, y el reinicio rompe la
  continuidad. El plugin no expone un identificador por instancia de actividad.
- El total único se calcula uniendo los tramos acreditados dentro de la
  ventana y convirtiendo a minutos al final. La unión no puede superar la
  ventana. Una reproducción sintética de 1131 minutos sumados a las 12:34
  da 754 minutos únicos. Los agregados de Android por app tienen su propia
  semántica y se mantienen separados del total único.
- Hoy y ayer usan el mismo minuto de corte local y la misma ventana previa
  de seis horas para reconstruir sus respectivos inicios. Los eventos
  posteriores al corte no se usan para cerrar una sesión de la comparación.
  Si un lado carece de tramos acreditados, queda sin valor. Un tramo
  acreditado menor a un minuto sí puede redondear hacia abajo a cero.
- Los tramos se reparten por hora civil después de eliminar solapes.
  R7 y la sugerencia nocturna requieren un evento de pantalla interactiva
  y excluyen el bloqueo conocido. Se conservan los criterios independientes
  de más de 420 minutos en siete días para R7 y más de 60 minutos acumulados
  para la sugerencia. El primero emite una advertencia de uso sostenido y
  el segundo es una sugerencia descriptiva de la pantalla Uso.
- La comparación y las reglas usan el mismo clasificador por paquete exacto
  o prefijo delimitado por punto. Incluye `com.zhiliaoapp.musically` y
  admite una lista configurable en el motor.

## Reglas e historial

- R1 une el uso distractor dentro del bloque académico activo. R2 evalúa el
  tiempo de la app distractora principal dentro del bloque laboral activo.
  R3 exige uso distractor en el intervalo de la tarea prioritaria activa.
- R5/R6 usan el total único acreditado. La ausencia de permiso o de eventos
  no sustituye esa métrica por una fila antigua. R8 cruza el pico con un
  instante de actividad observado.
- No cambiaron los umbrales, la prioridad, la severidad, las claves ni el
  cooldown. SQLite conserva el esquema v9 y las filas históricas. Las filas
  anteriores a la fase siguen reflejando la definición con que se capturaron.
  La evolución semanal puede abarcar ambas definiciones.
- Dashboard y Uso muestran el total único actual. El detalle de apps y los
  desbloqueos aún tienen sus propias fuentes. La presentación y los estados
  de actualización completos corresponden a la Fase 4.

## Verificación local

- `flutter --no-version-check analyze --no-pub` terminó sin incidencias.
- `flutter --no-version-check test --no-pub --reporter expanded` terminó con
  273 pruebas aprobadas. Se verificaron multiventana, solapes de un mismo
  paquete, cierre perdido, pausa huérfana, reinicio, cruce de medianoche,
  pantalla inactiva, bloqueo, permiso denegado, clasificación configurable,
  corte exacto, umbrales y cooldown.
- `./gradlew --offline :app:assembleDebug :app:assembleDebugAndroidTest`
  terminó correctamente. La APK principal se actualizó con `adb install -r`.

## Validación física

El 6 de noviembre, con la APK final en Android 15 por ADB inalámbrico,
Uso mostró **37 minutos** a las 00:52:08 y Dashboard mostró **37 minutos**
con corte de las 00:52 a las 00:52:14. Dashboard indicó monitoreo activo.
La lectura se limitó al total y a la hora. No se extrajeron registros de uso.
En ese minuto, el Worker periódico también confirmó la captura y terminó
con `estado=ok`. Registró una recomendación y cero notificaciones.
Quedó un único trabajo periódico registrado.

La muestra física acredita el total compartido en ese corte. Los escenarios
de multiventana y bloqueo nocturno se comprobaron con eventos sintéticos.
