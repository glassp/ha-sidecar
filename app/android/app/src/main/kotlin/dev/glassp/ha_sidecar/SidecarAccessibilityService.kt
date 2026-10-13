package dev.glassp.ha_sidecar

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.app.KeyguardManager
import android.graphics.Path
import android.graphics.Rect
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
        private const val SHADE_CLOSE_MS = 250L
        private const val VERIFY_MS = 700L
        private const val SWIPE_SHUT_MS = 90L
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
        // The shade reports no window state change while it is pulled down, only a stream of content changes from System UI.
        // Closing it on those (debounced) catches it within a frame or two, however slowly it is dragged.
        if (pkg == KioskController.SYSTEM_UI && event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            if (Prefs.lockdown(this)) closeShadeThrottled()
            return
        }
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
            if (getSystemService(KeyguardManager::class.java).isKeyguardLocked) return // the lock screen is the phone's, not ours
            // The power menu (power off / restart / emergency call) and other System UI dialogs are windows of their own that a
            // swipe does not close; Back does. Everything else System UI shows (the shade) is swiped shut.
            if (cls.contains("Dialog", ignoreCase = true)) performGlobalAction(GLOBAL_ACTION_BACK) else closeShade()
            if (cls.contains("Recents", ignoreCase = true)) bounce()
            return
        }
        if (KioskController.isAllowed(this, pkg)) return
        KioskController.lastBlockedApp = pkg
        KioskController.blockedCount++
        EventBus.emit("app_blocked", mapOf("package" to pkg))
        bounce()
    }

    private var lastShadeClose = 0L

    /**
     * True while the notification shade / quick settings are pulled down or open: System UI then has a window far taller than the
     * status bar (at rest it only has thin strips). Not while the lock screen is up, which is System UI too and must be left alone.
     */
    private fun shadeIsOpen(): Boolean = runCatching {
        if (getSystemService(KeyguardManager::class.java).isKeyguardLocked) return false
        val tall = resources.displayMetrics.heightPixels / 4
        val r = Rect()
        windows.any { w ->
            w.getBoundsInScreen(r)
            r.height() > tall && w.root?.packageName == KioskController.SYSTEM_UI
        }
    }.getOrDefault(false)

    private fun closeShadeThrottled() {
        val now = SystemClock.elapsedRealtime()
        if (now - lastShadeClose < SHADE_CLOSE_MS) return
        lastShadeClose = now
        if (shadeIsOpen()) closeShade()
    }

    /**
     * Closes the notification shade / quick settings by swiping it shut: a short upward gesture from the upper third of the screen
     * to the top edge, like a finger would. The global dismiss action is refused on some Android versions (Android 17 on a
     * Pixel 6 returns false while the shade is dragged), so Back and Home are the fallbacks if the gesture cannot be sent.
     */
    private fun closeShade() {
        if (swipeShadeShut()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && performGlobalAction(GLOBAL_ACTION_DISMISS_NOTIFICATION_SHADE)) return
        if (performGlobalAction(GLOBAL_ACTION_BACK)) return
        performGlobalAction(GLOBAL_ACTION_HOME)
    }

    private fun swipeShadeShut(): Boolean {
        val m = resources.displayMetrics
        val x = m.widthPixels * 0.5f
        val path = Path().apply {
            moveTo(x, m.heightPixels * 0.3f)
            lineTo(x, 1f)
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, SWIPE_SHUT_MS))
            .build()
        return runCatching { dispatchGesture(gesture, null, null) }.getOrDefault(false)
    }

    /** The package of the application window that is in front right now (not the last one that reported a change), or null if unknown. */
    fun frontPackage(): String? = runCatching {
        windows.filter { it.type == android.view.accessibility.AccessibilityWindowInfo.TYPE_APPLICATION }
            .let { apps -> apps.firstOrNull { it.isActive } ?: apps.maxByOrNull { it.layer } }
            ?.root?.packageName?.toString()
    }.getOrNull()

    private fun bounce() {
        val now = SystemClock.elapsedRealtime()
        if (now - lastBounce < BOUNCE_DEBOUNCE_MS) {
            // A blocked app showed up right after a bounce (fast repeated Back): there may be no further event for it, so look again.
            scheduleVerify()
            return
        }
        lastBounce = now
        handler.post { KioskController.launchTarget(this) }
        scheduleVerify()
    }

    /** Some time after a bounce: if a blocked app is still in front, bounce again. Keeps going until the kiosk is back. */
    private fun scheduleVerify() {
        handler.removeCallbacks(verify)
        handler.postDelayed(verify, VERIFY_MS)
    }

    private val verify = Runnable {
        if (!Prefs.lockdown(this)) return@Runnable
        val front = runCatching { rootInActiveWindow?.packageName?.toString() }.getOrNull()
        if (front != null && front != KioskController.SYSTEM_UI && !KioskController.isAllowed(this, front)) bounce()
    }
}
