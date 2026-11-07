#!/usr/bin/env bash
# Requiere las APK debug principal y de instrumentación ya instaladas.
# Admite -e concurrente true, -e esperarFallo true y -e verificarPersistencia true.
set -euo pipefail

paquete=com.prototipo.prototipo_tesis
runner="$paquete.test/$paquete.MonitoreoEnFrioTest"
marca=$(adb shell "date '+%m-%d %H:%M:%S.000'" | tr -d '\r')
resultado=$(adb shell am instrument -w "$@" "$runner")
printf '%s\n' "$resultado" |
  awk '/^INSTRUMENTATION_RESULT: (estado|duracion_ms|cpu_proceso_ms|resumenes_hoy|minutos_guardados|grupos_app_duplicados_hoy)=|^INSTRUMENTATION_CODE:/'
adb logcat -d -T "$marca" -s PrototipoMonitoreo:I '*:S' |
  awk '/PrototipoMonitoreo:/{print}'
printf '%s\n' "$resultado" | grep -q '^INSTRUMENTATION_CODE: -1'
