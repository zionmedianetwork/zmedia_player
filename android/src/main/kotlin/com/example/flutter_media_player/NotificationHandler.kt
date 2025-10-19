package com.example.flutter_media_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.session.MediaButtonReceiver
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.net.URL

/**
 * Handles media notifications using MediaSession and NotificationCompat
 */
class NotificationHandler(
    private val context: Context,
    private val playerId: String,
    private val methodChannel: MethodChannel
) {
    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val TAG = "NotificationHandler"
    }

    private var notificationManager: NotificationManager? = null
    private var mediaSession: MediaSessionCompat? = null
    private var notification: Notification? = null
    private var isShowing = false
    
    // Configuration
    private var channelId: String = "media_playback"
    private var channelName: String = "Media Playback"
    private var showPlayPause: Boolean = true
    private var showNext: Boolean = true
    private var showPrevious: Boolean = true
    private var showStop: Boolean = false
    private var showSeekForward: Boolean = false
    private var showSeekBackward: Boolean = false
    private var seekInterval: Int = 10
    
    // Current media info
    private var currentTitle: String? = null
    private var currentArtist: String? = null
    private var currentArtworkUrl: String? = null
    private var currentArtworkBitmap: Bitmap? = null
    private var isPlaying: Boolean = false
    private var position: Long = 0
    private var duration: Long = 0

    /**
     * Initialize the notification handler
     */
    fun initialize(config: Map<String, Any>) {
        android.util.Log.d(TAG, "Initializing notification handler for player: $playerId")
        
        // Parse configuration
        channelId = config["channelId"] as? String ?: channelId
        channelName = config["channelName"] as? String ?: channelName
        showPlayPause = config["showPlayPause"] as? Boolean ?: showPlayPause
        showNext = config["showNext"] as? Boolean ?: showNext
        showPrevious = config["showPrevious"] as? Boolean ?: showPrevious
        showStop = config["showStop"] as? Boolean ?: showStop
        showSeekForward = config["showSeekForward"] as? Boolean ?: showSeekForward
        showSeekBackward = config["showSeekBackward"] as? Boolean ?: showSeekBackward
        seekInterval = (config["seekInterval"] as? Number)?.toInt() ?: seekInterval
        
        // Initialize notification manager
        notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        // Create notification channel for Android O and above
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                channelName,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = config["channelDescription"] as? String ?: "Media playback notifications"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            notificationManager?.createNotificationChannel(channel)
        }
        
        // Create media session
        mediaSession = MediaSessionCompat(context, "FlutterMediaPlayer_$playerId").apply {
            setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS)
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    android.util.Log.d(TAG, "MediaSession: onPlay")
                    sendActionToFlutter("play")
                }
                
                override fun onPause() {
                    android.util.Log.d(TAG, "MediaSession: onPause")
                    sendActionToFlutter("pause")
                }
                
                override fun onSkipToNext() {
                    android.util.Log.d(TAG, "MediaSession: onSkipToNext")
                    sendActionToFlutter("next")
                }
                
                override fun onSkipToPrevious() {
                    android.util.Log.d(TAG, "MediaSession: onSkipToPrevious")
                    sendActionToFlutter("previous")
                }
                
                override fun onStop() {
                    android.util.Log.d(TAG, "MediaSession: onStop")
                    sendActionToFlutter("stop")
                }
                
                override fun onSeekTo(pos: Long) {
                    android.util.Log.d(TAG, "MediaSession: onSeekTo $pos")
                    // Handle seek if needed
                }
            })
            isActive = true
        }
        
        android.util.Log.d(TAG, "Notification handler initialized successfully")
    }

    /**
     * Show or update the notification
     */
    fun showNotification(mediaItem: Map<String, Any>, state: Map<String, Any>) {
        android.util.Log.d(TAG, "Showing notification")
        
        // Update media info
        currentTitle = mediaItem["title"] as? String ?: "Unknown Title"
        currentArtist = mediaItem["artist"] as? String ?: "Unknown Artist"
        currentArtworkUrl = mediaItem["artworkUrl"] as? String
        
        // Update playback state
        isPlaying = state["isPlaying"] as? Boolean ?: false
        position = (state["position"] as? Number)?.toLong() ?: 0
        duration = (state["duration"] as? Number)?.toLong() ?: 0
        
        // Update media session metadata
        updateMediaSessionMetadata()
        
        // Update playback state
        updateMediaSessionPlaybackState()
        
        // Load artwork if needed
        if (currentArtworkUrl != null && currentArtworkBitmap == null) {
            loadArtwork(currentArtworkUrl!!)
        }
        
        // Build and show notification
        buildAndShowNotification()
        
        isShowing = true
    }

    /**
     * Update notification state without changing media info
     */
    fun updateState(state: Map<String, Any>) {
        if (!isShowing) return
        
        android.util.Log.d(TAG, "Updating notification state")
        
        isPlaying = state["isPlaying"] as? Boolean ?: false
        position = (state["position"] as? Number)?.toLong() ?: 0
        duration = (state["duration"] as? Number)?.toLong() ?: 0
        
        updateMediaSessionPlaybackState()
        buildAndShowNotification()
    }

    /**
     * Update notification position
     */
    fun updatePosition(position: Long) {
        if (!isShowing) return
        
        this.position = position
        updateMediaSessionPlaybackState()
    }

    /**
     * Dismiss the notification
     */
    fun dismiss() {
        android.util.Log.d(TAG, "Dismissing notification")
        
        notificationManager?.cancel(NOTIFICATION_ID)
        mediaSession?.isActive = false
        isShowing = false
        currentArtworkBitmap = null
    }

    /**
     * Dispose the notification handler
     */
    fun dispose() {
        android.util.Log.d(TAG, "Disposing notification handler")
        
        dismiss()
        mediaSession?.release()
        mediaSession = null
        notificationManager = null
    }

    // Private helper methods

    private fun buildAndShowNotification() {
        val notification = buildNotification()
        this.notification = notification
        notificationManager?.notify(NOTIFICATION_ID, notification)
    }

    private fun buildNotification(): Notification {
        val builder = NotificationCompat.Builder(context, channelId)
            .setContentTitle(currentTitle)
            .setContentText(currentArtist)
            .setSmallIcon(android.R.drawable.ic_media_play) // Use app icon in production
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(isPlaying)
            .setShowWhen(false)
            .setStyle(androidx.media.app.NotificationCompat.MediaStyle()
                .setMediaSession(mediaSession?.sessionToken)
                .setShowActionsInCompactView(0, 1, 2))
        
        // Add artwork if available
        currentArtworkBitmap?.let {
            builder.setLargeIcon(it)
        }
        
        // Add actions
        if (showPrevious) {
            builder.addAction(createAction(
                android.R.drawable.ic_media_previous,
                "Previous",
                "previous"
            ))
        }
        
        if (showPlayPause) {
            if (isPlaying) {
                builder.addAction(createAction(
                    android.R.drawable.ic_media_pause,
                    "Pause",
                    "pause"
                ))
            } else {
                builder.addAction(createAction(
                    android.R.drawable.ic_media_play,
                    "Play",
                    "play"
                ))
            }
        }
        
        if (showNext) {
            builder.addAction(createAction(
                android.R.drawable.ic_media_next,
                "Next",
                "next"
            ))
        }
        
        if (showStop) {
            builder.addAction(createAction(
                android.R.drawable.ic_delete,
                "Stop",
                "stop"
            ))
        }
        
        return builder.build()
    }

    private fun createAction(icon: Int, title: String, action: String): NotificationCompat.Action {
        val intent = Intent("com.example.flutter_media_player.NOTIFICATION_ACTION").apply {
            putExtra("action", action)
            putExtra("playerId", playerId)
        }
        
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            action.hashCode(),
            intent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )
        
        return NotificationCompat.Action.Builder(icon, title, pendingIntent).build()
    }

    private fun updateMediaSessionMetadata() {
        val metadata = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, currentTitle)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, currentArtist)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
        
        currentArtworkBitmap?.let {
            metadata.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, it)
        }
        
        mediaSession?.setMetadata(metadata.build())
    }

    private fun updateMediaSessionPlaybackState() {
        val state = PlaybackStateCompat.Builder()
            .setState(
                if (isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                position,
                1.0f
            )
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                PlaybackStateCompat.ACTION_STOP or
                PlaybackStateCompat.ACTION_SEEK_TO
            )
            .build()
        
        mediaSession?.setPlaybackState(state)
    }

    private fun loadArtwork(url: String) {
        // Load artwork asynchronously
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val connection = URL(url).openConnection()
                connection.connect()
                val input = connection.getInputStream()
                val bitmap = android.graphics.BitmapFactory.decodeStream(input)
                input.close()
                
                withContext(Dispatchers.Main) {
                    currentArtworkBitmap = bitmap
                    if (isShowing) {
                        updateMediaSessionMetadata()
                        buildAndShowNotification()
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Failed to load artwork: ${e.message}")
            }
        }
    }

    private fun sendActionToFlutter(action: String) {
        CoroutineScope(Dispatchers.Main).launch {
            methodChannel.invokeMethod("onNotificationAction", mapOf(
                "playerId" to playerId,
                "action" to action
            ))
        }
    }
}

