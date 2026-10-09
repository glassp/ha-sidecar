package dev.glassp.ha_sidecar

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.provider.Settings
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors

/**
 * Pairing with Home Assistant (docs/PAIRING.md). While pairing mode is on (started by the user, ends after
 * [MODE_TTL_MS] or on success) the tablet
 *  - listens on a TCP port and speaks a tiny JSON-over-HTTP handshake that Home Assistant drives, and
 *  - advertises `_ha-sidecar._tcp` with mDNS so Home Assistant finds it (zeroconf discovery).
 *
 * Two ways to authorise Home Assistant: the **code** shown on the tablet (typed into Home Assistant, accepted
 * without further interaction) or **confirm**: the tablet shows a 6-digit comparison number and asks "Allow?".
 * Credentials for the tablet->HA connection arrive AES-GCM encrypted under keys derived in the handshake.
 */
object PairingServer {
    private const val TAG = "PairingServer"
    const val DEFAULT_PORT = 8750
    const val SERVICE_TYPE = "_ha-sidecar._tcp."
    private const val MODE_TTL_MS = 10 * 60_000L
    private const val SESSION_TTL_MS = 3 * 60_000L
    private const val CONFIRM_WAIT_MS = 90_000L
    private const val MAX_FAILED_PROOFS = 5

    private class Session(
        val id: String,
        val keys: PairingCrypto.Keys,
        val tabletPub: ByteArray,
        val haName: String,
        val mode: String,
        val createdAt: Long = System.currentTimeMillis(),
    ) {
        @Volatile var allowed: Boolean? = null
        val lock = Object()
    }

    private val lock = Any()
    private var appCtx: Context? = null
    private var server: ServerSocket? = null
    private var pool = Executors.newFixedThreadPool(6)
    private var nsd: NsdManager? = null
    private var nsdListener: NsdManager.RegistrationListener? = null

    @Volatile private var code = ""
    @Volatile private var expiresAt = 0L
    @Volatile private var failedProofs = 0
    @Volatile private var locked = false
    @Volatile private var session: Session? = null

    val active get() = server != null && System.currentTimeMillis() < expiresAt

    fun start(ctx: Context): Map<String, Any?> {
        synchronized(lock) {
            stopLocked()
            appCtx = ctx.applicationContext
            code = PairingCrypto.newCode()
            expiresAt = System.currentTimeMillis() + MODE_TTL_MS
            failedProofs = 0
            locked = false
            session = null
            pool = Executors.newFixedThreadPool(6)
            val socket = runCatching { ServerSocket(DEFAULT_PORT) }.getOrElse { ServerSocket(0) }
            server = socket
            Thread({ acceptLoop(socket) }, "pairing-accept").apply { isDaemon = true }.start()
            Thread({ expireWatcher(socket) }, "pairing-expiry").apply { isDaemon = true }.start()
            advertise(ctx.applicationContext, socket.localPort)
        }
        EventBus.emit("status_changed")
        return state(ctx)!!
    }

    fun stop() {
        synchronized(lock) { stopLocked() }
        EventBus.emit("status_changed")
    }

    private fun stopLocked() {
        runCatching { server?.close() }
        server = null
        session = null
        pool.shutdownNow()
        runCatching { nsdListener?.let { nsd?.unregisterService(it) } }
        nsdListener = null
    }

    /** Snapshot for the UI; null while pairing mode is off. */
    fun state(ctx: Context): Map<String, Any?>? {
        val s = server ?: return if (locked) mapOf("active" to false, "locked" to true) else null
        val sess = session
        return mapOf(
            "active" to true,
            "locked" to locked,
            "port" to s.localPort,
            "hosts" to addresses(),
            "code" to PairingCrypto.displayCode(code),
            "expires_at" to expiresAt,
            "device_id" to Prefs.deviceId(ctx),
            "name" to deviceName(ctx),
            "request" to sess?.takeIf { it.mode == "confirm" && it.allowed == null }
                ?.let { mapOf("session" to it.id, "ha_name" to it.haName, "sas" to it.keys.sas) },
        )
    }

    /** The user's answer to a confirm-mode request shown on the tablet. */
    fun answer(allow: Boolean) {
        val s = session ?: return
        s.allowed = allow
        synchronized(s.lock) { s.lock.notifyAll() }
        EventBus.emit("status_changed")
    }

    // --- mDNS ------------------------------------------------------------------------------------

    private fun advertise(ctx: Context, port: Int) {
        val manager = ctx.getSystemService(Context.NSD_SERVICE) as NsdManager
        val info = NsdServiceInfo().apply {
            serviceName = "ha-sidecar-" + Prefs.deviceId(ctx).take(8)
            serviceType = SERVICE_TYPE
            setPort(port)
            setAttribute("id", Prefs.deviceId(ctx))
            setAttribute("name", deviceName(ctx))
            setAttribute("model", Build.MODEL)
            setAttribute("v", "1")
        }
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(i: NsdServiceInfo) { Log.i(TAG, "mDNS registered as ${i.serviceName} on $port") }
            override fun onRegistrationFailed(i: NsdServiceInfo, code: Int) { Log.w(TAG, "mDNS registration failed: $code") }
            override fun onServiceUnregistered(i: NsdServiceInfo) { Log.i(TAG, "mDNS unregistered") }
            override fun onUnregistrationFailed(i: NsdServiceInfo, code: Int) { Log.w(TAG, "mDNS unregistration failed: $code") }
        }
        nsd = manager
        nsdListener = listener
        runCatching { manager.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener) }
            .onFailure { Log.w(TAG, "mDNS registration threw", it); nsdListener = null }
    }

    // --- server ----------------------------------------------------------------------------------

    private fun expireWatcher(socket: ServerSocket) {
        while (server === socket) {
            if (System.currentTimeMillis() >= expiresAt) {
                synchronized(lock) { if (server === socket) stopLocked() }
                EventBus.emit("status_changed")
                return
            }
            Thread.sleep(1000)
        }
    }

    private fun acceptLoop(socket: ServerSocket) {
        while (!socket.isClosed) {
            val client = runCatching { socket.accept() }.getOrNull() ?: return
            runCatching { pool.execute { handle(client) } }.onFailure { runCatching { client.close() } }
        }
    }

    private class Request(val method: String, val path: String, val body: String)

    private fun handle(client: Socket) {
        client.use {
            it.soTimeout = 15_000
            val ctx = appCtx ?: return
            val req = runCatching { readRequest(it.getInputStream()) }.getOrNull()
            val (status, body) = if (req == null) 400 to error("bad_request") else route(ctx, req)
            runCatching { writeResponse(it, status, body) }
        }
    }

    private fun route(ctx: Context, req: Request): Pair<Int, JSONObject> = try {
        when {
            req.method == "GET" && req.path == "/pair/v1/info" ->
                200 to JSONObject().put("v", 1).put("id", Prefs.deviceId(ctx)).put("name", deviceName(ctx))
                    .put("model", Build.MODEL).put("pairing", active)
            req.method == "POST" && req.path == "/pair/v1/hello" -> hello(ctx, JSONObject(req.body))
            req.method == "POST" && req.path == "/pair/v1/finish" -> finish(ctx, JSONObject(req.body))
            else -> 404 to error("not_found")
        }
    } catch (e: Exception) {
        Log.w(TAG, "request failed", e)
        400 to error("bad_request")
    }

    private fun hello(ctx: Context, b: JSONObject): Pair<Int, JSONObject> {
        if (!active) return 403 to error("not_pairing")
        val mode = b.optString("mode", "token")
        if (mode != "token" && mode != "confirm") return 400 to error("bad_mode")
        val haPub = Base64.decode(b.getString("ha_pub"), Base64.NO_WRAP)
        val haNonce = Base64.decode(b.getString("ha_nonce"), Base64.NO_WRAP)
        if (haNonce.size < 16) return 400 to error("bad_nonce")
        val pair = PairingCrypto.newKeyPair()
        val nonce = PairingCrypto.randomBytes(16)
        val keys = PairingCrypto.deriveKeys(PairingCrypto.sharedSecret(pair, haPub), haNonce, nonce)
        val sess = Session(
            PairingCrypto.randomBytes(8).joinToString("") { "%02x".format(it) }, keys,
            PairingCrypto.publicBytes(pair), b.optString("ha_name", "Home Assistant").take(64), mode,
        )
        session = sess
        if (mode == "confirm") {
            EventBus.emit("pairing_request", mapOf("session" to sess.id, "ha_name" to sess.haName, "sas" to keys.sas))
            EventBus.emit("status_changed")
            UiHost.show(ctx, UiHost.MAIN) // bring the app forward so the request is seen
        }
        return 200 to JSONObject().put("v", 1).put("session", sess.id)
            .put("tablet_pub", Base64.encodeToString(sess.tabletPub, Base64.NO_WRAP))
            .put("tablet_nonce", Base64.encodeToString(nonce, Base64.NO_WRAP))
            .put("id", Prefs.deviceId(ctx)).put("name", deviceName(ctx)).put("model", Build.MODEL)
    }

    private fun finish(ctx: Context, b: JSONObject): Pair<Int, JSONObject> {
        val sess = session?.takeIf { it.id == b.optString("session") && System.currentTimeMillis() - it.createdAt < SESSION_TTL_MS }
            ?: return 403 to error("no_session")
        if (!active) return 403 to error("not_pairing")

        if (sess.mode == "token") {
            val given = Base64.decode(b.optString("proof"), Base64.NO_WRAP)
            val expected = PairingCrypto.proof(sess.keys.mac, code)
            if (!PairingCrypto.constantTimeEquals(given, expected)) {
                if (++failedProofs >= MAX_FAILED_PROOFS) {
                    locked = true
                    synchronized(lock) { stopLocked() }
                    EventBus.emit("pairing_locked")
                    EventBus.emit("status_changed")
                }
                return 403 to error("bad_token")
            }
        } else {
            val deadline = System.currentTimeMillis() + CONFIRM_WAIT_MS
            synchronized(sess.lock) {
                while (sess.allowed == null && System.currentTimeMillis() < deadline) sess.lock.wait(500)
            }
            when (sess.allowed) {
                true -> Unit
                false -> return 403 to error("denied")
                null -> return 408 to error("timeout")
            }
        }

        val plain = try {
            PairingCrypto.open(
                sess.keys.enc, Base64.decode(b.getString("iv"), Base64.NO_WRAP),
                Base64.decode(b.getString("ct"), Base64.NO_WRAP), (PairingCrypto.INFO + sess.id).toByteArray(),
            )
        } catch (e: Exception) {
            return 403 to error("decrypt_failed")
        }
        val creds = JSONObject(String(plain))
        // org.json turns a JSON null into the string "null" with optString: check for it explicitly
        fun text(key: String): String? = if (creds.isNull(key)) null else creds.optString(key).ifBlank { null }
        EventBus.emit(
            "paired",
            mapOf(
                "token" to creds.getString("token"),
                "internal_url" to text("internal_url"),
                "external_url" to text("external_url"),
                "ha_name" to (text("ha_name") ?: sess.haName),
            ),
        )
        synchronized(lock) { stopLocked() }
        EventBus.emit("status_changed")
        return 200 to JSONObject().put("ok", true).put("id", Prefs.deviceId(ctx))
    }

    // --- tiny HTTP -------------------------------------------------------------------------------

    private fun error(code: String) = JSONObject().put("error", code)

    private fun readRequest(input: InputStream): Request {
        fun line(): String {
            val out = ByteArrayOutputStream()
            while (true) {
                val c = input.read()
                if (c == -1 || c == '\n'.code) break
                if (c != '\r'.code) out.write(c)
                if (out.size() > 4096) error("line too long")
            }
            return out.toString("UTF-8")
        }
        val first = line().split(" ")
        var length = 0
        while (true) {
            val h = line()
            if (h.isEmpty()) break
            if (h.startsWith("content-length:", ignoreCase = true)) length = h.substringAfter(':').trim().toInt()
        }
        require(length in 0..16_384)
        val body = ByteArray(length)
        var read = 0
        while (read < length) {
            val n = input.read(body, read, length - read)
            if (n < 0) break
            read += n
        }
        return Request(first[0], first.getOrElse(1) { "/" }.substringBefore('?'), String(body, 0, read))
    }

    private fun writeResponse(socket: Socket, status: Int, body: JSONObject) {
        val bytes = body.toString().toByteArray()
        val text = when (status) { 200 -> "OK"; 400 -> "Bad Request"; 403 -> "Forbidden"; 404 -> "Not Found"; 408 -> "Request Timeout"; else -> "Error" }
        socket.getOutputStream().apply {
            write("HTTP/1.1 $status $text\r\nContent-Type: application/json\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n".toByteArray())
            write(bytes)
            flush()
        }
    }

    // --- helpers ---------------------------------------------------------------------------------

    fun deviceName(ctx: Context): String =
        Settings.Global.getString(ctx.contentResolver, "device_name")?.takeIf { it.isNotBlank() } ?: Build.MODEL

    /** IPv4 addresses of this device, for the on-screen "address" line (manual pairing). */
    fun addresses(): List<String> = runCatching {
        NetworkInterface.getNetworkInterfaces().toList().filter { it.isUp && !it.isLoopback }
            .flatMap { it.inetAddresses.toList() }.filterIsInstance<Inet4Address>().map { it.hostAddress!! }
    }.getOrDefault(emptyList())
}
