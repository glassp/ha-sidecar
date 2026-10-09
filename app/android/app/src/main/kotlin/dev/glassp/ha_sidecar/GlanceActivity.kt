package dev.glassp.ha_sidecar

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.format.DateFormat
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.TextClock
import android.widget.TextView
import org.json.JSONArray
import java.util.Date

/**
 * "At a glance": clock, date, next alarm and a few Home Assistant values on pure black.
 * Shown by [BrightnessController] after glance_after_s without interaction or presence; any touch
 * or detected presence dismisses it and returns to the HA app. Drawn natively so it works while
 * the HA app (and the Flutter UI) is not visible.
 */
class GlanceActivity : Activity() {
    companion object {
        @Volatile var showing = false
            private set
        private var instance: GlanceActivity? = null
        private val main = Handler(Looper.getMainLooper())

        fun show(ctx: Context): Boolean {
            if (showing) return true
            val launcher: Context = SidecarAccessibilityService.instance ?: ctx
            return runCatching {
                launcher.startActivity(
                    Intent(launcher, GlanceActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
                )
            }.isSuccess
        }

        fun dismiss() {
            main.post { instance?.finish() }
        }

        /** New HA values arrived while the screen is up. */
        fun refresh() {
            main.post { instance?.render() }
        }
    }

    private lateinit var itemsGrid: GridLayout
    private lateinit var alarmView: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
        showing = true
        EventBus.emit("status_changed")

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.BLACK)
            setPadding(64, 64, 64, 64)
        }
        TextClock(this).apply {
            format24Hour = "HH:mm"
            format12Hour = "h:mm"
            textSize = 120f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            root.addView(this)
        }
        TextClock(this).apply {
            val pattern = DateFormat.getBestDateTimePattern(resources.configuration.locales[0], "EEEEdMMMM")
            format24Hour = pattern
            format12Hour = pattern
            textSize = 28f
            setTextColor(Color.LTGRAY)
            gravity = Gravity.CENTER
            root.addView(this)
        }
        alarmView = TextView(this).apply {
            textSize = 22f
            setTextColor(Color.GRAY)
            gravity = Gravity.CENTER
            setPadding(0, 16, 0, 48)
            root.addView(this)
        }
        itemsGrid = GridLayout(this).apply {
            columnCount = 3
            alignmentMode = GridLayout.ALIGN_BOUNDS
            root.addView(this, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        setContentView(root)
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        render()
    }

    fun render() {
        val next = AlarmScheduler.nextAlarmMillis(this)
        alarmView.text = if (next != null) "⏰ " + DateFormat.format("EEE HH:mm", Date(next)) else ""

        itemsGrid.removeAllViews()
        val items = runCatching { JSONArray(Prefs.glanceItemsJson(this)) }.getOrDefault(JSONArray())
        for (i in 0 until items.length().coerceAtMost(9)) {
            val o = items.getJSONObject(i)
            val cell = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(40, 16, 40, 16)
            }
            TextView(this).apply {
                text = o.optString("value")
                textSize = 36f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                cell.addView(this)
            }
            TextView(this).apply {
                text = o.optString("name")
                textSize = 16f
                setTextColor(Color.GRAY)
                gravity = Gravity.CENTER
                cell.addView(this)
            }
            itemsGrid.addView(cell)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_DOWN) {
            InteractionTracker.touch()
            finish()
        }
        return true
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        showing = false
        EventBus.emit("status_changed")
        super.onDestroy()
    }
}
