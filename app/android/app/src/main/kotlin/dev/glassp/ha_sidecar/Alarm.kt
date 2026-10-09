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
) {
    fun nextTriggerMillis(now: Long = System.currentTimeMillis()): Long? {
        if (!enabled) return null
        if (snoozedUntil > now) return snoozedUntil
        val zone = ZoneId.systemDefault()
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        for (offset in 0L..7L) {
            val date = today.plusDays(offset)
            if (days.isNotEmpty() && date.dayOfWeek.value !in days) continue
            val at = date.atTime(hour, minute).atZone(zone).toInstant().toEpochMilli()
            if (at > now) return at
        }
        return null
    }

    fun toJson(): JSONObject = JSONObject()
        .put("id", id).put("hour", hour).put("minute", minute)
        .put("days", JSONArray(days.sorted()))
        .put("label", label).put("enabled", enabled)
        .put("snooze_minutes", snoozeMinutes).put("snoozed_until", snoozedUntil)

    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id, "hour" to hour, "minute" to minute, "days" to days.sorted(),
        "label" to label, "enabled" to enabled, "snooze_minutes" to snoozeMinutes,
        "snoozed_until" to snoozedUntil, "next" to nextTriggerMillis(),
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
