package dev.glassp.ha_sidecar

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Drives the system update screens by tapping their buttons through the accessibility service.
 *
 * Privacy guard: window content is only inspected while a session is *armed* (by an
 * authenticated HA command, auto-expiring) and only for the system update packages below.
 * Outside of that the service never touches node trees.
 *
 * Button matching is by visible label and therefore best-effort: OEM update UIs differ.
 * Unmatched screens are reported to HA (`update_automation_idle`) rather than guessed at.
 */
object UpdateAutomation {
    private const val SESSION_MS = 30 * 60_000L
    private const val STEP_DEBOUNCE_MS = 1_500L
    private const val IDLE_TIMEOUT_MS = 90_000L
    private const val MAX_CLICKS_PER_LABEL = 2

    val PACKAGES = setOf(KioskController.SETTINGS, "com.google.android.gms", "com.google.android.apps.updater")

    /** Lower-case labels worth tapping, in rough flow order. Add translations as needed. */
    private val LABELS = listOf(
        "check for update", "check for updates", "download and install", "download", "install now", "install",
        "restart now", "restart", "reboot now",
        "nach updates suchen", "herunterladen und installieren", "herunterladen", "jetzt installieren",
        "installieren", "jetzt neu starten", "neu starten",
    )

    private val main = Handler(Looper.getMainLooper())
    private var armedUntil = 0L
    private var lastStep = 0L
    private var lastLabel: String? = null

    /** A button that stays on screen (e.g. "Check for update" when already up to date) must not be tapped forever. */
    private val clicks = mutableMapOf<String, Int>()
    private val idleCheck = object : Runnable {
        override fun run() {
            if (!isArmed()) return
            if (SystemClock.elapsedRealtime() - lastStep > IDLE_TIMEOUT_MS) finish("idle")
            else main.postDelayed(this, 15_000)
        }
    }

    fun arm(ctx: Context) {
        armedUntil = SystemClock.elapsedRealtime() + SESSION_MS
        lastStep = SystemClock.elapsedRealtime()
        lastLabel = null
        clicks.clear()
        main.removeCallbacks(idleCheck)
        main.postDelayed(idleCheck, 15_000)
        KioskController.allowTemporarily(ctx, KioskController.SETTINGS, SESSION_MS)
        KioskController.allowTemporarily(ctx, "com.google.android.gms", SESSION_MS)
        EventBus.emit("update_automation_started")
    }

    fun disarm() {
        armedUntil = 0
        main.removeCallbacks(idleCheck)
    }

    private fun finish(reason: String) {
        disarm()
        EventBus.emit("update_automation_finished", mapOf("reason" to reason, "steps" to clicks.toMap()))
    }

    fun isArmed() = SystemClock.elapsedRealtime() < armedUntil

    /** Called from the accessibility service for events of [pkg]; no-op unless armed. */
    fun onWindowChanged(root: AccessibilityNodeInfo?, pkg: String) {
        if (!isArmed() || pkg !in PACKAGES || root == null) return
        val now = SystemClock.elapsedRealtime()
        if (now - lastStep < STEP_DEBOUNCE_MS) return

        for (label in LABELS) {
            if ((clicks[label] ?: 0) >= MAX_CLICKS_PER_LABEL) continue
            val node = findClickable(root, label) ?: continue
            clicks[label] = (clicks[label] ?: 0) + 1
            lastStep = now
            lastLabel = label
            node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            EventBus.emit("update_automation_step", mapOf("label" to label))
            return
        }
    }

    private fun findClickable(root: AccessibilityNodeInfo, label: String): AccessibilityNodeInfo? {
        // findAccessibilityNodeInfosByText is a case-insensitive *substring* match; keep only exact labels
        // so "Install" does not click "Installed apps".
        for (candidate in root.findAccessibilityNodeInfosByText(label)) {
            val text = (candidate.text ?: candidate.contentDescription)?.toString()?.trim()?.lowercase()
            if (text != label) continue
            var n: AccessibilityNodeInfo? = candidate
            while (n != null && !n.isClickable) n = n.parent
            if (n != null && n.isEnabled) return n
        }
        return null
    }
}
