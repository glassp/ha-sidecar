package dev.glassp.ha_sidecar

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * What the companion watchdog and the dashboard-beacon heal did, kept on the tablet (survives restarts of the app and of the
 * tablet) so a freeze can be explained afterwards. A release build logs nothing to logcat that is still there the next morning.
 * Newest last on disk, newest first in [recent]. Only short codes are stored, never anything from the companion's window.
 */
object WatchdogLog {
    private const val MAX = 50
    private val lock = Any()

    /** [event]: `detected` | `heal_request` | `heal_refused` | `restart` | `gave_up` | `notify`; [detail] a reason or method. */
    fun add(ctx: Context, event: String, reason: String? = null, detail: String? = null) {
        synchronized(lock) {
            val list = runCatching { JSONArray(Prefs.watchdogLogJson(ctx)) }.getOrDefault(JSONArray())
            val entry = JSONObject().put("at", System.currentTimeMillis()).put("event", event)
            reason?.let { entry.put("reason", it) }
            detail?.let { entry.put("detail", it) }
            list.put(entry)
            val keep = JSONArray()
            for (i in maxOf(0, list.length() - MAX) until list.length()) keep.put(list.get(i))
            Prefs.setWatchdogLogJson(ctx, keep.toString())
        }
    }

    /** The last [n] entries, newest first, as plain maps for the status message. */
    fun recent(ctx: Context, n: Int = 20): List<Map<String, Any?>> = synchronized(lock) {
        val list = runCatching { JSONArray(Prefs.watchdogLogJson(ctx)) }.getOrDefault(JSONArray())
        (list.length() - 1 downTo maxOf(0, list.length() - n)).map { i ->
            val o = list.getJSONObject(i)
            mapOf("at" to o.optLong("at"), "event" to o.optString("event"), "reason" to o.optString("reason").ifEmpty { null }, "detail" to o.optString("detail").ifEmpty { null })
        }
    }
}
