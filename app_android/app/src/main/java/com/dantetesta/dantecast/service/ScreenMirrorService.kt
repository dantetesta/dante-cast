package com.dantetesta.dantecast.service

import android.Manifest
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.Display
import androidx.core.app.NotificationCompat
import com.dantetesta.dantecast.DanteCastApp
import com.dantetesta.dantecast.MainActivity
import com.dantetesta.dantecast.R
import com.dantetesta.dantecast.capture.DeviceAudioCapture
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
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
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
    private var audioCapture: DeviceAudioCapture? = null

    // Dados efetivos da sessão.
    @Volatile private var sessionWidth = 0
    @Volatile private var sessionHeight = 0
    @Volatile private var sessionFps = 30
    @Volatile private var sessionBitrate = 6_000_000
    @Volatile private var startTimeMs = 0L
    @Volatile private var lastRotation = 0

    // Áudio do dispositivo (gated por setting; default OFF).
    @Volatile private var deviceAudioRequested = false
    @Volatile private var deviceAudioActive = false

    // --- Rotação ---
    // DisplayManager + listener para reagir à rotação (recriar pipeline com novas dimensões).
    private var displayManager: DisplayManager? = null
    // Serializa as reconfigurações: só UMA roda por vez (evita corrida entre eventos seguidos).
    private val reconfigureMutex = Mutex()
    @Volatile private var streaming = false

    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) {}
        override fun onDisplayRemoved(displayId: Int) {}
        override fun onDisplayChanged(displayId: Int) {
            if (displayId != Display.DEFAULT_DISPLAY || !streaming) return
            val cap = captureManager ?: return
            val info = runCatching { cap.currentScreenInfo() }.getOrNull() ?: return
            // Reage se a rotação mudou OU se a orientação (paisagem/retrato) inverteu.
            val rotationChanged = info.rotation != lastRotation
            val orientationFlipped = (info.width >= info.height) != (sessionWidth >= sessionHeight)
            if (rotationChanged || orientationFlipped) {
                scope.launch { reconfigureForRotation(info) }
            }
        }
    }

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
        // 1) Lê parâmetros enviados pela Activity (antes do foreground, p/ decidir o tipo de FGS).
        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Int.MIN_VALUE)
        val data: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION") intent.getParcelableExtra(EXTRA_DATA)
        }
        // Áudio do dispositivo (gated): só ligamos se o usuário pediu, o SO suportar (API 29+)
        // E a permissão RECORD_AUDIO estiver concedida — caso contrário seguimos VIDEO-ONLY.
        deviceAudioRequested = intent.getBooleanExtra(EXTRA_DEVICE_AUDIO, false) &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            hasRecordAudioPermission()

        // 2) PRIMEIRO vai para foreground (requisito A14+). Inclui o tipo microphone se o áudio
        //    estiver habilitado — caso contrário usar FGS de microfone lançaria SecurityException.
        startAsForeground(withMicrophone = deviceAudioRequested)

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

                // 6) Streaming ativo: agora reagimos à rotação (recriação serializada da pipeline).
                streaming = true
                registerRotationListener()

                // 7) Áudio do dispositivo (opcional/gated): NUNCA pode quebrar o vídeo.
                if (deviceAudioRequested) {
                    startDeviceAudio(proj, mirrorClient)
                }

                Log.i(tag, "Sessão STREAMING ${sessionWidth}x${sessionHeight}@${sessionFps} audio=$deviceAudioActive")
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

    // ---------------------------- ROTAÇÃO (TASK 1) ----------------------------

    /** Registra o listener de mudança de display (rotação) no display padrão. */
    private fun registerRotationListener() {
        val dm = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        displayManager = dm
        // handler=null => callbacks na thread principal; o trabalho pesado vai p/ o scope.
        dm.registerDisplayListener(displayListener, null)
        Log.i(tag, "DisplayListener registrado (rotação)")
    }

    /** Remove o listener de rotação (idempotente). */
    private fun unregisterRotationListener() {
        runCatching { displayManager?.unregisterDisplayListener(displayListener) }
        displayManager = null
    }

    /**
     * Recria a pipeline (encoder + VirtualDisplay) quando a tela gira.
     *
     * Estratégia (minimiza o "gap" de vídeo):
     *   1. Calcula novas dimensões trocando W/H (preservando a escala da resolução escolhida),
     *      sempre pares (and 1.inv()).
     *   2. Cria um NOVO encoder com os MESMOS callbacks e obtém sua input Surface.
     *   3. capture.resize(novaSurface, ...) recria o VirtualDisplay sobre a nova surface.
     *   4. SÓ ENTÃO libera o encoder ANTIGO (novo já está pronto -> menor gap).
     *   5. Atualiza estado, envia ORIENTATION e força um keyframe (o Mac recupera na hora).
     *
     * Serializado por [reconfigureMutex]: apenas uma reconfiguração roda por vez.
     * Crash-safe: qualquer falha encerra a sessão (stopEverything).
     */
    private suspend fun reconfigureForRotation(info: ScreenCaptureManager.ScreenInfo) {
        reconfigureMutex.withLock {
            if (!streaming) return
            val capture = captureManager ?: return
            val mirrorClient = client ?: return
            val oldEnc = encoder ?: return

            // Recheca dentro do lock: outro evento pode já ter aplicado a mesma rotação.
            val rotationChanged = info.rotation != lastRotation
            val orientationFlipped = (info.width >= info.height) != (sessionWidth >= sessionHeight)
            if (!rotationChanged && !orientationFlipped) return

            // 1) Novas dimensões = troca W/H da sessão atual, preservando a escala. Pares.
            val newW = (sessionHeight and 1.inv())
            val newH = (sessionWidth and 1.inv())

            try {
                Log.i(tag, "Rotação: ${sessionWidth}x${sessionHeight} -> ${newW}x${newH} (rot=${info.rotation})")

                // 2) NOVO encoder com os MESMOS callbacks (lê sessionWidth/Height atualizados).
                val newEnc = H264Encoder(
                    onConfig = { csd ->
                        mirrorClient.sendVideoConfig(sessionWidth, sessionHeight, sessionFps, csd)
                    },
                    onFrame = { pts, key, bytes ->
                        mirrorClient.sendVideoFrame(pts, key, bytes)
                        SessionBus.update { it.copy(framesSent = it.framesSent + 1) }
                    },
                    onError = { t -> stopEverything(t) }
                )
                val newSurface = newEnc.configure(newW, newH, sessionFps, sessionBitrate)

                // 3) Recria o VirtualDisplay sobre a nova surface (mesma projeção).
                capture.resize(newSurface, newW, newH, info.densityDpi)

                // 4) Agora que o novo está ativo, libera o encoder antigo (menor gap possível).
                encoder = newEnc
                runCatching { oldEnc.release() }

                // 5) Atualiza estado + notifica o Mac + força keyframe.
                sessionWidth = newW; sessionHeight = newH; lastRotation = info.rotation
                mirrorClient.sendOrientation(Orientation(newW, newH, info.rotation))
                newEnc.requestSyncFrame()
                SessionBus.update { it.copy(width = newW, height = newH) }
                Log.i(tag, "Rotação aplicada: ${newW}x${newH}")
            } catch (t: Throwable) {
                Log.e(tag, "Falha ao reconfigurar para rotação", t)
                stopEverything(t)
            }
        }
    }

    // ---------------------------- ÁUDIO DO DISPOSITIVO (TASK 2) ----------------------------

    /** Verifica se RECORD_AUDIO foi concedida. */
    private fun hasRecordAudioPermission(): Boolean =
        checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    /**
     * Inicia a captura de áudio do dispositivo (API 29+) reaproveitando a mesma MediaProjection.
     * Qualquer falha apenas LOGA e mantém a sessão de vídeo (áudio é estritamente opcional).
     */
    private fun startDeviceAudio(proj: MediaProjection, mirrorClient: MirrorClient) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        if (!hasRecordAudioPermission()) {
            Log.w(tag, "Áudio pedido mas sem permissão RECORD_AUDIO — seguindo VIDEO-ONLY")
            return
        }
        try {
            // Anuncia o formato UMA vez (44100 Hz, 2 canais, 16 bits) antes dos frames.
            mirrorClient.sendAudioConfig(
                DeviceAudioCapture.SAMPLE_RATE,
                DeviceAudioCapture.CHANNELS,
                DeviceAudioCapture.BITS_PER_SAMPLE
            )
            val cap = DeviceAudioCapture(
                projection = proj,
                onPcm = { ptsMicros, pcm -> mirrorClient.sendAudioFrame(ptsMicros, pcm) },
                onError = { t ->
                    // Falha na leitura de áudio NÃO derruba o vídeo: apenas para a captura de áudio.
                    Log.w(tag, "Erro na captura de áudio — desativando áudio, vídeo segue", t)
                    stopDeviceAudio()
                }
            )
            cap.start()
            audioCapture = cap
            deviceAudioActive = true
            Log.i(tag, "Áudio do dispositivo ATIVO")
        } catch (t: Throwable) {
            // Permissão/captura bloqueada/exceção -> VIDEO-ONLY.
            Log.w(tag, "Não foi possível iniciar o áudio do dispositivo — seguindo VIDEO-ONLY", t)
            stopDeviceAudio()
        }
    }

    /** Para a captura de áudio (idempotente). */
    private fun stopDeviceAudio() {
        deviceAudioActive = false
        runCatching { audioCapture?.stop() }
        audioCapture = null
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

    private fun startAsForeground(withMicrophone: Boolean = false) {
        val notification = buildNotification(getString(R.string.notif_text))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Combina mediaProjection + microphone (quando o áudio está habilitado).
            var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            if (withMicrophone && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
            startForeground(NOTIF_ID, notification, type)
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
        streaming = false
        unregisterRotationListener()
        stopDeviceAudio()
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
        streaming = false
        unregisterRotationListener()
        stopDeviceAudio()
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
        const val EXTRA_DEVICE_AUDIO = "extra_device_audio"

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
            prefBitrate: Int,
            deviceAudio: Boolean = false
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
                putExtra(EXTRA_DEVICE_AUDIO, deviceAudio)
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
