package com.dantetesta.dantecast.model

import androidx.compose.runtime.Immutable

/**
 * Configurações de stream escolhidas pelo usuário (persistidas via DataStore).
 *
 * Importante: o Mac envia as configurações "oficiais" no HELLO_ACK. Estas aqui são
 * as preferências locais usadas como fallback / valor inicial e para a tela de Settings.
 */
@Immutable
data class StreamSettings(
    val resolution: Resolution = Resolution.HD1080,
    val fps: Fps = Fps.FPS30,
    /** bps. Se < 0, deriva automaticamente do preset. */
    val bitrate: Int = -1
) {
    /** Bitrate efetivo (resolve o automático). */
    fun effectiveBitrate(screenW: Int, screenH: Int): Int =
        if (bitrate > 0) bitrate
        else BitratePresets.suggestedBitrate(resolution, fps, screenW, screenH)
}
