package com.prototipo.prototipo_tesis

import android.content.Context
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.Operation
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

        val preferenciasTips = getSharedPreferences("preferencias_tips", Context.MODE_PRIVATE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "prototipo_tesis/preferencias_tips").setMethodCallHandler { call, result ->
            when (call.method) {
                "leerFechasOcultas" -> result.success(
                    preferenciasTips.getStringSet("fechas_ocultas", emptySet())!!.toList())
                "guardarFechasOcultas" -> {
                    val fechas = call.arguments as? List<*>
                    if (fechas == null || fechas.any { it !is String ||
                            !Regex("\\d{4}-\\d{2}-\\d{2}").matches(it) }) {
                        result.error("fechas_invalidas", "Fechas inválidas", null)
                    } else {
                        val guardado = preferenciasTips.edit()
                            .putStringSet("fechas_ocultas", fechas.filterIsInstance<String>().toSet())
                            .commit()
                        if (guardado) result.success(null)
                        else result.error("error_guardado", "No se pudo guardar el filtro", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MonitoreoUsoWorker.CANAL_CONTROL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "iniciar" -> {
                    val handle = call.argument<Number>("callbackHandle")?.toLong()
                    if (handle == null) {
                        Log.w("PrototipoMonitoreo", "control callback_ausente")
                        result.success(false)
                    } else {
                        PreferenciasMonitoreo.guardarCallbackHandle(applicationContext, handle)
                        responderOperacion(programarTrabajoPeriodico(), result)
                    }
                }

                "detener" -> {
                    val operacion = WorkManager.getInstance(applicationContext)
                        .cancelAllWorkByTag(MonitoreoUsoWorker::class.java.name)
                    responderOperacion(operacion, result)
                }

                "estaActivo" -> consultarEstado(result)

                "ejecutarAhora" -> {
                    val operacion = WorkManager.getInstance(applicationContext).enqueueUniqueWork(
                        "${MonitoreoUsoWorker.NOMBRE_TRABAJO}_ahora",
                        ExistingWorkPolicy.KEEP,
                        OneTimeWorkRequestBuilder<MonitoreoUsoWorker>().build(),
                    )
                    responderOperacion(operacion, result)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun programarTrabajoPeriodico(): Operation {
        // 15 minutos es el mínimo que permite WorkManager para trabajo periódico.
        val solicitud =
            PeriodicWorkRequestBuilder<MonitoreoUsoWorker>(15, TimeUnit.MINUTES).build()

        return WorkManager.getInstance(applicationContext).enqueueUniquePeriodicWork(
            MonitoreoUsoWorker.NOMBRE_TRABAJO,
            // Conserva el trabajo activo y crea otro si el anterior terminó
            // en error. UPDATE puede dejar intacto un trabajo ya finalizado.
            ExistingPeriodicWorkPolicy.KEEP,
            solicitud,
        )
    }

    private fun responderOperacion(operacion: Operation, result: MethodChannel.Result) {
        val futuro = operacion.result
        futuro.addListener(
            {
                val completada = try {
                    futuro.get()
                    true
                } catch (error: Exception) {
                    val tipo = (error.cause ?: error).javaClass.simpleName
                    Log.w("PrototipoMonitoreo", "control operacion_fallida tipo=$tipo")
                    false
                }
                result.success(completada)
            },
            ContextCompat.getMainExecutor(applicationContext),
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
