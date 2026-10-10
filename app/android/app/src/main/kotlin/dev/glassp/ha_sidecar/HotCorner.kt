package dev.glassp.ha_sidecar

import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.SystemClock
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager

/**
 * Invisible touch target in the top-left corner. Tapping it [TAPS] times within [WINDOW_MS]
 * opens the PIN screen. Uses an accessibility overlay when available (no extra permission),
 * otherwise a regular application overlay (needs "draw over other apps").
 */
object HotCorner {
    private const val TAPS = 5
    private const val WINDOW_MS = 5_000L
    private const val SIZE_DP = 72
    private const val GESTURE_BAR_DP = 32

    private var view: View? = null
    private var corner = ""
    private var windowManager: WindowManager? = null

    /** Shows the corner where the settings put it, moving it if the setting changed. */
    fun show(ctx: Context, accessibility: Boolean) {
        val wanted = DisplayConfig.get(ctx)["hot_corner"] as String
        if (view != null && corner == wanted) return
        hide()
        corner = wanted
        if (!accessibility && !android.provider.Settings.canDrawOverlays(ctx)) return

        val wm = ctx.getSystemService(WindowManager::class.java)
        val size = (SIZE_DP * ctx.resources.displayMetrics.density).toInt()
        var count = 0
        var windowStart = 0L

        val v = View(ctx)
        v.setOnTouchListener { _, ev ->
            if (ev.action == MotionEvent.ACTION_DOWN) {
                val now = SystemClock.elapsedRealtime()
                if (now - windowStart > WINDOW_MS) {
                    windowStart = now
                    count = 0
                }
                if (++count >= TAPS) {
                    count = 0
                    UiHost.show(ctx, UiHost.PIN)
                }
            }
            true
        }

        val type = if (accessibility) WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        else WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        val lp = WindowManager.LayoutParams(
            size, size, type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            val horizontal = if (corner.endsWith("right")) Gravity.END else Gravity.START
            val vertical = if (corner.startsWith("top")) Gravity.TOP else Gravity.BOTTOM
            gravity = vertical or horizontal
            // bottom corners sit above the system's gesture bar, which would take the taps
            if (vertical == Gravity.BOTTOM) y = (GESTURE_BAR_DP * ctx.resources.displayMetrics.density).toInt()
        }

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
