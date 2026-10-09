package dev.glassp.ha_sidecar

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * The sidecar's HOME entry point (invisible trampoline). Android starts the home app at boot and
 * whenever no task is left (HA app crashed / was killed / lock-task ended), which gives us
 * boot start and crash recovery for free: we start the engine and put the HA app back in front.
 */
class HomeActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        KeepAliveService.start(this) // engine + HA connection + overlay, also right after boot

        val opened = Prefs.kioskLauncher(this) &&
            KioskController.launchTarget(this, lockTask = Prefs.lockdown(this), dashboard = true)
        if (!opened) {
            // Launcher mode off, or the HA app is missing: show the sidecar UI instead of a blank screen.
            startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
        finish()
    }
}
