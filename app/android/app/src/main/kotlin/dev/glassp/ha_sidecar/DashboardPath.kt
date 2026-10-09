package dev.glassp.ha_sidecar

import java.net.URI

/**
 * Turns whatever the user pastes into the path the companion app's deep link needs.
 *
 *   https://home.example.org/lovelace/wall-panel  ->  lovelace/wall-panel
 *   /dashboard-kitchen/0?kiosk                    ->  dashboard-kitchen/0?kiosk
 *   homeassistant://navigate/lovelace/default     ->  lovelace/default
 *
 * Pure Kotlin (no Android classes) so it is unit-tested on the JVM.
 */
object DashboardPath {
    /** @return "" for blank input (clears the setting), null if it is not a usable dashboard link. */
    fun normalize(raw: String): String? {
        var s = raw.trim()
        if (s.isEmpty()) return ""
        for (prefix in listOf("homeassistant://navigate/", "homeassistant://navigate")) {
            if (s.startsWith(prefix, ignoreCase = true)) {
                s = s.substring(prefix.length)
                break
            }
        }
        if (s.contains("://")) {
            val uri = try {
                URI(s)
            } catch (e: Exception) {
                return null
            }
            if (uri.scheme?.lowercase() !in setOf("http", "https")) return null
            s = (uri.rawPath ?: "") + (uri.rawQuery?.let { "?$it" } ?: "")
        }
        s = s.substringBefore('#').trimStart('/')
        if (s.isEmpty() || s.startsWith("?") || s.any { it.isWhitespace() }) return null
        return s
    }

    /** `server=default` makes the app use its first server instead of asking which one. */
    fun deepLink(path: String): String {
        val clean = normalize(path) ?: path.trimStart('/')
        val sep = if (clean.contains('?')) "&" else "?"
        return "homeassistant://navigate/$clean${sep}server=default"
    }
}
