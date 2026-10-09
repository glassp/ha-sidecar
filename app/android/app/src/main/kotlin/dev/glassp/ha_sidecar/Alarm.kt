package dev.glassp.ha_sidecar

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId

/**
 * @param days ISO weekdays (1 = Monday .. 7 = Sunday); empty = one-shot.
 * @param snoozedUntil epoch ms; when in the future it overrides the regular schedule.
 */
data class Alarm(
    val id: String,
    val hour: Int,
    val minute: Int,
    val days: Set<Int> = emptySet(),
    val label: String = "",
    val enabled: Boolean = true,
    val snoozeMinutes: Int = 9,
    val snoozedUntil: Long = 0,
    /** Repeating alarm: ring on the occurrence after the next one (e.g. "skip tomorrow's alarm"). */
    val skipNext: Boolean = false,
) {
    fun nextTriggerMillis(now: Long = System.currentTimeMillis()): Long? {
        if (!enabled) return null
        if (snoozedUntil > now) return snoozedUntil
        val zone = ZoneId.systemDefault()
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        var toSkip = if (skipNext && days.isNotEmpty()) 1 else 0
        for (offset in 0L..14L) {
            val date = today.plusDays(offset)
            if (days.isNotEmpty() && date.dayOfWeek.value !in days) continue
            val at = date.atTime(hour, minute).atZone(zone).toInstant().toEpochMilli()
            if (at <= now) continue
            if (toSkip-- > 0) continue
            return at
        }
        return null
    }

    fun toJson(): JSONObject = JSONObject()
        .put("id", id).put("hour", hour).put("minute", minute)
        .put("days", JSONArray(days.sorted()))
        .put("label", label).put("enabled", enabled)
        .put("snooze_minutes", snoozeMinutes).put("snoozed_until", snoozedUntil).put("skip_next", skipNext)

    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id, "hour" to hour, "minute" to minute, "days" to days.sorted(),
        "label" to label, "enabled" to enabled, "snooze_minutes" to snoozeMinutes,
        "snoozed_until" to snoozedUntil, "skip_next" to skipNext, "next" to nextTriggerMillis(),
    )

    companion object {
        fun fromJson(o: JSONObject): Alarm {
            val d = o.optJSONArray("days") ?: JSONArray()
            return Alarm(
                id = o.getString("id"),
                hour = o.getInt("hour"),
                minute = o.getInt("minute"),
                days = (0 until d.length()).map { d.getInt(it) }.filter { it in 1..7 }.toSet(),
                label = o.optString("label", ""),
                enabled = o.optBoolean("enabled", true),
                snoozeMinutes = o.optInt("snooze_minutes", 9),
                snoozedUntil = o.optLong("snoozed_until", 0),
                skipNext = o.optBoolean("skip_next", false),
            )
        }
    }
}

object AlarmStore {
    fun all(ctx: Context): List<Alarm> {
        val arr = runCatching { JSONArray(Prefs.alarmsJson(ctx)) }.getOrDefault(JSONArray())
        return (0 until arr.length()).mapNotNull { runCatching { Alarm.fromJson(arr.getJSONObject(it)) }.getOrNull() }
    }

    private fun save(ctx: Context, list: List<Alarm>) {
        val arr = JSONArray()
        list.forEach { arr.put(it.toJson()) }
        Prefs.setAlarmsJson(ctx, arr.toString())
    }

    fun get(ctx: Context, id: String) = all(ctx).firstOrNull { it.id == id }

    fun upsert(ctx: Context, alarm: Alarm) {
        save(ctx, all(ctx).filter { it.id != alarm.id } + alarm)
    }

    fun remove(ctx: Context, id: String) {
        save(ctx, all(ctx).filter { it.id != id })
    }
}

/**
 * Uses AlarmManager.setAlarmClock: exempt from exact-alarm permission and Doze, and the OS
 * shows the soonest alarm in the system UI ("next alarm") like a stock clock app.
 */
object AlarmScheduler {
    const val ACTION_FIRE = "dev.glassp.ha_sidecar.ALARM_FIRE"

    private fun firePendingIntent(ctx: Context, alarmId: String): PendingIntent =
        PendingIntent.getBroadcast(
            ctx, alarmId.hashCode(),
            Intent(ctx, AlarmReceiver::class.java).setAction(ACTION_FIRE).putExtra("id", alarmId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    fun schedule(ctx: Context, alarm: Alarm) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        val at = alarm.nextTriggerMillis()
        if (at == null) {
            am.cancel(firePendingIntent(ctx, alarm.id))
            return
        }
        val show = PendingIntent.getActivity(
            ctx, 0, Intent(ctx, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        am.setAlarmClock(AlarmManager.AlarmClockInfo(at, show), firePendingIntent(ctx, alarm.id))
    }

    fun cancel(ctx: Context, id: String) {
        ctx.getSystemService(AlarmManager::class.java).cancel(firePendingIntent(ctx, id))
    }

    fun rescheduleAll(ctx: Context) {
        AlarmStore.all(ctx).forEach { schedule(ctx, it) }
    }

    fun nextAlarmMillis(ctx: Context): Long? =
        AlarmStore.all(ctx).mapNotNull { it.nextTriggerMillis() }.minOrNull()
}

/** Remote-control surface for alarms: mute (e.g. while away), skip the next occurrence, enable/disable. */
object AlarmEngine {
    fun isMuted(ctx: Context, now: Long = System.currentTimeMillis()) = Prefs.alarmsMutedUntil(ctx) > now

    /** Called when an alarm's time is reached. Muted alarms do not ring but still advance their schedule. */
    fun fire(ctx: Context, id: String) {
        val alarm = AlarmStore.get(ctx, id) ?: return
        if (!isMuted(ctx)) {
            AlarmService.ring(ctx, id)
            return
        }
        val next = alarm.copy(enabled = alarm.days.isNotEmpty(), snoozedUntil = 0, skipNext = false)
        AlarmStore.upsert(ctx, next)
        AlarmScheduler.schedule(ctx, next)
        EventBus.emit("alarm_skipped", mapOf("id" to alarm.id, "label" to alarm.label, "reason" to "muted"))
        EventBus.emit("status_changed")
    }

    /** @param untilMs epoch ms, [Long.MAX_VALUE] for "until unmuted", or null/<=now to unmute. */
    fun setMuted(ctx: Context, untilMs: Long?) {
        val until = if (untilMs != null && untilMs > System.currentTimeMillis()) untilMs else 0L
        val was = Prefs.alarmsMutedUntil(ctx) > System.currentTimeMillis()
        Prefs.setAlarmsMutedUntil(ctx, until)
        if (until > 0 != was || until > 0) {
            EventBus.emit(
                if (until > 0) "alarms_muted" else "alarms_unmuted",
                mapOf("until" to until.takeIf { it > 0 && it != Long.MAX_VALUE }),
            )
        }
        EventBus.emit("status_changed")
    }

    /** One-shot alarms are disabled, repeating ones ring on their following occurrence. @return false if unknown. */
    fun skipNext(ctx: Context, id: String?): Boolean {
        val alarm = (if (id == null) nextAlarm(ctx) else AlarmStore.get(ctx, id)) ?: return false
        val changed = if (alarm.days.isEmpty()) alarm.copy(enabled = false, snoozedUntil = 0)
        else alarm.copy(skipNext = !alarm.skipNext)
        AlarmStore.upsert(ctx, changed)
        AlarmScheduler.schedule(ctx, changed)
        EventBus.emit(
            "alarm_skipped",
            mapOf("id" to alarm.id, "label" to alarm.label, "reason" to if (changed.skipNext || alarm.days.isEmpty()) "skip_next" else "skip_cleared"),
        )
        EventBus.emit("status_changed")
        return true
    }

    fun setEnabled(ctx: Context, id: String, enabled: Boolean): Boolean {
        val alarm = AlarmStore.get(ctx, id) ?: return false
        val changed = alarm.copy(enabled = enabled, snoozedUntil = 0, skipNext = false)
        AlarmScheduler.schedule(ctx, changed)
        AlarmStore.upsert(ctx, changed)
        EventBus.emit("status_changed")
        return true
    }

    private fun nextAlarm(ctx: Context): Alarm? =
        AlarmStore.all(ctx).filter { it.nextTriggerMillis() != null }.minByOrNull { it.nextTriggerMillis()!! }
}
