package com.dantetesta.dantecast.capture

import android.content.Context
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.projection.MediaProjection
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import android.view.Surface
import android.view.WindowManager

/**
 * Gerencia a captura de tela via MediaProjection -> VirtualDisplay -> Surface do encoder.
 *
 * Android 14+ (API 34): É OBRIGATÓRIO registrar um [MediaProjection.Callback].
 * Quando onStop dispara (usuário/sistema revoga a projeção), paramos a captura.
 */
class ScreenCaptureManager(
    private val context: Context,
    private val onProjectionStopped: () -> Unit
) {
    private val tag = "ScreenCapture"

    private var virtualDisplay: VirtualDisplay? = null
    private var mediaProjection: MediaProjection? = null
    private val handler = Handler(Looper.getMainLooper())

    // Callback exigido pelo Android 14+: a projeção pode ser revogada a qualquer momento.
    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            Log.i(tag, "MediaProjection.onStop — projeção revogada")
            onProjectionStopped()
        }
    }

    /** Resolução física da tela (para o modo NATIVE e para o ORIENTATION). */
    data class ScreenInfo(val width: Int, val height: Int, val densityDpi: Int, val rotation: Int)

    fun currentScreenInfo(): ScreenInfo {
        val metrics = DisplayMetrics()
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        @Suppress("DEPRECATION")
        val display = wm.defaultDisplay
        @Suppress("DEPRECATION")
        display.getRealMetrics(metrics)
        val rotationDeg = when (display.rotation) {
            Surface.ROTATION_0 -> 0
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
        return ScreenInfo(metrics.widthPixels, metrics.heightPixels, metrics.densityDpi, rotationDeg)
    }

    /**
     * Inicia a projeção e cria o VirtualDisplay desenhando em [surface] (input do encoder).
     *
     * @param projection MediaProjection já obtida no service (após startForeground).
     * @param surface Surface de entrada do encoder.
     * @param width/height dimensões do VirtualDisplay (devem casar com o encoder).
     * @param densityDpi densidade do display virtual.
     */
    fun start(
        projection: MediaProjection,
        surface: Surface,
        width: Int,
        height: Int,
        densityDpi: Int
    ) {
        mediaProjection = projection
        // Registrar o callback ANTES de criar o VirtualDisplay (requisito Android 14+).
        projection.registerCallback(projectionCallback, handler)

        virtualDisplay = projection.createVirtualDisplay(
            "DanteCastDisplay",
            width,
            height,
            densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            surface,
            null,
            handler
        )
        Log.i(tag, "VirtualDisplay criado ${width}x${height} @${densityDpi}dpi")
    }

    /**
     * Reaproveita a projeção mas troca o tamanho do VirtualDisplay (ex.: rotação).
     * Recria o VirtualDisplay apontando para a (nova) surface.
     */
    fun resize(surface: Surface, width: Int, height: Int, densityDpi: Int) {
        val projection = mediaProjection ?: return
        runCatching { virtualDisplay?.release() }
        virtualDisplay = projection.createVirtualDisplay(
            "DanteCastDisplay",
            width,
            height,
            densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            surface,
            null,
            handler
        )
        Log.i(tag, "VirtualDisplay redimensionado ${width}x${height}")
    }

    /** Libera VirtualDisplay e a projeção de forma limpa. */
    fun release() {
        runCatching { virtualDisplay?.release() }
        runCatching {
            mediaProjection?.unregisterCallback(projectionCallback)
            mediaProjection?.stop()
        }
        virtualDisplay = null
        mediaProjection = null
        Log.i(tag, "Captura liberada")
    }
}
