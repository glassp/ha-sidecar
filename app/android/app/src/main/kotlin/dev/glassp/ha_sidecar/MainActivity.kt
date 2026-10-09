package dev.glassp.ha_sidecar

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/** UI host only. The engine (and with it the HA connection) lives in [SidecarEngine]. */
class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine = SidecarEngine.get(context)

    // Channels and plugins are registered once when the engine is created.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {}

    override fun shouldDestroyEngineWithHost(): Boolean = false
}
