package com.zionmedianetwork.zmedia_player

import android.content.Context
import androidx.mediarouter.media.MediaRouter
import androidx.mediarouter.media.MediaRouteSelector
import com.google.android.gms.cast.*
import com.google.android.gms.cast.framework.*
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import com.google.android.gms.common.api.ResultCallback
import com.google.android.gms.common.images.WebImage
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import org.json.JSONObject

/**
 * Handles Chromecast functionality using Google Cast SDK
 */
class CastHandler(
    private val context: Context,
    private val playerId: String,
    private val methodChannel: MethodChannel
) {
    companion object {
        private const val TAG = "CastHandler"
        private const val CAST_NAMESPACE = "urn:x-cast:com.google.cast.media"
        // Must match the receiver app ID in CastOptionsProvider
        private const val RECEIVER_APP_ID = "CC1AD845"
    }

    // Owned scope: cancelled in dispose() to stop all coroutines launched by this handler.
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    private var castContext: CastContext? = null
    private var sessionManager: SessionManager? = null
    private var remoteMediaClient: RemoteMediaClient? = null
    private var config: Map<String, Any>? = null

    // MediaRouter for device discovery
    private var mediaRouter: MediaRouter? = null
    private var mediaRouteSelector: MediaRouteSelector? = null
    private var isDiscovering = false

    private val sessionManagerListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarting(session: CastSession) {
            android.util.Log.d(TAG, "Cast session starting")
            notifyCastStatusChanged("connecting", null, false)
        }

        override fun onSessionStarted(session: CastSession, sessionId: String) {
            android.util.Log.d(TAG, "Cast session started: $sessionId")
            remoteMediaClient = session.remoteMediaClient
            setupRemoteMediaClientListeners()
            notifyCastStatusChanged("connected", getDeviceInfo(session), true)
        }

        override fun onSessionEnding(session: CastSession) {
            android.util.Log.d(TAG, "Cast session ending")
            notifyCastStatusChanged("disconnecting", null, false)
        }

        override fun onSessionEnded(session: CastSession, error: Int) {
            android.util.Log.d(TAG, "Cast session ended with error code: $error")
            remoteMediaClient = null
            notifyCastStatusChanged("disconnected", null, false)
        }

        override fun onSessionResuming(session: CastSession, sessionId: String) {
            android.util.Log.d(TAG, "Cast session resuming: $sessionId")
        }

        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            android.util.Log.d(TAG, "Cast session resumed")
            remoteMediaClient = session.remoteMediaClient
            setupRemoteMediaClientListeners()
            notifyCastStatusChanged("connected", getDeviceInfo(session), true)
        }

        override fun onSessionSuspended(session: CastSession, reason: Int) {
            android.util.Log.d(TAG, "Cast session suspended: $reason")
        }

        override fun onSessionStartFailed(session: CastSession, error: Int) {
            android.util.Log.e(TAG, "Cast session start failed: $error")
            notifyCastStatusChanged("failed", null, false, "Failed to start cast session")
        }

        override fun onSessionResumeFailed(session: CastSession, error: Int) {
            android.util.Log.e(TAG, "Cast session resume failed: $error")
        }
    }

    private val mediaRouterCallback = object : MediaRouter.Callback() {
        override fun onRouteAdded(router: MediaRouter, route: MediaRouter.RouteInfo) {
            android.util.Log.d(TAG, "Cast route added: ${route.name}")
            if (isDiscovering) {
                notifyDevicesChanged()
            }
        }

        override fun onRouteRemoved(router: MediaRouter, route: MediaRouter.RouteInfo) {
            android.util.Log.d(TAG, "Cast route removed: ${route.name}")
            if (isDiscovering) {
                notifyDevicesChanged()
            }
        }

        override fun onRouteChanged(router: MediaRouter, route: MediaRouter.RouteInfo) {
            android.util.Log.d(TAG, "Cast route changed: ${route.name}")
            if (isDiscovering) {
                notifyDevicesChanged()
            }
        }
    }

    /**
     * Initialize the cast handler
     */
    fun initialize(config: Map<String, Any>) {
        android.util.Log.d(TAG, "Initializing cast handler for player: $playerId")

        this.config = config

        try {
            // Get Cast context
            castContext = CastContext.getSharedInstance(context)
            sessionManager = castContext?.sessionManager

            // Initialize MediaRouter for device discovery
            mediaRouter = MediaRouter.getInstance(context)
            mediaRouteSelector = MediaRouteSelector.Builder()
                .addControlCategory(CastMediaControlIntent.categoryForCast(RECEIVER_APP_ID))
                .build()

            // Register session listener
            sessionManager?.addSessionManagerListener(sessionManagerListener, CastSession::class.java)

            // Check if already connected
            val currentSession = sessionManager?.currentCastSession
            if (currentSession != null && currentSession.isConnected) {
                remoteMediaClient = currentSession.remoteMediaClient
                setupRemoteMediaClientListeners()
                notifyCastStatusChanged("connected", getDeviceInfo(currentSession), true)
            } else {
                notifyCastStatusChanged("disconnected", null, false)
            }

            android.util.Log.d(TAG, "Cast handler initialized successfully")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to initialize cast handler: ${e.message}", e)
        }
    }

    /**
     * Start device discovery
     */
    fun startDiscovery() {
        android.util.Log.d(TAG, "Starting cast device discovery")
        android.util.Log.d(TAG, "Using receiver app ID: $RECEIVER_APP_ID")

        isDiscovering = true
        notifyCastStatusChanged("discovering", null, false)

        try {
            // Register MediaRouter callback to listen for device changes
            mediaRouter?.addCallback(
                mediaRouteSelector!!,
                mediaRouterCallback,
                MediaRouter.CALLBACK_FLAG_REQUEST_DISCOVERY
            )

            android.util.Log.d(TAG, "MediaRouter callback registered with discovery flag")

            // Log current route count
            val currentRouteCount = mediaRouter?.routes?.size ?: 0
            android.util.Log.d(TAG, "Current MediaRouter routes: $currentRouteCount")

            // Immediately notify with currently available devices
            notifyDevicesChanged()

            android.util.Log.d(TAG, "Cast device discovery started successfully")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to start discovery: ${e.message}", e)
            isDiscovering = false
        }
    }

    /**
     * Stop device discovery
     */
    fun stopDiscovery() {
        android.util.Log.d(TAG, "Stopping cast device discovery")

        isDiscovering = false

        try {
            // Unregister MediaRouter callback
            mediaRouter?.removeCallback(mediaRouterCallback)
            android.util.Log.d(TAG, "Cast device discovery stopped successfully")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to stop discovery: ${e.message}", e)
        }
    }

    /**
     * Connect to a cast device
     */
    fun connect(deviceId: String): Boolean {
        android.util.Log.d(TAG, "========================================")
        android.util.Log.d(TAG, "Connecting to cast device: $deviceId")

        // Check if already connected
        val currentSession = sessionManager?.currentCastSession
        if (currentSession != null && currentSession.isConnected) {
            val currentDeviceId = currentSession.castDevice?.deviceId
            if (currentDeviceId == deviceId) {
                android.util.Log.d(TAG, "Already connected to this device")
                android.util.Log.d(TAG, "========================================")
                return true
            }
        }

        // Find the route with the matching deviceId
        val router = mediaRouter
        if (router == null) {
            android.util.Log.e(TAG, "MediaRouter is null, cannot connect")
            android.util.Log.e(TAG, "========================================")
            return false
        }

        val routes = router.routes
        for (route in routes) {
            if (route.id == deviceId) {
                android.util.Log.d(TAG, "Found route for device: ${route.name}")
                try {
                    // Select the route to initiate connection
                    // This is async - the session will connect via callbacks
                    router.selectRoute(route)
                    android.util.Log.d(TAG, "✓ Route selected - Cast session will connect asynchronously")
                    android.util.Log.d(TAG, "========================================")
                    return true
                } catch (e: Exception) {
                    android.util.Log.e(TAG, "Failed to select route: ${e.message}", e)
                    android.util.Log.e(TAG, "========================================")
                    return false
                }
            }
        }

        android.util.Log.e(TAG, "No route found for device ID: $deviceId")
        android.util.Log.e(TAG, "========================================")
        return false
    }

    /**
     * Disconnect from current cast device
     */
    fun disconnect() {
        android.util.Log.d(TAG, "Disconnecting from cast device")

        try {
            sessionManager?.endCurrentSession(true)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error disconnecting from cast: ${e.message}", e)
        }
    }

    /**
     * Load media on cast device.
     *
     * Polling for RemoteMediaClient readiness runs on the main thread: it reads
     * the Cast SDK's currentCastSession, which asserts the main thread. coroutine
     * delay() suspends rather than blocks, so the UI thread is never held (no ANR).
     * The owned [scope] is used so this coroutine is automatically cancelled
     * when [dispose] is called.
     */
    fun loadMedia(mediaItem: Map<String, Any>) {
        android.util.Log.d(TAG, "========================================")
        android.util.Log.d(TAG, "Loading media on cast device")
        android.util.Log.d(TAG, "Media title: ${mediaItem["title"]}")
        android.util.Log.d(TAG, "Media URL: ${mediaItem["url"]}")

        // MUST run on Main: the poll reads sessionManager.currentCastSession
        // (Cast SDK getCurrentCastSession()), which asserts the main thread.
        scope.launch(Dispatchers.Main) {
            // Poll for remote media client on the main thread, max 2 s.
            var client: RemoteMediaClient? = remoteMediaClient
            var attempts = 0
            val maxAttempts = 20 // 20 × 100 ms = 2 000 ms

            while (client == null && attempts < maxAttempts) {
                android.util.Log.d(TAG, "Waiting for remote media client... (attempt ${attempts + 1}/$maxAttempts)")
                delay(100)
                client = remoteMediaClient ?: sessionManager?.currentCastSession?.remoteMediaClient
                attempts++
            }

            if (client == null) {
                android.util.Log.e(TAG, "Cannot load media: No remote media client available after ${maxAttempts * 100}ms!")
                android.util.Log.e(TAG, "SessionManager: $sessionManager")
                android.util.Log.e(TAG, "Current session: ${sessionManager?.currentCastSession}")
                android.util.Log.e(TAG, "Session connected: ${sessionManager?.currentCastSession?.isConnected}")
                android.util.Log.e(TAG, "========================================")
                return@launch
            }

            android.util.Log.d(TAG, "✓ Remote media client available after ${attempts * 100}ms: $client")

            // Update our reference and send the load request back on Main.
            withContext(Dispatchers.Main) {
                remoteMediaClient = client

                try {
                    val mediaInfo = buildMediaInfo(mediaItem)
                    android.util.Log.d(TAG, "MediaInfo built - Content ID: ${mediaInfo.contentId}")

                    val request = MediaLoadRequestData.Builder()
                        .setMediaInfo(mediaInfo)
                        .setAutoplay(true)
                        .build()

                    android.util.Log.d(TAG, "Sending load request to Cast device...")
                    val loadResult = client.load(request)

                    loadResult.setResultCallback { mediaChannelResult ->
                        if (mediaChannelResult.status.isSuccess) {
                            android.util.Log.d(TAG, "✓✓✓ Media successfully loaded on Cast device!")
                        } else {
                            android.util.Log.e(TAG, "✗✗✗ Failed to load media on Cast device: ${mediaChannelResult.status}")
                        }
                    }

                    android.util.Log.d(TAG, "========================================")
                } catch (e: Exception) {
                    // e.message can embed the media URL logged above at Log.d (Media URL:
                    // ..., stripped from release by ProGuard) — redact here too since Log.e
                    // is not stripped (H-03).
                    android.util.Log.e(TAG, "Error loading media on cast: ${LogSanitizer.redactUrls(e.message)}", e)
                    android.util.Log.e(TAG, "========================================")
                }
            }
        }
    }

    /**
     * Play on cast device
     */
    fun play() {
        remoteMediaClient?.play()
    }

    /**
     * Pause on cast device
     */
    fun pause() {
        remoteMediaClient?.pause()
    }

    /**
     * Seek on cast device
     */
    fun seekTo(position: Long) {
        remoteMediaClient?.seek(position, RemoteMediaClient.RESUME_STATE_UNCHANGED)
    }

    /**
     * Set volume on cast device
     */
    fun setVolume(volume: Double) {
        try {
            val castSession = sessionManager?.currentCastSession
            castSession?.volume = volume
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error setting cast volume: ${e.message}", e)
        }
    }

    /**
     * Dispose the cast handler
     */
    fun dispose() {
        android.util.Log.d(TAG, "Disposing cast handler")

        // Cancel all coroutines owned by this handler before any other teardown.
        scope.cancel()

        // Stop discovery if active
        if (isDiscovering) {
            stopDiscovery()
        }

        // Remove session listener
        sessionManager?.removeSessionManagerListener(sessionManagerListener, CastSession::class.java)

        // Cleanup references
        remoteMediaClient = null
        sessionManager = null
        castContext = null
        mediaRouter = null
        mediaRouteSelector = null
    }

    // Private helper methods

    private fun buildMediaInfo(mediaItem: Map<String, Any>): MediaInfo {
        val contentId = mediaItem["url"] as? String ?: ""
        val title = mediaItem["title"] as? String ?: "Unknown Title"
        val artworkUrl = mediaItem["artworkUrl"] as? String
        val duration = (mediaItem["duration"] as? Number)?.toLong() ?: MediaInfo.UNKNOWN_DURATION

        // Detect content type from URL
        val contentType = when {
            contentId.contains(".m3u8") || contentId.contains("/hls/") -> "application/x-mpegurl" // HLS
            contentId.contains(".mpd") -> "application/dash+xml" // DASH
            contentId.contains(".mp4") -> "video/mp4" // MP4
            contentId.contains(".webm") -> "video/webm" // WebM
            contentId.contains(".mkv") -> "video/x-matroska" // MKV
            else -> "video/mp4" // Default to MP4
        }

        android.util.Log.d(TAG, "Content type detected: $contentType for URL: $contentId")

        val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MOVIE).apply {
            putString(MediaMetadata.KEY_TITLE, title)
            if (artworkUrl != null) {
                addImage(WebImage(android.net.Uri.parse(artworkUrl)))
            }
        }

        return MediaInfo.Builder(contentId)
            .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
            .setContentType(contentType)
            .setMetadata(metadata)
            .setStreamDuration(duration)
            .build()
    }

    private fun setupRemoteMediaClientListeners() {
        val client = remoteMediaClient ?: return

        client.registerCallback(object : RemoteMediaClient.Callback() {
            override fun onStatusUpdated() {
                val mediaStatus = client.mediaStatus
                if (mediaStatus != null) {
                    android.util.Log.d(TAG, "Cast media status updated: ${mediaStatus.playerState}")
                    // Notify Flutter of status changes if needed
                }
            }

            override fun onMetadataUpdated() {
                android.util.Log.d(TAG, "Cast media metadata updated")
            }

            override fun onQueueStatusUpdated() {
                android.util.Log.d(TAG, "Cast queue status updated")
            }
        })
    }

    private fun getDeviceInfo(session: CastSession): Map<String, Any> {
        val device = session.castDevice
        return mapOf(
            "id" to (device?.deviceId ?: "unknown"),
            "name" to (device?.friendlyName ?: "Unknown Device"),
            "type" to "chromecast",
            "model" to (device?.modelName ?: ""),
            "manufacturer" to "Google",
            "isConnected" to true
        )
    }

    private fun notifyDevicesChanged() {
        val devices = getAvailableDevices()

        scope.launch {
            methodChannel.invokeMethod("onCastDevicesChanged", mapOf(
                "playerId" to playerId,
                "devices" to devices
            ))
        }
    }

    /**
     * Get list of available Cast devices from MediaRouter
     */
    private fun getAvailableDevices(): List<Map<String, Any>> {
        val devices = mutableListOf<Map<String, Any>>()

        try {
            val router = mediaRouter ?: run {
                android.util.Log.w(TAG, "MediaRouter is null, cannot get devices")
                return devices
            }
            val selector = mediaRouteSelector ?: run {
                android.util.Log.w(TAG, "MediaRouteSelector is null, cannot get devices")
                return devices
            }

            // Get all routes
            val routes = router.routes
            android.util.Log.d(TAG, "Scanning ${routes.size} total routes")

            for (route in routes) {
                val matchesSelector = route.matchesSelector(selector)
                val isDefault = route.isDefault

                android.util.Log.d(TAG, "Route: ${route.name}, matches=$matchesSelector, isDefault=$isDefault, enabled=${route.isEnabled}")

                // Check if this route matches our Cast selector and is not the default route
                if (matchesSelector && !isDefault) {
                    val device = mapOf(
                        "id" to route.id,
                        "name" to route.name,
                        "type" to "chromecast",
                        "description" to (route.description ?: ""),
                        "isConnected" to route.isSelected,
                        "isConnecting" to (route.connectionState == MediaRouter.RouteInfo.CONNECTION_STATE_CONNECTING),
                        "isAvailable" to route.isEnabled
                    )
                    devices.add(device)
                    android.util.Log.d(TAG, "✓ Found Cast device: ${route.name} (${route.id})")
                }
            }

            android.util.Log.d(TAG, "Total Cast devices found: ${devices.size}")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error getting available devices: ${e.message}", e)
        }

        return devices
    }

    private fun notifyCastStatusChanged(
        state: String,
        device: Map<String, Any>?,
        isCasting: Boolean,
        errorMessage: String? = null
    ) {
        val statusMap = mapOf(
            "playerId" to playerId,
            "state" to state,
            "device" to device,
            "isAvailable" to true,
            "isCasting" to isCasting,
            "errorMessage" to errorMessage
        )

        scope.launch {
            methodChannel.invokeMethod("onCastStatusChanged", statusMap)
        }
    }
}
