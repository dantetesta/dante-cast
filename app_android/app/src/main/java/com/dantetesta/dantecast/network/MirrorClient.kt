package com.dantetesta.dantecast.network

import android.util.Log
import com.dantetesta.dantecast.pairing.Hello
import com.dantetesta.dantecast.pairing.HelloAck
import com.dantetesta.dantecast.pairing.Orientation
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Cliente TCP do protocolo DCWP v1.
 *
 * Design:
 *  - 1 coroutine ESCRITORA dedicada consome uma fila (Channel) de frames já montados.
 *    Assim a thread do encoder NUNCA bloqueia no socket — ela só faz `enqueue(...)`.
 *  - 1 coroutine LEITORA processa HELLO_ACK, PONG e PINGs do Mac (echo).
 *  - PING periódico (~2s) mede a latência (RTT) via System.nanoTime.
 *
 * Callbacks são chamados a partir das coroutines internas; o consumidor deve ser thread-safe.
 */
class MirrorClient(
    private val onHelloAck: (HelloAck) -> Unit,
    private val onLatency: (Long) -> Unit,
    private val onDisconnected: (Throwable?) -> Unit
) {
    private val tag = "MirrorClient"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var socket: Socket? = null
    private var output: BufferedOutputStream? = null
    private var input: DataInputStream? = null

    // Fila de saída: frames já serializados (header + payload).
    // Capacidade limitada + DROP_OLDEST evita acúmulo de memória se a rede engasgar:
    // preferimos descartar frames antigos (latência) a estourar RAM.
    private val outbound = Channel<ByteArray>(capacity = 64, onBufferOverflow = kotlinx.coroutines.channels.BufferOverflow.DROP_OLDEST)

    private var writerJob: Job? = null
    private var readerJob: Job? = null
    private var pingJob: Job? = null

    private val running = AtomicBoolean(false)

    // Para casar PING->PONG e medir RTT (assumindo um ping pendente por vez).
    @Volatile private var lastPingNanos: Long = 0L

    /**
     * Conecta TCP e dispara as coroutines de leitura/escrita.
     * @throws Exception se a conexão falhar (o chamador trata erro).
     */
    suspend fun connect(ip: String, port: Int, connectTimeoutMs: Int = 8000) = withContext(Dispatchers.IO) {
        val s = Socket()
        s.tcpNoDelay = true                 // baixa latência (desliga Nagle)
        s.keepAlive = true
        s.connect(InetSocketAddress(ip, port), connectTimeoutMs)
        socket = s
        output = BufferedOutputStream(s.getOutputStream(), 256 * 1024)
        input = DataInputStream(s.getInputStream())
        running.set(true)

        startWriter()
        startReader()
        Log.i(tag, "Conectado a $ip:$port")
    }

    // ---------------------------- WRITER ----------------------------

    private fun startWriter() {
        writerJob = scope.launch {
            try {
                for (frame in outbound) {
                    val out = output ?: break
                    out.write(frame)
                    // flush imediato para frames de vídeo (latência baixa).
                    out.flush()
                }
            } catch (t: Throwable) {
                if (running.get()) teardown(t)
            }
        }
    }

    // ---------------------------- READER ----------------------------

    private fun startReader() {
        readerJob = scope.launch {
            val inp = input ?: return@launch
            try {
                while (isActive && running.get()) {
                    val header = WireProtocol.readHeader(inp)
                    val payload = WireProtocol.readPayload(inp, header.payloadLength)
                    handleIncoming(header.type, payload)
                }
            } catch (t: Throwable) {
                if (running.get()) teardown(t)
            }
        }
    }

    private fun handleIncoming(type: Byte, payload: ByteArray) {
        when (type) {
            WireProtocol.Type.HELLO_ACK -> {
                runCatching { WireProtocol.decodeHelloAck(payload) }
                    .onSuccess { ack ->
                        // Notifica quem aguarda o handshake (sendHelloAwaitAck) e o callback público.
                        ackProxy.target?.invoke(ack)
                        onHelloAck(ack)
                    }
                    .onFailure { Log.e(tag, "HELLO_ACK inválido", it) }
            }
            WireProtocol.Type.PONG -> {
                // RTT = agora - quando enviamos o PING (eco do nosso nanos).
                val echoed = runCatching { WireProtocol.decodePingPong(payload) }.getOrNull()
                if (echoed != null && echoed == lastPingNanos) {
                    val rttNs = System.nanoTime() - echoed
                    onLatency(rttNs / 1_000_000) // ms
                }
            }
            WireProtocol.Type.PING -> {
                // O Mac também pode pingar: ecoamos o valor de volta como PONG.
                enqueueRaw(WireProtocol.buildFrame(WireProtocol.Type.PONG, payload))
            }
            WireProtocol.Type.STREAM_STOP, WireProtocol.Type.BYE -> {
                Log.i(tag, "Mac solicitou parada (type=$type)")
                teardown(null)
            }
            WireProtocol.Type.ERROR -> {
                val err = runCatching { WireProtocol.decodeError(payload) }.getOrNull()
                Log.w(tag, "ERROR do Mac: ${err?.code} ${err?.message}")
                teardown(Exception(err?.message ?: "Erro do Mac"))
            }
            else -> Log.d(tag, "Mensagem ignorada type=$type")
        }
    }

    // ---------------------------- HANDSHAKE ----------------------------

    /** Envia HELLO e aguarda o HELLO_ACK (com timeout). Retorna o ack recebido. */
    suspend fun sendHelloAwaitAck(hello: Hello, timeoutMs: Long = 8000): HelloAck {
        // Promessa simples baseada em um campo que o reader preenche via callback externo;
        // aqui usamos um Channel local para sincronizar a primeira resposta.
        val ackChannel = Channel<HelloAck>(capacity = 1)
        val proxy = ackProxy
        proxy.target = { ack -> ackChannel.trySend(ack) }
        try {
            enqueueRaw(WireProtocol.buildFrame(WireProtocol.Type.HELLO, WireProtocol.encodeHello(hello)))
            return withTimeout(timeoutMs) { ackChannel.receive() }
        } finally {
            proxy.target = null
        }
    }

    // Proxy interno: o reader chama onHelloAck (callback público) E este proxy (handshake).
    private val ackProxy = AckProxy()
    private class AckProxy { @Volatile var target: ((HelloAck) -> Unit)? = null }

    // ---------------------------- ENVIO PÚBLICO ----------------------------

    /** Enfileira VIDEO_CONFIG (SPS/PPS). */
    fun sendVideoConfig(width: Int, height: Int, fps: Int, csdAnnexB: ByteArray) {
        enqueueRaw(WireProtocol.buildFrame(WireProtocol.Type.VIDEO_CONFIG, WireProtocol.encodeVideoConfig(width, height, fps, csdAnnexB)))
    }

    /** Enfileira um VIDEO_FRAME (AU em Annex-B). Não bloqueia. */
    fun sendVideoFrame(ptsMicros: Long, keyframe: Boolean, accessUnit: ByteArray) {
        enqueueRaw(WireProtocol.buildFrame(WireProtocol.Type.VIDEO_FRAME, WireProtocol.encodeVideoFrame(ptsMicros, keyframe, accessUnit)))
    }

    /** Enfileira ORIENTATION. */
    fun sendOrientation(o: Orientation) {
        enqueueRaw(WireProtocol.buildFrame(WireProtocol.Type.ORIENTATION, WireProtocol.encodeOrientation(o)))
    }

    /** Inicia PINGs periódicos para medir latência. */
    fun startHeartbeat(intervalMs: Long = 2000) {
        if (pingJob?.isActive == true) return
        pingJob = scope.launch {
            while (isActive && running.get()) {
                val nanos = System.nanoTime()
                lastPingNanos = nanos
                enqueueRaw(WireProtocol.buildFrame(WireProtocol.Type.PING, WireProtocol.encodePingPong(nanos)))
                delay(intervalMs)
            }
        }
    }

    // ---------------------------- TEARDOWN ----------------------------

    /** Envia BYE (best-effort) e encerra tudo. */
    fun sendByeAndClose() {
        runCatching {
            val out = output
            if (out != null) {
                out.write(WireProtocol.buildFrame(WireProtocol.Type.BYE))
                out.flush()
            }
        }
        teardown(null)
    }

    /** Encerra socket e coroutines de forma segura (idempotente). */
    fun teardown(cause: Throwable?) {
        if (!running.getAndSet(false)) return
        outbound.close()
        pingJob?.cancel()
        readerJob?.cancel()
        writerJob?.cancel()
        runCatching { input?.close() }
        runCatching { output?.close() }
        runCatching { socket?.close() }
        input = null; output = null; socket = null
        onDisconnected(cause)
        scope.cancel()
    }

    // ---------------------------- INTERNALS ----------------------------

    private fun enqueueRaw(frame: ByteArray) {
        if (!running.get()) return
        // trySend não bloqueia; com DROP_OLDEST, frames antigos somem se a fila encher.
        outbound.trySend(frame)
    }
}
