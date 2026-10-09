package dev.glassp.ha_sidecar

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import kotlin.math.abs

/** Public switchboard: decides whether the presence camera should run and starts/stops the service. */
object PresenceCamera {
    @Volatile var active = false
    @Volatile var error: String? = null
    @Volatile var score = 0f
    @Volatile var runningFacing: String? = null

    fun hasPermission(ctx: Context) =
        ctx.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    /** Device owner can grant the camera permission silently. */
    fun ensurePermission(ctx: Context) {
        if (hasPermission(ctx) || !KioskController.isDeviceOwner(ctx)) return
        runCatching {
            ctx.getSystemService(android.app.admin.DevicePolicyManager::class.java).setPermissionGrantState(
                KioskController.admin(ctx), ctx.packageName, Manifest.permission.CAMERA,
                android.app.admin.DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED,
            )
        }
    }

    /** Start, stop or restart (facing changed) to match the config. Safe to call often. */
    fun refresh(ctx: Context) {
        val cfg = DisplayConfig.get(ctx)
        val wanted = cfg["camera_presence"] == true
        val facing = cfg["camera_facing"] as String
        if (!wanted) {
            if (active || runningFacing != null) ctx.stopService(Intent(ctx, PresenceCameraService::class.java))
            error = null
            return
        }
        ensurePermission(ctx)
        if (!hasPermission(ctx)) {
            error = "camera_permission"
            EventBus.emit("status_changed")
            return
        }
        if (runningFacing == facing) return
        if (runningFacing != null) ctx.stopService(Intent(ctx, PresenceCameraService::class.java))
        try {
            ctx.startForegroundService(Intent(ctx, PresenceCameraService::class.java))
        } catch (e: Exception) {
            // Android 14+ only allows starting camera foreground services while the app has a visible window
            error = "start_blocked: ${e.javaClass.simpleName}"
            EventBus.emit("status_changed")
        }
    }

    fun snapshot(ctx: Context): Map<String, Any?> = mapOf(
        "camera_permission" to hasPermission(ctx),
        "camera_active" to active,
        "camera_error" to error,
        "camera_score" to score,
    )
}

/**
 * Frame-differencing motion detector on a tiny luminance grid. Frames are analysed in memory and
 * dropped: nothing is stored or sent anywhere, only "motion yes/no" reaches [BrightnessController].
 */
class PresenceCameraService : Service() {
    private val thread = HandlerThread("presence-camera").apply { start() }
    private val handler = Handler(thread.looper)
    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null
    private var cameraId: String? = null
    private var prev: FloatArray? = null
    private var lastProcessed = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("presence", "Presence camera", NotificationManager.IMPORTANCE_LOW))
        val n = Notification.Builder(this, "presence")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentTitle("Presence camera active")
            .setContentText("Frames are analysed on the device and never stored or sent")
            .setOngoing(true)
            .build()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(4712, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
            } else startForeground(4712, n)
        } catch (e: Exception) {
            PresenceCamera.error = "start_blocked: ${e.javaClass.simpleName}"
            EventBus.emit("status_changed")
            stopSelf()
            return START_NOT_STICKY
        }
        open()
        return START_STICKY
    }

    @Suppress("MissingPermission")
    private fun open() {
        val facing = DisplayConfig.get(this)["camera_facing"] as String
        val want = if (facing == "back") CameraCharacteristics.LENS_FACING_BACK else CameraCharacteristics.LENS_FACING_FRONT
        val cm = getSystemService(CameraManager::class.java)
        val id = cm.cameraIdList.firstOrNull { cm.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == want }
            ?: cm.cameraIdList.firstOrNull()
        if (id == null) {
            PresenceCamera.error = "no_camera"
            EventBus.emit("status_changed")
            stopSelf()
            return
        }
        cameraId = id
        PrivacyMonitor.ownCameraIds += id
        val map = cm.getCameraCharacteristics(id).get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)!!
        val size = map.getOutputSizes(ImageFormat.YUV_420_888).filter { it.width <= 640 }
            .minByOrNull { abs(it.width - 320) + abs(it.height - 240) } ?: map.getOutputSizes(ImageFormat.YUV_420_888).last()
        reader = ImageReader.newInstance(size.width, size.height, ImageFormat.YUV_420_888, 2).also {
            it.setOnImageAvailableListener(::onFrame, handler)
        }
        try {
            cm.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    device = camera
                    val surface = reader!!.surface
                    camera.createCaptureSession(listOf(surface), object : CameraCaptureSession.StateCallback() {
                        override fun onConfigured(s: CameraCaptureSession) {
                            session = s
                            val req = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply { addTarget(surface) }
                            s.setRepeatingRequest(req.build(), null, handler)
                            PresenceCamera.active = true
                            PresenceCamera.runningFacing = facing
                            PresenceCamera.error = null
                            PrivacyMonitor.refreshCamera()
                            EventBus.emit("status_changed")
                        }

                        override fun onConfigureFailed(s: CameraCaptureSession) = fail("session_failed")
                    }, handler)
                }

                override fun onDisconnected(camera: CameraDevice) = fail("disconnected")
                override fun onError(camera: CameraDevice, error: Int) = fail("camera_error_$error")
            }, handler)
        } catch (e: Exception) {
            fail(e.javaClass.simpleName)
        }
    }

    private fun fail(reason: String) {
        PresenceCamera.error = reason
        EventBus.emit("status_changed")
        stopSelf()
    }

    private fun onFrame(r: ImageReader) {
        val img = r.acquireLatestImage() ?: return
        try {
            val cfg = DisplayConfig.get(this)
            val fps = (cfg["camera_fps"] as Int).coerceIn(1, 10)
            val now = System.currentTimeMillis()
            if (now - lastProcessed < 1000L / fps) return
            lastProcessed = now

            val plane = img.planes[0]
            val buf = plane.buffer
            val gw = 32
            val gh = 24
            val grid = FloatArray(gw * gh)
            val w = img.width
            val h = img.height
            for (gy in 0 until gh) for (gx in 0 until gw) {
                // mean of a 4x4 block at the cell centre
                var sum = 0
                val cx = (gx * w) / gw + w / (2 * gw)
                val cy = (gy * h) / gh + h / (2 * gh)
                for (dy in -2 until 2) for (dx in -2 until 2) {
                    val x = (cx + dx).coerceIn(0, w - 1)
                    val y = (cy + dy).coerceIn(0, h - 1)
                    sum += buf.get(y * plane.rowStride + x * plane.pixelStride).toInt() and 0xFF
                }
                grid[gy * gw + gx] = sum / 16f
            }
            val p = prev
            prev = grid
            if (p == null) return

            // ignore global brightness shifts (auto exposure, lights switching) by removing the mean change
            var meanDiff = 0f
            for (i in grid.indices) meanDiff += grid[i] - p[i]
            meanDiff /= grid.size
            val s = (cfg["camera_sensitivity"] as Int) / 100f
            val cellThr = 30f - 24f * s // 30 .. 6 grey levels
            val minFraction = 0.12f - 0.11f * s // 12 % .. 1 % of cells
            var changed = 0
            for (i in grid.indices) if (abs(grid[i] - p[i] - meanDiff) > cellThr) changed++
            val fraction = changed.toFloat() / grid.size
            PresenceCamera.score = fraction
            if (fraction > minFraction) BrightnessController.cameraMotion()
        } finally {
            img.close()
        }
    }

    override fun onDestroy() {
        session?.close()
        device?.close()
        reader?.close()
        cameraId?.let { PrivacyMonitor.ownCameraIds -= it }
        PrivacyMonitor.refreshCamera()
        PresenceCamera.active = false
        PresenceCamera.runningFacing = null
        thread.quitSafely()
        EventBus.emit("status_changed")
        super.onDestroy()
    }
}
