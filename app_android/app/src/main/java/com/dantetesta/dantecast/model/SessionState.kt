package com.dantetesta.dantecast.model

import androidx.compose.runtime.Immutable

/**
 * Estados do ciclo de vida da conexão/streaming no lado Android.
 * Espelha conceitualmente o ConnectionStatus do macOS.
 */
enum class SessionState {
    IDLE,          // nada acontecendo
    CONNECTING,    // socket TCP conectando
    HANDSHAKING,   // HELLO enviado, aguardando HELLO_ACK
    STREAMING,     // enviando VIDEO_FRAME ativamente
    DISCONNECTED,  // encerrado/caiu
    ERROR          // falha
}

/**
 * Snapshot observável da sessão para a UI (StreamingScreen).
 * @param macName nome do Mac (do HELLO_ACK ou do QR).
 * @param width/height resolução efetiva negociada.
 * @param fps fps efetivo.
 * @param bitrate bps efetivo.
 * @param elapsedMs tempo de transmissão.
 * @param latencyMs RTT medido via PING/PONG.
 * @param framesSent contador para diagnóstico.
 * @param errorMessage texto de erro (quando state == ERROR).
 */
@Immutable
data class SessionStatus(
    val state: SessionState = SessionState.IDLE,
    val macName: String = "",
    val width: Int = 0,
    val height: Int = 0,
    val fps: Int = 0,
    val bitrate: Int = 0,
    val elapsedMs: Long = 0L,
    val latencyMs: Long = -1L,
    val framesSent: Long = 0L,
    val errorMessage: String? = null
)
