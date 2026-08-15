package com.zionmedianetwork.zmedia_player

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.util.Log

/**
 * Network monitoring for real-time connection status and quality assessment.
 *
 * Uses ConnectivityManager.NetworkCallback to monitor network changes and
 * estimate quality based on bandwidth capabilities. Provides callbacks for
 * network availability, loss, and quality changes.
 *
 * H-06: every [Callback] method is handed a full status map matching the
 * shape [lib/src/models/network_status.dart]'s `NetworkStatus.fromPlatform`
 * expects (`quality`, `downloadSpeed`, `isMetered`, `connectionType`) so the
 * plugin layer (see `ZMediaPlayerPlugin.onNetworkAvailable` /
 * `onNetworkLost` / `onNetworkQualityChanged`) can forward it to Dart
 * unmodified instead of re-deriving it from individual scalar arguments.
 */
class NetworkMonitor(
    private val context: Context,
    private val callback: Callback
) {
    companion object {
        private const val TAG = "NetworkMonitor"

        // Quality thresholds (Kbps)
        private const val EXCELLENT_THRESHOLD = 5000 // 5 Mbps
        private const val GOOD_THRESHOLD = 1000      // 1 Mbps
        private const val FAIR_THRESHOLD = 500       // 500 Kbps
    }

    private val connectivityManager: ConnectivityManager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var isMonitoring = false
    private var currentNetwork: Network? = null
    private var lastNetworkQuality: String = "unknown"

    /**
     * Callback interface for network events. Every method receives the full
     * status map (see class doc) so callers never need to reconstruct it
     * from partial arguments.
     */
    interface Callback {
        fun onNetworkAvailable(status: Map<String, Any>)
        fun onNetworkLost(status: Map<String, Any>)
        fun onNetworkQualityChanged(status: Map<String, Any>)
    }

    /**
     * Starts monitoring network status. Safe to call once; a second call
     * while already monitoring is a no-op (mirrors [stopMonitoring]'s own
     * guard so start/stop can be called defensively from plugin lifecycle
     * hooks without double-registering the callback).
     */
    fun startMonitoring() {
        if (isMonitoring) {
            Log.d(TAG, "Already monitoring network")
            return
        }

        val networkRequest = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                Log.d(TAG, "Network available: $network")
                currentNetwork = network
                val caps = connectivityManager.getNetworkCapabilities(network)
                callback.onNetworkAvailable(getNetworkStatusFromCapabilities(caps))

                // Check initial quality
                checkNetworkQuality(network, caps)
            }

            override fun onLost(network: Network) {
                Log.d(TAG, "Network lost: $network")
                if (currentNetwork == network) {
                    currentNetwork = null
                    lastNetworkQuality = "offline"
                    callback.onNetworkLost(offlineStatus())
                }
            }

            override fun onCapabilitiesChanged(
                network: Network,
                capabilities: NetworkCapabilities
            ) {
                Log.d(TAG, "Network capabilities changed: $network")
                checkNetworkQuality(network, capabilities)
            }
        }

        try {
            connectivityManager.registerNetworkCallback(networkRequest, networkCallback!!)
            isMonitoring = true
            Log.d(TAG, "Network monitoring started")

            // Check current network status
            checkCurrentNetwork()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start network monitoring", e)
            networkCallback = null
        }
    }

    /**
     * Stops monitoring network status and unregisters the callback.
     * `ConnectivityManager.NetworkCallback` leaks if never unregistered, so
     * every caller of [startMonitoring] must be paired with a call here
     * (see `ZMediaPlayerPlugin.onDetachedFromEngine`).
     */
    fun stopMonitoring() {
        if (!isMonitoring) {
            return
        }

        try {
            networkCallback?.let { connectivityManager.unregisterNetworkCallback(it) }
            networkCallback = null
            isMonitoring = false
            currentNetwork = null
            Log.d(TAG, "Network monitoring stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop network monitoring", e)
        }
    }

    /**
     * Gets current network status
     */
    fun getCurrentNetworkStatus(): Map<String, Any> {
        val network = currentNetwork ?: connectivityManager.activeNetwork

        if (network == null) {
            return offlineStatus()
        }

        val capabilities = connectivityManager.getNetworkCapabilities(network)
        return getNetworkStatusFromCapabilities(capabilities)
    }

    /**
     * Checks if network is currently available
     */
    fun isNetworkAvailable(): Boolean {
        val network = connectivityManager.activeNetwork ?: return false
        val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    // Private methods

    private fun checkCurrentNetwork() {
        val network = connectivityManager.activeNetwork
        if (network != null) {
            currentNetwork = network
            val caps = connectivityManager.getNetworkCapabilities(network)
            callback.onNetworkAvailable(getNetworkStatusFromCapabilities(caps))
            checkNetworkQuality(network, caps)
        } else {
            callback.onNetworkLost(offlineStatus())
        }
    }

    private fun checkNetworkQuality(
        network: Network,
        capabilities: NetworkCapabilities? = null
    ) {
        val caps = capabilities ?: connectivityManager.getNetworkCapabilities(network)

        if (caps == null) {
            Log.w(TAG, "No capabilities available for network: $network")
            return
        }

        val status = getNetworkStatusFromCapabilities(caps)
        val quality = status["quality"] as String

        if (quality != lastNetworkQuality) {
            lastNetworkQuality = quality
            callback.onNetworkQualityChanged(status)
        }
    }

    private fun getNetworkStatusFromCapabilities(
        capabilities: NetworkCapabilities?
    ): Map<String, Any> {
        if (capabilities == null) {
            return offlineStatus()
        }

        // Get download bandwidth (in Kbps)
        val downloadKbps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            capabilities.linkDownstreamBandwidthKbps
        } else {
            // Estimate based on connection type for older Android versions
            estimateBandwidthFromType(capabilities)
        }

        // Convert Kbps to bytes per second
        val downloadSpeed = (downloadKbps * 1024) / 8

        // Determine quality
        val quality = when {
            downloadKbps >= EXCELLENT_THRESHOLD -> "excellent"
            downloadKbps >= GOOD_THRESHOLD -> "good"
            downloadKbps >= FAIR_THRESHOLD -> "fair"
            downloadKbps > 0 -> "poor"
            else -> "offline"
        }

        // Check if metered
        val isMetered = !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)

        // Determine connection type
        val connectionType = when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> "bluetooth"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            else -> "unknown"
        }

        return mapOf(
            "quality" to quality,
            "downloadSpeed" to downloadSpeed,
            "isMetered" to isMetered,
            "connectionType" to connectionType
        )
    }

    private fun estimateBandwidthFromType(capabilities: NetworkCapabilities): Int {
        return when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 10000 // 10 Mbps
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 2000 // 2 Mbps
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> 50000 // 50 Mbps
            else -> 1000 // 1 Mbps default
        }
    }

    /** Canonical "no connection" status map, shared by every offline path. */
    private fun offlineStatus(): Map<String, Any> = mapOf(
        "quality" to "offline",
        "downloadSpeed" to 0,
        "isMetered" to false,
        "connectionType" to "none"
    )
}
