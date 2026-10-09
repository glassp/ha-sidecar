package dev.glassp.ha_sidecar

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/**
 * Native-side persisted state. Everything that must keep being enforced while the Flutter
 * engine is not running (lockdown flag, allowlist, PIN, alarms) lives here, not in Dart.
 */
object Prefs {
    private const val PIN_ITERATIONS = 120_000
    private const val MAX_FAILS_BEFORE_LOCKOUT = 5

    private fun sp(ctx: Context): SharedPreferences =
        ctx.applicationContext.getSharedPreferences("sidecar_native", Context.MODE_PRIVATE)

    fun lockdown(ctx: Context) = sp(ctx).getBoolean("lockdown", false)
    fun setLockdown(ctx: Context, v: Boolean) = sp(ctx).edit().putBoolean("lockdown", v).apply()

    /** When on, the sidecar acts as the home app: opens the HA app on boot / Home / when it dies. */
    fun kioskLauncher(ctx: Context) = sp(ctx).getBoolean("kiosk_launcher", false)
    fun setKioskLauncher(ctx: Context, v: Boolean) = sp(ctx).edit().putBoolean("kiosk_launcher", v).apply()

    fun keepScreenOn(ctx: Context) = sp(ctx).getBoolean("keep_screen_on", false)
    fun setKeepScreenOn(ctx: Context, v: Boolean) = sp(ctx).edit().putBoolean("keep_screen_on", v).apply()

    fun allowlist(ctx: Context): Set<String> =
        sp(ctx).getStringSet("allowlist", emptySet())!!.toSet()

    fun setAllowlist(ctx: Context, v: Collection<String>) =
        sp(ctx).edit().putStringSet("allowlist", v.toSet()).apply()

    /** The app lockdown keeps in the foreground (normally the HA companion app). */
    fun targetPackage(ctx: Context): String? = sp(ctx).getString("target_package", null)
    fun setTargetPackage(ctx: Context, v: String?) = sp(ctx).edit().putString("target_package", v).apply()

    /** Temporary allowances (package -> expiry epoch ms), e.g. Settings during an OS update. */
    fun tempAllowed(ctx: Context): Set<String> {
        val now = System.currentTimeMillis()
        return sp(ctx).all.entries
            .filter { it.key.startsWith("temp:") && (it.value as? Long ?: 0L) > now }
            .map { it.key.removePrefix("temp:") }
            .toSet()
    }

    fun addTempAllowed(ctx: Context, pkg: String, durationMs: Long) =
        sp(ctx).edit().putLong("temp:$pkg", System.currentTimeMillis() + durationMs).apply()

    fun alarmsJson(ctx: Context): String = sp(ctx).getString("alarms", "[]")!!
    fun setAlarmsJson(ctx: Context, v: String) = sp(ctx).edit().putString("alarms", v).apply()

    fun pendingUpdate(ctx: Context): String? = sp(ctx).getString("pending_update", null)
    fun pendingUpdateFingerprint(ctx: Context): String? = sp(ctx).getString("pending_update_fp", null)
    fun setPendingUpdate(ctx: Context, json: String?, fingerprint: String?) =
        sp(ctx).edit().putString("pending_update", json).putString("pending_update_fp", fingerprint).apply()

    // --- PIN -------------------------------------------------------------------------------

    fun hasPin(ctx: Context) = sp(ctx).contains("pin_hash")

    fun setPin(ctx: Context, pin: String) {
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        sp(ctx).edit()
            .putString("pin_salt", Base64.encodeToString(salt, Base64.NO_WRAP))
            .putString("pin_hash", Base64.encodeToString(hash(pin, salt), Base64.NO_WRAP))
            .putInt("pin_fails", 0)
            .putLong("pin_locked_until", 0)
            .apply()
    }

    /** @return 0 = ok, -1 = wrong PIN, >0 = locked out, milliseconds remaining. */
    fun verifyPin(ctx: Context, pin: String): Long {
        val p = sp(ctx)
        val now = System.currentTimeMillis()
        val lockedUntil = p.getLong("pin_locked_until", 0)
        if (lockedUntil > now) return lockedUntil - now

        val salt = Base64.decode(p.getString("pin_salt", null) ?: return -1, Base64.NO_WRAP)
        val expected = Base64.decode(p.getString("pin_hash", null) ?: return -1, Base64.NO_WRAP)
        if (MessageDigest.isEqual(expected, hash(pin, salt))) {
            p.edit().putInt("pin_fails", 0).putLong("pin_locked_until", 0).apply()
            return 0
        }
        val fails = p.getInt("pin_fails", 0) + 1
        val edit = p.edit().putInt("pin_fails", fails)
        if (fails >= MAX_FAILS_BEFORE_LOCKOUT) {
            // 30 s, 60 s, 120 s ... capped at 15 min
            val steps = fails - MAX_FAILS_BEFORE_LOCKOUT
            val lock = (30_000L shl steps.coerceAtMost(5)).coerceAtMost(15 * 60_000L)
            edit.putLong("pin_locked_until", now + lock)
        }
        edit.apply()
        return -1
    }

    private fun hash(pin: String, salt: ByteArray): ByteArray {
        val spec = PBEKeySpec(pin.toCharArray(), salt, PIN_ITERATIONS, 256)
        return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
    }
}
