package com.dantetesta.dantecast.model

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

// DataStore de preferências (instância única por processo, via extensão de Context).
private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "dantecast_settings")

/**
 * Persiste/observa as [StreamSettings] do usuário usando DataStore Preferences.
 */
class SettingsRepository(private val context: Context) {

    private object Keys {
        val RESOLUTION = stringPreferencesKey("resolution")
        val FPS = intPreferencesKey("fps")
        val BITRATE = intPreferencesKey("bitrate")
    }

    /** Fluxo reativo das settings (com defaults quando ausente). */
    val settings: Flow<StreamSettings> = context.dataStore.data.map { prefs ->
        StreamSettings(
            resolution = Resolution.fromLabel(prefs[Keys.RESOLUTION] ?: Resolution.HD1080.label),
            fps = Fps.fromValue(prefs[Keys.FPS] ?: 30),
            bitrate = prefs[Keys.BITRATE] ?: -1
        )
    }

    suspend fun setResolution(resolution: Resolution) {
        context.dataStore.edit { it[Keys.RESOLUTION] = resolution.label }
    }

    suspend fun setFps(fps: Fps) {
        context.dataStore.edit { it[Keys.FPS] = fps.value }
    }

    /** bitrate <= 0 significa "automático" (deriva do preset). */
    suspend fun setBitrate(bitrate: Int) {
        context.dataStore.edit { it[Keys.BITRATE] = bitrate }
    }
}
