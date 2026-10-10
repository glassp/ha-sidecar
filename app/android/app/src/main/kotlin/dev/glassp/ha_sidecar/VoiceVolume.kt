package dev.glassp.ha_sidecar

import android.content.Context
import android.media.AudioManager

/**
 * Voice answers, announcements and the pings play on the media stream (the assistant usage maps to it). The tablet can be kept
 * silent the rest of the time: during a voice session the media volume is set to the configured voice volume, and when the
 * session is over the previous level comes back.
 *
 *  - [raise] is idempotent: the level from before the first call is the one that is restored.
 *  - [restore] puts it back only if nobody touched the volume meanwhile (someone who turned it up or down during the answer
 *    keeps their choice).
 *  - The previous level is also written to disk, so that a crash or a kill during an answer cannot leave the tablet loud:
 *    [restoreStale] (at start-up) puts it back.
 */
object VoiceVolume {
    private const val PREFS = "voice_volume"
    private const val KEY_PREVIOUS = "previous"
    private const val KEY_APPLIED = "applied"

    private var raised = false

    fun raise(ctx: Context, percent: Int) {
        val am = ctx.getSystemService(AudioManager::class.java) ?: return
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val target = Math.round(percent.coerceIn(0, 100) / 100f * max)
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!raised) {
            prefs.edit()
                .putInt(KEY_PREVIOUS, am.getStreamVolume(AudioManager.STREAM_MUSIC))
                .putInt(KEY_APPLIED, target)
                .apply()
            raised = true
        } else {
            prefs.edit().putInt(KEY_APPLIED, target).apply()
        }
        // flags = 0: no volume panel pops up over the answer
        runCatching { am.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0) }
    }

    fun restore(ctx: Context) {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.contains(KEY_PREVIOUS)) return
        val am = ctx.getSystemService(AudioManager::class.java)
        val previous = prefs.getInt(KEY_PREVIOUS, -1)
        val applied = prefs.getInt(KEY_APPLIED, -1)
        prefs.edit().clear().apply()
        raised = false
        if (am == null || previous < 0) return
        val now = am.getStreamVolume(AudioManager.STREAM_MUSIC)
        if (now == applied) runCatching { am.setStreamVolume(AudioManager.STREAM_MUSIC, previous, 0) }
    }

    /** At start-up: a level left over from a process that died during an answer. */
    fun restoreStale(ctx: Context) {
        if (!raised) restore(ctx)
    }

    /** The media volume as a percentage (for the status, so a test can see what the tablet does). */
    fun percent(ctx: Context): Int {
        val am = ctx.getSystemService(AudioManager::class.java) ?: return -1
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        return Math.round(am.getStreamVolume(AudioManager.STREAM_MUSIC) * 100f / max)
    }
}
