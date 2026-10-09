package dev.glassp.ha_sidecar

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * One process-wide FlutterEngine. It is started by [KeepAliveService] (boot, process restart)
 * as well as by [MainActivity], and it outlives the activity: the HA connection and command
 * handling run in this engine's Dart isolate, so they keep working while the HA companion
 * app is in front and the sidecar UI is closed.
 */
object SidecarEngine {
    @Volatile
    private var engine: FlutterEngine? = null

    @Synchronized
    fun get(ctx: Context): FlutterEngine {
        engine?.let { return it }
        val app = ctx.applicationContext
        val e = FlutterEngine(app)
        GeneratedPluginRegistrant.registerWith(e)

        val messenger = e.dartExecutor.binaryMessenger
        MethodChannel(messenger, PlatformChannel.METHODS).setMethodCallHandler { call, result ->
            PlatformChannel.handle(app, call, result)
        }
        EventChannel(messenger, PlatformChannel.EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) = EventBus.attach(events)
            override fun onCancel(arguments: Any?) = EventBus.detach()
        })

        e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        engine = e
        return e
    }
}
