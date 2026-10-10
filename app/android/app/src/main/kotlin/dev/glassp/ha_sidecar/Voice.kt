package dev.glassp.ha_sidecar

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Base64
import kotlin.math.sqrt

/**
 * Microphone capture and answer playback for the Assist satellite (docs/VOICE.md). The audio goes to Dart as
 * `voice_frame` events (100 ms of 16 kHz mono PCM16, base64, plus a 0..1 level) because the Home Assistant connection
 * lives there; Dart sends them on. Recording runs in a microphone foreground service so it keeps working
 * when the sidecar is not the visible app.
 */
object Voice {
    const val SAMPLE_RATE = 16_000
    const val FRAME_SAMPLES = WakeWordEngine.CHUNK // 80 ms: one frame for the wake word model and for Home Assistant
    const val MAX_RECORD_MS = 30_000L // safety stop: Home Assistant normally ends the turn long before
    private const val COOLDOWN_MS = 2_000L // after a turn or a detection the wake word stays quiet for a moment

    @Volatile var session: String? = null
        private set
    @Volatile private var sessionStartedAt = 0L
    @Volatile private var micThread: Thread? = null
    @Volatile var error: String? = null
        private set

    private val main = Handler(Looper.getMainLooper())

    /** Debug builds only (see [WakeWordDebug]): frames played into the loop instead of the microphone, 80 ms apart. */
    @Volatile var debugInject: java.util.concurrent.ConcurrentLinkedQueue<ShortArray>? = null

    fun hasPermission(ctx: Context) =
        ctx.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    /** A device owner can grant the microphone silently; otherwise the user is asked once. */
    fun ensurePermission(ctx: Context) {
        if (hasPermission(ctx) || !KioskController.isDeviceOwner(ctx)) return
        runCatching {
            ctx.getSystemService(android.app.admin.DevicePolicyManager::class.java).setPermissionGrantState(
                KioskController.admin(ctx), ctx.packageName, Manifest.permission.RECORD_AUDIO,
                android.app.admin.DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED,
            )
        }
    }

    fun requestPermission(ctx: Context) {
        ensurePermission(ctx)
        if (hasPermission(ctx)) return
        ctx.startActivity(
            Intent(ctx, PermissionActivity::class.java).putExtra("perm", Manifest.permission.RECORD_AUDIO)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    /** Starts recording for [id]. @return null on success or an error code for Dart (`mic_permission`, `mic_busy`, `mic_failed`). */
    @Synchronized
    fun start(ctx: Context, id: String): String? {
        ensurePermission(ctx)
        if (!hasPermission(ctx)) {
            requestPermission(ctx)
            return "mic_permission"
        }
        if (session != null) return "mic_busy"
        error = null
        sessionStartedAt = System.currentTimeMillis()
        session = id
        return if (ensureMic(ctx)) null else {
            session = null
            "mic_failed"
        }
    }

    /** Ends the turn's recording; the microphone stays open only if the wake word needs it. */
    @Synchronized
    fun stop(@Suppress("UNUSED_PARAMETER") ctx: Context) {
        session = null
    }

    /** Makes sure the microphone service runs (it ends by itself when neither a turn nor the wake word needs it). */
    @Synchronized
    fun ensureMic(ctx: Context): Boolean {
        if (micThread?.isAlive == true) return true
        return try {
            ctx.startForegroundService(Intent(ctx, VoiceService::class.java))
            true
        } catch (e: Exception) {
            error = "start_blocked: ${e.javaClass.simpleName}"
            false
        }
    }

    internal fun micRunning() = micThread?.isAlive == true

    /**
     * The one microphone loop (runs on the service's thread). While a turn is active every frame goes to Dart (and from there to
     * Home Assistant); otherwise, if the wake word is on, frames go to the wake word engine.
     */
    @Suppress("MissingPermission")
    internal fun micLoop(ctx: Context) {
        val me = Thread.currentThread()
        micThread = me
        val min = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val rec = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT, maxOf(min, FRAME_SAMPLES * 2 * 6),
            )
        } catch (e: Exception) {
            micFailed(ctx, "mic_failed")
            return
        }
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            rec.release()
            micFailed(ctx, "mic_failed")
            return
        }
        var engine: WakeWordEngine? = null
        var engineWords: List<String> = emptyList()
        var quietUntil = 0L
        var wasTurn = false
        val buf = ShortArray(FRAME_SAMPLES)
        try {
            rec.startRecording()
            while (micThread === me && (session != null || WakeWord.wanted)) {
                var filled = 0
                val injected = debugInject?.poll()
                if (injected != null) {
                    System.arraycopy(injected, 0, buf, 0, FRAME_SAMPLES)
                    filled = FRAME_SAMPLES
                    Thread.sleep(80)
                }
                while (filled < FRAME_SAMPLES) {
                    val n = rec.read(buf, filled, FRAME_SAMPLES - filled)
                    if (n <= 0) {
                        micFailed(ctx, "mic_failed")
                        return
                    }
                    filled += n
                }
                val id = session
                val now = System.currentTimeMillis()
                if (id != null) {
                    wasTurn = true
                    if (now - sessionStartedAt > MAX_RECORD_MS) {
                        EventBus.emit("voice_record_timeout", mapOf("session" to id))
                        session = null
                        continue
                    }
                    emitFrame(id, buf)
                } else if (WakeWord.wanted) {
                    if (wasTurn) {
                        wasTurn = false
                        quietUntil = now + COOLDOWN_MS
                        engine?.reset()
                    }
                    val words = WakeWord.activeIds
                    if (words.isEmpty()) {
                        Thread.sleep(80) // the chosen models are still downloading: nothing to listen for yet
                        continue
                    }
                    if (engine == null || engineWords != words) {
                        engine?.close()
                        engine = runCatching { WakeWordEngine(ctx, words) }.getOrElse {
                            android.util.Log.e("WakeWord", "engine failed", it)
                            WakeWord.engineFailed(it)
                            null
                        }
                        engineWords = words
                        WakeWord.listening = engine != null
                    }
                    val best = engine?.feed(buf)?.maxByOrNull { it.value }
                    WakeWord.lastScore = best?.value ?: 0f
                    if (best != null && now >= quietUntil && best.value >= WakeWord.threshold) {
                        quietUntil = now + COOLDOWN_MS
                        engine?.reset()
                        WakeWord.detected(best.key, best.value)
                    }
                }
            }
        } finally {
            runCatching { rec.stop() }
            rec.release()
            engine?.close()
            WakeWord.listening = false
            if (micThread === me) micThread = null
        }
    }

    private fun emitFrame(id: String, buf: ShortArray) {
        val bytes = ByteArray(FRAME_SAMPLES * 2)
        var sum = 0.0
        for (i in 0 until FRAME_SAMPLES) {
            val s = buf[i].toInt()
            bytes[2 * i] = (s and 0xff).toByte()
            bytes[2 * i + 1] = ((s shr 8) and 0xff).toByte()
            sum += s.toDouble() * s
        }
        val level = (sqrt(sum / FRAME_SAMPLES) / 8000.0).coerceIn(0.0, 1.0)
        EventBus.emit(
            "voice_frame",
            mapOf("session" to id, "data" to Base64.encodeToString(bytes, Base64.NO_WRAP), "level" to level),
        )
    }

    private fun micFailed(ctx: Context, code: String) {
        error = code
        val id = session
        session = null
        micThread = null
        if (id != null) EventBus.emit("voice_record_error", mapOf("session" to id, "code" to code))
        if (WakeWord.wanted) WakeWord.micFailed(code)
    }

    // --- ping sounds ---------------------------------------------------------------------------------

    /**
     * A short synthesized ping, so the user hears when the assistant starts listening (`start`, rising) and when the conversation
     * is over (`end`, falling). [done] is called when it has been played, so recording can start right after it and not hear it.
     */
    fun ping(kind: String, done: () -> Unit) {
        val notes = if (kind == "end") listOf(700.0 to 90, 440.0 to 140) else listOf(660.0 to 70, 990.0 to 100)
        val rate = 22_050
        val pcm = ArrayList<Short>()
        for ((hz, ms) in notes) {
            val n = rate * ms / 1000
            for (i in 0 until n) {
                // a short fade at both ends so the blip does not click
                val env = minOf(1.0, i / (rate * 0.008), (n - i) / (rate * 0.012))
                pcm.add((Math.sin(2 * Math.PI * hz * i / rate) * env * 9000).toInt().toShort())
            }
        }
        val data = pcm.toShortArray()
        val ms = notes.sumOf { it.second }
        try {
            val track = android.media.AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANT).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build(),
                )
                .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(rate).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setBufferSizeInBytes(data.size * 2)
                .setTransferMode(android.media.AudioTrack.MODE_STATIC)
                .build()
            track.write(data, 0, data.size)
            track.play()
            android.util.Log.i("VoicePing", kind)
            main.postDelayed({
                runCatching { track.stop() }
                track.release()
                done()
            }, ms + 40L)
        } catch (e: Exception) {
            android.util.Log.w("VoicePing", "ping failed: $e")
            main.post(done)
        }
    }

    // --- playback ------------------------------------------------------------------------------------

    private var player: MediaPlayer? = null
    private var focus: AudioFocusRequest? = null
    private var playbackDone: ((String?) -> Unit)? = null
    private var appCtx: Context? = null

    /** Plays [url] (an http(s) address); [done] gets null when it played to the end, else an error code. Interrupts a running playback. */
    fun play(ctx: Context, url: String, done: (String?) -> Unit) {
        main.post {
            appCtx = ctx.applicationContext
            stopPlaybackNow("interrupted")
            val am = ctx.getSystemService(AudioManager::class.java)
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK).setAudioAttributes(attrs).build()
            am.requestAudioFocus(req)
            focus = req
            playbackDone = done
            val mp = MediaPlayer()
            player = mp
            try {
                mp.setAudioAttributes(attrs)
                mp.setDataSource(url)
                mp.setOnPreparedListener { it.start() }
                mp.setOnCompletionListener { finishPlayback(ctx, mp, null) }
                mp.setOnErrorListener { _, what, extra ->
                    finishPlayback(ctx, mp, "playback_error:$what/$extra")
                    true
                }
                mp.prepareAsync()
                // a stalled download must not block the turn forever
                main.postDelayed({ if (player === mp && !mp.isPlaying) finishPlayback(ctx, mp, "playback_timeout") }, 20_000)
            } catch (e: Exception) {
                finishPlayback(ctx, mp, "playback_error:${e.javaClass.simpleName}")
            }
        }
    }

    fun stopPlayback(ctx: Context) {
        main.post { stopPlaybackNow("interrupted") }
    }

    private fun stopPlaybackNow(reason: String) {
        val mp = player ?: return
        val ctx = appCtx ?: return releaseOnly(mp, reason)
        finishPlayback(ctx, mp, reason)
    }

    private fun releaseOnly(mp: MediaPlayer, reason: String) {
        player = null
        runCatching { mp.release() }
        val cb = playbackDone
        playbackDone = null
        cb?.invoke(reason)
    }

    private fun finishPlayback(ctx: Context, mp: MediaPlayer, error: String?) {
        if (player !== mp) return
        player = null
        runCatching { if (mp.isPlaying) mp.stop() }
        runCatching { mp.release() }
        focus?.let { runCatching { ctx.getSystemService(AudioManager::class.java).abandonAudioFocusRequest(it) } }
        focus = null
        val cb = playbackDone
        playbackDone = null
        cb?.invoke(error)
    }
}

class VoiceService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("voice", "Voice assistant", NotificationManager.IMPORTANCE_LOW))
        val listeningForWord = WakeWord.wanted && Voice.session == null
        val n = Notification.Builder(this, "voice")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle(if (listeningForWord) "Listening for the wake word" else "Listening")
            .setContentText(
                if (listeningForWord) "Audio is analysed on the device and never stored or sent until the wake word is heard"
                else "The microphone is only used while the assistant listens",
            )
            .setOngoing(true)
            .build()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(4713, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else startForeground(4713, n)
        } catch (e: Exception) {
            val id = Voice.session
            if (id != null) EventBus.emit("voice_record_error", mapOf("session" to id, "code" to "mic_blocked"))
            if (WakeWord.wanted) WakeWord.micFailed("start_blocked")
            stopSelf()
            return START_NOT_STICKY
        }
        if (Voice.micRunning()) return START_NOT_STICKY // already looping: it picks up the new need by itself
        if (Voice.session == null && !WakeWord.wanted) {
            stopSelf()
            return START_NOT_STICKY
        }
        Thread({
            // a need that arrived while the loop was ending (a turn, the wake word switched on) starts it again
            do {
                Voice.micLoop(applicationContext)
            } while (Voice.error == null && (Voice.session != null || WakeWord.wanted))
            stopSelf()
        }, "voice-mic").start()
        return START_NOT_STICKY
    }
}
