package dev.glassp.ha_sidecar

/** Counts taps: true on the [taps]-th tap within [windowMs] of the first one of a run, then starts over. */
class TapCounter(private val taps: Int = 5, private val windowMs: Long = 5_000L) {
    private var count = 0
    private var windowStart = 0L

    fun tap(now: Long): Boolean {
        if (count == 0 || now - windowStart > windowMs) {
            windowStart = now
            count = 0
        }
        if (++count >= taps) {
            count = 0
            return true
        }
        return false
    }
}
