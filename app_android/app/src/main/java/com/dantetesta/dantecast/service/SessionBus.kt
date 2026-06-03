package com.dantetesta.dantecast.service

import com.dantetesta.dantecast.model.SessionStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * Barramento de estado da sessão, compartilhado entre o [ScreenMirrorService]
 * (que roda em processo, fora do escopo da Activity) e o ViewModel/UI.
 *
 * Como o service e a UI vivem no MESMO processo, um singleton com StateFlow é a
 * forma mais simples e robusta de espelhar o estado em tempo real, sem IPC/bind.
 */
object SessionBus {
    private val _state = MutableStateFlow(SessionStatus())
    val state: StateFlow<SessionStatus> = _state.asStateFlow()

    fun update(transform: (SessionStatus) -> SessionStatus) = _state.update(transform)

    fun current(): SessionStatus = _state.value

    /** Reseta o estado (ao voltar para telas iniciais). */
    fun reset() {
        _state.value = SessionStatus()
    }
}
