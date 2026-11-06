package com.prototipo.prototipo_tesis

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

/**
 * Trabajo periódico de Android (WorkManager) que ejecuta el ciclo de monitoreo
 * con la interfaz cerrada.
 *
 * No reimplementa lógica: arranca un [FlutterEngine] headless y ejecuta el
 * mismo punto de entrada Dart que usa la aplicación, de modo que las reglas, el
 * cooldown y las notificaciones son exactamente los mismos.
 *
 * WorkManager garantiza la ejecución periódica (mínimo ~15 min), la supervivencia
 * a reinicios y el respeto de Doze/batería.
 */
class MonitoreoUsoWorker(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {

    override fun doWork(): Result {
        // Sin el handle del callback Dart no hay nada que ejecutar.
        val handle = PreferenciasMonitoreo.obtenerCallbackHandle(applicationContext)
            ?: return Result.success()

        val completado = CompletableFuture<Boolean>()
        var engine: FlutterEngine? = null

        return try {
            engine = FlutterEngine(applicationContext)

            // El canal se registra ANTES de arrancar Dart: el isolate avisa aquí
            // cuando termina su ciclo.
            MethodChannel(engine.dartExecutor.binaryMessenger, CANAL_COMPLETADO)
                .setMethodCallHandler { call, result ->
                    if (call.method == "completado") {
                        completado.complete(true)
                        result.success(null)
                    } else {
                        result.notImplemented()
                    }
                }

            val info = FlutterCallbackInformation.lookupCallbackInformation(handle)
                ?: return Result.success()

            val entrypoint = DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                info.callbackName,
                info.callbackLibraryPath,
            )
            engine.dartExecutor.executeDartEntrypoint(entrypoint)

            // Espera acotada: si Dart no responde, el trabajo se reintenta.
            completado.get(TIEMPO_MAXIMO_MINUTOS, TimeUnit.MINUTES)
            Result.success()
        } catch (_: Exception) {
            Result.retry()
        } finally {
            engine?.destroy()
        }
    }

    companion object {
        /** Nombre del trabajo único en WorkManager. */
        const val NOMBRE_TRABAJO = "monitoreo_uso_horarios"

        /** Canal de control app <-> nativo. */
        const val CANAL_CONTROL = "prototipo_tesis/monitoreo"

        /** Canal por el que el isolate de fondo avisa de que terminó. */
        const val CANAL_COMPLETADO = "prototipo_tesis/monitoreo_completado"

        private const val TIEMPO_MAXIMO_MINUTOS = 4L
    }
}

/** Persistencia mínima del handle del callback Dart (SharedPreferences). */
object PreferenciasMonitoreo {
    private const val ARCHIVO = "monitoreo_prefs"
    private const val CLAVE_HANDLE = "callback_handle"

    fun guardarCallbackHandle(context: Context, handle: Long) {
        context.getSharedPreferences(ARCHIVO, Context.MODE_PRIVATE)
            .edit()
            .putLong(CLAVE_HANDLE, handle)
            .apply()
    }

    fun obtenerCallbackHandle(context: Context): Long? {
        val valor = context.getSharedPreferences(ARCHIVO, Context.MODE_PRIVATE)
            .getLong(CLAVE_HANDLE, -1L)
        return if (valor == -1L) null else valor
    }
}
