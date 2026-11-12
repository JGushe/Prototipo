package com.prototipo.prototipo_tesis;

import android.app.Activity;
import android.app.Instrumentation;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.os.Bundle;
import android.os.Process;
import android.os.SystemClock;
import androidx.work.OneTimeWorkRequest;
import androidx.work.WorkInfo;
import androidx.work.WorkManager;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;

/** Ejecuta el Worker en el proceso Android, sin iniciar una FlutterActivity. */
public final class MonitoreoEnFrioTest extends Instrumentation {
    private boolean concurrente;
    private boolean esperarFallo;
    private boolean verificarPersistencia;

    @Override
    public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        if (arguments != null) {
            concurrente = "true".equals(arguments.getString("concurrente"));
            esperarFallo = "true".equals(arguments.getString("esperarFallo"));
            verificarPersistencia = "true".equals(arguments.getString("verificarPersistencia"));
        }
        start();
    }

    @Override
    public void onStart() {
        Bundle resultado = new Bundle();
        WorkManager workManager = WorkManager.getInstance(getTargetContext());
        List<OneTimeWorkRequest> trabajos = new ArrayList<>();
        int ciclos = concurrente ? 2 : 1;
        for (int i = 0; i < ciclos; i++) {
            trabajos.add(new OneTimeWorkRequest.Builder(MonitoreoUsoWorker.class).build());
        }
        long inicio = SystemClock.elapsedRealtime();
        long cpuInicial = Process.getElapsedCpuTime();
        try {
            workManager.enqueue(trabajos).getResult().get(10, TimeUnit.SECONDS);
            long limite = inicio + 60_000;
            while (SystemClock.elapsedRealtime() < limite) {
                List<WorkInfo.State> estados = new ArrayList<>();
                for (OneTimeWorkRequest trabajo : trabajos) {
                    WorkInfo info = workManager.getWorkInfoById(trabajo.getId())
                            .get(5, TimeUnit.SECONDS);
                    if (info != null && info.getState().isFinished()) {
                        estados.add(info.getState());
                    }
                }
                if (estados.size() == ciclos) {
                    WorkInfo.State esperado =
                            esperarFallo ? WorkInfo.State.FAILED : WorkInfo.State.SUCCEEDED;
                    resultado.putString("estado",
                            ciclos == 1 ? estados.get(0).name() : estados.toString());
                    resultado.putLong("duracion_ms", SystemClock.elapsedRealtime() - inicio);
                    resultado.putLong("cpu_proceso_ms", Process.getElapsedCpuTime() - cpuInicial);
                    if (verificarPersistencia) comprobarDatos(resultado);
                    boolean datosValidos = !verificarPersistencia
                            || (resultado.getInt("resumenes_hoy", -1) == 1
                                && resultado.getInt("grupos_app_duplicados_hoy", -1) == 0);
                    finish(estados.stream().allMatch(esperado::equals) && datosValidos
                            ? Activity.RESULT_OK : Activity.RESULT_CANCELED, resultado);
                    return;
                }
                SystemClock.sleep(500);
            }
            resultado.putString("estado", "TIMEOUT");
        } catch (Exception error) {
            resultado.putString("estado", error.getClass().getSimpleName());
        }
        for (OneTimeWorkRequest trabajo : trabajos) {
            workManager.cancelWorkById(trabajo.getId());
        }
        finish(Activity.RESULT_CANCELED, resultado);
    }

    private void comprobarDatos(Bundle resultado) {
        String fecha = LocalDate.now().toString();
        String ruta = getTargetContext().getDatabasePath("prototipo_tesis.db").getPath();
        try (SQLiteDatabase db = SQLiteDatabase.openDatabase(
                ruta, null, SQLiteDatabase.OPEN_READONLY)) {
            try (Cursor resumen = db.rawQuery(
                    "SELECT COUNT(*), MAX(tiempoTotalMinutos) FROM uso_pantalla WHERE fecha = ?",
                    new String[]{fecha})) {
                if (resumen.moveToFirst()) {
                    resultado.putInt("resumenes_hoy", resumen.getInt(0));
                    if (!resumen.isNull(1)) {
                        resultado.putInt("minutos_guardados", resumen.getInt(1));
                    }
                }
            }
            try (Cursor duplicados = db.rawQuery(
                    "SELECT COUNT(*) FROM (SELECT 1 FROM app_uso WHERE fecha = ? "
                    + "GROUP BY nombrePaquete HAVING COUNT(*) > 1)", new String[]{fecha})) {
                if (duplicados.moveToFirst()) {
                    resultado.putInt("grupos_app_duplicados_hoy", duplicados.getInt(0));
                }
            }
        }
    }
}
