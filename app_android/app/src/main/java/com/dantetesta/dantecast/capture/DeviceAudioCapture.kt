package com.dantetesta.dantecast.capture

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.annotation.RequiresApi
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Captura o ÁUDIO do dispositivo (playback) via [AudioPlaybackCaptureConfiguration] (API 29+).
 *
 * Reaproveita a MESMA [MediaProjection] já obtida pelo service (não pede nova permissão de
 * captura). Requer RECORD_AUDIO em runtime e que o app/jogo de origem permita a captura
 * (apps podem marcar o áudio como não-capturável — nesse caso recebemos silêncio ou nada).
 *
 * Saída: PCM signed 16-bit LITTLE-endian intercalado (estéreo), entregue cru ao callback
 * [onPcm]; o protocolo apenas prefixa um pts big-endian (ver WireProtocol.encodeAudioFrame).
 *
 * NUNCA deve derrubar a sessão de vídeo: o service trata exceções e segue VIDEO-ONLY.
 */
@RequiresApi(Build.VERSION_CODES.Q)
class DeviceAudioCapture(
    private val projection: MediaProjection,
    private val onPcm: (ptsMicros: Long, pcm: ByteArray) -> Unit,
    private val onError: (Throwable) -> Unit
) {
    private val tag = "DeviceAudioCapture"

    private var audioRecord: AudioRecord? = null
    private var captureThread: Thread? = null
    private val running = AtomicBoolean(false)

    /**
     * Constrói o AudioRecord e começa a ler PCM em uma thread dedicada.
     * @throws SecurityException se RECORD_AUDIO não foi concedida.
     * @throws IllegalStateException se o AudioRecord não inicializar.
     */
    fun start() {
        if (running.get()) return

        // Configuração de captura: capturamos somente usos "audíveis" comuns.
        val config = AudioPlaybackCaptureConfiguration.Builder(projection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()

        val audioFormat = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(SAMPLE_RATE)
            .setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
            .build()

        // Buffer dimensionado a partir do mínimo do sistema (com folga p/ evitar overrun).
        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_STEREO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        val bufferSize = if (minBuf > 0) minBuf * 2 else SAMPLE_RATE * CHANNELS * 2 // fallback ~0.5s

        val record = AudioRecord.Builder()
            .setAudioFormat(audioFormat)
            .setBufferSizeInBytes(bufferSize)
            .setAudioPlaybackCaptureConfig(config) // lança SecurityException sem RECORD_AUDIO
            .build()

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            runCatching { record.release() }
            throw IllegalStateException("AudioRecord não inicializou (state=${record.state})")
        }

        audioRecord = record
        running.set(true)
        record.startRecording()

        // Tamanho de leitura por iteração: ~20ms de áudio (baixa latência, pouco overhead).
        // 44100 * 2 canais * 2 bytes * 0.02s ≈ 3528 bytes.
        val readChunk = (SAMPLE_RATE * CHANNELS * BYTES_PER_SAMPLE / 50).coerceAtLeast(1024)

        captureThread = thread(name = "DanteCastAudio", isDaemon = true) {
            val buffer = ByteArray(readChunk)
            try {
                while (running.get()) {
                    val read = record.read(buffer, 0, buffer.size)
                    if (read > 0) {
                        // pts monotônico em micros (independente de wall-clock).
                        val ptsMicros = SystemClock.elapsedRealtimeNanos() / 1000
                        // Copia exatamente os bytes lidos (read pode ser < buffer.size).
                        val pcm = if (read == buffer.size) buffer.copyOf() else buffer.copyOf(read)
                        onPcm(ptsMicros, pcm)
                    } else if (read == AudioRecord.ERROR_INVALID_OPERATION ||
                        read == AudioRecord.ERROR_BAD_VALUE ||
                        read == AudioRecord.ERROR_DEAD_OBJECT
                    ) {
                        Log.w(tag, "AudioRecord.read erro=$read — encerrando captura de áudio")
                        break
                    }
                    // read == 0: nada disponível ainda; o loop volta a tentar.
                }
            } catch (t: Throwable) {
                if (running.get()) onError(t)
            }
        }
        Log.i(tag, "Captura de áudio iniciada ${SAMPLE_RATE}Hz ${CHANNELS}ch buffer=$bufferSize")
    }

    /** Para a leitura e libera o AudioRecord. Idempotente. */
    fun stop() {
        if (!running.getAndSet(false)) return
        runCatching { audioRecord?.stop() }
        runCatching { audioRecord?.release() }
        audioRecord = null
        // Não chamamos join() para evitar bloquear o teardown; a thread sai pelo flag.
        captureThread = null
        Log.i(tag, "Captura de áudio liberada")
    }

    companion object {
        const val SAMPLE_RATE = 44100
        const val CHANNELS = 2
        const val BITS_PER_SAMPLE = 16
        private const val BYTES_PER_SAMPLE = 2
    }
}
