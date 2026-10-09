package dev.glassp.ha_sidecar

import android.app.ActivityOptions
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import org.json.JSONObject

/**
 * Single entry point for kiosk enforcement.
 *
 * Mode selection:
 *  - device_owner: real lock-task mode (OS hides/blocks system UI, only allowlisted packages run)
 *  - accessibility: fallback; [SidecarAccessibilityService] reacts to foreground changes and
 *    bounces back to the target app, closes the shade, blocks recents.
 *  - none: no enforcement possible, lockdown requests are rejected.
 */
object KioskController {
    /** Official HA companion app package names (full + minimal flavor). */
    val COMPANION_PACKAGES = listOf(
        "io.homeassistant.companion.android",
        "io.homeassistant.companion.android.minimal",
    )
    const val SYSTEM_UI = "com.android.systemui"
    const val SETTINGS = "com.android.settings"

    /** Last non-system foreground package, reported by the accessibility service. */
    @Volatile
    var lastForeground: String? = null

    private val main = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null

    private fun dpm(ctx: Context) = ctx.getSystemService(DevicePolicyManager::class.java)
    fun admin(ctx: Context) = ComponentName(ctx, SidecarDeviceAdminReceiver::class.java)

    fun isDeviceOwner(ctx: Context) = dpm(ctx).isDeviceOwnerApp(ctx.packageName)

    fun isAccessibilityEnabled(ctx: Context): Boolean {
        val enabled = Settings.Secure.getString(
            ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val me = ComponentName(ctx, SidecarAccessibilityService::class.java).flattenToString()
        return enabled.split(':').any { it.equals(me, ignoreCase = true) }
    }

    fun canDrawOverlays(ctx: Context) = Settings.canDrawOverlays(ctx)

    fun mode(ctx: Context): String = when {
        isDeviceOwner(ctx) -> "device_owner"
        isAccessibilityEnabled(ctx) -> "accessibility"
        else -> "none"
    }

    /** The app lockdown pins to the front. */
    fun targetPackage(ctx: Context): String? {
        Prefs.targetPackage(ctx)?.let { return it }
        return COMPANION_PACKAGES.firstOrNull { isInstalled(ctx, it) }
    }

    private fun isInstalled(ctx: Context, pkg: String) =
        ctx.packageManager.getLaunchIntentForPackage(pkg) != null

    private fun imePackages(ctx: Context): Set<String> =
        ctx.getSystemService(InputMethodManager::class.java)
            .enabledInputMethodList.map { it.packageName }.toSet()

    /** Everything that may be in the foreground while locked down. */
    fun effectiveAllowlist(ctx: Context): Set<String> {
        val set = mutableSetOf(ctx.packageName)
        targetPackage(ctx)?.let(set::add)
        set += Prefs.allowlist(ctx)
        set += Prefs.tempAllowed(ctx)
        set += imePackages(ctx)
        return set
    }

    fun isAllowed(ctx: Context, pkg: String) = pkg in effectiveAllowlist(ctx)

    // --- home role --------------------------------------------------------------------------

    fun isDefaultHome(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roles = ctx.getSystemService(android.app.role.RoleManager::class.java)
            return roles.isRoleHeld(android.app.role.RoleManager.ROLE_HOME)
        }
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolved = ctx.packageManager.resolveActivity(home, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
        return resolved?.activityInfo?.packageName == ctx.packageName
    }

    fun setKioskLauncher(ctx: Context, enabled: Boolean) {
        Prefs.setKioskLauncher(ctx, enabled)
        applyPolicy(ctx)
    }

    /** Device owner can force the home app without the user picking it in Settings. */
    private fun applyHomePolicy(ctx: Context) {
        val d = dpm(ctx)
        val a = admin(ctx)
        if (Prefs.kioskLauncher(ctx)) {
            val filter = IntentFilter(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                addCategory(Intent.CATEGORY_DEFAULT)
            }
            d.addPersistentPreferredActivity(a, filter, ComponentName(ctx, HomeActivity::class.java))
        } else {
            d.clearPackagePersistentPreferredActivities(a, ctx.packageName)
        }
    }

    // --- lockdown ---------------------------------------------------------------------------

    /** @return null on success, otherwise an error code. */
    fun setLockdown(ctx: Context, enabled: Boolean): String? {
        if (enabled) {
            if (!Prefs.hasPin(ctx)) return "pin_required"
            if (mode(ctx) == "none") return "no_enforcement_available"
        }
        Prefs.setLockdown(ctx, enabled)
        applyPolicy(ctx)
        if (enabled) launchTarget(ctx, lockTask = true)
        refreshOverlay(ctx)
        EventBus.emit("lockdown_changed", mapOf("enabled" to enabled))
        return null
    }

    /** Re-applies device-owner policy from persisted prefs (call on boot / allowlist change). */
    fun applyPolicy(ctx: Context) {
        if (!isDeviceOwner(ctx)) return
        val d = dpm(ctx)
        val a = admin(ctx)
        applyHomePolicy(ctx)
        val locked = Prefs.lockdown(ctx)
        if (locked) {
            d.setLockTaskPackages(a, effectiveAllowlist(ctx).toTypedArray())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                d.setLockTaskFeatures(a, DevicePolicyManager.LOCK_TASK_FEATURE_NONE)
            }
            runCatching { d.setStatusBarDisabled(a, true) }
        } else {
            // Removing a package from the list ends its lock task. Our own package must go too,
            // otherwise the PIN screen's task (started inside the lock) stays locked.
            d.setLockTaskPackages(a, emptyArray())
            runCatching { d.setStatusBarDisabled(a, false) }
        }
    }

    fun setAllowlist(ctx: Context, packages: Collection<String>) {
        Prefs.setAllowlist(ctx, packages)
        applyPolicy(ctx)
    }

    /** Lets [pkg] run while locked down for [durationMs] (e.g. Settings for an OS update). */
    fun allowTemporarily(ctx: Context, pkg: String, durationMs: Long) {
        Prefs.addTempAllowed(ctx, pkg, durationMs)
        applyPolicy(ctx)
        main.postDelayed({ applyPolicy(ctx) }, durationMs + 1_000)
    }

    // --- launching --------------------------------------------------------------------------

    /**
     * Brings the HA app to the front with a plain intent (no force-stop, no task reset), so
     * the dashboard it is showing is kept. [navigatePath] uses the companion app's
     * `homeassistant://navigate/<path>` deep link to also switch dashboard.
     */
    fun launchTarget(ctx: Context, lockTask: Boolean = false, navigatePath: String? = null): Boolean {
        val pkg = targetPackage(ctx) ?: return false
        return launchPackage(ctx, pkg, lockTask, navigatePath)
    }

    fun launchPackage(ctx: Context, pkg: String, lockTask: Boolean = false, navigatePath: String? = null): Boolean {
        val intent = if (navigatePath != null) {
            Intent(Intent.ACTION_VIEW, Uri.parse("homeassistant://navigate/${navigatePath.trimStart('/')}")).setPackage(pkg)
        } else {
            ctx.packageManager.getLaunchIntentForPackage(pkg) ?: return false
        }
        // REORDER_TO_FRONT keeps the existing task as is; RESET_TASK_IF_NEEDED would not.
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        val options = if (lockTask && isDeviceOwner(ctx) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // Lock-task is only applied to a task that is *started* with the option, so the
            // HA app is restarted once when lockdown is enabled (later bounces just reorder).
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK)
            ActivityOptions.makeBasic().apply { setLockTaskEnabled(true) }.toBundle()
        } else null
        // An enabled accessibility service is exempt from the background-activity-start
        // restrictions; prefer its context so this also works while the HA app is in front.
        val launcher: Context = SidecarAccessibilityService.instance ?: ctx
        return runCatching { launcher.startActivity(intent, options) }.isSuccess
    }

    // --- overlay (hot corner for the on-device PIN) -----------------------------------------

    fun refreshOverlay(ctx: Context) {
        main.post {
            val svc = SidecarAccessibilityService.instance
            val owner: Context = svc ?: ctx.applicationContext
            // touch watcher: always (interaction sensor, dimming, glance)
            TouchWatcher.show(owner, accessibility = svc != null)
            if (Prefs.lockdown(ctx)) HotCorner.show(owner, accessibility = svc != null) else HotCorner.hide()
        }
    }

    // --- security counters (reported to HA) ----------------------------------------------------

    @Volatile var lastBlockedApp: String? = null
    @Volatile var blockedCount = 0

    // --- screen -----------------------------------------------------------------------------

    @Suppress("DEPRECATION")
    fun setKeepScreenOn(ctx: Context, on: Boolean) {
        Prefs.setKeepScreenOn(ctx, on)
        val pm = ctx.getSystemService(PowerManager::class.java)
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        if (on) {
            wakeLock = pm.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK, "ha_sidecar:keep_on").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
        if (isDeviceOwner(ctx)) {
            // 7 = AC | USB | wireless
            runCatching {
                dpm(ctx).setGlobalSetting(admin(ctx), Settings.Global.STAY_ON_WHILE_PLUGGED_IN, if (on) "7" else "0")
            }
        }
    }

    @Suppress("DEPRECATION")
    fun wakeScreen(ctx: Context) {
        val pm = ctx.getSystemService(PowerManager::class.java)
        pm.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP, "ha_sidecar:wake"
        ).acquire(3_000)
    }

    /** @return null on success, else an error code. */
    fun sleepScreen(ctx: Context): String? {
        if (isDeviceOwner(ctx)) {
            dpm(ctx).lockNow()
            return null
        }
        val svc = SidecarAccessibilityService.instance
        if (svc != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            svc.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_LOCK_SCREEN)
            return null
        }
        return "needs_device_owner_or_accessibility"
    }

    fun setBrightness(ctx: Context, level: Int): String? {
        if (!Settings.System.canWrite(ctx)) return "write_settings_permission"
        val cr = ctx.contentResolver
        Settings.System.putInt(cr, Settings.System.SCREEN_BRIGHTNESS_MODE, Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL)
        Settings.System.putInt(cr, Settings.System.SCREEN_BRIGHTNESS, level.coerceIn(0, 255))
        return null
    }

    // --- status -----------------------------------------------------------------------------

    fun status(ctx: Context): Map<String, Any?> {
        val pm = ctx.getSystemService(PowerManager::class.java)
        val battery = ctx.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val plugged = (battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0

        // A pending update is stale once the build changed (update was installed).
        var pending = Prefs.pendingUpdate(ctx)
        if (pending != null && Prefs.pendingUpdateFingerprint(ctx) != Build.FINGERPRINT) {
            Prefs.setPendingUpdate(ctx, null, null)
            pending = null
        }

        return mapOf(
            "mode" to mode(ctx),
            "device_owner" to isDeviceOwner(ctx),
            "accessibility_enabled" to isAccessibilityEnabled(ctx),
            "overlay_granted" to canDrawOverlays(ctx),
            "write_settings_granted" to Settings.System.canWrite(ctx),
            "lockdown" to Prefs.lockdown(ctx),
            "has_pin" to Prefs.hasPin(ctx),
            "kiosk_launcher" to Prefs.kioskLauncher(ctx),
            "is_home_app" to isDefaultHome(ctx),
            "keep_screen_on" to Prefs.keepScreenOn(ctx),
            "screen_on" to pm.isInteractive,
            "brightness" to Settings.System.getInt(ctx.contentResolver, Settings.System.SCREEN_BRIGHTNESS, -1).takeIf { it >= 0 },
            "target_package" to targetPackage(ctx),
            "foreground_app" to lastForeground,
            "allowlist" to Prefs.allowlist(ctx).sorted(),
            "battery_level" to if (level >= 0) level * 100 / scale else null,
            "charging" to plugged,
            "android_release" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT,
            "security_patch" to Build.VERSION.SECURITY_PATCH,
            "build" to Build.DISPLAY,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "pending_update" to pending?.let { JSONObject(it).toMap() },
            "next_alarm" to AlarmScheduler.nextAlarmMillis(ctx),
            "alarm_ringing" to (AlarmService.ringingId != null),
            "last_interaction" to InteractionTracker.lastMs,
            "camera_in_use" to PrivacyMonitor.cameraInUse,
            "mic_in_use" to PrivacyMonitor.micInUse,
            "last_blocked_app" to lastBlockedApp,
            "blocked_count" to blockedCount,
            "pin_failures" to Prefs.pinFails(ctx),
            "cfg" to DisplayConfig.get(ctx),
        ) + BrightnessController.snapshot()
    }

    private fun JSONObject.toMap(): Map<String, Any?> =
        keys().asSequence().associateWith { opt(it) }
}
