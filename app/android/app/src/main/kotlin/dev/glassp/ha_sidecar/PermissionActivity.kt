package dev.glassp.ha_sidecar

import android.app.Activity
import android.content.pm.PackageManager
import android.os.Bundle

/** Invisible activity that shows the Android runtime-permission dialog (needs a foreground UI). */
class PermissionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val perm = intent.getStringExtra("perm")
        if (perm == null || checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED) {
            finish()
            return
        }
        requestPermissions(arrayOf(perm), 1)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        PresenceCamera.refresh(this)
        WakeWord.refresh(this)
        EventBus.emit("network_changed", NetworkMonitor.snapshot())
        EventBus.emit("status_changed")
        finish()
    }
}
