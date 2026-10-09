package dev.glassp.ha_sidecar

import android.accessibilityservice.AccessibilityService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent

/**
 * Fallback enforcement when the app is not device owner, and foreground-app reporting in
 * both modes. It can read window content (needed to tap the system-update buttons), but only
 * does so while [UpdateAutomation] is armed and only for system update packages.
 */
class SidecarAccessibilityService : AccessibilityService() {
    companion object {
        @Volatile
        var instance: SidecarAccessibilityService? = null
            private set
        private const val BOUNCE_DEBOUNCE_MS = 400L
    }

    private val handler = Handler(Looper.getMainLooper())
    private var lastReported: String? = null
    private var lastBounce = 0L

    override fun onServiceConnected() {
        instance = this
        KioskController.refreshOverlay(this)
        EventBus.emit("status_changed")
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        instance = null
        HotCorner.hide()
        TouchWatcher.hide()
        if (Prefs.lockdown(this)) EventBus.emit("guard_disabled")
        EventBus.emit("status_changed")
        return super.onUnbind(intent)
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: return
        if (UpdateAutomation.isArmed() && pkg in UpdateAutomation.PACKAGES) {
            UpdateAutomation.onWindowChanged(rootInActiveWindow, pkg)
        }
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val cls = event.className?.toString().orEmpty()

        if (pkg != KioskController.SYSTEM_UI && pkg != lastReported) {
            lastReported = pkg
            KioskController.lastForeground = pkg
            EventBus.emit("foreground_app", mapOf("package" to pkg))
        }
        if (!Prefs.lockdown(this)) return

        // Device owner already enforces via lock task; only bounce as belt and braces.
        if (pkg == KioskController.SYSTEM_UI) {
            closeShade()
            if (cls.contains("Recents", ignoreCase = true)) bounce()
            return
        }
        if (KioskController.isAllowed(this, pkg)) return
        KioskController.lastBlockedApp = pkg
        KioskController.blockedCount++
        EventBus.emit("app_blocked", mapOf("package" to pkg))
        bounce()
    }

    private fun closeShade() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            performGlobalAction(GLOBAL_ACTION_DISMISS_NOTIFICATION_SHADE)
        } else {
            performGlobalAction(GLOBAL_ACTION_BACK)
        }
    }

    private fun bounce() {
        val now = SystemClock.elapsedRealtime()
        if (now - lastBounce < BOUNCE_DEBOUNCE_MS) return
        lastBounce = now
        handler.post { KioskController.launchTarget(this) }
    }
}
