# 📄 Informe — Etapa 3: Análisis de horarios preciso

**Rama:** `feature/Motor-Recomendaciones-Adaptado`
**Alcance:** que un horario pueda determinar correctamente si un `DateTime`
concreto pertenece al periodo configurado (día, hora y minutos).
**Fecha:** Agosto 2026

---

## 🎯 Objetivo

`Horario` ya guardaba minutos y `diasSemana`, pero `contieneHora()` solo
comparaba horas enteras e ignoraba los días. El motor necesita saber si un
`DateTime` concreto cae dentro de un horario laboral o académico, incluyendo
horarios nocturnos.

---

## ✅ Cambios realizados

| # | Archivo | Cambio |
|---|---------|--------|
| 1 | `lib/models/horario.dart` | `contieneDateTime()`, `minutosDesdeMedianoche()`, `minutosInicio`, `minutosFin`, `cruzaMedianoche`, `tieneDuracion`; `contieneHora()` se conserva. |
| 2 | `lib/services/analisis_horario_service.dart` | El análisis usa el **DateTime real** del pico y expone `horarioActivoEn()`. |
| 3 | `test/horario_test.dart` | **19 pruebas nuevas** con los casos límite pedidos. |

### Modelo `Horario`

- `static int minutosDesdeMedianoche(int hora, int minuto)` — conversión
  interna solicitada (hora/minuto → minutos desde medianoche).
- `minutosInicio` / `minutosFin` — el rango del horario en minutos.
- `cruzaMedianoche` — `minutosFin < minutosInicio` (p. ej. 22:00 → 02:00).
- `tieneDuracion` — `false` si inicio y fin coinciden; en ese caso el rango es
  vacío y ningún `DateTime` pertenece a él.
- **`contieneDateTime(DateTime)`** valida, en este orden:
  1. **día de la semana** (`fechaHora.weekday`, 1=lunes … 7=domingo);
  2. **minutos**, comparando contra los límites en minutos;
  3. **horario normal** → `inicio <= t < fin` (fin exclusivo);
  4. **cruce de medianoche** → `t >= inicio` (noche) o `t < fin` (madrugada),
     resolviendo el día por el **día de inicio del bloque**.

**Semántica del horario nocturno:** `diasSemana` indica el día en que *empieza*
el bloque. Un horario del **lunes 22:00-02:00** cubre la noche del lunes y la
madrugada del **martes** (aunque el martes no esté configurado).

**Compatibilidad:** `contieneHora(int)` se mantiene con su comportamiento
original (solo horas, sin días ni minutos) porque el motor de recomendaciones
—Regla 6— todavía lo usa. No se tocó el motor ni sus reglas.

### `AnalisisHorarioService`

- `_calcularUsoPorHora()` reemplaza el cálculo interno y devuelve, además de los
  minutos por hora, un **momento real representativo** de cada hora (el
  `DateTime` de la última sesión detectada en esa hora).
- `obtenerUsoPorHora()` conserva su firma y ahora delega en el método anterior.
- Nuevo método público **`horarioActivoEn(DateTime, {horarios})`**: devuelve el
  objeto `Horario` que contiene ese instante, o `null`. Es el punto que el motor
  podrá reutilizar en la próxima etapa.
- `analizar()` cruza el **momento real del pico** con los horarios mediante
  `contieneDateTime`, en lugar de comparar solo la hora entera. Se eliminó el
  helper privado `_horarioQueContiene()`.
- `AnalisisHorario` incorpora el campo opcional `horarioPico` con el horario
  detectado, para no recalcularlo.

**Sin cambios** en la interfaz, en las reglas del motor ni en el esquema SQLite.

---

## 🧪 Verificación

```
dart analyze lib test   →  No issues found!
flutter test            →  00:00 +36: All tests passed!  (19 nuevas + 17 previas)
```

`test/horario_test.dart` cubre los casos solicitados:

| Caso | Prueba |
|------|--------|
| Lunes dentro del horario | `lunes dentro del horario` |
| Lunes fuera | `lunes fuera del horario` |
| Día no configurado | `día no configurado (sábado)` |
| Límite inferior | `límite inferior: 08:00 pertenece, 07:59 no` |
| Límite superior | `límite superior: 16:00 queda fuera, 15:59 dentro` |
| Cruce de medianoche | `Horario que cruza medianoche 22:00-02:00 (lunes)` |

Además: minutos en ambos extremos (`08:30-16:45`), `contieneHora` legado,
`minutosDesdeMedianoche`, cruce de medianoche con domingo/martes, rango vacío
(`inicio == fin`) y `diasSemana` vacío.

---

## ⚠️ Notas

1. **Entorno:** `dart analyze` y `flutter test` necesitan lanzar procesos hijos
   (servidor de análisis / `flutter_tester`); el sandbox confinado los deniega,
   por lo que se ejecutaron con acceso ampliado.
2. **Cambio de comportamiento deliberado:** las sugerencias de `analizar()` ahora
   consideran el día de la semana del pico real, no solo la hora. Es la
   corrección pedida en el punto 5; no se añadieron reglas nuevas.
3. **Respaldo defensivo:** si no hubiera un momento registrado para la hora pico,
   se usa hoy a esa hora. En la práctica no ocurre, porque solo se registra la
   hora cuando hay minutos de uso.
4. **`inicio == fin`** se interpreta como rango vacío (no como 24 h). El valor
   `cruzaMedianoche` usa comparación estricta (`fin < inicio`).
5. El aviso `databaseFactory not initialized` del `widget_test` es preexistente
   y no afecta al resultado.

---

## 📌 Criterios de aceptación

- [x] Un `DateTime` determina correctamente si pertenece a un horario.
- [x] Los minutos son considerados.
- [x] Los días de la semana son considerados.
- [x] Los horarios nocturnos funcionan.
- [x] Las pruebas cubren los casos límite.
- [x] `dart analyze` / tests sin errores.

---

## ⏭️ Siguiente etapa (no iniciada)

- [ ] Usar `horarioActivoEn()` y la tarea planificada como contexto de las
      reglas del motor.
- [ ] Exponer en la interfaz el caso de horarios que cruzan medianoche.
- [ ] Probar en teléfono físico con datos reales.
