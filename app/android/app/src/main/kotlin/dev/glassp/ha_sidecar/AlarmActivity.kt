package dev.glassp.ha_sidecar

import android.app.Activity
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextClock
import android.widget.TextView

/** Full-screen ringing UI shown over the lock screen and over the locked-down kiosk. */
class AlarmActivity : Activity() {
    private val ended = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = finish()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (AlarmService.ringingId == null) {
            finish()
            return
        }
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        getSystemService(KeyguardManager::class.java).requestDismissKeyguard(this, null)

        val label = AlarmStore.get(this, AlarmService.ringingId!!)?.label.orEmpty()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.BLACK)
            setPadding(48, 48, 48, 48)
        }
        TextClock(this).apply {
            format24Hour = "HH:mm"
            format12Hour = "h:mm"
            textSize = 96f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            root.addView(this)
        }
        TextView(this).apply {
            text = label
            textSize = 28f
            setTextColor(Color.LTGRAY)
            gravity = Gravity.CENTER
            setPadding(0, 16, 0, 64)
            root.addView(this)
        }
        Button(this).apply {
            text = "Snooze"
            textSize = 24f
            setOnClickListener { AlarmService.snooze(this@AlarmActivity) }
            root.addView(this)
        }
        Button(this).apply {
            text = "Dismiss"
            textSize = 24f
            setOnClickListener { AlarmService.stop(this@AlarmActivity) }
            root.addView(this)
        }
        setContentView(root)

        val filter = IntentFilter(AlarmService.ACTION_ENDED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(ended, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(ended, filter)
        }
    }

    override fun onDestroy() {
        runCatching { unregisterReceiver(ended) }
        super.onDestroy()
    }
}
