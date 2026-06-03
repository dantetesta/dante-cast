package com.dantetesta.dantecast.network

import com.dantetesta.dantecast.pairing.Hello
import com.dantetesta.dantecast.pairing.HelloAck
import com.dantetesta.dantecast.pairing.Orientation
import com.dantetesta.dantecast.pairing.ProtocolError
import kotlinx.serialization.json.Json
import java.io.DataInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * ============================ DCWP v1 — WIRE PROTOCOL ============================
 *
 * Fonte ÚNICA de framing do protocolo. DEVE bater byte-a-byte com o lado macOS.
 *
 * Transporte: TCP. Mac = SERVIDOR (escuta). Android = CLIENTE (conecta em ip:port).
 * Todos os inteiros multibyte em BIG-ENDIAN (ordem de rede).
 *
 * Cada mensagem = HEADER de 12 bytes + payload:
 *   bytes 0..3 : magic ASCII "DCWP" = 0x44,0x43,0x57,0x50
 *   byte  4    : version = 0x01
 *   byte  5    : type
 *   bytes 6..7 : flags uint16 (reservado = 0)
 *   bytes 8..11: payloadLength uint32 (rejeitar > 16 MiB)
 *
 * Tipos:
 *   0x01 HELLO        (A→M, JSON)
 *   0x02 HELLO_ACK    (M→A, JSON)
 *   0x10 VIDEO_CONFIG (A→M, binário)
 *   0x11 VIDEO_FRAME  (A→M, binário)
 *   0x12 AUDIO_CONFIG (A→M, binário)
 *   0x13 AUDIO_FRAME  (A→M, binário)
 *   0x20 ORIENTATION  (A→M, JSON)
 *   0x30 PING         (binário 8B)
 *   0x31 PONG         (binário 8B)
 *   0x40 STREAM_STOP  (vazio)
 *   0x41 BYE          (vazio)
 *   0x42 ERROR        (JSON)
 * ================================================================================
 */
object WireProtocol {

    // ---- Constantes do header ----
    val MAGIC = byteArrayOf(0x44, 0x43, 0x57, 0x50) // "DCWP"
    const val VERSION: Byte = 0x01
    const val HEADER_SIZE = 12
    const val MAX_PAYLOAD = 16 * 1024 * 1024 // 16 MiB

    // ---- Tipos de mensagem ----
    object Type {
        const val HELLO: Byte = 0x01
        const val HELLO_ACK: Byte = 0x02
        const val VIDEO_CONFIG: Byte = 0x10
        const val VIDEO_FRAME: Byte = 0x11
        const val AUDIO_CONFIG: Byte = 0x12
        const val AUDIO_FRAME: Byte = 0x13
        const val ORIENTATION: Byte = 0x20
        const val PING: Byte = 0x30
        const val PONG: Byte = 0x31
        const val STREAM_STOP: Byte = 0x40
        const val BYE: Byte = 0x41
        const val ERROR: Byte = 0x42
    }

    /** JSON usado para os payloads textuais do protocolo. */
    val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        isLenient = true
    }

    // ============================ HEADER ============================

    /** Monta um frame completo (header + payload) pronto para enviar. */
    fun buildFrame(type: Byte, payload: ByteArray = ByteArray(0), flags: Int = 0): ByteArray {
        require(payload.size <= MAX_PAYLOAD) { "Payload excede 16 MiB" }
        val buf = ByteBuffer.allocate(HEADER_SIZE + payload.size).order(ByteOrder.BIG_ENDIAN)
        buf.put(MAGIC)                 // 0..3
        buf.put(VERSION)               // 4
        buf.put(type)                  // 5
        buf.putShort((flags and 0xFFFF).toShort()) // 6..7
        buf.putInt(payload.size)       // 8..11 (uint32 — tamanhos < 2^31 cabem em Int)
        if (payload.isNotEmpty()) buf.put(payload)
        return buf.array()
    }

    /** Representa um header já parseado. */
    data class Header(val type: Byte, val flags: Int, val payloadLength: Int)

    /**
     * Lê e valida exatamente 12 bytes de header de um stream.
     * @throws ProtocolException em magic/version/length inválidos.
     */
    fun readHeader(input: DataInputStream): Header {
        val header = ByteArray(HEADER_SIZE)
        input.readFully(header) // bloqueia até completar 12 bytes (ou EOF -> exceção)
        val buf = ByteBuffer.wrap(header).order(ByteOrder.BIG_ENDIAN)

        val magic = ByteArray(4).also { buf.get(it) }
        if (!magic.contentEquals(MAGIC)) {
            throw ProtocolException("Magic inválido: ${magic.joinToString { "%02X".format(it) }}")
        }
        val version = buf.get()
        if (version != VERSION) {
            throw ProtocolException("Versão não suportada: $version")
        }
        val type = buf.get()
        val flags = buf.short.toInt() and 0xFFFF
        val length = buf.int
        if (length < 0 || length > MAX_PAYLOAD) {
            throw ProtocolException("payloadLength inválido: $length")
        }
        return Header(type, flags, length)
    }

    /** Lê exatamente `length` bytes de payload. */
    fun readPayload(input: DataInputStream, length: Int): ByteArray {
        if (length == 0) return ByteArray(0)
        val payload = ByteArray(length)
        input.readFully(payload)
        return payload
    }

    // ============================ PAYLOADS — ENCODE ============================

    fun encodeHello(hello: Hello): ByteArray =
        json.encodeToString(Hello.serializer(), hello).toByteArray(Charsets.UTF_8)

    fun encodeOrientation(o: Orientation): ByteArray =
        json.encodeToString(Orientation.serializer(), o).toByteArray(Charsets.UTF_8)

    fun encodeError(e: ProtocolError): ByteArray =
        json.encodeToString(ProtocolError.serializer(), e).toByteArray(Charsets.UTF_8)

    /**
     * VIDEO_CONFIG payload:
     *   [width uint16][height uint16][fps uint16][flags uint16] + SPS/PPS em Annex-B.
     * `csd` deve ser EXATAMENTE os bytes do BUFFER_FLAG_CODEC_CONFIG do MediaCodec.
     */
    fun encodeVideoConfig(width: Int, height: Int, fps: Int, csdAnnexB: ByteArray, flags: Int = 0): ByteArray {
        val buf = ByteBuffer.allocate(8 + csdAnnexB.size).order(ByteOrder.BIG_ENDIAN)
        buf.putShort((width and 0xFFFF).toShort())
        buf.putShort((height and 0xFFFF).toShort())
        buf.putShort((fps and 0xFFFF).toShort())
        buf.putShort((flags and 0xFFFF).toShort())
        buf.put(csdAnnexB)
        return buf.array()
    }

    /**
     * VIDEO_FRAME payload:
     *   [ptsMicros int64][flags uint8 (bit0=1 => keyframe/IDR)][reserved 3 bytes] + AU Annex-B.
     */
    fun encodeVideoFrame(ptsMicros: Long, keyframe: Boolean, accessUnit: ByteArray): ByteArray {
        val buf = ByteBuffer.allocate(12 + accessUnit.size).order(ByteOrder.BIG_ENDIAN)
        buf.putLong(ptsMicros)                       // 0..7
        buf.put(if (keyframe) 0x01.toByte() else 0)  // 8 (bit0 = keyframe)
        buf.put(0); buf.put(0); buf.put(0)           // 9..11 reservado
        buf.put(accessUnit)
        return buf.array()
    }

    /**
     * AUDIO_CONFIG payload (8 bytes, BIG-ENDIAN):
     *   [sampleRate uint32][channels uint16][bitsPerSample uint16]
     * Ex.: 44100 Hz, 2 canais, 16 bits.
     */
    fun encodeAudioConfig(sampleRate: Int, channels: Int, bitsPerSample: Int): ByteArray {
        val buf = ByteBuffer.allocate(8).order(ByteOrder.BIG_ENDIAN)
        buf.putInt(sampleRate)                          // 0..3 uint32
        buf.putShort((channels and 0xFFFF).toShort())   // 4..5 uint16
        buf.putShort((bitsPerSample and 0xFFFF).toShort()) // 6..7 uint16
        return buf.array()
    }

    /**
     * AUDIO_FRAME payload:
     *   [ptsMicros int64 BIG-ENDIAN] (sub-header de 8 bytes) + PCM cru anexado AS-IS.
     *
     * ATENÇÃO: o PCM é signed 16-bit LITTLE-endian intercalado (saída nativa do AudioRecord).
     * NÃO trocamos a ordem dos samples — apenas o sub-header de pts é big-endian.
     */
    fun encodeAudioFrame(ptsMicros: Long, pcm: ByteArray): ByteArray {
        val buf = ByteBuffer.allocate(8 + pcm.size).order(ByteOrder.BIG_ENDIAN)
        buf.putLong(ptsMicros) // 0..7 (big-endian)
        buf.put(pcm)           // PCM little-endian preservado byte-a-byte
        return buf.array()
    }

    /** PING/PONG payload: int64 big-endian (System.nanoTime). */
    fun encodePingPong(nanos: Long): ByteArray =
        ByteBuffer.allocate(8).order(ByteOrder.BIG_ENDIAN).putLong(nanos).array()

    fun decodePingPong(payload: ByteArray): Long {
        require(payload.size >= 8) { "Payload PING/PONG curto demais" }
        return ByteBuffer.wrap(payload, 0, 8).order(ByteOrder.BIG_ENDIAN).long
    }

    // ============================ PAYLOADS — DECODE ============================

    fun decodeHelloAck(payload: ByteArray): HelloAck =
        json.decodeFromString(HelloAck.serializer(), payload.toString(Charsets.UTF_8))

    fun decodeError(payload: ByteArray): ProtocolError =
        json.decodeFromString(ProtocolError.serializer(), payload.toString(Charsets.UTF_8))
}

/** Erro de framing/parse do protocolo DCWP. */
class ProtocolException(message: String) : Exception(message)
