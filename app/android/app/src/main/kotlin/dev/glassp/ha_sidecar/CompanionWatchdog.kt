package dev.glassp.ha_sidecar

import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import java.util.concurrent.Callable
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * Relaunches the Home Assistant companion app when it is frozen (docs/ROADMAP.md, phase 2.5).
 *
 * A crashed or killed app is already handled by the home role; a *frozen* one is still "running". Signals:
 *  1. **UI probe**: while the app is in front, the accessibility tree of its window is fetched every [probe] seconds. A
 *     frozen UI thread cannot answer, the root comes back null (measured: within ~3 s). [BAD_PROBES] in a row = frozen.
 *  2. **ANR dialog**: Android's "isn't responding" dialog (package `android`, buttons `aerr_close` / `aerr_wait`), found by
 *     view id so it works in any language. Answered with "Close app".
 *  3. **Start-up hang**: after a launch the tree must show real content within [startup] seconds.
 * Recovery: tap "Close app" if the dialog is up, otherwise (device owner) hide + unhide the package, which kills the
 * process, then launch it again. At most [MAX_RESTARTS] per [WINDOW_MS]; beyond that it gives up and raises an event
 * instead (a boot loop must not hide a real problem). Not while an alarm rings, the PIN pad is open, the screen is off or
 * the system update automation runs.
 *
 * Privacy: only the *number* of nodes of the companion's window and the system ANR dialog are looked at; the content of the
 * app is never read.
 */
object CompanionWatchdog {
    private const val TAG = "CompanionWatchdog"
    private const val BAD_PROBES = 3
    private const val MIN_NODES = 4
    private const val MAX_RESTARTS = 3
    private const val WINDOW_MS = 10 * 60_000L
    private const val GIVE_UP_MS = 30 * 60_000L
    private const val NOTIFY_COOLDOWN_MS = 5 * 60_000L
    private const val ANR_PACKAGE = "android"
    private const val PROBE_TIMEOUT_MS = 8_000L

    private val thread = HandlerThread("companion-watchdog").apply { start() }
    private val handler = Handler(thread.looper)

    /** The accessibility calls go to the app being probed: a frozen app can make them block, so they run elsewhere. */
    private val worker = Executors.newSingleThreadExecutor { r -> Thread(r, "companion-probe").apply { isDaemon = true } }
    private var inFlight: Future<Snap>? = null

    /** What one probe saw. [root] false = the window could not be read in time (frozen, or the call hung). */
    private class Snap(val root: Boolean, val pkg: String?, val nodes: Int, val anrClose: AccessibilityNodeInfo?)
    private var ctx: Context? = null

    @Volatile var responsive: Boolean? = null
        private set
    @Volatile var state = "off"
        private set
    @Volatile var restarts = 0
        private set
    @Volatile var lastReason: String? = null
        private set
    @Volatile var lastRestartAt = 0L
        private set

    private var bad = 0
    private var launchedAt = 0L
    private var healthySinceLaunch = true
    private var lastTargetForeground = 0L
    private var gaveUpUntil = 0L
    private var notifyUntil = 0L
    private val restartTimes = ArrayDeque<Long>()
    private val tick = object : Runnable {
        override fun run() {
            val c = ctx ?: return
            runCatching { probe(c) }.onFailure { Log.w(TAG, "probe failed", it) }
            schedule(c)
        }
    }

    fun start(context: Context) {
        ctx = context.applicationContext
        refresh(context)
    }

    /** Called when the settings change. */
    fun refresh(context: Context) {
        ctx = context.applicationContext
        handler.removeCallbacks(tick)
        if (!enabled(context)) {
            state = "off"
            responsive = null
            bad = 0
            gaveUpUntil = 0
            restartTimes.clear()
            EventBus.emit("status_changed")
            return
        }
        handler.postDelayed(tick, 3_000)
    }

    private fun cfg(c: Context) = DisplayConfig.get(c)
    private fun enabled(c: Context) = cfg(c)["watchdog"] == true
    private fun probeMs(c: Context) = (cfg(c)["watchdog_probe_s"] as Int) * 1000L
    private fun startupMs(c: Context) = (cfg(c)["watchdog_startup_s"] as Int) * 1000L

    private fun schedule(c: Context) {
        handler.removeCallbacks(tick)
        if (enabled(c)) handler.postDelayed(tick, probeMs(c))
    }

    /** The target app was (re)launched by us: it gets [startup] seconds to show real content. */
    fun noteLaunch() {
        launchedAt = SystemClock.elapsedRealtime()
        healthySinceLaunch = false
        bad = 0
    }

    fun snapshot(c: Context): Map<String, Any?> = mapOf(
        "enabled" to enabled(c),
        "state" to state,
        "responsive" to responsive,
        "restarts" to restarts,
        "last_reason" to lastReason,
        "last_restart_at" to lastRestartAt.takeIf { it > 0 },
        "log" to WatchdogLog.recent(c),
    )

    // --- probing ---------------------------------------------------------------------------------------

    private fun idleReason(c: Context): String? {
        if (SidecarAccessibilityService.instance == null) return "no_accessibility"
        if (!c.getSystemService(PowerManager::class.java).isInteractive) return "idle"
        if (AlarmService.ringingId != null || AlarmService.ringingTimerId != null) return "idle"
        if (UiHost.isShowing(UiHost.PIN) || UiHost.isShowing(UiHost.ALARM) || UiHost.isShowing(UiHost.GLANCE)) return "idle"
        if (UpdateAutomation.isArmed()) return "idle"
        return null
    }

    private fun probe(c: Context) {
        val now = SystemClock.elapsedRealtime()
        val target = KioskController.targetPackage(c) ?: run { state = "idle"; return }
        if (now < gaveUpUntil) { // stays visible (UI, Home Assistant) however the app is doing meanwhile
            state = "gave_up"
            responsive = null
            return
        }
        idleReason(c)?.let { why ->
            state = why
            if (why != "no_accessibility") bad = 0
            responsive = null
            EventBus.emit("status_changed")
            return
        }
        val fg = KioskController.lastForeground
        if (fg == target) lastTargetForeground = now
        // the ANR dialog replaces the foreground package with "android"
        val maybeAnr = fg == ANR_PACKAGE && now - lastTargetForeground < 5 * 60_000L
        // right after a launch we issued the app may not have reported a window yet (or froze while starting)
        val launching = !healthySinceLaunch && launchedAt > 0 && now - launchedAt < startupMs(c) + 3 * probeMs(c)
        if (fg != target && !maybeAnr && !launching) {
            state = "idle"; responsive = null; bad = 0
            EventBus.emit("status_changed")
            return
        }
        val service = SidecarAccessibilityService.instance ?: return
        val snap = fetch(service, target)
        Log.d(TAG, "probe fg=$fg root=${snap.root} pkg=${snap.pkg} nodes=${snap.nodes} bad=$bad settled=$healthySinceLaunch")

        if (snap.pkg == ANR_PACKAGE && snap.anrClose != null) {
            report(c, target, "anr", snap.anrClose)
            return
        }
        val healthy = snap.root && snap.pkg == target && snap.nodes >= (if (healthySinceLaunch) 1 else MIN_NODES)
        if (healthy) {
            healthySinceLaunch = true
            bad = 0
            responsive = true
            state = "ok"
        } else if (!snap.root) {
            bad++
            responsive = false
            if (bad >= BAD_PROBES) { report(c, target, "ui_frozen", null); return }
        } else if (!healthySinceLaunch && now - launchedAt > startupMs(c)) {
            report(c, target, "startup_hang", null)
            return
        }
        EventBus.emit("status_changed")
    }

    /** Reads the active window on the worker thread; no answer within [PROBE_TIMEOUT_MS] counts as "could not be read". */
    private fun fetch(service: SidecarAccessibilityService, target: String): Snap {
        val stuck = inFlight?.takeIf { !it.isDone }
        if (stuck != null) return Snap(false, null, 0, null) // the previous call never came back
        val f = worker.submit(Callable {
            val root = service.rootInActiveWindow
            val pkg = root?.packageName?.toString()
            Snap(
                root != null, pkg,
                if (root != null && pkg == target) countNodes(root, 50) else 0,
                if (pkg == ANR_PACKAGE && root != null) closeButton(root) else null,
            )
        })
        inFlight = f
        return try {
            f.get(PROBE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        } catch (e: TimeoutException) {
            Snap(false, null, 0, null)
        } catch (e: ExecutionException) {
            Snap(false, null, 0, null)
        }
    }

    private fun countNodes(root: AccessibilityNodeInfo, limit: Int): Int {
        var n = 0
        val queue = ArrayDeque<AccessibilityNodeInfo>().apply { add(root) }
        while (queue.isNotEmpty() && n < limit) {
            val node = queue.removeFirst()
            n++
            for (i in 0 until node.childCount) node.getChild(i)?.let { queue.add(it) }
        }
        return n
    }

    private fun closeButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? =
        root.findAccessibilityNodeInfosByViewId("android:id/aerr_close")?.firstOrNull()

    // --- reacting --------------------------------------------------------------------------------------

    private fun report(c: Context, target: String, reason: String, anrClose: AccessibilityNodeInfo?) {
        responsive = false
        WatchdogLog.add(c, "detected", reason, if ((cfg(c)["watchdog_action"] as String) == "notify") "notify" else "restart")
        val now = SystemClock.elapsedRealtime()
        if ((cfg(c)["watchdog_action"] as String) == "notify") {
            state = "unresponsive"
            if (now >= notifyUntil) {
                notifyUntil = now + NOTIFY_COOLDOWN_MS
                EventBus.emit("companion_unresponsive", mapOf("reason" to reason, "package" to target, "action" to "notify"))
            }
            EventBus.emit("status_changed")
            return
        }
        recover(c, target, reason, anrClose)
    }

    /** Restart now, on request (HA button / the app). Counts toward the limit but is not blocked by it. */
    fun restartNow(context: Context): Boolean {
        val c = context.applicationContext
        ctx = c
        val target = KioskController.targetPackage(c) ?: return false
        handler.post { recover(c, target, "manual", null, force = true) }
        return true
    }

    /** Counts a restart against the limit. @return false (and gives up) if the limit is reached. */
    private fun reserveRestart(target: String, reason: String, force: Boolean): Boolean = synchronized(restartTimes) {
        val now = SystemClock.elapsedRealtime()
        while (restartTimes.isNotEmpty() && now - restartTimes.first() > WINDOW_MS) restartTimes.removeFirst()
        if (!force && restartTimes.size >= MAX_RESTARTS) {
            gaveUpUntil = now + GIVE_UP_MS
            state = "gave_up"
            ctx?.let { WatchdogLog.add(it, "gave_up", reason, "${restartTimes.size} restarts in ${WINDOW_MS / 60_000} min") }
            Log.w(TAG, "giving up on $target after ${restartTimes.size} restarts in ${WINDOW_MS / 60_000} minutes ($reason)")
            EventBus.emit(
                "companion_restart_gave_up",
                mapOf("reason" to reason, "package" to target, "restarts_in_window" to restartTimes.size),
            )
            EventBus.emit("status_changed")
            return false
        }
        restartTimes.addLast(now)
        true
    }

    /**
     * Restart requested from outside (the dashboard beacon in Home Assistant found the page dead). Same rules as the
     * probe: not while the screen is off, an alarm rings or the PIN pad is open, not when the app is not in front, and
     * counted against the limit. Works without the watchdog switch and without the accessibility service.
     * @return `healed` true if a restart was started, else `why`.
     */
    fun heal(context: Context, reason: String): Map<String, Any?> {
        val c = context.applicationContext
        ctx = c
        val target = KioskController.targetPackage(c) ?: return mapOf("healed" to false, "why" to "not_installed")
        fun refused(why: String): Map<String, Any?> {
            WatchdogLog.add(c, "heal_refused", reason, why)
            EventBus.emit("status_changed")
            return mapOf("healed" to false, "why" to why)
        }
        if (!c.getSystemService(PowerManager::class.java).isInteractive) return refused("screen_off")
        if (AlarmService.ringingId != null || AlarmService.ringingTimerId != null || UiHost.isShowing(UiHost.PIN) ||
            UiHost.isShowing(UiHost.ALARM) || UpdateAutomation.isArmed()
        ) return refused("busy")
        val fg = KioskController.lastForeground
        if (fg != target && fg != ANR_PACKAGE) return refused("not_in_front")
        if (!reserveRestart(target, reason, force = false)) return refused("rate_limited")
        WatchdogLog.add(c, "heal_request", reason, "accepted")
        handler.post { execute(c, target, reason, null) }
        return mapOf("healed" to true)
    }

    private fun recover(c: Context, target: String, reason: String, anrClose: AccessibilityNodeInfo?, force: Boolean = false) {
        if (!reserveRestart(target, reason, force)) return
        execute(c, target, reason, anrClose)
    }

    private fun execute(c: Context, target: String, reason: String, anrClose: AccessibilityNodeInfo?) {
        restarts++
        lastReason = reason
        lastRestartAt = System.currentTimeMillis()
        state = "restarting"
        bad = 0
        EventBus.emit("companion_unresponsive", mapOf("reason" to reason, "package" to target, "action" to "restart"))

        val method = when {
            anrClose != null && runCatching { anrClose.performAction(AccessibilityNodeInfo.ACTION_CLICK) }.getOrDefault(false) -> "anr_close"
            KioskController.isDeviceOwner(c) -> {
                val dpm = c.getSystemService(android.app.admin.DevicePolicyManager::class.java)
                val admin = KioskController.admin(c)
                // hiding kills the frozen process; unhiding makes it launchable again with its data intact
                val hidden = runCatching { dpm.setApplicationHidden(admin, target, true) }.getOrDefault(false)
                Thread.sleep(700)
                runCatching { dpm.setApplicationHidden(admin, target, false) }
                if (hidden) "hide_unhide" else "hide_failed" // false = the system refused: the process was not killed
            }
            else -> "relaunch_only" // nothing can kill it without device owner or the dialog: bring it to the front and tell HA
        }
        Thread.sleep(if (method == "anr_close") 1200 else 400)
        noteLaunch()
        KioskController.launchTarget(c, lockTask = Prefs.lockdown(c), dashboard = true)
        WatchdogLog.add(c, "restart", reason, method)
        EventBus.emit("companion_restarted", mapOf("reason" to reason, "method" to method, "count" to restarts, "package" to target))
        Log.i(TAG, "restarted $target: $reason via $method")
        state = "ok"
        responsive = null
        EventBus.emit("status_changed")
    }
}
