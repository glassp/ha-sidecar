package dev.glassp.ha_sidecar

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TapCounterTest {
    @Test fun fifthTapWithinTheWindowFires() {
        val c = TapCounter(5, 5_000)
        repeat(4) { assertFalse(c.tap(it * 200L)) }
        assertTrue(c.tap(800))
    }

    @Test fun tapsSpreadOverTooLongDoNotFire() {
        val c = TapCounter(5, 5_000)
        for (i in 0 until 4) assertFalse(c.tap(i * 2_000L))
        assertFalse("the fifth tap comes after the window of the first", c.tap(8_000))
    }

    @Test fun afterFiringItStartsOver() {
        val c = TapCounter(5, 5_000)
        repeat(4) { c.tap(it * 100L) }
        assertTrue(c.tap(400))
        repeat(4) { assertFalse(c.tap(1_000L + it * 100L)) }
        assertTrue(c.tap(1_400))
    }

    @Test fun aSlowRunDoesNotLeaveCountsBehindForTheNextOne() {
        val c = TapCounter(5, 5_000)
        c.tap(0); c.tap(100)
        // 10 s later a fresh run needs all five again
        for (i in 0 until 4) assertFalse(c.tap(10_000L + i * 100L))
        assertTrue(c.tap(10_400))
    }
}
