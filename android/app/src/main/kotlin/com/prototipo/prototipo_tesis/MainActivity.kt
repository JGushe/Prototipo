package com.prototipo.prototipo_tesis

import android.content.Context
import androidx.core.content.ContextCompat
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

/**
 * Actividad principal. Además de la interfaz Flutter, expone el canal de
 * control del monitoreo en segundo plano:
 *
 * - `iniciar`: guarda el handle del callback Dart y programa WorkManager.
 * - `detener`: cancela el trabajo periódico.
 * - `estaActivo`: informa si el monitoreo está programado o en ejecución.
 * - `ejecutarAhora`: lanza un ciclo inmediato (pruebas en el dispositivo).
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MonitoreoUsoWorker.CANAL_CONTROL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "iniciar" -> {
                    val handle = call.argument<Long>("callbackHandle")
                    if (handle == null) {
                        result.success(false)
                    } else {
                        PreferenciasMonitoreo.guardarCallbackHandle(applicationContext, handle)
                        programarTrabajoPeriodico()
                        result.success(true)
                    }
                }

                "detener" -> {
                    WorkManager.getInstance(applicationContext)
                        .cancelUniqueWork(MonitoreoUsoWorker.NOMBRE_TRABAJO)
                    result.success(true)
                }

                "estaActivo" -> consultarEstado(result)

                "ejecutarAhora" -> {
                    WorkManager.getInstance(applicationContext).enqueueUniqueWork(
                        "${MonitoreoUsoWorker.NOMBRE_TRABAJO}_ahora",
                        ExistingWorkPolicy.KEEP,
                        OneTimeWorkRequestBuilder<MonitoreoUsoWorker>().build(),
                    )
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun programarTrabajoPeriodico() {
        // 15 minutos es el mínimo que permite WorkManager para trabajo periódico.
        val solicitud =
            PeriodicWorkRequestBuilder<MonitoreoUsoWorker>(15, TimeUnit.MINUTES).build()

        WorkManager.getInstance(applicationContext).enqueueUniquePeriodicWork(
            MonitoreoUsoWorker.NOMBRE_TRABAJO,
            ExistingPeriodicWorkPolicy.UPDATE,
            solicitud,
        )
    }

    private fun consultarEstado(result: MethodChannel.Result) {
        val futuro = WorkManager.getInstance(applicationContext)
            .getWorkInfosForUniqueWork(MonitoreoUsoWorker.NOMBRE_TRABAJO)

        futuro.addListener(
            {
                val activo = try {
                    futuro.get().any {
                        it.state == WorkInfo.State.ENQUEUED || it.state == WorkInfo.State.RUNNING
                    }
                } catch (_: Exception) {
                    false
                }
                result.success(activo)
            },
            ContextCompat.getMainExecutor(applicationContext),
        )
    }
}
