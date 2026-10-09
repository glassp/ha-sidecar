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
        // at-a-glance screen
        "glance" to false,
        "glance_after_s" to 300,
    )

    private val MODES = setOf("auto", "day", "night", "manual")
    private val FACINGS = setOf("front", "back")

    fun get(ctx: Context): Map<String, Any> {
        val stored = runCatching { JSONObject(Prefs.displayConfigJson(ctx)) }.getOrDefault(JSONObject())
        return DEFAULTS.mapValues { (k, def) -> if (stored.has(k)) coerce(k, stored.get(k), def) ?: def else def }
    }

    /** @return the new full config; unknown keys and invalid values are ignored (old value kept). */
    fun set(ctx: Context, changes: Map<*, *>): Map<String, Any> {
        val current = JSONObject(get(ctx))
        for ((k, v) in changes) {
            val key = k as? String ?: continue
            val def = DEFAULTS[key] ?: continue
            current.put(key, coerce(key, v, def) ?: continue)
        }
        Prefs.setDisplayConfigJson(ctx, current.toString())
        BrightnessController.poke()
        EventBus.emit("status_changed")
        return get(ctx)
    }

    /** Coerces [value] to the type of [def]; null if it does not fit. */
    private fun coerce(key: String, value: Any?, def: Any): Any? = when (def) {
        is Boolean -> value as? Boolean
        is Int -> (value as? Number)?.toInt()?.let { clamp(key, it) }
        is Double -> (value as? Number)?.toDouble()?.coerceIn(0.0, 10.0)
        is String -> (value as? String)?.takeIf { validString(key, it) }
        else -> null
    }

    private fun clamp(key: String, v: Int): Int = when {
        key.endsWith("_level") -> v.coerceIn(0, 255)
        key.startsWith("night_start") || key.startsWith("night_end") -> v.coerceIn(0, 24 * 60 - 1)
        key == "camera_sensitivity" -> v.coerceIn(0, 100)
        key == "camera_fps" -> v.coerceIn(1, 10)
        key.endsWith("_s") -> v.coerceIn(1, 24 * 3600)
        else -> v
    }

    private fun validString(key: String, v: String) = when (key) {
        "mode" -> v in MODES
        "camera_facing" -> v in FACINGS
        else -> true
    }
}
