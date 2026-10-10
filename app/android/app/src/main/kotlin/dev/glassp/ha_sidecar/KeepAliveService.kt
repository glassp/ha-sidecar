package dev.glassp.ha_sidecar

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps the process (HA connection, overlay, wake lock) alive while the companion app is in
 * the foreground. Also restores persisted kiosk state after a process restart.
 */
class KeepAliveService : Service() {
    companion object {
        private const val CHANNEL = "keepalive"
        private const val NOTIFICATION_ID = 4710

        fun start(ctx: Context) {
            runCatching { ctx.startForegroundService(Intent(ctx, KeepAliveService::class.java)) }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "HA Sidecar running", NotificationManager.IMPORTANCE_MIN)
        )
        val n = Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_manage)
            .setContentTitle("HA Sidecar is running")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }

        SidecarEngine.get(this) // headless Dart: HA connection survives without the UI
        BrightnessController.start(this)
        PrivacyMonitor.start(this)
        PresenceCamera.refresh(this)
        VoiceVolume.restoreStale(this)
        WakeWord.refresh(this)
        WakeWordDebug.register(applicationContext)
        NetworkMonitor.start(this)
        CompanionWatchdog.start(this)
        KioskController.setKeepScreenOn(this, Prefs.keepScreenOn(this))
        KioskController.applyPolicy(this)
        KioskController.refreshOverlay(this)
        return START_STICKY
    }
}
