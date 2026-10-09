package dev.glassp.ha_sidecar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Bundle
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
        val filter = IntentFilter(AlarmService.ACTION_ENDED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) registerReceiver(alarmEnded, filter, Context.RECEIVER_NOT_EXPORTED)
        else registerReceiver(alarmEnded, filter)
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
        setShowWhenLocked(overlay)
        setTurnScreenOn(r == UiHost.ALARM)
        val keepOn = r == UiHost.ALARM
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
        if (overlayOnly) {
            runCatching { stopLockTask() }
            UiHost.route = UiHost.MAIN
            finish()
        } else {
            applyRoute(UiHost.MAIN)
        }
    }
}
