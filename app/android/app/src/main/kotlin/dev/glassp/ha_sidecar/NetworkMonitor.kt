package dev.glassp.ha_sidecar

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper

/**
 * What kind of network the tablet is on: Wi-Fi (and its name), Ethernet, cellular, VPN. Home Assistant is reached on
 * its internal address at home and on its external address elsewhere, so the Dart side needs to know when this changes.
 * The Wi-Fi name needs the location permission (an Android rule) and shows up as null without it.
 */
object NetworkMonitor {
    private val main = Handler(Looper.getMainLooper())
    private var ctx: Context? = null
    private var started = false
    @Volatile private var last: Map<String, Any?> = emptyMap()
    private val publish = Runnable { publishNow() }

    fun start(context: Context) {
        if (started) return
        started = true
        ctx = context.applicationContext
        val cm = ctx!!.getSystemService(ConnectivityManager::class.java)
        cm.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = changed()
            override fun onLost(network: Network) = changed()
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = changed()
        })
        // a VPN is not necessarily the default network of every app; watch all networks for it
        cm.registerNetworkCallback(
            android.net.NetworkRequest.Builder().build(),
            object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = changed()
                override fun onLost(network: Network) = changed()
            },
        )
        publishNow()
    }

    private fun changed() {
        main.removeCallbacks(publish)
        main.postDelayed(publish, 600) // Wi-Fi roaming produces bursts
    }

    private fun publishNow() {
        val now = snapshot()
        if (now != last) {
            last = now
            EventBus.emit("network_changed", now)
            EventBus.emit("status_changed")
        }
    }

    /** `ssid` is null when unknown (not on Wi-Fi, no location permission, or location switched off). */
    fun snapshot(): Map<String, Any?> {
        val c = ctx ?: return mapOf("connected" to false)
        val cm = c.getSystemService(ConnectivityManager::class.java)
        var wifi = false
        var ethernet = false
        var cellular = false
        var vpn = false
        var connected = false
        for (n in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(n) ?: continue
            if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) continue
            // a VPN network usually is not "validated" the same way; count it when it is up at all
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) { vpn = true; continue }
            if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) continue
            connected = true
            wifi = wifi || caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
            ethernet = ethernet || caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
            cellular = cellular || caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
        }
        return mapOf(
            "connected" to (connected || vpn),
            "wifi" to wifi, "ethernet" to ethernet, "cellular" to cellular, "vpn" to vpn,
            "ssid" to if (wifi) ssid(c) else null,
            "location_granted" to locationGranted(c),
        )
    }

    fun locationGranted(c: Context) =
        c.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    @Suppress("DEPRECATION")
    private fun ssid(c: Context): String? {
        if (!locationGranted(c)) return null
        val raw = c.applicationContext.getSystemService(WifiManager::class.java)?.connectionInfo?.ssid ?: return null
        val name = raw.removePrefix("\"").removeSuffix("\"")
        return name.takeIf { it.isNotBlank() && it != WifiManager.UNKNOWN_SSID }
    }
}
