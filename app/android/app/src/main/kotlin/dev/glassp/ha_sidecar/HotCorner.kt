package dev.glassp.ha_sidecar

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.graphics.Path
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import kotlin.math.hypot

/**
 * A hidden corner: tapping it [TAPS] times within [WINDOW_MS] opens the PIN screen. The corner is top left by default, which is
 * where the Home Assistant menu button sits, so it must not swallow the touch: it counts the tap and then replays the same
 * touch onto whatever is underneath through the accessibility service (the overlay is made untouchable for that moment, so the
 * replay reaches the app). The menu opens and closes as usual while five taps also open the PIN screen.
 *
 * Without the accessibility service nothing can be replayed: the corner is then a plain overlay that keeps the touches (it needs
 * "draw over other apps"); move it with the `hot_corner` setting if it covers something.
 */
object HotCorner {
    private const val TAPS = 5
    private const val WINDOW_MS = 5_000L
    private const val SIZE_DP = 72
    private const val GESTURE_BAR_DP = 32
    private const val TAP_MAX_MS = 500L
    private const val TAP_REPLAY_MS = 25L
    private const val MAX_POINTS = 200
    private const val MAX_REPLAY_MS = 3_000L
    private const val UNTOUCHABLE_SETTLE_MS = 35L // the window manager applies the flag asynchronously

    private val main = Handler(Looper.getMainLooper())
    private var view: View? = null
    private var params: WindowManager.LayoutParams? = null
    private var corner = ""
    private var windowManager: WindowManager? = null
    private val counter = TapCounter(TAPS, WINDOW_MS)

    /** True from the moment a counted touch is handed on until the replay has finished: touches in that time are our own replay. */
    @Volatile private var replaying = false

    private class Point(val t: Long, val x: Float, val y: Float)

    /** Shows the corner where the settings put it, moving it if the setting changed. */
    fun show(ctx: Context, accessibility: Boolean) {
        val wanted = DisplayConfig.get(ctx)["hot_corner"] as String
        if (view != null && corner == wanted) return
        hide()
        corner = wanted
        if (!accessibility && !android.provider.Settings.canDrawOverlays(ctx)) return

        val wm = ctx.getSystemService(WindowManager::class.java)
        val size = (SIZE_DP * ctx.resources.displayMetrics.density).toInt()
        val slop = ViewConfiguration.get(ctx).scaledTouchSlop.toFloat()

        val points = ArrayList<Point>()
        val v = View(ctx)
        v.setOnTouchListener { _, ev ->
            if (replaying) return@setOnTouchListener true // our own replay reached the corner before it became untouchable: not a tap
            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    points.clear()
                    points += Point(ev.eventTime, ev.rawX, ev.rawY)
                }
                MotionEvent.ACTION_MOVE -> if (points.size < MAX_POINTS) points += Point(ev.eventTime, ev.rawX, ev.rawY)
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> if (points.isNotEmpty()) {
                    points += Point(ev.eventTime, ev.rawX, ev.rawY)
                    val first = points.first()
                    val duration = ev.eventTime - first.t
                    val moved = points.any { hypot(it.x - first.x, it.y - first.y) > slop }
                    val isTap = ev.actionMasked == MotionEvent.ACTION_UP && !moved && duration <= TAP_MAX_MS
                    if (isTap && counter.tap(SystemClock.elapsedRealtime())) UiHost.show(ctx, UiHost.PIN)
                    // a tap is replayed as a short one (the press length does not matter), anything else as it was
                    replay(points.toList(), if (isTap) TAP_REPLAY_MS else duration)
                    points.clear()
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
            params = lp
            windowManager = wm
        }
    }

    /** Hands the touch that was just counted on to the app under the corner, as the same gesture, a moment later. */
    private fun replay(points: List<Point>, durationMs: Long) {
        val svc: AccessibilityService = SidecarAccessibilityService.instance ?: return
        val v = view ?: return
        val wm = windowManager ?: return
        val lp = params ?: return
        fun touchable(on: Boolean) {
            lp.flags = if (on) lp.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
            else lp.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
            runCatching { wm.updateViewLayout(v, lp) }
        }
        fun finish() {
            touchable(true)
            replaying = false
        }
        val path = Path().apply {
            moveTo(points.first().x, points.first().y)
            for (p in points.drop(1)) lineTo(p.x, p.y)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, durationMs.coerceIn(20, MAX_REPLAY_MS))
        val done = object : AccessibilityService.GestureResultCallback() {
            override fun onCompleted(g: GestureDescription?) = finish()
            override fun onCancelled(g: GestureDescription?) = finish()
        }
        replaying = true
        touchable(false)
        // only after the window manager has applied the flag, or the replay lands on this window and is counted as another tap
        main.postDelayed({
            val sent = runCatching { svc.dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), done, main) }.getOrDefault(false)
            if (!sent) finish()
        }, UNTOUCHABLE_SETTLE_MS)
    }

    fun hide() {
        val v = view ?: return
        runCatching { windowManager?.removeView(v) }
        view = null
        params = null
        windowManager = null
    }
}
