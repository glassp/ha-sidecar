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
    const val FRAME_SAMPLES = 1_600 // 100 ms
    const val MAX_RECORD_MS = 30_000L // safety stop: Home Assistant normally ends the turn long before

    @Volatile var session: String? = null
        private set
    @Volatile private var recorder: Thread? = null
    @Volatile var error: String? = null
        private set

    private val main = Handler(Looper.getMainLooper())

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
        session = id
        error = null
        return try {
            ctx.startForegroundService(Intent(ctx, VoiceService::class.java))
            null
        } catch (e: Exception) {
            session = null
            error = "start_blocked: ${e.javaClass.simpleName}"
            "mic_failed"
        }
    }

    @Synchronized
    fun stop(ctx: Context) {
        session = null
        recorder = null // the loop notices and ends
        ctx.stopService(Intent(ctx, VoiceService::class.java))
    }

    /** Runs on the service's thread: reads the microphone until [stop] or the safety limit. */
    @Suppress("MissingPermission")
    internal fun record(ctx: Context, id: String) {
        val min = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val rec = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT, maxOf(min, FRAME_SAMPLES * 2 * 4),
            )
        } catch (e: Exception) {
            fail(ctx, id, "mic_failed")
            return
        }
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            rec.release()
            fail(ctx, id, "mic_failed")
            return
        }
        val me = Thread.currentThread()
        recorder = me
        val buf = ShortArray(FRAME_SAMPLES)
        val started = System.currentTimeMillis()
        try {
            rec.startRecording()
            while (session == id && recorder === me) {
                if (System.currentTimeMillis() - started > MAX_RECORD_MS) {
                    EventBus.emit("voice_record_timeout", mapOf("session" to id))
                    break
                }
                var filled = 0
                while (filled < FRAME_SAMPLES && session == id) {
                    val n = rec.read(buf, filled, FRAME_SAMPLES - filled)
                    if (n <= 0) {
                        fail(ctx, id, "mic_failed")
                        return
                    }
                    filled += n
                }
                if (filled < FRAME_SAMPLES) break
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
        } finally {
            runCatching { rec.stop() }
            rec.release()
        }
    }

    private fun fail(ctx: Context, id: String, code: String) {
        error = code
        if (session == id) session = null
        EventBus.emit("voice_record_error", mapOf("session" to id, "code" to code))
        ctx.stopService(Intent(ctx, VoiceService::class.java))
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
        val n = Notification.Builder(this, "voice")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Listening")
            .setContentText("The microphone is only used while the assistant listens")
            .setOngoing(true)
            .build()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(4713, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else startForeground(4713, n)
        } catch (e: Exception) {
            val id = Voice.session
            EventBus.emit("voice_record_error", mapOf("session" to id, "code" to "mic_blocked"))
            stopSelf()
            return START_NOT_STICKY
        }
        val id = Voice.session
        if (id == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        Thread({ Voice.record(applicationContext, id) }, "voice-record").start()
        return START_NOT_STICKY
    }
}
