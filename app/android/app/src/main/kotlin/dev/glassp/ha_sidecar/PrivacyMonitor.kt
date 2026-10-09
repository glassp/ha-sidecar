package dev.glassp.ha_sidecar

import android.content.Context
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.media.AudioRecordingConfiguration
import android.os.Handler
import android.os.Looper

/** Is any app using the camera / microphone right now? (No permission needed.) */
object PrivacyMonitor {
    @Volatile var cameraInUse = false
        private set
    @Volatile var micInUse = false
        private set

    /** Camera ids opened by the sidecar itself (presence camera); not reported as "in use". */
    val ownCameraIds = java.util.concurrent.CopyOnWriteArraySet<String>()

    private val busyCameras = java.util.concurrent.CopyOnWriteArraySet<String>()
    private var started = false

    @Synchronized
    fun start(ctx: Context) {
        if (started) return
        started = true
        val handler = Handler(Looper.getMainLooper())

        runCatching {
            ctx.getSystemService(CameraManager::class.java).registerAvailabilityCallback(
                object : CameraManager.AvailabilityCallback() {
                    override fun onCameraUnavailable(cameraId: String) {
                        busyCameras += cameraId
                        refreshCamera()
                    }

                    override fun onCameraAvailable(cameraId: String) {
                        busyCameras -= cameraId
                        refreshCamera()
                    }
                },
                handler,
            )
        }
        runCatching {
            ctx.getSystemService(AudioManager::class.java).registerAudioRecordingCallback(
                object : AudioManager.AudioRecordingCallback() {
                    override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>) {
                        val now = configs.isNotEmpty()
                        if (now != micInUse) {
                            micInUse = now
                            EventBus.emit("status_changed")
                        }
                    }
                },
                handler,
            )
        }
    }

    /** Call when the sidecar opens/closes its own camera so it does not flag itself. */
    fun refreshCamera() {
        val now = busyCameras.any { it !in ownCameraIds }
        if (now != cameraInUse) {
            cameraInUse = now
            EventBus.emit("status_changed")
        }
    }
}
