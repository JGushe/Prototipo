package com.prototipo.prototipo_tesis

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

/** Ejecuta el ciclo Dart en un motor headless sin bloquear el hilo principal. */
class MonitoreoUsoWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        Log.i(TAG, "inicio intento=${runAttemptCount + 1}")
        val handle = PreferenciasMonitoreo.obtenerCallbackHandle(applicationContext)
            ?: return terminar("callback_invalido")

        return try {
            // FlutterEngine y sus canales deben crearse y destruirse en el hilo principal.
            withContext(Dispatchers.Main) {
                val engine = FlutterEngine(applicationContext)
                val canal = MethodChannel(engine.dartExecutor.binaryMessenger, CANAL_COMPLETADO)
                try {
                    // La consulta usa JNI. En arranque en frío, el motor carga
                    // Flutter antes de intentar resolver el handle persistido.
                    val info = FlutterCallbackInformation.lookupCallbackInformation(handle)
                        ?: return@withContext terminar("callback_invalido")
                    val completado = CompletableDeferred<String>()
                    canal.setMethodCallHandler { call, result ->
                        if (call.method != "completado") {
                            result.notImplemented()
                        } else {
                            val estadoDart = call.argument<String>("estado")
                            val estado = when (estadoDart) {
                                "ok", "sin_permiso_uso", "sin_datos_uso",
                                "error_ciclo", "error_notificacion" -> estadoDart
                                else -> "respuesta_invalida"
                            }
                            if (estado == "ok") {
                                val generadas = call.argument<Int>("generadas") ?: 0
                                val notificadas = call.argument<Int>("notificadas") ?: 0
                                Log.i(TAG, "captura_confirmada generadas=$generadas notificadas=$notificadas")
                            }
                            result.success(null)
                            completado.complete(estado)
                        }
                    }
                    val callback = DartExecutor.DartCallback(
                        applicationContext.assets,
                        FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                        info,
                    )
                    engine.dartExecutor.executeDartCallback(callback)
                    terminar(withTimeout(TIEMPO_MAXIMO_MS) { completado.await() })
                } finally {
                    canal.setMethodCallHandler(null)
                    engine.destroy()
                }
            }
        } catch (_: TimeoutCancellationException) {
            terminar("timeout")
        } catch (e: CancellationException) {
            Log.i(TAG, "fin estado=cancelado")
            throw e
        } catch (_: Exception) {
            terminar("error_motor")
        } catch (_: LinkageError) {
            terminar("error_motor")
        }
    }

    private fun terminar(estado: String): Result {
        val reintentar = estado in ESTADOS_REINTENTABLES && runAttemptCount < MAX_REINTENTOS
        val resultado = when {
            estado == "ok" -> Result.success()
            reintentar -> Result.retry()
            else -> Result.failure()
        }
        Log.i(TAG, "fin estado=$estado reintento=$reintentar")
        return resultado
    }

    companion object {
        /** Nombre del trabajo único en WorkManager. */
        const val NOMBRE_TRABAJO = "monitoreo_uso_horarios"

        /** Canal de control app <-> nativo. */
        const val CANAL_CONTROL = "prototipo_tesis/monitoreo"

        /** Canal por el que el isolate de fondo avisa de que terminó. */
        const val CANAL_COMPLETADO = "prototipo_tesis/monitoreo_completado"

        private const val TAG = "PrototipoMonitoreo"
        private const val TIEMPO_MAXIMO_MS = 4 * 60 * 1000L
        private const val MAX_REINTENTOS = 2
        private val ESTADOS_REINTENTABLES = setOf("timeout", "error_motor", "error_ciclo")
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
