package com.dantetesta.dantecast.model

/**
 * Presets de qualidade/resolução/fps do stream.
 * Os valores espelham o lado macOS (StreamSettings.swift) para coerência da UX.
 */

/** Resolução alvo do encoder. `NATIVE` usa as dimensões reais da tela. */
enum class Resolution(val label: String, val width: Int, val height: Int) {
    HD720("720p", 1280, 720),
    HD1080("1080p", 1920, 1080),
    NATIVE("Nativa", 0, 0); // 0,0 => decidir em runtime a partir do display

    companion object {
        fun fromLabel(label: String): Resolution =
            entries.firstOrNull { it.label == label } ?: HD1080
    }
}

/** Taxa de quadros suportada. O protocolo anuncia [30, 60]. */
enum class Fps(val value: Int) {
    FPS30(30),
    FPS60(60);

    companion object {
        fun fromValue(v: Int): Fps = if (v >= 60) FPS60 else FPS30
    }
}

/**
 * Bitrate padrão sugerido (bps) a partir da resolução e fps.
 * Mantém qualidade razoável sem saturar a LAN.
 */
object BitratePresets {
    fun suggestedBitrate(resolution: Resolution, fps: Fps, screenW: Int, screenH: Int): Int {
        val (w, h) = if (resolution == Resolution.NATIVE) screenW to screenH
        else resolution.width to resolution.height
        // Heurística simples baseada em pixels/segundo.
        val pixels = (w.coerceAtLeast(1)).toLong() * h.coerceAtLeast(1)
        val base = when {
            pixels >= 1920L * 1080 -> 8_000_000
            pixels >= 1280L * 720 -> 5_000_000
            else -> 3_000_000
        }
        // 60fps adiciona ~50% de bitrate.
        return if (fps == Fps.FPS60) (base * 3) / 2 else base
    }

    const val MIN_BITRATE = 1_000_000
    const val MAX_BITRATE = 20_000_000
}
