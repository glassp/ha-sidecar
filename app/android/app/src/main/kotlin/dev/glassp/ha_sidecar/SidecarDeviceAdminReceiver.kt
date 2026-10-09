package dev.glassp.ha_sidecar

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONObject

/**
 * Device-owner entry point. Provisioned once via:
 *   adb shell dpm set-device-owner dev.glassp.ha_sidecar/.SidecarDeviceAdminReceiver
 */
class SidecarDeviceAdminReceiver : DeviceAdminReceiver() {

    /** Only delivered to the device owner. This is the only reliable "OS update available" signal. */
    override fun onSystemUpdatePending(context: Context, intent: Intent, receivedTime: Long) {
        val info = JSONObject()
            .put("received_at", if (receivedTime > 0) receivedTime else System.currentTimeMillis())
            .put("build_at_detection", Build.VERSION.INCREMENTAL)
        Prefs.setPendingUpdate(context, info.toString(), Build.FINGERPRINT)
        EventBus.emit("system_update_pending", mapOf("received_at" to receivedTime))
    }

    override fun onLockTaskModeEntering(context: Context, intent: Intent, pkg: String) {
        EventBus.emit("lock_task_changed", mapOf("active" to true, "package" to pkg))
    }

    override fun onLockTaskModeExiting(context: Context, intent: Intent) {
        EventBus.emit("lock_task_changed", mapOf("active" to false))
    }
}
