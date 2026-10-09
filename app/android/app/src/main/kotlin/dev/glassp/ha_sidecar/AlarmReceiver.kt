package dev.glassp.ha_sidecar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Not exported: only our own PendingIntents can ring an alarm. */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != AlarmScheduler.ACTION_FIRE) return
        val id = intent.getStringExtra("id") ?: return
        AlarmEngine.fire(context, id)
    }
}

/** Not exported: only our own PendingIntents can finish a timer. */
class TimerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TimerScheduler.ACTION_FIRE) return
        TimerEngine.fire(context, intent.getStringExtra("id") ?: return)
    }
}

/** Exported so the system can deliver boot/time broadcasts; actions are checked explicitly. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> {
                AlarmScheduler.rescheduleAll(context)
                TimerEngine.rescheduleAll(context)
                if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
                    intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
                ) {
                    KioskController.applyPolicy(context)
                    KeepAliveService.start(context)
                    // Back into the locked-down kiosk after a reboot / app update.
                    // With launcher mode, Android starts HomeActivity at boot which does this itself.
                    if (Prefs.lockdown(context) && !Prefs.kioskLauncher(context)) {
                        KioskController.launchTarget(context, lockTask = true, dashboard = true)
                    }
                }
            }
        }
    }
}
