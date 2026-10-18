package dev.glassp.ha_sidecar

import android.content.Context
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AudioEffect
import android.media.audiofx.NoiseSuppressor

/**
 * What the microphone loop sets up, from the settings `echo_cancellation`, `noise_suppression` and `mic_source`. Pure, so that
 * the choice can be unit tested; the effects themselves ([MicEffects]) need a device.
 *
 *  - `echo_cancellation`: `auto` and `on` attach the platform's acoustic echo canceller when the device has one (they differ
 *    only in how the app reports a tablet that has none), `off` leaves the microphone as it was before the setting existed.
 *  - `noise_suppression`: the platform's noise suppressor, off by default (it changes the audio the wake word models hear).
 *  - `mic_source`: `auto` is the voice recognition source plus the effects above; `voice_communication` is the source Android
 *    tunes for calls, which may apply echo cancellation and automatic gain control by itself (the vendor decides).
 *  - Automatic gain control is never attached: it pumps the level, which the wake word and speech recognition do not like.
 */
data class MicPlan(val source: Int, val echo: Boolean, val noise: Boolean) {
    /** The source as a word, for logs and the status. */
    val sourceName get() = nameOf(source)

    companion object {
        val ECHO_MODES = setOf("auto", "on", "off")
        val SOURCES = setOf("auto", "voice_recognition", "voice_communication")

        fun of(cfg: Map<String, Any?>) = MicPlan(
            source = if (cfg["mic_source"] == "voice_communication") MediaRecorder.AudioSource.VOICE_COMMUNICATION
            else MediaRecorder.AudioSource.VOICE_RECOGNITION,
            echo = cfg["echo_cancellation"] != "off",
            noise = cfg["noise_suppression"] == true,
        )

        fun nameOf(source: Int) =
            if (source == MediaRecorder.AudioSource.VOICE_COMMUNICATION) "voice_communication" else "voice_recognition"
    }
}

/** What the diagnostic sensors say about one effect (the same words go to the app and to Home Assistant). */
object EffectState {
    const val ACTIVE = "active" // enabled on the microphone that is recording right now
    const val UNAVAILABLE = "unavailable" // the tablet has no such effect, or it could not be attached
    const val DISABLED = "disabled" // switched off in the settings
    const val IDLE = "idle" // wanted and supported, attached when the microphone next starts (it is not recording)

    fun of(wanted: Boolean, supported: Boolean, failed: Boolean, attached: Boolean) = when {
        !wanted -> DISABLED
        !supported || failed -> UNAVAILABLE
        attached -> ACTIVE
        else -> IDLE
    }
}

/**
 * The platform's audio effects on the microphone ([AcousticEchoCanceler], [NoiseSuppressor]) and what they report. Effects can
 * be missing, throw or return null depending on the vendor, so every call is guarded: a failure is logged and shows as
 * `unavailable`, the microphone loop carries on without the effect.
 */
object MicEffects {
    private const val TAG = "MicEffects"

    /** The setup the settings ask for; the microphone loop ends (and is started again by its service) when it changes. */
    @Volatile var plan: MicPlan = MicPlan.of(emptyMap())
        private set

    @Volatile private var recordingSource = -1 // the source of the recorder that runs now, -1 = none
    @Volatile private var echoAttached = false
    @Volatile private var noiseAttached = false
    @Volatile private var echoFailed = false // the last attempt to attach threw, returned null or would not enable
    @Volatile private var noiseFailed = false

    // whether the device has the effect does not change while it runs; asking costs a round trip to the audio server
    private val echoSupported by lazy { runCatching { AcousticEchoCanceler.isAvailable() }.getOrDefault(false) }
    private val noiseSupported by lazy { runCatching { NoiseSuppressor.isAvailable() }.getOrDefault(false) }

    /** Re-reads the settings. Safe to call often; the caller announces the change. */
    fun refresh(ctx: Context) {
        plan = MicPlan.of(DisplayConfig.get(ctx))
    }

    /** The effects attached to one recorder (whose source is [source]); [close] releases them. */
    class Attached internal constructor(
        private val echo: AcousticEchoCanceler?,
        private val noise: NoiseSuppressor?,
        source: Int,
    ) : AutoCloseable {
        init {
            recordingSource = source
            echoAttached = echo != null
            noiseAttached = noise != null
            EventBus.emit("status_changed")
        }

        override fun close() {
            echo?.let { release("echo canceller", it) }
            noise?.let { release("noise suppressor", it) }
            recordingSource = -1
            echoAttached = false
            noiseAttached = false
            EventBus.emit("status_changed")
        }
    }

    /**
     * Attaches what [wanted] asks for to the recorder with [sessionId] (initialised, not yet recording) and keeps the result for
     * the status. Never throws.
     */
    fun attach(sessionId: Int, source: Int, wanted: MicPlan): Attached {
        echoFailed = false
        noiseFailed = false
        val echo = if (wanted.echo && echoSupported) {
            enabled("echo canceller") { AcousticEchoCanceler.create(sessionId) }.also { echoFailed = it == null }
        } else null
        val noise = if (wanted.noise && noiseSupported) {
            enabled("noise suppressor") { NoiseSuppressor.create(sessionId) }.also { noiseFailed = it == null }
        } else null
        android.util.Log.i(TAG, "source=${MicPlan.nameOf(source)} echo=${stateOf(echo)} noise=${stateOf(noise)}")
        return Attached(echo, noise, source)
    }

    private fun stateOf(fx: AudioEffect?) = if (fx != null) "on" else "off"

    /** Creates an effect with [create] and enables it; null (after releasing it) if anything goes wrong. */
    private fun <T : AudioEffect> enabled(name: String, create: () -> T?): T? {
        var fx: T? = null
        try {
            fx = create()
            if (fx == null) {
                android.util.Log.w(TAG, "$name: the platform returned none")
                return null
            }
            val rc = fx.setEnabled(true)
            if (rc != AudioEffect.SUCCESS || !fx.enabled) {
                android.util.Log.w(TAG, "$name: could not be enabled (status $rc)")
                release(name, fx)
                return null
            }
            return fx
        } catch (e: Exception) {
            android.util.Log.w(TAG, "$name failed", e)
            fx?.let { release(name, it) }
            return null
        }
    }

    private fun release(name: String, fx: AudioEffect) {
        try {
            fx.release()
        } catch (e: Exception) {
            android.util.Log.w(TAG, "$name: release failed", e)
        }
    }

    val echoState get() = EffectState.of(plan.echo, echoSupported, echoFailed, echoAttached)
    val noiseState get() = EffectState.of(plan.noise, noiseSupported, noiseFailed, noiseAttached)

    /** For logs: the setup the last wake word score was heard through. */
    fun label() =
        "source=${if (recordingSource >= 0) MicPlan.nameOf(recordingSource) else "none"} echo=$echoState noise=$noiseState"

    /** For the status; reads the settings first, so it is right also before the microphone ever ran in this process. */
    fun snapshot(ctx: Context): Map<String, Any?> {
        refresh(ctx)
        return mapOf(
            "echo_cancellation_state" to echoState,
            "noise_suppression_state" to noiseState,
            "mic_source_in_use" to if (recordingSource >= 0) MicPlan.nameOf(recordingSource) else null,
        )
    }
}
