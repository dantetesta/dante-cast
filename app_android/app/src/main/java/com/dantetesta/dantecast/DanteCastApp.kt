package com.dantetesta.dantecast

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context

/**
 * Application: cria o canal de notificação usado pelo foreground service.
 */
class DanteCastApp : Application() {

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        // Canais existem desde a API 26 (nosso minSdk), então sempre criamos.
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.notif_channel_name),
            NotificationManager.IMPORTANCE_LOW // sem som/vibração: é status persistente
        ).apply {
            description = getString(R.string.notif_channel_desc)
            setShowBadge(false)
        }
        notificationManager(this).createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL_ID = "dantecast_mirror"

        fun notificationManager(context: Context): NotificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }
}
