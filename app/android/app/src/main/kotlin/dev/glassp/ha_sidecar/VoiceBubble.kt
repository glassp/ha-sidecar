package dev.glassp.ha_sidecar

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * The voice screen as a small card docked to the bottom of whatever is in front (usually the dashboard), so asking something
 * does not take the whole screen. It is a native overlay window, not part of the dashboard, and shows no timers (those belong on
 * the dashboard, see the timers card). The Dart side owns all state and sends a snapshot on every change ([update]); taps go back
 * as `bubble_action` events: `done` (stop recording), `end` (end the conversation), `again`, `close` and `expand` (open the
 * full-screen page).
 *
 * Needs the same as the other overlays: an enabled accessibility service, or "draw over other apps". Without either, or with the
 * screen off, [available] is false and Dart opens the full-screen page instead.
 */
object VoiceBubble {
    private const val WIDTH_DP = 600
    private const val SIDE_MARGIN_DP = 16
    private const val BOTTOM_MARGIN_DP = 48

    private val main = Handler(Looper.getMainLooper())
    private var root: LinearLayout? = null
    private var windowManager: WindowManager? = null
    private var holder: Holder? = null

    private class Holder(
        val status: TextView,
        val close: TextView,
        val wave: WaveView,
        val user: TextView,
        val answer: TextView,
        val wait: View,
        val waitTrack: View,
        val buttons: LinearLayout,
        val done: TextView,
        val end: TextView,
        val again: TextView,
    ) {
        var anim: ValueAnimator? = null
        var waitKey: Long = -1
        lateinit var volRow: LinearLayout
        lateinit var volBar: android.widget.SeekBar
        lateinit var volIcon: TextView
        lateinit var volText: TextView
        var dragging = false
        var lastVolumeSent = 0L
    }

    fun available(ctx: Context): Boolean {
        val pm = ctx.getSystemService(PowerManager::class.java)
        if (pm != null && !pm.isInteractive) return false // a dark screen needs the activity to wake it
        return SidecarAccessibilityService.instance != null || android.provider.Settings.canDrawOverlays(ctx)
    }

    fun update(ctx: Context, s: Map<String, Any?>) {
        main.post { render(ctx, s) }
    }

    fun hide() {
        main.post { remove() }
    }

    // --- window ---------------------------------------------------------------------------------------------------------

    private fun render(ctx: Context, s: Map<String, Any?>) {
        if (root == null && !add(ctx)) return
        val h = holder ?: return
        val state = s["state"] as? String ?: "listening"
        val labels = (s["labels"] as? Map<*, *>)?.mapKeys { it.key.toString() }?.mapValues { it.value?.toString().orEmpty() }.orEmpty()
        val user = s["user"] as? String ?: ""
        val answer = s["assistant"] as? String ?: ""
        val error = s["error"] as? String ?: ""
        val level = (s["level"] as? Number)?.toFloat() ?: 0f
        val inConversation = s["in_conversation"] == true

        val accent = when (state) {
            "error" -> Color.parseColor("#F2B8B5")
            "thinking" -> Color.parseColor("#EFB8C8")
            else -> Color.parseColor("#CFBCFF")
        }
        h.status.text = labels[if (state == "listening" && s["follow_up"] == true) "follow_up" else state].orEmpty()
        h.status.setTextColor(accent)
        h.wave.mode = state
        h.wave.accent = accent
        h.wave.push(level)
        h.wave.visibility = if (state == "error") View.GONE else View.VISIBLE
        h.user.visibility = if (user.isEmpty()) View.GONE else View.VISIBLE
        h.user.text = user
        val shown = if (state == "error") error else answer
        h.answer.visibility = if (shown.isEmpty() && state != "thinking") View.GONE else View.VISIBLE
        h.answer.text = if (shown.isEmpty()) "• • •" else shown
        h.answer.setTextColor(if (state == "error") Color.parseColor("#F2B8B5") else Color.parseColor("#E6E1EC"))

        // the draining bar: how long the conversation waits for you to start speaking (a new deadline restarts it)
        val deadline = (s["wait_deadline_ms"] as? Number)?.toLong() ?: 0L
        val total = (s["wait_total_ms"] as? Number)?.toLong() ?: 0L
        val left = deadline - System.currentTimeMillis()
        if (deadline > 0 && total > 0 && left > 0) {
            h.waitTrack.visibility = View.VISIBLE
            if (h.waitKey != deadline) {
                h.waitKey = deadline
                h.anim?.cancel()
                val from = (left.toFloat() / total).coerceIn(0f, 1f)
                h.anim = ValueAnimator.ofFloat(from, 0f).apply {
                    duration = left
                    interpolator = android.view.animation.LinearInterpolator()
                    addUpdateListener {
                        val width = (h.waitTrack.width * (it.animatedValue as Float)).toInt()
                        h.wait.layoutParams = h.wait.layoutParams.also { p -> p.width = width }
                    }
                    start()
                }
            }
        } else {
            h.anim?.cancel()
            h.anim = null
            h.waitKey = -1
            h.waitTrack.visibility = View.GONE
        }

        // the voice volume: shown while the voice volume is managed; not fought over while it is being dragged
        val volume = (s["volume"] as? Number)?.toInt() ?: -1
        h.volRow.visibility = if (volume >= 0 && state != "error") View.VISIBLE else View.GONE
        if (volume >= 0 && !h.dragging) {
            h.volBar.progress = volume
            h.volText.text = "$volume %"
            h.volIcon.text = volumeGlyph(volume)
        }

        // buttons: created once (a press must not land on a view that is replaced a moment later), only shown or hidden here
        fun show(b: TextView, label: String, visible: Boolean) {
            b.text = label
            b.visibility = if (visible && label.isNotEmpty()) View.VISIBLE else View.GONE
        }
        show(h.done, labels["done"].orEmpty(), state == "listening")
        show(h.again, labels["again"].orEmpty(), state == "error")
        show(h.end, labels["end"].orEmpty(), state != "error" && inConversation)
        h.buttons.visibility = if (state == "error" || state == "listening" || inConversation) View.VISIBLE else View.GONE
    }

    private fun act(action: String) {
        EventBus.emit("bubble_action", mapOf("action" to action))
    }

    private fun add(ctx: Context): Boolean {
        if (!available(ctx)) return false
        val svc = SidecarAccessibilityService.instance
        val owner: Context = svc ?: ctx
        val wm = owner.getSystemService(WindowManager::class.java)

        val card = LinearLayout(owner).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(owner, 18), dp(owner, 12), dp(owner, 18), dp(owner, 16))
            background = GradientDrawable().apply {
                cornerRadius = dp(owner, 28).toFloat()
                setColor(Color.parseColor("#FF201C27"))
                setStroke(dp(owner, 1), Color.parseColor("#4A4458"))
            }
            setOnClickListener { act("expand") }
        }
        val header = LinearLayout(owner).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val status = TextView(owner).apply { setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f); typeface = Typeface.DEFAULT_BOLD }
        val close = TextView(owner).apply {
            text = "✕"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            setTextColor(Color.parseColor("#CAC4D0"))
            gravity = Gravity.CENTER
            setOnClickListener { act("close") }
        }
        header.addView(status, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        header.addView(close, LinearLayout.LayoutParams(dp(owner, 44), dp(owner, 44)))
        card.addView(header)

        val wave = WaveView(owner)
        card.addView(wave, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(owner, 40)))

        val user = TextView(owner).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTextColor(Color.parseColor("#EADDFF"))
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
            setPadding(dp(owner, 14), dp(owner, 8), dp(owner, 14), dp(owner, 8))
            background = GradientDrawable().apply { cornerRadius = dp(owner, 18).toFloat(); setColor(Color.parseColor("#4F378B")) }
        }
        card.addView(user, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.END
            topMargin = dp(owner, 8)
        })
        val answer = TextView(owner).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            maxLines = 6
            ellipsize = TextUtils.TruncateAt.END
        }
        card.addView(answer, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(owner, 10) })

        val volRow = LinearLayout(owner).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val volIcon = TextView(owner).apply { setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f); gravity = Gravity.CENTER }
        val tint = android.content.res.ColorStateList.valueOf(Color.parseColor("#CFBCFF"))
        val volBar = android.widget.SeekBar(owner).apply {
            max = 100
            progressTintList = tint
            thumbTintList = tint
            progressBackgroundTintList = android.content.res.ColorStateList.valueOf(Color.parseColor("#4A4458"))
        }
        val volText = TextView(owner).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTextColor(Color.parseColor("#CAC4D0"))
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
        }
        volRow.addView(volIcon, LinearLayout.LayoutParams(dp(owner, 28), ViewGroup.LayoutParams.WRAP_CONTENT))
        volRow.addView(volBar, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        volRow.addView(volText, LinearLayout.LayoutParams(dp(owner, 52), ViewGroup.LayoutParams.WRAP_CONTENT))
        card.addView(volRow, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(owner, 36)).apply { topMargin = dp(owner, 8) })

        val track = android.widget.FrameLayout(owner).apply {
            background = GradientDrawable().apply { cornerRadius = dp(owner, 2).toFloat(); setColor(Color.parseColor("#33CFBCFF")) }
        }
        val waitBar = View(owner).apply { background = GradientDrawable().apply { cornerRadius = dp(owner, 2).toFloat(); setColor(Color.parseColor("#CFBCFF")) } }
        track.addView(waitBar, android.widget.FrameLayout.LayoutParams(0, dp(owner, 3)))
        card.addView(track, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(owner, 3)).apply { topMargin = dp(owner, 12) })

        val buttons = LinearLayout(owner).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        fun makeButton(action: String, filled: Boolean): TextView {
            val b = pill(owner, "", filled) { act(action) }
            buttons.addView(b, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(owner, 40)).apply { marginEnd = dp(owner, 8) })
            return b
        }
        val doneButton = makeButton("done", true)
        val againButton = makeButton("again", true)
        val endButton = makeButton("end", false)
        card.addView(buttons, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(owner, 12) })

        val metrics = owner.resources.displayMetrics
        val width = min(dp(owner, WIDTH_DP), metrics.widthPixels - 2 * dp(owner, SIDE_MARGIN_DP))
        val type = if (svc != null) WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY else WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        val lp = WindowManager.LayoutParams(
            width, ViewGroup.LayoutParams.WRAP_CONTENT, type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = dp(owner, BOTTOM_MARGIN_DP)
        }
        val ok = runCatching { wm.addView(card, lp) }.isSuccess
        if (!ok) return false
        card.alpha = 0f
        card.translationY = dp(owner, 40).toFloat()
        card.animate().alpha(1f).translationY(0f).setDuration(180).start()
        root = card
        windowManager = wm
        val h = Holder(status, close, wave, user, answer, waitBar, track, buttons, doneButton, endButton, againButton)
        h.volRow = volRow
        h.volBar = volBar
        h.volIcon = volIcon
        h.volText = volText
        volBar.setOnSeekBarChangeListener(object : android.widget.SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(bar: android.widget.SeekBar, progress: Int, fromUser: Boolean) {
                if (!fromUser) return
                volText.text = "$progress %"
                volIcon.text = volumeGlyph(progress)
                val now = System.currentTimeMillis()
                if (now - h.lastVolumeSent > 120) {
                    h.lastVolumeSent = now
                    EventBus.emit("bubble_action", mapOf("action" to "volume", "percent" to progress))
                }
            }

            override fun onStartTrackingTouch(bar: android.widget.SeekBar) {
                h.dragging = true
            }

            override fun onStopTrackingTouch(bar: android.widget.SeekBar) {
                h.dragging = false
                EventBus.emit("bubble_action", mapOf("action" to "volume", "percent" to bar.progress))
            }
        })
        holder = h
        return true
    }

    private fun remove() {
        val v = root ?: return
        holder?.anim?.cancel()
        holder?.wave?.stop()
        runCatching { windowManager?.removeView(v) }
        root = null
        windowManager = null
        holder = null
    }

    private fun pill(ctx: Context, label: String, filled: Boolean, onClick: () -> Unit) = TextView(ctx).apply {
        text = label
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setPadding(dp(ctx, 18), 0, dp(ctx, 18), 0)
        setTextColor(if (filled) Color.parseColor("#381E72") else Color.parseColor("#CFBCFF"))
        background = GradientDrawable().apply {
            cornerRadius = dp(ctx, 20).toFloat()
            if (filled) setColor(Color.parseColor("#CFBCFF")) else setStroke(dp(ctx, 1), Color.parseColor("#938F99"))
        }
        setOnClickListener { onClick() }
    }

    private fun volumeGlyph(percent: Int) = when {
        percent <= 0 -> "🔇"
        percent < 40 -> "🔈"
        percent < 75 -> "🔉"
        else -> "🔊"
    }

    private fun dp(ctx: Context, v: Int) = (v * ctx.resources.displayMetrics.density).toInt()

    /** The bars: follow the microphone level while listening, a slow ripple while thinking and speaking. */
    private class WaveView(ctx: Context) : View(ctx) {
        var mode = "listening"
        var accent = Color.WHITE
        private val levels = ArrayDeque<Float>()
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val rect = RectF()
        private var running = true

        fun push(level: Float) {
            levels.addLast(level)
            while (levels.size > BARS) levels.removeFirst()
            if (running) postInvalidateOnAnimation()
        }

        fun stop() {
            running = false
        }

        override fun onDraw(canvas: Canvas) {
            val w = width.toFloat()
            val h = height.toFloat()
            val gap = w / BARS
            val bar = gap * 0.55f
            paint.color = accent
            val t = System.currentTimeMillis() / 600.0
            for (i in 0 until BARS) {
                val a = if (mode == "listening") {
                    val idx = i - (BARS - levels.size)
                    if (idx >= 0) levels[idx] else 0f
                } else {
                    (0.25f + 0.2f * sin(t * 2 * PI / 3 + i * 0.35).toFloat()).coerceAtLeast(0.05f)
                }
                val bh = max(bar, abs(a).coerceAtMost(1f) * h)
                val cx = gap * i + gap / 2
                rect.set(cx - bar / 2, (h - bh) / 2, cx + bar / 2, (h + bh) / 2)
                canvas.drawRoundRect(rect, bar / 2, bar / 2, paint)
            }
            if (mode != "listening" && running) postInvalidateDelayed(60)
        }

        companion object {
            const val BARS = 32
        }
    }
}
