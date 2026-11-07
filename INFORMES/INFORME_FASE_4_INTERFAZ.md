# Fase 4 — Lectura de uso compartida en Flutter

**Base local** `master`, commit `2961981`, con las fases anteriores aplicadas localmente.

## Comportamiento

- Dashboard, Uso y Tips comparten una lectura por sesión de interfaz. La
  hora de corte se muestra solo en Dashboard. La lectura usa eventos de
  uso de Android.
  Al cambiar de pestaña se reutiliza la lectura durante cinco minutos.
  Si la lectura ya no es reciente, se señala como captura antigua. El
  cambio de fecha retira la muestra anterior de la vista de hoy.
- El estado distingue consulta inicial, actualización manual, permiso
  ausente, datos insuficientes y error. Un fallo de lectura conserva el
  último corte válido del día. Si se revoca el permiso, la interfaz deja
  de mostrar los valores de esa lectura.
- Los botones de Dashboard y Uso comparten una sola captura manual en
  curso. El cambio de pestaña solo lee. El monitoreo periódico de Android
  conserva su programación independiente de esos controles.
- El tiempo único y el tiempo del día en apps distractoras comparten el
  corte. El ranking se etiqueta como estadísticas por aplicación. El
  resumen del motor separa el tiempo distractor del bloque evaluado.
  El porcentaje requiere un total positivo y un numerador dentro de ese
  total. La descripción accesible identifica qué mide.
- Se conservan la comparación diaria y la evolución de siete días.
  No se modificaron reglas, esquema SQLite ni registros históricos.

## Verificación local

- Análisis Flutter sin incidencias, compilación debug offline y **278
  pruebas aprobadas**.
- Pruebas de widgets en claro y oscuro, navegación Dashboard → Uso → Tips
  y regreso, una sola lectura y una sola consulta de detalle, formato
  `7 h 6 min`, semántica de porcentaje y estados de lectura.
- Prueba de actualización concurrente con una captura y una lectura
  posterior. Los fixtures de estado y tema no cambian las preferencias
  ni los permisos del dispositivo.

## Validación física

La APK final se actualizó con `adb install -r` sobre la instalación existente.
El 6 de noviembre, entre las 01:06:01 y las 01:06:15, Dashboard y Uso mostraron
**51 minutos con corte a las 01:05**. Tips conservó el mismo corte y la misma
fuente. El regreso a Dashboard conservó el total y Android registró un
único trabajo periódico. Solo se leyeron etiquetas y totales de la interfaz.

Después de un doble toque en **Actualizar datos** y el cambio inmediato
a Uso, la pantalla mantuvo 51 minutos con corte a las 01:05 mientras decía
**Actualizando captura…**. Al terminar mostró 52 minutos con corte a las
01:06. Android seguía registrando un único trabajo periódico.
