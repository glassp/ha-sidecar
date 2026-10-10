package dev.glassp.ha_sidecar

import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.Executors

/** Dart <-> native bridge. Method names mirror lib/platform/kiosk_platform.dart. */
object PlatformChannel {
    const val METHODS = "dev.glassp.ha_sidecar/platform"
    const val EVENTS = "dev.glassp.ha_sidecar/events"

    private const val SETTINGS_GRACE_MS = 15 * 60_000L

    fun handle(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        try {
            dispatch(ctx, call, result)
        } catch (e: SecurityException) {
            result.error("security", e.message, null)
        } catch (e: Exception) {
            result.error("native_error", e.message, e.javaClass.simpleName)
        }
    }

    private fun dispatch(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(KioskController.status(ctx))

            // lockdown ---------------------------------------------------------------------
            "setLockdown" -> {
                val err = KioskController.setLockdown(ctx, call.argument<Boolean>("enabled") == true)
                if (err == null) result.success(null) else result.error(err, err, null)
            }
            "setAllowlist" -> {
                KioskController.setAllowlist(ctx, call.argument<List<String>>("packages").orEmpty())
                result.success(null)
            }
            "setKioskLauncher" -> {
                KioskController.setKioskLauncher(ctx, call.argument<Boolean>("enabled") == true)
                EventBus.emit("status_changed")
                result.success(null)
            }
            "setTargetPackage" -> {
                Prefs.setTargetPackage(ctx, call.argument<String>("package"))
                result.success(null)
            }
            "setPin" -> {
                val pin = call.argument<String>("pin").orEmpty()
                if (pin.length < 4) return result.error("pin_too_short", "PIN needs 4+ digits", null)
                Prefs.setPin(ctx, pin)
                result.success(null)
            }
            "verifyPin" -> result.success(Prefs.verifyPin(ctx, call.argument<String>("pin").orEmpty()))

            // apps -------------------------------------------------------------------------
            "launchApp" -> result.success(
                KioskController.launchPackage(ctx, call.argument<String>("package").orEmpty(), navigatePath = call.argument<String>("path"))
            )
            "bringHaToFront" -> result.success(
                KioskController.launchTarget(ctx, navigatePath = call.argument<String>("path"), dashboard = true)
            )
            "listLaunchableApps" -> result.success(listLaunchableApps(ctx))

            // screen -----------------------------------------------------------------------
            "setKeepScreenOn" -> {
                KioskController.setKeepScreenOn(ctx, call.argument<Boolean>("enabled") == true)
                result.success(null)
            }
            "wakeScreen" -> {
                KioskController.wakeScreen(ctx)
                result.success(null)
            }
            "sleepScreen" -> {
                val err = KioskController.sleepScreen(ctx)
                if (err == null) result.success(null) else result.error(err, err, null)
            }
            "setBrightness" -> {
                val err = KioskController.setBrightness(ctx, call.argument<Int>("level") ?: 128)
                if (err == null) result.success(null) else result.error(err, err, null)
            }

            // display / presence -----------------------------------------------------------
            "setDisplayConfig" -> {
                val r = DisplayConfig.set(ctx, call.argument<Map<String, Any?>>("config").orEmpty())
                if (r.rejected.isEmpty()) result.success(r.config)
                else result.error("invalid_value", "Not a valid value for: ${r.rejected.joinToString()}", null)
            }
            "setExternalPresence" -> {
                BrightnessController.setExternalPresence(call.argument<Boolean>("present") == true)
                result.success(null)
            }
            "setExternalNight" -> {
                BrightnessController.extNight = call.argument<Boolean>("night")
                BrightnessController.poke()
                result.success(null)
            }

            "closeUi" -> result.success(UiHost.close(call.argument<String>("route").orEmpty()))
            "bubbleAvailable" -> result.success(VoiceBubble.available(ctx))
            "bubbleUpdate" -> {
                @Suppress("UNCHECKED_CAST")
                VoiceBubble.update(ctx, (call.arguments as? Map<String, Any?>).orEmpty())
                result.success(null)
            }
            "bubbleHide" -> {
                VoiceBubble.hide()
                result.success(null)
            }
            "reportTouch" -> {
                InteractionTracker.touch()
                result.success(null)
            }
            "unlockWithPin" -> {
                val r = Prefs.verifyPin(ctx, call.argument<String>("pin").orEmpty())
                when {
                    r == 0L -> {
                        KioskController.setLockdown(ctx, false)
                        EventBus.emit("lockdown_disabled_by_pin")
                    }
                    r == -1L -> EventBus.emit("pin_failed", mapOf("failures" to Prefs.pinFails(ctx)))
                }
                result.success(r)
            }
            "setGlanceItems" -> {
                val items = org.json.JSONArray(call.argument<List<Map<String, Any?>>>("items").orEmpty().map { org.json.JSONObject(it) })
                Prefs.setGlanceItemsJson(ctx, items.toString())
                EventBus.emit("status_changed")
                result.success(null)
            }
            "showGlance" -> result.success(UiHost.show(ctx, UiHost.GLANCE))
            "hideGlance" -> {
                UiHost.close(UiHost.GLANCE)
                result.success(null)
            }
            "requestPermission" -> {
                val perm = when (call.argument<String>("name")) {
                    "camera" -> android.Manifest.permission.CAMERA
                    "location" -> android.Manifest.permission.ACCESS_FINE_LOCATION
                    "notifications" ->
                        if (Build.VERSION.SDK_INT >= 33) android.Manifest.permission.POST_NOTIFICATIONS
                        else return result.success(null)
                    else -> return result.error("bad_args", "unknown permission", null)
                }
                ctx.startActivity(
                    Intent(ctx, PermissionActivity::class.java).putExtra("perm", perm).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                result.success(null)
            }

            // alarms -----------------------------------------------------------------------
            "getAlarms" -> result.success(AlarmStore.all(ctx).map { it.toMap() })
            "upsertAlarm" -> {
                val map = call.argument<Map<String, Any?>>("alarm") ?: return result.error("bad_args", "alarm missing", null)
                val alarm = Alarm.fromJson(JSONObject(map))
                AlarmScheduler.schedule(ctx, alarm) // throws if exact alarms are not permitted: do not persist then
                AlarmStore.upsert(ctx, alarm)
                EventBus.emit("status_changed")
                result.success(alarm.toMap())
            }
            "removeAlarm" -> {
                val id = call.argument<String>("id").orEmpty()
                AlarmScheduler.cancel(ctx, id)
                AlarmStore.remove(ctx, id)
                EventBus.emit("status_changed")
                result.success(null)
            }
            "stopAlarm" -> {
                AlarmService.stop(ctx)
                result.success(null)
            }
            "snoozeAlarm" -> {
                AlarmService.snooze(ctx)
                result.success(null)
            }
            "setAlarmEnabled" -> {
                val id = call.argument<String>("id").orEmpty()
                if (AlarmEngine.setEnabled(ctx, id, call.argument<Boolean>("enabled") == true)) result.success(null)
                else result.error("not_found", "no alarm $id", null)
            }
            "skipNextAlarm" -> {
                if (AlarmEngine.skipNext(ctx, call.argument<String>("id"))) result.success(null)
                else result.error("not_found", "no such alarm", null)
            }
            "setAlarmsMuted" -> {
                // `until_ms`: epoch ms; `forever`; or neither = unmute
                val until = if (call.argument<Boolean>("forever") == true) Long.MAX_VALUE
                else call.argument<Number>("until_ms")?.toLong()
                AlarmEngine.setMuted(ctx, until)
                result.success(null)
            }

            "healDashboard" ->
                result.success(CompanionWatchdog.heal(ctx, call.argument<String>("reason") ?: "beacon"))
            "restartCompanion" ->
                if (CompanionWatchdog.restartNow(ctx)) result.success(null)
                else result.error("not_found", "no Home Assistant app installed", null)

            // voice (Assist satellite) -------------------------------------------------------------
            "voiceStart" -> result.success(Voice.start(ctx, call.argument<String>("session").orEmpty()))
            "voiceStop" -> {
                Voice.stop(ctx)
                result.success(null)
            }
            "voicePlay" -> Voice.play(ctx, call.argument<String>("url").orEmpty()) { err -> result.success(err) }
            "voicePing" -> Voice.ping(call.argument<String>("kind").orEmpty()) { result.success(null) }
            "voiceStopPlayback" -> {
                Voice.stopPlayback(ctx)
                result.success(null)
            }
            "downloadWakeWord" -> {
                WakeWord.download(ctx, call.argument<String>("id").orEmpty())
                result.success(null)
            }
            "removeWakeWord" -> {
                WakeWord.remove(ctx, call.argument<String>("id").orEmpty())
                result.success(null)
            }
            "micPermission" -> result.success(Voice.hasPermission(ctx))
            "requestMicPermission" -> {
                Voice.requestPermission(ctx)
                result.success(null)
            }
            "showUi" -> result.success(UiHost.show(ctx, call.argument<String>("route").orEmpty()))

            // pairing with Home Assistant ----------------------------------------------------------
            "startPairing" -> result.success(PairingServer.start(ctx))
            "stopPairing" -> {
                PairingServer.stop()
                result.success(null)
            }
            "answerPairing" -> {
                PairingServer.answer(call.argument<Boolean>("allow") == true)
                result.success(null)
            }

            // timers and stopwatches ------------------------------------------------------------
            "getTimers" -> result.success(TimerEngine.snapshot(ctx))
            "startTimer" -> {
                val id = call.argument<String>("id").orEmpty()
                try {
                    val t = TimerEngine.start(
                        ctx, id, call.argument<String>("label").orEmpty(),
                        call.argument<String>("kind") ?: SidecarTimer.KIND_COUNTDOWN,
                        call.argument<Number>("duration_ms")?.toLong() ?: 0L,
                    )
                    result.success(t.toMap())
                } catch (e: TimerEngine.Invalid) {
                    result.error("invalid_value", e.message, null)
                }
            }
            "pauseTimer" -> {
                if (TimerEngine.pause(ctx, call.argument<String>("id").orEmpty())) result.success(null)
                else result.error("not_found", "no running timer with that id", null)
            }
            "resumeTimer" -> {
                if (TimerEngine.resume(ctx, call.argument<String>("id").orEmpty())) result.success(null)
                else result.error("not_found", "no paused timer with that id", null)
            }
            "cancelTimer" -> {
                if (TimerEngine.cancel(ctx, call.argument<String>("id").orEmpty())) result.success(null)
                else result.error("not_found", "no timer with that id", null)
            }
            "adjustTimer" -> {
                val ok = TimerEngine.adjust(
                    ctx, call.argument<String>("id").orEmpty(), call.argument<Number>("delta_ms")?.toLong() ?: 0L,
                )
                if (ok) result.success(null) else result.error("not_found", "no countdown with that id", null)
            }

            // system -----------------------------------------------------------------------
            "startKeepAlive" -> {
                KeepAliveService.start(ctx)
                result.success(null)
            }
            "openSettings" -> result.success(openSettings(ctx, call.argument<String>("kind").orEmpty()))
            "runSystemUpdate" -> {
                if (!KioskController.isAccessibilityEnabled(ctx)) return result.error("needs_accessibility", "accessibility guard must be enabled", null)
                UpdateAutomation.arm(ctx)
                result.success(openSettings(ctx, "system_update"))
            }
            "installSystemUpdate" -> installSystemUpdate(ctx, call.argument<String>("uri").orEmpty(), result)
            "reboot" -> {
                if (!KioskController.isDeviceOwner(ctx)) return result.error("needs_device_owner", "reboot needs device owner", null)
                ctx.getSystemService(DevicePolicyManager::class.java).reboot(KioskController.admin(ctx))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun listLaunchableApps(ctx: Context): List<Map<String, String>> {
        val pm = ctx.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(intent, 0)
            .map { mapOf("package" to it.activityInfo.packageName, "label" to it.loadLabel(pm).toString()) }
            .distinctBy { it["package"] }
            .sortedBy { it["label"]!!.lowercase() }
    }

    /**
     * Opens a settings screen. For the OS update screen the Settings package is allowed
     * temporarily so lockdown does not immediately throw the user back out.
     */
    private fun openSettings(ctx: Context, kind: String): Boolean {
        val pkgUri = Uri.parse("package:${ctx.packageName}")
        val intent = when (kind) {
            "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            "home" -> Intent(Settings.ACTION_HOME_SETTINGS)
            "overlay" -> Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, pkgUri)
            "write_settings" -> Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, pkgUri)
            "notifications" -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, ctx.packageName)
            "battery" -> Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            "full_screen_intent" ->
                if (Build.VERSION.SDK_INT >= 34) Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, pkgUri) else return false
            "system_update" -> {
                if (Prefs.lockdown(ctx)) KioskController.allowTemporarily(ctx, KioskController.SETTINGS, SETTINGS_GRACE_MS)
                Intent("android.settings.SYSTEM_UPDATE_SETTINGS")  // not a public constant
            }
            else -> return false
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return runCatching { ctx.startActivity(intent) }.isSuccess
    }

    /**
     * Device owner only, A/B devices only: installs an OTA package the *caller supplies*.
     * Android offers no API to download or discover updates for third-party apps.
     */
    private fun installSystemUpdate(ctx: Context, uri: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return result.error("unsupported", "needs Android 10+", null)
        if (!KioskController.isDeviceOwner(ctx)) return result.error("needs_device_owner", "device owner required", null)
        if (uri.isBlank()) return result.error("bad_args", "uri missing", null)
        val dpm = ctx.getSystemService(DevicePolicyManager::class.java)
        dpm.installSystemUpdate(
            KioskController.admin(ctx), Uri.parse(uri), Executors.newSingleThreadExecutor(),
            object : DevicePolicyManager.InstallSystemUpdateCallback() {
                override fun onInstallUpdateError(errorCode: Int, errorMessage: String) {
                    EventBus.emit("system_update_install_error", mapOf("code" to errorCode, "message" to errorMessage))
                }
            },
        )
        result.success(null)
    }
}
