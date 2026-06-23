package com.zionmedianetwork.zmedia_player

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
        private const val TAG = "NotificationHandler"
    }

    // Per-instance notification ID derived from playerId so that multiple concurrent
    // player instances do not overwrite or cancel each other's notifications.
    // hashCode() can be negative; AND with 0x7FFFFFFF ensures a positive value and
    // avoids 0 (which is reserved/invalid for notification IDs on some Android versions).
    private val notificationId: Int = (playerId.hashCode() and 0x7FFFFFFF).let { if (it == 0) 1 else it }

    // Owned scope: all coroutines are cancelled in dispose() to prevent leaks.
    // Main dispatcher matches the original intent (invokeMethod must run on Main).
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

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
    private var currentMediaUrl: String? = null
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

        val newArtworkUrl = mediaItem["artworkUrl"] as? String
        val newMediaUrl = mediaItem["url"] as? String

        // Detect when the media item changes so a stale bitmap is not reused
        // for a different video.  A change is identified by either the artworkUrl
        // or the media URL changing.
        val mediaChanged = (newArtworkUrl != currentArtworkUrl) || (newMediaUrl != currentMediaUrl)
        if (mediaChanged) {
            currentArtworkBitmap = null
        }

        // Update media info
        currentTitle = mediaItem["title"] as? String ?: "Unknown Title"
        currentArtist = mediaItem["artist"] as? String ?: "Unknown Artist"
        currentArtworkUrl = newArtworkUrl
        currentMediaUrl = newMediaUrl

        // Update playback state
        isPlaying = state["isPlaying"] as? Boolean ?: false
        position = (state["position"] as? Number)?.toLong() ?: 0
        duration = (state["duration"] as? Number)?.toLong() ?: 0

        // Update media session metadata
        updateMediaSessionMetadata()

        // Update playback state
        updateMediaSessionPlaybackState()

        // Artwork resolution:
        // 1. If an artworkUrl is provided, load from URL (takes priority).
        // 2. Otherwise, if the media URL is present, generate a thumbnail frame.
        if (currentArtworkUrl != null && currentArtworkBitmap == null) {
            loadArtwork(currentArtworkUrl!!)
        } else if (currentArtworkUrl.isNullOrEmpty() && currentArtworkBitmap == null
            && !currentMediaUrl.isNullOrEmpty()) {
            generateThumbnail(currentMediaUrl!!)
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

        notificationManager?.cancel(notificationId)
        mediaSession?.isActive = false
        isShowing = false
        currentArtworkBitmap = null
    }

    /**
     * Dispose the notification handler
     */
    fun dispose() {
        android.util.Log.d(TAG, "Disposing notification handler")

        // Cancel all coroutines owned by this handler (artwork loading, action forwarding).
        scope.cancel()

        dismiss()
        mediaSession?.release()
        mediaSession = null
        notificationManager = null
    }

    // Private helper methods

    private fun buildAndShowNotification() {
        val notification = buildNotification()
        this.notification = notification
        notificationManager?.notify(notificationId, notification)
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
        val intent = Intent("com.zionmedianetwork.zmedia_player.NOTIFICATION_ACTION").apply {
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
        // Load artwork asynchronously on the IO dispatcher via the owned scope.
        scope.launch(Dispatchers.IO) {
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

    /**
     * Generates a thumbnail from the video at [url] and sets it as the
     * notification artwork.  Called only when artworkUrl is absent.
     * Works with remote URLs; MediaMetadataRetriever reads just the range
     * it needs so it does not download the entire file.
     *
     * Black-frame avoidance strategy
     * ─────────────────────────────
     * Many videos (e.g. Big Buck Bunny) open with a black fade-in.
     * The previous implementation called getFrameAtTime(1_000_000,
     * OPTION_CLOSEST_SYNC), which snaps to the nearest sync (I-frame)
     * at or before the requested time — often frame 0 (black).
     *
     * The fix has two parts:
     *   1. Read the actual duration before choosing the target position so we
     *      can pick a time well inside real content.
     *   2. Use OPTION_CLOSEST instead of OPTION_CLOSEST_SYNC so the decoder
     *      returns the actual frame at the target time rather than the nearest
     *      (possibly distant, possibly black) sync keyframe.
     *
     * Target time calculation (same formula as iOS):
     *   • durationMs ≥ 3 000 ms → clamp(durationMs × 0.1, 3 000 ms, 10 000 ms)
     *   • 0 < durationMs < 3 000 ms  → durationMs / 2   (short clip, midpoint)
     *   • fallback (unknown / 0)      → 5 000 ms fixed
     */
    private fun generateThumbnail(url: String) {
        scope.launch(Dispatchers.IO) {
            val retriever = android.media.MediaMetadataRetriever()
            try {
                // Pass an empty headers map so the overload that accepts headers
                // is used — this avoids the deprecated single-argument setDataSource.
                retriever.setDataSource(url, emptyMap<String, String>())

                // Read the actual duration so we can pick a meaningful target time.
                val durationMs = retriever
                    .extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull() ?: 0L

                // Compute target time in milliseconds, then convert to microseconds.
                val targetMs: Long = when {
                    durationMs >= 3_000L -> {
                        // 10 % of duration, clamped to [3 s, 10 s]
                        val tenPercent = (durationMs * 0.1).toLong()
                        tenPercent.coerceIn(3_000L, 10_000L)
                    }
                    durationMs > 0L -> {
                        // Very short clip — use the midpoint
                        durationMs / 2
                    }
                    else -> {
                        // Unknown duration — fixed 5-second offset
                        5_000L
                    }
                }
                val targetUs = targetMs * 1_000L

                android.util.Log.d(TAG, "Thumbnail: duration=${durationMs}ms → target=${targetMs}ms")

                // OPTION_CLOSEST returns the actual decoded frame nearest the
                // requested time, not the nearest sync keyframe.  This means
                // we get the frame at ~targetMs even if it is a P- or B-frame,
                // rather than snapping back to the (potentially black) keyframe
                // at t=0.
                val bitmap = retriever.getFrameAtTime(
                    targetUs,
                    android.media.MediaMetadataRetriever.OPTION_CLOSEST
                )

                withContext(Dispatchers.Main) {
                    // Only apply if the media item hasn't changed while we were
                    // generating (guard by comparing the URL captured at trigger time).
                    if (currentMediaUrl == url && currentArtworkBitmap == null) {
                        currentArtworkBitmap = bitmap
                        if (isShowing && bitmap != null) {
                            updateMediaSessionMetadata()
                            buildAndShowNotification()
                            android.util.Log.d(TAG, "Video thumbnail generated and applied")
                        }
                    } else {
                        android.util.Log.d(TAG, "Thumbnail discarded — media changed during generation")
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Failed to generate thumbnail: ${e.message}")
            } finally {
                try {
                    retriever.release()
                } catch (ignore: Exception) {
                    // release() itself can throw on some older API levels; ignore.
                }
            }
        }
    }

    private fun sendActionToFlutter(action: String) {
        scope.launch {
            methodChannel.invokeMethod("onNotificationAction", mapOf(
                "playerId" to playerId,
                "action" to action
            ))
        }
    }
}
