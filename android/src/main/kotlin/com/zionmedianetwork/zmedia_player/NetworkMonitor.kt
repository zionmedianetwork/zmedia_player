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
     * Callback interface for network events
     */
    interface Callback {
        fun onNetworkAvailable(network: Network)
        fun onNetworkLost()
        fun onNetworkQualityChanged(quality: String, downloadSpeed: Int, isMetered: Boolean)
    }

    /**
     * Starts monitoring network status
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
                callback.onNetworkAvailable(network)

                // Check initial quality
                checkNetworkQuality(network)
            }

            override fun onLost(network: Network) {
                Log.d(TAG, "Network lost: $network")
                if (currentNetwork == network) {
                    currentNetwork = null
                    lastNetworkQuality = "offline"
                    callback.onNetworkLost()
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
     * Stops monitoring network status
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
            return mapOf(
                "quality" to "offline",
                "downloadSpeed" to 0,
                "isMetered" to false,
                "connectionType" to "none"
            )
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
            callback.onNetworkAvailable(network)
            checkNetworkQuality(network)
        } else {
            callback.onNetworkLost()
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
        val downloadSpeed = status["downloadSpeed"] as Int
        val isMetered = status["isMetered"] as Boolean

        if (quality != lastNetworkQuality) {
            lastNetworkQuality = quality
            callback.onNetworkQualityChanged(quality, downloadSpeed, isMetered)
        }
    }

    private fun getNetworkStatusFromCapabilities(
        capabilities: NetworkCapabilities?
    ): Map<String, Any> {
        if (capabilities == null) {
            return mapOf(
                "quality" to "offline",
                "downloadSpeed" to 0,
                "isMetered" to false,
                "connectionType" to "none"
            )
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
}
