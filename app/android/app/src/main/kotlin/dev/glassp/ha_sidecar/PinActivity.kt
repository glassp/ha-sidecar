package dev.glassp.ha_sidecar

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.TextView

/** Native PIN pad that disables lockdown. Pure code UI so it works without the Flutter engine. */
class PinActivity : Activity() {
    private val entered = StringBuilder()
    private lateinit var dots: TextView
    private lateinit var message: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        setShowWhenLocked(true)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.BLACK)
            setPadding(48, 48, 48, 48)
        }
        TextView(this).apply {
            text = "Enter PIN to leave kiosk mode"
            setTextColor(Color.WHITE)
            textSize = 20f
            gravity = Gravity.CENTER
            root.addView(this)
        }
        dots = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 36f
            typeface = Typeface.MONOSPACE
            gravity = Gravity.CENTER
            setPadding(0, 32, 0, 16)
            root.addView(this)
        }
        message = TextView(this).apply {
            setTextColor(Color.parseColor("#FF8A80"))
            gravity = Gravity.CENTER
            root.addView(this)
        }

        val grid = GridLayout(this).apply { columnCount = 3 }
        val keys = listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "OK")
        for (k in keys) {
            val b = Button(this).apply {
                text = k
                textSize = 22f
                setOnClickListener { onKey(k) }
            }
            val lp = GridLayout.LayoutParams().apply {
                width = 220
                height = 160
                setMargins(8, 8, 8, 8)
            }
            grid.addView(b, lp)
        }
        root.addView(
            grid,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        )
        Button(this).apply {
            text = "Cancel"
            setOnClickListener { finish() }
            root.addView(this)
        }
        setContentView(root)
        render()
    }

    private fun onKey(k: String) {
        when (k) {
            "C" -> if (entered.isNotEmpty()) entered.deleteCharAt(entered.length - 1)
            "OK" -> submit()
            else -> if (entered.length < 12) entered.append(k)
        }
        render()
    }

    private fun submit() {
        when (val r = Prefs.verifyPin(this, entered.toString())) {
            0L -> {
                KioskController.setLockdown(this, false)
                EventBus.emit("lockdown_disabled_by_pin")
                runCatching { stopLockTask() }
                finish()
            }
            -1L -> {
                message.text = "Wrong PIN"
                EventBus.emit("pin_failed", mapOf("failures" to Prefs.pinFails(this)))
            }
            else -> message.text = "Locked. Try again in ${r / 1000 + 1}s"
        }
        entered.clear()
    }

    private fun render() {
        dots.text = "●".repeat(entered.length).ifEmpty { " " }
    }
}
