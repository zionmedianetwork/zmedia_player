package com.example.flutter_media_player

import android.content.Context
import com.google.android.gms.cast.*
import com.google.android.gms.cast.framework.*
import com.google.android.gms.common.api.ResultCallback
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
    }

    private var castContext: CastContext? = null
    private var sessionManager: SessionManager? = null
    private var remoteMediaClient: RemoteMediaClient? = null
    private var config: Map<String, Any>? = null
    
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
        
        // Discovery is automatic with Cast SDK
        // We'll notify about available devices through the Cast button
        notifyCastStatusChanged("discovering", null, false)
        
        // Simulate discovery completion after a short delay
        CoroutineScope(Dispatchers.Main).launch {
            delay(1000)
            notifyDevicesChanged()
        }
    }

    /**
     * Stop device discovery
     */
    fun stopDiscovery() {
        android.util.Log.d(TAG, "Stopping cast device discovery")
        // Discovery management is handled by Cast SDK automatically
    }

    /**
     * Connect to a cast device
     */
    fun connect(deviceId: String): Boolean {
        android.util.Log.d(TAG, "Connecting to cast device: $deviceId")
        
        // The Cast SDK handles connection through the Cast button/dialog
        // This method can be used to programmatically trigger the Cast dialog
        
        val currentSession = sessionManager?.currentCastSession
        if (currentSession != null && currentSession.isConnected) {
            android.util.Log.d(TAG, "Already connected to a cast device")
            return true
        }
        
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
     * Load media on cast device
     */
    fun loadMedia(mediaItem: Map<String, Any>) {
        android.util.Log.d(TAG, "Loading media on cast device")
        
        val client = remoteMediaClient
        if (client == null) {
            android.util.Log.w(TAG, "Cannot load media: No remote media client")
            return
        }
        
        try {
            val mediaInfo = buildMediaInfo(mediaItem)
            val request = MediaLoadRequestData.Builder()
                .setMediaInfo(mediaInfo)
                .setAutoplay(true)
                .build()
            
            client.load(request)
            
            android.util.Log.d(TAG, "Media loaded on cast device")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error loading media on cast: ${e.message}", e)
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
        remoteMediaClient?.seek(position)
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
        
        sessionManager?.removeSessionManagerListener(sessionManagerListener, CastSession::class.java)
        remoteMediaClient = null
        sessionManager = null
        castContext = null
    }

    // Private helper methods

    private fun buildMediaInfo(mediaItem: Map<String, Any>): MediaInfo {
        val contentId = mediaItem["url"] as? String ?: ""
        val title = mediaItem["title"] as? String ?: "Unknown Title"
        val artworkUrl = mediaItem["artworkUrl"] as? String
        val duration = (mediaItem["duration"] as? Number)?.toLong() ?: MediaInfo.UNKNOWN_DURATION
        
        val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MOVIE).apply {
            putString(MediaMetadata.KEY_TITLE, title)
            if (artworkUrl != null) {
                addImage(WebImage(android.net.Uri.parse(artworkUrl)))
            }
        }
        
        return MediaInfo.Builder(contentId)
            .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
            .setContentType("application/x-mpegurl") // For HLS
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
            "id" to (device.deviceId ?: "unknown"),
            "name" to (device.friendlyName ?: "Unknown Device"),
            "type" to "chromecast",
            "model" to (device.modelName ?: ""),
            "manufacturer" to "Google",
            "isConnected" to true
        )
    }

    private fun notifyDevicesChanged() {
        // In a real implementation, we would get the list of available devices
        // For now, we'll send an empty list since Cast SDK handles device discovery through UI
        val devices = emptyList<Map<String, Any>>()
        
        CoroutineScope(Dispatchers.Main).launch {
            methodChannel.invokeMethod("onCastDevicesChanged", mapOf(
                "playerId" to playerId,
                "devices" to devices
            ))
        }
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
        
        CoroutineScope(Dispatchers.Main).launch {
            methodChannel.invokeMethod("onCastStatusChanged", statusMap)
        }
    }
}

