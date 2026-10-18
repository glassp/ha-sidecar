package dev.glassp.ha_sidecar

import android.content.Context
import org.json.JSONObject

/**
 * Brightness / presence / glance settings. One JSON blob so HA can set any key through the
 * generic `set_config` command, with defaults and type coercion in one place.
 */
object DisplayConfig {
    private val DEFAULTS: Map<String, Any> = linkedMapOf(
        // "manual" = the sidecar never touches brightness
        "mode" to "manual", // auto | day | night | manual
        "theme" to "system", // app UI: system | light | dark | night (dark while it is night)
        // dashboards (paths in the HA frontend, e.g. "lovelace/wall-panel"; a pasted browser URL is reduced to its path)
        "kiosk_dashboard" to "", // required to enable lockdown; opened on boot, Home press and lockdown start
        "glance_dashboard" to "", // optional: shown instead of the native clock screen when idle
        // developer option: levels are shown and set as raw Android values (0..255) instead of percent
        "raw_brightness" to false,
        "auto_dim" to true,
        "night_light" to true,
        "day_level" to 200,
        "day_dim_level" to 60,
        "night_level" to 6,
        "night_light_level" to 50,
        "night_touch_level" to 120,
        "dim_after_s" to 120,
        "presence_hold_s" to 30,
        "night_hold_s" to 20,
        "fade_s" to 1.5,
        "night_start" to 22 * 60,
        "night_end" to 6 * 60 + 30,
        // camera presence (off by default: privacy)
        "camera_presence" to false,
        "camera_facing" to "front", // front | back
        "camera_sensitivity" to 50, // 0..100
        "camera_fps" to 3,
        // companion app watchdog: relaunch the Home Assistant app when it freezes (needs the accessibility service)
        "watchdog" to false,
        "watchdog_action" to "restart", // restart | notify
        "watchdog_probe_s" to 20,
        "watchdog_startup_s" to 90,
        // voice conversation: after an answer the tablet listens again until nothing is said for this long
        "conversation" to true,
        "conversation_timeout_s" to 8,
        "voice_sounds" to true, // the ping when listening starts and when the conversation ends
        "voice_volume" to 50, // media volume (%) during a voice session; the previous level comes back afterwards
        "voice_skin" to "midnight", // the look of the voice screen and the card
        // microphone: the platform's echo canceller keeps the tablet from hearing its own speaker (see MicPlan; "off" is the escape hatch)
        "echo_cancellation" to "auto", // auto | on | off
        "noise_suppression" to false, // the platform's noise suppressor on the microphone
        "mic_source" to "auto", // auto | voice_recognition | voice_communication
        "hot_corner" to "top_left", // where the hidden PIN corner is (it passes the touch on, so it can sit on the Home Assistant menu button)
        "voice_docked" to true, // voice shows as a small card over whatever is on screen instead of a full-screen page
        // on-device wake word (off by default: it keeps the microphone open; the models are downloaded when it is switched on)
        "wake_word" to false,
        "wake_word_ids" to WakeWordModels.DEFAULT_ID, // comma separated catalogue ids
        "wake_word_threshold" to 50, // percent
        // at-a-glance screen
        "glance" to false,
        "glance_after_s" to 300,
    )

    private val MODES = setOf("auto", "day", "night", "manual")
    private val FACINGS = setOf("front", "back")
    private val THEMES = setOf("system", "light", "dark", "night")
    private val CORNERS = setOf("bottom_left", "bottom_right", "top_left", "top_right")
    private val VOICE_SKINS = setOf("midnight", "aurora", "sunrise", "paper", "contrast")

    fun get(ctx: Context): Map<String, Any> {
        val stored = runCatching { JSONObject(Prefs.displayConfigJson(ctx)) }.getOrDefault(JSONObject())
        return DEFAULTS.mapValues { (k, def) -> if (stored.has(k)) coerce(k, stored.get(k), def) ?: def else def }
    }

    class Result(val config: Map<String, Any>, val rejected: List<String>)

    /** Applies [changes]; unknown keys are ignored, invalid values are reported in [Result.rejected] and not applied. */
    fun set(ctx: Context, changes: Map<*, *>): Result {
        val current = JSONObject(get(ctx))
        val rejected = mutableListOf<String>()
        for ((k, v) in changes) {
            val key = k as? String ?: continue
            val def = DEFAULTS[key] ?: continue
            val coerced = coerce(key, v, def)
            if (coerced == null) rejected += key else current.put(key, coerced)
        }
        Prefs.setDisplayConfigJson(ctx, current.toString())
        BrightnessController.poke()
        PresenceCamera.refresh(ctx)
        CompanionWatchdog.refresh(ctx)
        WakeWord.refresh(ctx)
        MicEffects.refresh(ctx) // a running microphone loop notices a changed setup and restarts itself
        KioskController.refreshOverlay(ctx) // the hot corner may have moved
        EventBus.emit("status_changed")
        return Result(get(ctx), rejected)
    }

    fun kioskDashboard(ctx: Context): String = get(ctx)["kiosk_dashboard"] as String

    /** Coerces [value] to the type of [def]; null if it does not fit. */
    private fun coerce(key: String, value: Any?, def: Any): Any? = when (def) {
        is Boolean -> value as? Boolean
        is Int -> (value as? Number)?.toInt()?.let { clamp(key, it) }
        is Double -> (value as? Number)?.toDouble()?.coerceIn(0.0, 10.0)
        is String -> (value as? String)?.let { if (key.endsWith("_dashboard")) DashboardPath.normalize(it) else it.takeIf { v -> validString(key, v) } }
        else -> null
    }

    private fun clamp(key: String, v: Int): Int = when {
        key.endsWith("_level") -> v.coerceIn(0, 255)
        key.startsWith("night_start") || key.startsWith("night_end") -> v.coerceIn(0, 24 * 60 - 1)
        key == "camera_sensitivity" -> v.coerceIn(0, 100)
        key == "camera_fps" -> v.coerceIn(1, 10)
        key == "wake_word_threshold" -> v.coerceIn(10, 99)
        key == "conversation_timeout_s" -> v.coerceIn(3, 30)
        key == "voice_volume" -> v.coerceIn(0, 100)
        key == "watchdog_probe_s" -> v.coerceIn(5, 300)
        key == "watchdog_startup_s" -> v.coerceIn(20, 600)
        key.endsWith("_s") -> v.coerceIn(1, 24 * 3600)
        else -> v
    }

    private fun validString(key: String, v: String) = when (key) {
        "mode" -> v in MODES
        "camera_facing" -> v in FACINGS
        "theme" -> v in THEMES
        "voice_skin" -> v in VOICE_SKINS
        "echo_cancellation" -> v in MicPlan.ECHO_MODES
        "mic_source" -> v in MicPlan.SOURCES
        "hot_corner" -> v in CORNERS
        "watchdog_action" -> v == "restart" || v == "notify"
        "wake_word_ids" -> v.split(',').map { it.trim() }.filter { it.isNotEmpty() }.all { WakeWordModels.word(it) != null }
        else -> true
    }
}
