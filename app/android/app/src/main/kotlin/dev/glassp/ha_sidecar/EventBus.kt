package dev.glassp.ha_sidecar

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Native -> Dart event stream. Events emitted while no Dart listener is attached are
 * buffered (bounded) and flushed on attach, so alarm/lockdown events are not lost.
 */
object EventBus {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private val buffer = ArrayDeque<Map<String, Any?>>()

    fun attach(s: EventChannel.EventSink) {
        main.post {
            sink = s
            while (buffer.isNotEmpty()) s.success(buffer.removeFirst())
        }
    }

    fun detach() {
        main.post { sink = null }
    }

    fun emit(type: String, data: Map<String, Any?> = emptyMap()) {
        main.post {
            val event = mapOf("type" to type, "data" to data)
            val s = sink
            if (s != null) {
                s.success(event)
            } else {
                buffer.addLast(event)
                while (buffer.size > 50) buffer.removeFirst()
            }
        }
    }
}
