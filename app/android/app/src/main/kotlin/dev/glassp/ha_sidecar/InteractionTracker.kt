package dev.glassp.ha_sidecar

import android.content.Context
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.graphics.PixelFormat
import android.view.Gravity

/**
 * "Someone touched the screen", regardless of which app is in front. Fed by [TouchWatcher]
 * (a 1px overlay that receives ACTION_OUTSIDE for every touch elsewhere) so the sidecar can
 * dim, wake and hide the glance screen while the HA app is on screen.
 */
object InteractionTracker {
    @Volatile
    var lastMs: Long = System.currentTimeMillis()
        private set
    private var lastEmit = 0L

    fun touch() {
        lastMs = System.currentTimeMillis()
        BrightnessController.poke()
        val now = SystemClock.elapsedRealtime()
        if (now - lastEmit > 10_000) {
            lastEmit = now
            EventBus.emit("interaction", mapOf("at" to lastMs))
        }
    }

    fun idleMs(): Long = System.currentTimeMillis() - lastMs
}

/** 1x1 px overlay with FLAG_WATCH_OUTSIDE_TOUCH; never consumes real touches. */
object TouchWatcher {
    private var view: View? = null
    private var windowManager: WindowManager? = null

    fun show(ctx: Context, accessibility: Boolean) {
        if (view != null) return
        if (!accessibility && !android.provider.Settings.canDrawOverlays(ctx)) return
        val wm = ctx.getSystemService(WindowManager::class.java)
        val v = View(ctx)
        v.setOnTouchListener { _, ev ->
            if (ev.action == MotionEvent.ACTION_OUTSIDE || ev.action == MotionEvent.ACTION_DOWN) InteractionTracker.touch()
            false
        }
        val type = if (accessibility) WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        else WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        val lp = WindowManager.LayoutParams(
            1, 1, type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.BOTTOM or Gravity.END }
        runCatching {
            wm.addView(v, lp)
            view = v
            windowManager = wm
        }
    }

    fun hide() {
        val v = view ?: return
        runCatching { windowManager?.removeView(v) }
        view = null
        windowManager = null
    }
}
