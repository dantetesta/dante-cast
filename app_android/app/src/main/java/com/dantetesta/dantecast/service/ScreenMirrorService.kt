package com.dantetesta.dantecast.service

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.dantetesta.dantecast.DanteCastApp
import com.dantetesta.dantecast.MainActivity
import com.dantetesta.dantecast.R
import com.dantetesta.dantecast.capture.ScreenCaptureManager
import com.dantetesta.dantecast.encoder.H264Encoder
import com.dantetesta.dantecast.model.SessionState
import com.dantetesta.dantecast.network.MirrorClient
import com.dantetesta.dantecast.pairing.Hello
import com.dantetesta.dantecast.pairing.HelloCapabilities
import com.dantetesta.dantecast.pairing.HelloDevice
import com.dantetesta.dantecast.pairing.Orientation
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * Foreground Service (type=mediaProjection) que conduz toda a sessão de espelhamento.
 *
 * ORDEM CRÍTICA (Android 14+):
 *   1. A Activity obtém o token de captura (MediaProjectionManager.createScreenCaptureIntent).
 *   2. Inicia ESTE service passando o resultCode + data Intent.
 *   3. O service chama startForeground(type=mediaProjection) ANTES de obter a MediaProjection.
 *   4. SÓ ENTÃO getMediaProjection(...) e cria o VirtualDisplay.
 *
 * O service também faz: conectar TCP, HELLO/HELLO_ACK, VIDEO_CONFIG, VIDEO_FRAME, PING/PONG.
 */
class ScreenMirrorService : Service() {

    private val tag = "ScreenMirrorService"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private var captureManager: ScreenCaptureManager? = null
    private var encoder: H264Encoder? = null
    private var client: MirrorClient? = null
    private var projection: MediaProjection? = null

    // Dados efetivos da sessão.
    @Volatile private var sessionWidth = 0
    @Volatile private var sessionHeight = 0
    @Volatile private var sessionFps = 30
    @Volatile private var sessionBitrate = 6_000_000
    @Volatile private var startTimeMs = 0L
    @Volatile private var lastRotation = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                Log.i(tag, "ACTION_STOP recebido")
                stopEverything(null)
                return START_NOT_STICKY
            }
            ACTION_START -> startSession(intent)
        }
        return START_NOT_STICKY
    }

    private fun startSession(intent: Intent) {
        // 1) PRIMEIRO vai para foreground com o tipo mediaProjection (requisito A14+).
        startAsForeground()

        // 2) Lê parâmetros enviados pela Activity.
        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Int.MIN_VALUE)
        val data: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION") intent.getParcelableExtra(EXTRA_DATA)
        }
        val ip = intent.getStringExtra(EXTRA_IP) ?: return failAndStop("IP ausente")
        val port = intent.getIntExtra(EXTRA_PORT, 7843)
        val token = intent.getStringExtra(EXTRA_TOKEN) ?: return failAndStop("Token ausente")
        val macName = intent.getStringExtra(EXTRA_MAC_NAME) ?: ""
        val prefRes = intent.getIntExtra(EXTRA_PREF_RES_W, 0) to intent.getIntExtra(EXTRA_PREF_RES_H, 0)
        val prefFps = intent.getIntExtra(EXTRA_PREF_FPS, 30)
        val prefBitrate = intent.getIntExtra(EXTRA_PREF_BITRATE, -1)

        if (data == null || resultCode == Int.MIN_VALUE) {
            return failAndStop("Token de captura inválido")
        }

        SessionBus.update { it.copy(state = SessionState.CONNECTING, macName = macName) }

        scope.launch {
            try {
                // 3) Obtém a MediaProjection DEPOIS do startForeground.
                val pm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                val proj = pm.getMediaProjection(resultCode, data)
                    ?: return@launch failAndStop("Falha ao obter MediaProjection")
                projection = proj

                // Resolve dimensões a partir da tela + preferências.
                val capture = ScreenCaptureManager(this@ScreenMirrorService) {
                    // Projeção revogada -> encerra sessão.
                    stopEverything(Exception("Projeção revogada"))
                }
                captureManager = capture
                val screen = capture.currentScreenInfo()
                lastRotation = screen.rotation

                val (w, h) = resolveDimensions(prefRes, screen.width, screen.height)
                sessionWidth = w; sessionHeight = h; sessionFps = prefFps
                sessionBitrate = if (prefBitrate > 0) prefBitrate else 6_000_000

                // 4) Conecta TCP + handshake.
                val mirrorClient = MirrorClient(
                    onHelloAck = { /* tratado via sendHelloAwaitAck */ },
                    onLatency = { rttMs -> SessionBus.update { it.copy(latencyMs = rttMs) } },
                    onDisconnected = { cause -> stopEverything(cause) }
                )
                client = mirrorClient
                mirrorClient.connect(ip, port)

                SessionBus.update { it.copy(state = SessionState.HANDSHAKING) }

                val hello = Hello(
                    protocolVersion = 1,
                    token = token,
                    device = HelloDevice(
                        id = deviceId(),
                        name = Build.MODEL ?: "Android",
                        model = Build.MODEL ?: "Android",
                        osVersion = Build.VERSION.SDK_INT.toString()
                    ),
                    capabilities = HelloCapabilities(
                        maxWidth = maxOf(screen.width, screen.height),
                        maxHeight = maxOf(screen.width, screen.height),
                        fpsOptions = listOf(30, 60)
                    )
                )
                val ack = mirrorClient.sendHelloAwaitAck(hello)
                if (!ack.accepted) {
                    return@launch failAndStop(ack.reason.ifBlank { getString(R.string.state_rejected) })
                }

                // O Mac decide as configurações oficiais (HELLO_ACK.settings).
                ack.settings?.let { s ->
                    if (s.width > 0 && s.height > 0) {
                        // Respeita a proporção da tela mas usa a resolução pedida pelo Mac.
                        sessionWidth = s.width; sessionHeight = s.height
                    }
                    if (s.fps in intArrayOf(30, 60)) sessionFps = s.fps
                    if (s.bitrate > 0) sessionBitrate = s.bitrate
                }
                val effMac = ack.macName.ifBlank { macName }

                // 5) Encoder -> Surface -> VirtualDisplay.
                val enc = H264Encoder(
                    onConfig = { csd ->
                        mirrorClient.sendVideoConfig(sessionWidth, sessionHeight, sessionFps, csd)
                    },
                    onFrame = { pts, key, bytes ->
                        mirrorClient.sendVideoFrame(pts, key, bytes)
                        SessionBus.update { it.copy(framesSent = it.framesSent + 1) }
                    },
                    onError = { t -> stopEverything(t) }
                )
                encoder = enc
                val surface = enc.configure(sessionWidth, sessionHeight, sessionFps, sessionBitrate)

                capture.start(proj, surface, sessionWidth, sessionHeight, screen.densityDpi)

                // Envia orientação inicial e inicia heartbeat.
                mirrorClient.sendOrientation(Orientation(sessionWidth, sessionHeight, screen.rotation))
                mirrorClient.startHeartbeat(2000)

                startTimeMs = System.currentTimeMillis()
                SessionBus.update {
                    it.copy(
                        state = SessionState.STREAMING,
                        macName = effMac,
                        width = sessionWidth,
                        height = sessionHeight,
                        fps = sessionFps,
                        bitrate = sessionBitrate
                    )
                }
                updateNotification(effMac)
                startElapsedTicker()
                Log.i(tag, "Sessão STREAMING ${sessionWidth}x${sessionHeight}@${sessionFps}")
            } catch (t: Throwable) {
                Log.e(tag, "Falha ao iniciar sessão", t)
                failAndStop(t.message ?: "Erro de conexão")
            }
        }
    }

    /** Atualiza periodicamente o tempo decorrido na UI. */
    private fun startElapsedTicker() {
        scope.launch {
            while (true) {
                kotlinx.coroutines.delay(1000)
                if (startTimeMs == 0L) continue
                val elapsed = System.currentTimeMillis() - startTimeMs
                SessionBus.update { it.copy(elapsedMs = elapsed) }
            }
        }
    }

    /** Resolve dimensões finais a partir da preferência e da tela física. */
    private fun resolveDimensions(pref: Pair<Int, Int>, screenW: Int, screenH: Int): Pair<Int, Int> {
        if (pref.first <= 0 || pref.second <= 0) return screenW to screenH // NATIVE
        // Mantém a orientação física: escala a preferência para a proporção da tela.
        val portrait = screenH >= screenW
        val (pw, ph) = if (portrait) minOf(pref.first, pref.second) to maxOf(pref.first, pref.second)
        else maxOf(pref.first, pref.second) to minOf(pref.first, pref.second)
        // Garante dimensões pares (exigência de muitos encoders H.264).
        return (pw and 1.inv()) to (ph and 1.inv())
    }

    // ---------------------------- FOREGROUND ----------------------------

    private fun startAsForeground() {
        val notification = buildNotification(getString(R.string.notif_text))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    private fun buildNotification(text: String): Notification {
        val openIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val stopIntent = PendingIntent.getService(
            this, 1,
            Intent(this, ScreenMirrorService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, DanteCastApp.CHANNEL_ID)
            .setContentTitle(getString(R.string.notif_title))
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setContentIntent(openIntent)
            .addAction(0, getString(R.string.notif_stop), stopIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun updateNotification(macName: String) {
        val text = if (macName.isNotBlank()) "${getString(R.string.notif_text)} ($macName)"
        else getString(R.string.notif_text)
        DanteCastApp.notificationManager(this).notify(NOTIF_ID, buildNotification(text))
    }

    // ---------------------------- TEARDOWN ----------------------------

    private fun failAndStop(message: String) {
        SessionBus.update { it.copy(state = SessionState.ERROR, errorMessage = message) }
        stopEverything(Exception(message))
    }

    private fun stopEverything(cause: Throwable?) {
        runCatching { client?.sendByeAndClose() }
        runCatching { encoder?.release() }
        runCatching { captureManager?.release() }
        runCatching { projection?.stop() }
        client = null; encoder = null; captureManager = null; projection = null

        val finalState = SessionBus.current()
        if (finalState.state != SessionState.ERROR) {
            SessionBus.update { it.copy(state = SessionState.DISCONNECTED) }
        }
        startTimeMs = 0L
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        super.onDestroy()
        runCatching { encoder?.release() }
        runCatching { captureManager?.release() }
        scope.cancel()
    }

    private fun deviceId(): String {
        // ID estável por instalação (não usa identificadores de hardware).
        val prefs = getSharedPreferences("dantecast_prefs", Context.MODE_PRIVATE)
        var id = prefs.getString("device_id", null)
        if (id == null) {
            id = UUID.randomUUID().toString()
            prefs.edit().putString("device_id", id).apply()
        }
        return id
    }

    companion object {
        const val NOTIF_ID = 1001

        const val ACTION_START = "com.dantetesta.dantecast.action.START"
        const val ACTION_STOP = "com.dantetesta.dantecast.action.STOP"

        const val EXTRA_RESULT_CODE = "extra_result_code"
        const val EXTRA_DATA = "extra_data"
        const val EXTRA_IP = "extra_ip"
        const val EXTRA_PORT = "extra_port"
        const val EXTRA_TOKEN = "extra_token"
        const val EXTRA_MAC_NAME = "extra_mac_name"
        const val EXTRA_PREF_RES_W = "extra_pref_res_w"
        const val EXTRA_PREF_RES_H = "extra_pref_res_h"
        const val EXTRA_PREF_FPS = "extra_pref_fps"
        const val EXTRA_PREF_BITRATE = "extra_pref_bitrate"

        /** Helper para iniciar o service a partir da Activity/ViewModel. */
        fun start(
            context: Context,
            resultCode: Int,
            data: Intent,
            ip: String,
            port: Int,
            token: String,
            macName: String,
            prefResW: Int,
            prefResH: Int,
            prefFps: Int,
            prefBitrate: Int
        ) {
            val intent = Intent(context, ScreenMirrorService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_RESULT_CODE, resultCode)
                putExtra(EXTRA_DATA, data)
                putExtra(EXTRA_IP, ip)
                putExtra(EXTRA_PORT, port)
                putExtra(EXTRA_TOKEN, token)
                putExtra(EXTRA_MAC_NAME, macName)
                putExtra(EXTRA_PREF_RES_W, prefResW)
                putExtra(EXTRA_PREF_RES_H, prefResH)
                putExtra(EXTRA_PREF_FPS, prefFps)
                putExtra(EXTRA_PREF_BITRATE, prefBitrate)
            }
            // startForegroundService: o service tem ~5s para chamar startForeground().
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, ScreenMirrorService::class.java).apply { action = ACTION_STOP }
            context.startService(intent)
        }
    }
}
