package dev.glassp.ha_sidecar

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject

/**
 * A labeled countdown ("batch 1") or count-up ("treadmill").
 *
 * Time is stored as segments so pausing works and a reboot loses nothing: while running, the elapsed time is
 * [elapsedBeforeMs] + (now - [startedAt]). A finished countdown stays (state `finished`) until it is dismissed.
 */
data class SidecarTimer(
    val id: String,
    val label: String,
    /** `countdown` or `countup`. */
    val kind: String,
    /** Countdown length; 0 for count-ups. */
    val durationMs: Long,
    /** `running`, `paused` or `finished`. */
    val state: String,
    val startedAt: Long = 0,
    val elapsedBeforeMs: Long = 0,
    /** Epoch ms when a countdown reached zero; the time since then is shown as overtime. */
    val finishedAt: Long = 0,
) {
    val isCountdown get() = kind == KIND_COUNTDOWN

    fun elapsedMs(now: Long): Long =
        elapsedBeforeMs + if (state == STATE_RUNNING) (now - startedAt).coerceAtLeast(0) else 0

    fun remainingMs(now: Long): Long =
        if (isCountdown) (durationMs - elapsedMs(now)).coerceAtLeast(0) else 0

    /** Epoch ms when a running countdown ends. */
    fun endsAt(now: Long): Long? =
        if (isCountdown && state == STATE_RUNNING) now + remainingMs(now) else null

    fun toJson(): JSONObject = JSONObject()
        .put("id", id).put("label", label).put("kind", kind).put("duration_ms", durationMs)
        .put("state", state).put("started_at", startedAt).put("elapsed_before_ms", elapsedBeforeMs)
        .put("finished_at", finishedAt)

    /** Snapshot for Dart / Home Assistant. [started] is the virtual start of a running count-up. */
    fun toMap(now: Long = System.currentTimeMillis()): Map<String, Any?> = mapOf(
        "id" to id, "label" to label, "kind" to kind, "state" to state,
        "duration_ms" to durationMs, "elapsed_ms" to elapsedMs(now), "remaining_ms" to remainingMs(now),
        "ends_at" to endsAt(now),
        "started_at" to if (state == STATE_RUNNING) now - elapsedMs(now) else null,
        "finished_at" to finishedAt.takeIf { state == STATE_FINISHED && it > 0 },
    )

    companion object {
        const val KIND_COUNTDOWN = "countdown"
        const val KIND_COUNTUP = "countup"
        const val STATE_RUNNING = "running"
        const val STATE_PAUSED = "paused"
        const val STATE_FINISHED = "finished"
        const val MAX_TIMERS = 20
        const val MAX_DURATION_MS = 99L * 3_600_000

        fun fromJson(o: JSONObject) = SidecarTimer(
            id = o.getString("id"),
            label = o.optString("label", ""),
            kind = o.optString("kind", KIND_COUNTDOWN),
            durationMs = o.optLong("duration_ms", 0),
            state = o.optString("state", STATE_RUNNING),
            startedAt = o.optLong("started_at", 0),
            elapsedBeforeMs = o.optLong("elapsed_before_ms", 0),
            finishedAt = o.optLong("finished_at", 0),
        )
    }
}

object TimerStore {
    fun all(ctx: Context): List<SidecarTimer> {
        val arr = runCatching { JSONArray(Prefs.timersJson(ctx)) }.getOrDefault(JSONArray())
        return (0 until arr.length()).mapNotNull { runCatching { SidecarTimer.fromJson(arr.getJSONObject(it)) }.getOrNull() }
    }

    private fun save(ctx: Context, list: List<SidecarTimer>) {
        val arr = JSONArray()
        list.forEach { arr.put(it.toJson()) }
        Prefs.setTimersJson(ctx, arr.toString())
    }

    fun get(ctx: Context, id: String) = all(ctx).firstOrNull { it.id == id }

    /** Replaces in place so the display order stays stable. */
    fun upsert(ctx: Context, timer: SidecarTimer) {
        val list = all(ctx)
        save(ctx, if (list.any { it.id == timer.id }) list.map { if (it.id == timer.id) timer else it } else list + timer)
    }

    fun remove(ctx: Context, id: String) = save(ctx, all(ctx).filter { it.id != id })
}

/** Exact wake-up when a countdown ends (USE_EXACT_ALARM is declared, no user permission needed). */
object TimerScheduler {
    const val ACTION_FIRE = "dev.glassp.ha_sidecar.TIMER_FIRE"

    private fun pending(ctx: Context, id: String) = PendingIntent.getBroadcast(
        ctx, ("timer:$id").hashCode(),
        Intent(ctx, TimerReceiver::class.java).setAction(ACTION_FIRE).putExtra("id", id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun schedule(ctx: Context, timer: SidecarTimer) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        val at = timer.endsAt(System.currentTimeMillis())
        if (at == null) am.cancel(pending(ctx, timer.id))
        else am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(ctx, timer.id))
    }

    fun cancel(ctx: Context, id: String) = ctx.getSystemService(AlarmManager::class.java).cancel(pending(ctx, id))
}

/** All timer operations. Every change is persisted, rescheduled and reported (event + status) in one place. */
object TimerEngine {
    class Invalid(message: String) : Exception(message)

    private fun now() = System.currentTimeMillis()

    private fun payload(t: SidecarTimer, extra: Map<String, Any?> = emptyMap()): Map<String, Any?> =
        mapOf("id" to t.id, "label" to t.label, "kind" to t.kind, "duration_s" to t.durationMs / 1000) + extra

    private fun report(type: String, t: SidecarTimer, extra: Map<String, Any?> = emptyMap()) {
        EventBus.emit(type, payload(t, extra))
        EventBus.emit("status_changed")
    }

    /** Starts (or restarts, if [id] exists) a timer. @throws Invalid for bad values. */
    fun start(ctx: Context, id: String, label: String, kind: String, durationMs: Long): SidecarTimer {
        if (kind != SidecarTimer.KIND_COUNTDOWN && kind != SidecarTimer.KIND_COUNTUP) throw Invalid("kind must be countdown or countup")
        if (id.isBlank() || id.length > 64) throw Invalid("id must be 1-64 characters")
        if (label.length > 64) throw Invalid("label too long")
        if (kind == SidecarTimer.KIND_COUNTDOWN && durationMs !in 1_000..SidecarTimer.MAX_DURATION_MS) {
            throw Invalid("duration must be between 1 second and 99 hours")
        }
        val all = TimerStore.all(ctx)
        if (all.none { it.id == id } && all.size >= SidecarTimer.MAX_TIMERS) throw Invalid("too many timers")
        if (AlarmService.ringingTimerId == id) AlarmService.stop(ctx) // restarting a ringing timer silences it
        val t = SidecarTimer(
            id, label.trim(), kind, if (kind == SidecarTimer.KIND_COUNTUP) 0 else durationMs,
            SidecarTimer.STATE_RUNNING, startedAt = now(),
        )
        TimerStore.upsert(ctx, t)
        TimerScheduler.schedule(ctx, t)
        report("timer_started", t)
        return t
    }

    fun pause(ctx: Context, id: String): Boolean {
        val t = TimerStore.get(ctx, id)?.takeIf { it.state == SidecarTimer.STATE_RUNNING } ?: return false
        val paused = t.copy(state = SidecarTimer.STATE_PAUSED, elapsedBeforeMs = t.elapsedMs(now()), startedAt = 0)
        TimerStore.upsert(ctx, paused)
        TimerScheduler.cancel(ctx, id)
        report("timer_paused", paused, mapOf("remaining_s" to paused.remainingMs(now()) / 1000))
        return true
    }

    fun resume(ctx: Context, id: String): Boolean {
        val t = TimerStore.get(ctx, id)?.takeIf { it.state == SidecarTimer.STATE_PAUSED } ?: return false
        val running = t.copy(state = SidecarTimer.STATE_RUNNING, startedAt = now())
        TimerStore.upsert(ctx, running)
        TimerScheduler.schedule(ctx, running)
        report("timer_resumed", running)
        return true
    }

    /** Removes a timer without ringing. */
    fun cancel(ctx: Context, id: String): Boolean {
        val t = TimerStore.get(ctx, id) ?: return false
        if (AlarmService.ringingTimerId == id) AlarmService.stop(ctx)
        TimerScheduler.cancel(ctx, id)
        TimerStore.remove(ctx, id)
        report("timer_cancelled", t)
        return true
    }

    /** Adds (or, negative, removes) time on a countdown; may be used on a finished one to run it again. */
    fun adjust(ctx: Context, id: String, deltaMs: Long): Boolean {
        val t = TimerStore.get(ctx, id)?.takeIf { it.isCountdown } ?: return false
        if (AlarmService.ringingTimerId == id) AlarmService.stop(ctx)
        val base = if (t.state == SidecarTimer.STATE_FINISHED) {
            t.copy(state = SidecarTimer.STATE_RUNNING, startedAt = now(), elapsedBeforeMs = t.durationMs, finishedAt = 0)
        } else t
        val duration = (base.durationMs + deltaMs).coerceIn(1_000, SidecarTimer.MAX_DURATION_MS)
        val changed = base.copy(durationMs = duration)
        // a countdown that is now already over finishes immediately
        TimerStore.upsert(ctx, changed)
        TimerScheduler.schedule(ctx, changed)
        report("timer_extended", changed, mapOf("delta_s" to deltaMs / 1000))
        if (changed.state == SidecarTimer.STATE_RUNNING && changed.remainingMs(now()) == 0L) fire(ctx, id)
        return true
    }

    /** The scheduled end of a countdown: mark it finished and ring. */
    fun fire(ctx: Context, id: String) {
        val t = TimerStore.get(ctx, id)?.takeIf { it.isCountdown && it.state == SidecarTimer.STATE_RUNNING } ?: return
        val finished = t.copy(
            state = SidecarTimer.STATE_FINISHED, elapsedBeforeMs = t.durationMs, startedAt = 0,
            finishedAt = t.endsAt(now())?.coerceAtMost(now()) ?: now(),
        )
        TimerStore.upsert(ctx, finished)
        report("timer_finished", finished)
        AlarmService.ringTimer(ctx, id)
    }

    /** The ringing ended: a snooze adds [SNOOZE_MS] to the timer, anything else removes it. */
    fun ringEnded(ctx: Context, id: String, snooze: Boolean, reason: String) {
        val t = TimerStore.get(ctx, id) ?: return
        if (snooze) {
            val again = t.copy(
                state = SidecarTimer.STATE_RUNNING, startedAt = now(), elapsedBeforeMs = 0, durationMs = SNOOZE_MS, finishedAt = 0,
            )
            TimerStore.upsert(ctx, again)
            TimerScheduler.schedule(ctx, again)
            report("timer_snoozed", again)
        } else if (reason == "timeout") {
            // silenced after the ring timeout: stays listed as finished, with the overtime counting up
            report("timer_ring_timeout", t)
        } else {
            TimerStore.remove(ctx, id)
            report("timer_dismissed", t, mapOf("reason" to reason))
        }
    }

    /** After boot / time change: re-arm countdowns, ring those that ended while the tablet was off. */
    fun rescheduleAll(ctx: Context) {
        for (t in TimerStore.all(ctx)) {
            if (t.state != SidecarTimer.STATE_RUNNING || !t.isCountdown) continue
            if (t.remainingMs(now()) == 0L) fire(ctx, t.id) else TimerScheduler.schedule(ctx, t)
        }
    }

    fun snapshot(ctx: Context): List<Map<String, Any?>> = TimerStore.all(ctx).map { it.toMap() }

    const val SNOOZE_MS = 60_000L
}
