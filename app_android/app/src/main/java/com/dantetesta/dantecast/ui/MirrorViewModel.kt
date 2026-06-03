package com.dantetesta.dantecast.ui

import android.app.Application
import android.content.Intent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.dantetesta.dantecast.model.Fps
import com.dantetesta.dantecast.model.Resolution
import com.dantetesta.dantecast.model.SessionState
import com.dantetesta.dantecast.model.SessionStatus
import com.dantetesta.dantecast.model.SettingsRepository
import com.dantetesta.dantecast.model.StreamSettings
import com.dantetesta.dantecast.pairing.PairingQr
import com.dantetesta.dantecast.service.ScreenMirrorService
import com.dantetesta.dantecast.service.SessionBus
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * ViewModel central da UI.
 *  - Guarda o alvo de pareamento (PairingQr) escolhido na ScanQrScreen.
 *  - Expõe settings (DataStore) e o status da sessão (SessionBus).
 *  - Dispara start/stop do foreground service de espelhamento.
 *
 * O fluxo de PERMISSÃO de captura é dono da Activity (precisa de ActivityResult);
 * o ViewModel guarda o alvo e a Activity, após obter o token, chama [startMirroring].
 */
class MirrorViewModel(app: Application) : AndroidViewModel(app) {

    private val settingsRepo = SettingsRepository(app)

    // Alvo de pareamento atual (definido após escanear o QR / entrada manual).
    var pairingTarget: PairingQr? = null
        private set

    // Status da sessão espelhado do service (process-global StateFlow).
    val sessionStatus: StateFlow<SessionStatus> = SessionBus.state

    // Settings observáveis.
    val settings: StateFlow<StreamSettings> = settingsRepo.settings.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = StreamSettings()
    )

    /** Define o alvo escolhido pelo usuário (QR ou manual). */
    fun setPairingTarget(qr: PairingQr) {
        pairingTarget = qr
        // Pré-popula o nome do Mac no status para feedback imediato.
        SessionBus.update { it.copy(macName = qr.name) }
    }

    // ---------------- Settings ----------------

    fun updateResolution(resolution: Resolution) = viewModelScope.launch {
        settingsRepo.setResolution(resolution)
    }

    fun updateFps(fps: Fps) = viewModelScope.launch {
        settingsRepo.setFps(fps)
    }

    fun updateBitrate(bitrateBps: Int) = viewModelScope.launch {
        settingsRepo.setBitrate(bitrateBps)
    }

    fun updateDeviceAudio(enabled: Boolean) = viewModelScope.launch {
        settingsRepo.setDeviceAudioEnabled(enabled)
    }

    // ---------------- Sessão ----------------

    /**
     * Inicia o espelhamento. Chamado pela Activity DEPOIS de obter o token de captura.
     * @param resultCode/data resultado do MediaProjectionManager.createScreenCaptureIntent.
     */
    fun startMirroring(resultCode: Int, data: Intent) {
        val target = pairingTarget ?: return
        val s = settings.value
        // 0,0 => NATIVE (o service resolve a resolução real da tela).
        val (w, h) = if (s.resolution == Resolution.NATIVE) 0 to 0
        else s.resolution.width to s.resolution.height
        // bitrate efetivo: para NATIVE usamos uma referência 1080p como base.
        val bitrate = s.effectiveBitrate(
            screenW = if (w > 0) w else 1920,
            screenH = if (h > 0) h else 1080
        )

        ScreenMirrorService.start(
            context = getApplication(),
            resultCode = resultCode,
            data = data,
            ip = target.ip,
            port = target.port,
            token = target.token,
            macName = target.name,
            prefResW = w,
            prefResH = h,
            prefFps = s.fps.value,
            prefBitrate = bitrate,
            deviceAudio = s.deviceAudioEnabled
        )
    }

    /** Para o espelhamento (botão STOP / sair). */
    fun stopMirroring() {
        ScreenMirrorService.stop(getApplication())
    }

    /** Reseta o estado para voltar às telas iniciais (após desconexão/erro). */
    fun resetSession() {
        SessionBus.reset()
        pairingTarget = null
    }

    /** Conveniência: a sessão está ativa (conectando/streaming)? */
    fun isSessionActive(): Boolean {
        val st = sessionStatus.value.state
        return st == SessionState.CONNECTING || st == SessionState.HANDSHAKING || st == SessionState.STREAMING
    }
}
