package com.dantetesta.dantecast.encoder

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Bundle
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer

/**
 * Encoder H.264 (video/avc) baseado em MediaCodec no modo Surface.
 *
 * Fluxo:
 *  - configure() cria o codec, define bitrate/fps/keyframe interval e cria a INPUT Surface,
 *    que será o alvo do VirtualDisplay (ScreenCaptureManager desenha nela).
 *  - O loop async (Callback) entrega:
 *      (a) o buffer CODEC_CONFIG (SPS/PPS em Annex-B) -> onConfig
 *      (b) cada access unit codificado -> onFrame(ptsMicros, keyframe, bytes)
 *  - requestSyncFrame() força um keyframe (ex.: após rotação).
 *
 * Os bytes entregues são EXATAMENTE a saída do MediaCodec (já em Annex-B com start codes),
 * compatíveis com o que o protocolo DCWP espera para VIDEO_CONFIG/VIDEO_FRAME.
 */
class H264Encoder(
    private val onConfig: (csdAnnexB: ByteArray) -> Unit,
    private val onFrame: (ptsMicros: Long, keyframe: Boolean, data: ByteArray) -> Unit,
    private val onError: (Throwable) -> Unit
) {
    private val tag = "H264Encoder"
    private val mime = MediaFormat.MIMETYPE_VIDEO_AVC

    private var codec: MediaCodec? = null
    private var inputSurface: Surface? = null

    @Volatile private var started = false

    /**
     * Configura e inicia o encoder. Retorna a INPUT Surface a ser usada pelo VirtualDisplay.
     */
    fun configure(width: Int, height: Int, fps: Int, bitrate: Int): Surface {
        val format = MediaFormat.createVideoFormat(mime, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            // Keyframe a cada 1s — bom equilíbrio entre recuperação e overhead.
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            // VBR para qualidade estável; CBR também é aceitável dependendo do device.
            setInteger(MediaFormat.KEY_BITRATE_MODE, MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR)
            // --- Baixa latência (anti-lag) ---
            // Prioridade tempo-real (0 = realtime, 1 = best-effort).
            setInteger(MediaFormat.KEY_PRIORITY, 0)
            // Pede ao encoder a maior taxa de operação possível (não limita a fps).
            setInteger(MediaFormat.KEY_OPERATING_RATE, Short.MAX_VALUE.toInt())
            // Latência de 1 frame (sem reordenação/B-frames acumulados), onde suportado.
            setInteger(MediaFormat.KEY_LATENCY, 1)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                // Modo de baixa latência explícito (API 30+) — ignorado se não suportado.
                runCatching { setInteger(MediaFormat.KEY_LOW_LATENCY, 1) }
            }
            // Não forçamos profile/level: deixar o encoder escolher maximiza a compatibilidade
            // entre devices (forçar Baseline+nível fixo pode falhar em configure() em alguns SoCs).
        }

        val c = MediaCodec.createEncoderByType(mime)
        // Callback async: não bloqueamos threads esperando buffers.
        c.setCallback(object : MediaCodec.Callback() {
            override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
                // Modo Surface: a entrada vem da Surface, não usamos input buffers.
            }

            override fun onOutputBufferAvailable(
                codec: MediaCodec,
                index: Int,
                info: MediaCodec.BufferInfo
            ) {
                try {
                    val outBuf: ByteBuffer = codec.getOutputBuffer(index) ?: run {
                        codec.releaseOutputBuffer(index, false); return
                    }
                    outBuf.position(info.offset)
                    outBuf.limit(info.offset + info.size)

                    val isConfig = (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
                    val isKeyframe = (info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0

                    if (info.size > 0) {
                        val bytes = ByteArray(info.size)
                        outBuf.get(bytes)
                        if (isConfig) {
                            // SPS/PPS (CODEC_CONFIG) -> VIDEO_CONFIG
                            onConfig(bytes)
                        } else {
                            // Access unit -> VIDEO_FRAME (pts em microssegundos)
                            onFrame(info.presentationTimeUs, isKeyframe, bytes)
                        }
                    }
                    codec.releaseOutputBuffer(index, false)
                } catch (t: Throwable) {
                    onError(t)
                }
            }

            override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
                Log.e(tag, "Erro no MediaCodec", e)
                onError(e)
            }

            override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
                // Em modo Surface, o CODEC_CONFIG vem como buffer; este callback é informativo.
                Log.d(tag, "Formato de saída mudou: $format")
            }
        })

        c.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        inputSurface = c.createInputSurface()
        c.start()
        codec = c
        started = true
        Log.i(tag, "Encoder iniciado ${width}x${height}@${fps} ${bitrate}bps")
        return inputSurface!!
    }

    /** Força um keyframe (sync frame) — usar após rotação / reconfiguração. */
    fun requestSyncFrame() {
        if (!started) return
        runCatching {
            val params = Bundle().apply {
                putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
            }
            codec?.setParameters(params)
        }
    }

    /** Ajusta o bitrate em tempo real (opcional; útil para adaptação de rede). */
    fun updateBitrate(bitrate: Int) {
        if (!started) return
        runCatching {
            val params = Bundle().apply {
                putInt(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, bitrate)
            }
            codec?.setParameters(params)
        }
    }

    /** Sinaliza fim de stream e libera tudo. */
    fun release() {
        if (!started && codec == null) return
        started = false
        runCatching { codec?.signalEndOfInputStream() }
        runCatching { codec?.stop() }
        runCatching { codec?.release() }
        runCatching { inputSurface?.release() }
        codec = null
        inputSurface = null
        Log.i(tag, "Encoder liberado")
    }
}
