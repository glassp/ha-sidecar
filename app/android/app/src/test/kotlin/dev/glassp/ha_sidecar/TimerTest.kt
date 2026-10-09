package dev.glassp.ha_sidecar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class TimerTest {
    private fun countdown(state: String, startedAt: Long = 0, before: Long = 0, duration: Long = 600_000) =
        SidecarTimer("t", "batch 1", SidecarTimer.KIND_COUNTDOWN, duration, state, startedAt, before)

    @Test fun runningCountdownCountsDown() {
        val t = countdown(SidecarTimer.STATE_RUNNING, startedAt = 1_000)
        assertEquals(60_000, t.elapsedMs(61_000))
        assertEquals(540_000, t.remainingMs(61_000))
        assertEquals(601_000L, t.endsAt(61_000))
    }

    @Test fun pausedCountdownKeepsItsRemainingTime() {
        val t = countdown(SidecarTimer.STATE_PAUSED, before = 100_000)
        assertEquals(500_000, t.remainingMs(9_999_999))
        assertNull(t.endsAt(9_999_999))
    }

    @Test fun remainingNeverGoesNegative() {
        assertEquals(0, countdown(SidecarTimer.STATE_RUNNING, startedAt = 0).remainingMs(10_000_000))
    }

    @Test fun countUpHasNoEndAndVirtualStart() {
        val t = SidecarTimer("w", "treadmill", SidecarTimer.KIND_COUNTUP, 0, SidecarTimer.STATE_RUNNING, startedAt = 5_000, elapsedBeforeMs = 2_000)
        assertEquals(12_000, t.elapsedMs(15_000))
        assertNull(t.endsAt(15_000))
        assertEquals(3_000L, t.toMap(15_000)["started_at"]) // now - elapsed
    }

    @Test fun skipNextMovesToTheFollowingOccurrence() {
        val zone = ZoneId.systemDefault()
        val now = LocalDate.of(2030, 1, 7).atTime(12, 0).atZone(zone).toInstant().toEpochMilli() // a Monday
        val every = (1..7).toSet()
        val plain = Alarm("a", 7, 0, days = every).nextTriggerMillis(now)!!
        val skipped = Alarm("a", 7, 0, days = every, skipNext = true).nextTriggerMillis(now)!!
        assertEquals(24 * 3_600_000L, skipped - plain)
        assertTrue(Alarm("a", 7, 0, days = setOf(1), skipNext = true).nextTriggerMillis(now)!! - plain >= 6 * 24 * 3_600_000L)
    }
}
