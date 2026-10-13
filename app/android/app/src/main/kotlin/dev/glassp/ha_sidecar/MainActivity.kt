package dev.glassp.ha_sidecar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/** The one Flutter activity: normal app UI plus the PIN, alarm and idle pages (see [UiHost]). */
class MainActivity : FlutterActivity() {
    private var overlayOnly = false
    private val alarmEnded = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (UiHost.route == UiHost.ALARM) closeRoute()
        }
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine = SidecarEngine.get(context)

    // Channels and plugins are registered once when the engine is created.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {}

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        val r = intent.getStringExtra("route") ?: UiHost.MAIN
        overlayOnly = r != UiHost.MAIN
        applyRoute(r)
        super.onCreate(savedInstanceState)
        UiHost.activity = this
        ContextCompat.registerReceiver(this, alarmEnded, IntentFilter(AlarmService.ACTION_ENDED), ContextCompat.RECEIVER_NOT_EXPORTED)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val r = intent.getStringExtra("route") ?: UiHost.MAIN
        if (r == UiHost.MAIN) overlayOnly = false // the user opened the app: keep the activity after an overlay ends
        applyRoute(r)
    }

    override fun onResume() {
        super.onResume()
        UiHost.activity = this
        UiHost.resumed = true
        applyFlags(UiHost.route)
        UiHost.announce(UiHost.route)
    }

    override fun onPause() {
        UiHost.resumed = false
        super.onPause()
    }

    override fun onDestroy() {
        runCatching { unregisterReceiver(alarmEnded) }
        if (UiHost.activity === this) {
            UiHost.activity = null
            UiHost.route = UiHost.MAIN
        }
        super.onDestroy()
    }

    /** Window flags per page: over the lock screen, screen on, no screenshots of the PIN pad, immersive idle screen. */
    private fun applyRoute(r: String) {
        UiHost.route = r
        applyFlags(r)
        UiHost.announce(r)
        EventBus.emit("status_changed")
    }

    private fun applyFlags(r: String) {
        val overlay = r != UiHost.MAIN
        val wake = r == UiHost.ALARM || r == UiHost.VOICE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(overlay)
            setTurnScreenOn(wake)
        } else {
            // Android 8.0 (API 26) has no such methods: the window flags do the same
            @Suppress("DEPRECATION")
            fun flag(f: Int, on: Boolean) = if (on) window.addFlags(f) else window.clearFlags(f)
            @Suppress("DEPRECATION")
            flag(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED, overlay)
            @Suppress("DEPRECATION")
            flag(WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON, wake)
        }
        val keepOn = r == UiHost.ALARM || r == UiHost.VOICE
        if (keepOn) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // Release builds only, so debug builds stay capturable for development.
        val secure = r == UiHost.PIN && applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0
        if (secure) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE) else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility =
            if (r == UiHost.GLANCE) View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            else View.SYSTEM_UI_FLAG_VISIBLE
    }

    /** Leave the current overlay page. */
    fun closeRoute() {
        val locked = Prefs.lockdown(this)
        val wasGlance = UiHost.route == UiHost.GLANCE
        // While the kiosk is locked the only way out of an overlay is back to the dashboard, never to the sidecar's own screen
        // (which can be open behind it: the PIN pad reuses that activity), so the activity is finished and the app brought back.
        if (overlayOnly || locked) {
            runCatching { stopLockTask() }
            UiHost.route = UiHost.MAIN
            finish()
            if (locked && wasGlance) {
                // the companion app is underneath (the idle screen is translucent): finishing is enough. Start it only if it is not.
                val app = applicationContext
                Handler(Looper.getMainLooper()).postDelayed({
                    if (KioskController.lastForeground != KioskController.targetPackage(app)) KioskController.launchTarget(app)
                }, 700)
            } else if (locked) KioskController.launchTarget(this)
        } else {
            applyRoute(UiHost.MAIN)
        }
    }
}
