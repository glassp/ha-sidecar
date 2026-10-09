package dev.glassp.ha_sidecar

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import java.util.Calendar

/**
 * Time-of-day brightness with presence awareness, evaluated on the tablet (works offline).
 *
 *  Day:   active  -> day_level;  idle (no touch, no presence) -> day_dim_level when auto_dim.
 *  Night: base    -> night_level;
 *         presence near the kiosk (camera / HA sensor) -> night_light_level   (see the floor)
 *         recent touch -> night_touch_level for night_hold_s.
 *  Presence = HA presence entity on, or camera motion, each held for presence_hold_s.
 *  Mode `manual` never touches brightness; `day`/`night` force a period; `auto` follows the
 *  HA-provided night state when set (e.g. sun below horizon) else the night_start/night_end schedule.
 */
object BrightnessController {
    private val main = Handler(Looper.getMainLooper())
    private var ctx: Context? = null
    private var started = false

    // inputs
    @Volatile var extPresence = false
        private set
    @Volatile private var extPresenceOffAt = 0L
    @Volatile var extNight: Boolean? = null
    @Volatile var lastCameraMotion = 0L

    // output
    @Volatile var target = -1
        private set
    @Volatile var isNight = false
        private set
    @Volatile var present = false
        private set
    @Volatile var error: String? = null
        private set
    private var current = -1f
    private var rampFrom = 0f
    private var rampStart = 0L
    private var rampMs = 0L
    private var manualModeApplied = false
    private var lastApplied = -1
    private var lastMode = ""
    private var lastEmitted = ""

    private val tick = object : Runnable {
        override fun run() {
            evaluate()
            main.postDelayed(this, if (current.toInt() != target && target >= 0) 100 else 1000)
        }
    }

    @Synchronized
    fun start(context: Context) {
        if (started) return
        started = true
        ctx = context.applicationContext
        main.post(tick)
    }

    /** Re-evaluate right now (touch, config change, presence change). */
    fun poke() {
        if (!started) return
        main.removeCallbacks(tick)
        main.post(tick)
    }

    fun setExternalPresence(on: Boolean) {
        if (extPresence && !on) extPresenceOffAt = System.currentTimeMillis()
        extPresence = on
        poke()
    }

    fun cameraMotion() {
        lastCameraMotion = System.currentTimeMillis()
        poke()
    }

    fun snapshot(): Map<String, Any?> = mapOf(
        "is_night" to isNight,
        "presence" to present,
        "target_brightness" to target.takeIf { it >= 0 },
        "display_error" to error,
        "camera_motion" to (System.currentTimeMillis() - lastCameraMotion < 5_000),
        "ext_night" to extNight,
        "ext_presence" to extPresence,
    )

    // --- logic ------------------------------------------------------------------------------

    private fun evaluate() {
        val c = ctx ?: return
        val cfg = DisplayConfig.get(c)
        val now = System.currentTimeMillis()
        val holdMs = (cfg["presence_hold_s"] as Int) * 1000L

        present = extPresence || now - extPresenceOffAt < holdMs || now - lastCameraMotion < holdMs
        val mode = cfg["mode"] as String
        if (mode != lastMode) {
            lastMode = mode
            lastApplied = -1 // re-assert our level after (re)enabling
            manualModeApplied = false
        }
        isNight = when (mode) {
            "night" -> true
            "day" -> false
            else -> extNight ?: inSchedule(cfg["night_start"] as Int, cfg["night_end"] as Int)
        }

        if (mode != "manual") {
            val t = desiredLevel(cfg, now)
            if (t != target) startRamp(t, ((cfg["fade_s"] as Double) * 1000).toLong())
            stepRamp(c)
        } else {
            target = -1
            error = null
        }
        glance(c, cfg, now)
        emitIfChanged(c)
    }

    /** Show the at-a-glance screen when idle and nobody is near; dismiss it when someone is. */
    private fun glance(c: Context, cfg: Map<String, Any>, now: Long) {
        if (cfg["glance"] != true) {
            if (GlanceActivity.showing) GlanceActivity.dismiss()
            return
        }
        if (GlanceActivity.showing) {
            if (present) {
                GlanceActivity.dismiss()
                InteractionTracker.touch() // restart the idle timer so it does not pop straight back
            }
            return
        }
        val idleMs = now - InteractionTracker.lastMs
        val pm = c.getSystemService(PowerManager::class.java)
        if (idleMs > (cfg["glance_after_s"] as Int) * 1000L && !present && pm.isInteractive &&
            AlarmService.ringingId == null && !PinActivity.visible
        ) GlanceActivity.show(c)
    }

    private fun desiredLevel(cfg: Map<String, Any>, now: Long): Int {
        val interacted = now - InteractionTracker.lastMs
        return if (!isNight) {
            val idleDim = (cfg["auto_dim"] as Boolean) && interacted > (cfg["dim_after_s"] as Int) * 1000L && !present
            if (idleDim) cfg["day_dim_level"] as Int else cfg["day_level"] as Int
        } else {
            when {
                interacted < (cfg["night_hold_s"] as Int) * 1000L -> cfg["night_touch_level"] as Int
                (cfg["night_light"] as Boolean) && present -> cfg["night_light_level"] as Int
                else -> cfg["night_level"] as Int
            }
        }
    }

    private fun inSchedule(startMin: Int, endMin: Int): Boolean {
        val cal = Calendar.getInstance()
        val m = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        return if (startMin <= endMin) m in startMin until endMin else m >= startMin || m < endMin
    }

    private fun startRamp(to: Int, ms: Long) {
        rampFrom = if (current < 0) readSystem() else current
        rampStart = System.currentTimeMillis()
        rampMs = ms
        target = to
    }

    private fun stepRamp(c: Context) {
        if (target < 0) return
        val pm = c.getSystemService(PowerManager::class.java)
        if (!pm.isInteractive) return // screen off: apply when it wakes
        val frac = if (rampMs <= 0) 1f else ((System.currentTimeMillis() - rampStart).toFloat() / rampMs).coerceIn(0f, 1f)
        val level = rampFrom + (target - rampFrom) * frac
        if (level.toInt() != lastApplied) apply(c, level)
        current = level
    }

    private fun apply(c: Context, level: Float) {
        if (!Settings.System.canWrite(c)) {
            error = "write_settings_permission"
            return
        }
        error = null
        val cr = c.contentResolver
        if (!manualModeApplied) {
            Settings.System.putInt(cr, Settings.System.SCREEN_BRIGHTNESS_MODE, Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL)
            manualModeApplied = true
        }
        lastApplied = level.toInt().coerceIn(0, 255)
        Settings.System.putInt(cr, Settings.System.SCREEN_BRIGHTNESS, lastApplied)
    }

    private fun readSystem(): Float {
        val c = ctx ?: return 128f
        return Settings.System.getInt(c.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128).toFloat()
    }

    private fun emitIfChanged(c: Context) {
        val key = "$isNight|$present|${target / 10}|$error"
        if (key != lastEmitted) {
            lastEmitted = key
            EventBus.emit("status_changed")
        }
    }
}
