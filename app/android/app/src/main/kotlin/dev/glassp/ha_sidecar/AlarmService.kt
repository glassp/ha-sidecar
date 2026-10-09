package dev.glassp.ha_sidecar

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator

/** Plays the alarm on the ALARM audio stream, independent of the Flutter engine. */
class AlarmService : Service() {
    companion object {
        const val ACTION_RING = "dev.glassp.ha_sidecar.RING"
        const val ACTION_STOP = "dev.glassp.ha_sidecar.STOP"
        const val ACTION_SNOOZE = "dev.glassp.ha_sidecar.SNOOZE"
        const val ACTION_ENDED = "dev.glassp.ha_sidecar.ALARM_ENDED"
        private const val CHANNEL = "alarm"
        private const val NOTIFICATION_ID = 4711
        private const val AUTO_STOP_MS = 10 * 60_000L

        @Volatile
        var ringingId: String? = null

        fun ring(ctx: Context, id: String) {
            ctx.startForegroundService(
                Intent(ctx, AlarmService::class.java).setAction(ACTION_RING).putExtra("id", id)
            )
        }

        fun stop(ctx: Context) = ctx.startService(Intent(ctx, AlarmService::class.java).setAction(ACTION_STOP))
        fun snooze(ctx: Context) = ctx.startService(Intent(ctx, AlarmService::class.java).setAction(ACTION_SNOOZE))
    }

    private val handler = Handler(Looper.getMainLooper())
    private val autoStop = Runnable { finishRinging(snooze = false, reason = "timeout") }
    private var player: MediaPlayer? = null
    private var current: Alarm? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_RING -> startRinging(intent.getStringExtra("id"))
            ACTION_STOP -> finishRinging(snooze = false, reason = "dismissed")
            ACTION_SNOOZE -> finishRinging(snooze = true, reason = "snoozed")
            else -> stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun startRinging(id: String?) {
        val alarm = id?.let { AlarmStore.get(this, it) }
        if (alarm == null) {
            // startForegroundService() promises a startForeground(); keep the contract.
            startForeground(NOTIFICATION_ID, buildNotification(null))
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        current = alarm
        ringingId = alarm.id

        // One-shots disable themselves, repeating alarms schedule their next occurrence.
        val next = alarm.copy(enabled = alarm.days.isNotEmpty(), snoozedUntil = 0)
        AlarmStore.upsert(this, next)
        AlarmScheduler.schedule(this, next)

        val notification = buildNotification(alarm)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        playSound()
        vibrate()
        UiHost.show(this, UiHost.ALARM)
        handler.postDelayed(autoStop, AUTO_STOP_MS)
        EventBus.emit("alarm_ringing", mapOf("id" to alarm.id, "label" to alarm.label))
        EventBus.emit("status_changed")
    }

    private fun finishRinging(snooze: Boolean, reason: String) {
        handler.removeCallbacks(autoStop)
        val alarm = current
        if (snooze && alarm != null) {
            val until = System.currentTimeMillis() + alarm.snoozeMinutes * 60_000L
            val snoozed = (AlarmStore.get(this, alarm.id) ?: alarm).copy(enabled = true, snoozedUntil = until)
            AlarmStore.upsert(this, snoozed)
            AlarmScheduler.schedule(this, snoozed)
        }
        player?.run { runCatching { stop() }; release() }
        player = null
        getSystemService(Vibrator::class.java)?.cancel()
        ringingId = null
        current = null
        sendBroadcast(Intent(ACTION_ENDED).setPackage(packageName))
        EventBus.emit("alarm_stopped", mapOf("id" to alarm?.id, "reason" to reason))
        EventBus.emit("status_changed")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun playSound() {
        val uri = RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        player = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            setDataSource(this@AlarmService, uri)
            isLooping = true
            prepare()
            start()
        }
    }

    private fun vibrate() {
        getSystemService(Vibrator::class.java)
            ?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 600, 600), 0))
    }

    private fun buildNotification(alarm: Alarm?): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Alarms", NotificationManager.IMPORTANCE_HIGH)
        )
        fun action(title: String, act: String) = Notification.Action.Builder(
            Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel), title,
            PendingIntent.getService(
                this, act.hashCode(), Intent(this, AlarmService::class.java).setAction(act),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        ).build()

        val fullScreen = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).putExtra("route", UiHost.ALARM),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(alarm?.label?.ifBlank { null } ?: "Alarm")
            .setCategory(Notification.CATEGORY_ALARM)
            .setOngoing(true)
            .setFullScreenIntent(fullScreen, true)
            .addAction(action("Snooze", ACTION_SNOOZE))
            .addAction(action("Dismiss", ACTION_STOP))
            .build()
    }

    override fun onDestroy() {
        handler.removeCallbacks(autoStop)
        player?.release()
        player = null
        super.onDestroy()
    }
}
