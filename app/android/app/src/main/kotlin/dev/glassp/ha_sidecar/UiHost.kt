package dev.glassp.ha_sidecar

import android.content.Context
import android.content.Intent

/**
 * All visible UI is Flutter, hosted by the single [MainActivity] (a Flutter engine can only be attached
 * to one activity at a time). Full-screen pages that must appear over other apps (PIN pad, ringing
 * alarm, idle screen) are *routes* of that activity: native code starts it with a `route` extra and
 * the activity applies the matching window flags and tells Dart which page to show.
 */
object UiHost {
    const val MAIN = "main"
    const val PIN = "/pin"
    const val ALARM = "/alarm"
    const val GLANCE = "/glance"
    const val VOICE = "/voice"

    @Volatile var activity: MainActivity? = null
    @Volatile var route: String = MAIN
    @Volatile var resumed = false

    fun isShowing(r: String) = activity != null && route == r

    /** Brings the Flutter UI to the front showing [r]. Works from a service while the sidecar is not visible. */
    fun show(ctx: Context, r: String): Boolean {
        val launcher: Context = SidecarAccessibilityService.instance ?: ctx
        return runCatching {
            launcher.startActivity(
                Intent(launcher, MainActivity::class.java)
                    .putExtra("route", r)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_NO_ANIMATION)
            )
        }.isSuccess
    }

    /** Ends the page [r] if it is showing: closes the activity when it was started only for the overlay, otherwise returns to the app. */
    fun close(r: String): Boolean {
        val a = activity?.takeIf { route == r } ?: return false
        a.runOnUiThread { a.closeRoute() }
        return true
    }

    fun announce(r: String) = EventBus.emit("ui_route", mapOf("route" to r))
}
