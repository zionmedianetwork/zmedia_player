package com.example.flutter_media_player

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.google.android.exoplayer2.*
import com.google.android.exoplayer2.source.MediaSource
import com.google.android.exoplayer2.source.ProgressiveMediaSource
import com.google.android.exoplayer2.source.hls.HlsMediaSource
import com.google.android.exoplayer2.source.dash.DashMediaSource
import com.google.android.exoplayer2.upstream.DefaultDataSource
import com.google.android.exoplayer2.upstream.DefaultHttpDataSource
import com.google.android.exoplayer2.upstream.DataSource
import com.google.android.exoplayer2.ui.AspectRatioFrameLayout
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

class MediaPlayerManager(
    private val context: Context,
    private val methodChannel: MethodChannel
) {
    private val players = ConcurrentHashMap<String, MediaPlayerInstance>()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun initializePlayer(playerId: String, config: Map<String, Any>?) {
        mainHandler.post {
            val playerInstance = MediaPlayerInstance(context, playerId, methodChannel, config)
            players[playerId] = playerInstance
        }
    }

    fun loadMediaItem(playerId: String, mediaItem: Map<String, Any>) {
        mainHandler.post {
            players[playerId]?.loadMediaItem(mediaItem)
        }
    }

    fun setPlaylist(playerId: String, playlist: Map<String, Any>, startIndex: Int) {
        mainHandler.post {
            players[playerId]?.setPlaylist(playlist, startIndex)
        }
    }

    fun play(playerId: String) {
        mainHandler.post {
            players[playerId]?.play()
        }
    }

    fun pause(playerId: String) {
        mainHandler.post {
            players[playerId]?.pause()
        }
    }

    fun stop(playerId: String) {
        mainHandler.post {
            players[playerId]?.stop()
        }
    }

    fun seekTo(playerId: String, position: Int) {
        mainHandler.post {
            players[playerId]?.seekTo(position)
        }
    }

    fun setVolume(playerId: String, volume: Float) {
        mainHandler.post {
            players[playerId]?.setVolume(volume)
        }
    }

    fun setPlaybackSpeed(playerId: String, speed: Float) {
        mainHandler.post {
            players[playerId]?.setPlaybackSpeed(speed)
        }
    }

    fun setMuted(playerId: String, muted: Boolean) {
        mainHandler.post {
            players[playerId]?.setMuted(muted)
        }
    }

    fun setBoxFit(playerId: String, boxFit: String) {
        mainHandler.post {
            players[playerId]?.setBoxFit(boxFit)
        }
    }

    fun setSubtitleTrack(playerId: String, subtitleTrack: Map<String, Any>?) {
        mainHandler.post {
            players[playerId]?.setSubtitleTrack(subtitleTrack)
        }
    }

    fun setQualityTrack(playerId: String, qualityTrack: Map<String, Any>) {
        mainHandler.post {
            players[playerId]?.setQualityTrack(qualityTrack)
        }
    }

    fun setAudioTrack(playerId: String, audioTrack: Map<String, Any>) {
        mainHandler.post {
            players[playerId]?.setAudioTrack(audioTrack)
        }
    }

    fun enableAutoQuality(playerId: String) {
        mainHandler.post {
            players[playerId]?.enableAutoQuality()
        }
    }

    fun skipToIndex(playerId: String, index: Int) {
        mainHandler.post {
            players[playerId]?.skipToIndex(index)
        }
    }

    fun updateConfig(playerId: String, config: Map<String, Any>) {
        mainHandler.post {
            players[playerId]?.updateConfig(config)
        }
    }

    fun getPlayerView(playerId: String): MediaPlayerView? {
        return players[playerId]?.getPlayerView()
    }

    fun disposePlayer(playerId: String) {
        mainHandler.post {
            players[playerId]?.dispose()
            players.remove(playerId)
        }
    }

    fun dispose() {
        mainHandler.post {
            players.values.forEach { it.dispose() }
            players.clear()
        }
    }
}

class MediaPlayerInstance(
    private val context: Context,
    private val playerId: String,
    private val methodChannel: MethodChannel,
    private var config: Map<String, Any>?
) {
    private var exoPlayer: ExoPlayer? = null
    private var playerView: MediaPlayerView? = null
    private val dataSourceFactory: DefaultDataSource.Factory
    private var currentMediaSource: MediaSource? = null
    private var currentPlaylist: List<Map<String, Any>>? = null
    private var currentIndex = 0
    private var positionUpdateHandler: Handler? = null
    private var positionUpdateRunnable: Runnable? = null
    private var originalVolume: Float = 1f
    
    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            val stateName = when (playbackState) {
                Player.STATE_IDLE -> "IDLE"
                Player.STATE_BUFFERING -> "BUFFERING"
                Player.STATE_READY -> "READY"
                Player.STATE_ENDED -> "ENDED"
                else -> "UNKNOWN"
            }
            android.util.Log.d("MediaPlayerInstance", "ExoPlayer state: $stateName, playWhenReady: ${exoPlayer?.playWhenReady}")
            
            val state = when (playbackState) {
                Player.STATE_IDLE -> "idle"
                Player.STATE_BUFFERING -> "buffering"
                Player.STATE_READY -> if (exoPlayer?.playWhenReady == true) "playing" else "ready"
                Player.STATE_ENDED -> "completed"
                else -> "idle"
            }
            
            notifyStateChanged(state, playbackState == Player.STATE_BUFFERING)
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            android.util.Log.d("MediaPlayerInstance", "IsPlaying changed: $isPlaying")
            val state = if (isPlaying) "playing" else "paused"
            notifyStateChanged(state, false)
        }

        override fun onPlayerError(error: PlaybackException) {
            android.util.Log.e("MediaPlayerInstance", "Player error: ${error.message}")
            notifyError(error.message ?: "Unknown playback error")
        }

        override fun onMediaMetadataChanged(mediaMetadata: MediaMetadata) {
            android.util.Log.d("MediaPlayerInstance", "Media metadata changed")
            notifyDurationChanged()
        }
    }

    init {
        // Initialize data source factory with custom headers support
        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setUserAgent("Flutter Media Player")
        dataSourceFactory = DefaultDataSource.Factory(context, httpDataSourceFactory)
        
        initializeExoPlayer()
    }

    private fun initializeExoPlayer() {
        exoPlayer = ExoPlayer.Builder(context)
            .build()
            .apply {
                addListener(playerListener)
                // Apply initial configuration
                config?.let { applyConfig(it) }
            }
        
        // Start position updates
        startPositionUpdates()
    }

    fun loadMediaItem(mediaItem: Map<String, Any>) {
        val url = mediaItem["url"] as? String ?: return
        val httpHeaders = mediaItem["httpHeaders"] as? Map<String, String>
        
        android.util.Log.d("MediaPlayerInstance", "Loading media: $url")
        
        val uri = Uri.parse(url)
        val mediaSource: MediaSource
        
        // Create media source with custom headers if provided
        if (httpHeaders != null && httpHeaders.isNotEmpty()) {
            val customHttpDataSourceFactory = DefaultHttpDataSource.Factory()
                .setUserAgent("Flutter Media Player")
            
            // Set custom headers
            httpHeaders.forEach { (key, value) ->
                customHttpDataSourceFactory.setDefaultRequestProperties(mapOf(key to value))
            }
            
            val customDataSourceFactory = DefaultDataSource.Factory(context, customHttpDataSourceFactory)
            mediaSource = createMediaSource(uri, customDataSourceFactory)
        } else {
            mediaSource = createMediaSource(uri, dataSourceFactory)
        }
        
        exoPlayer?.apply {
            // Stop current playback if any
            stop()
            clearMediaItems()
            
            // Set new media source
            setMediaSource(mediaSource)
            prepare()
            
            android.util.Log.d("MediaPlayerInstance", "Media prepared, autoPlay: ${config?.get("autoPlay")}")
            
            if (config?.get("autoPlay") as? Boolean == true) {
                playWhenReady = true
            }
        }
        
        currentMediaSource = mediaSource
    }

    fun setPlaylist(playlist: Map<String, Any>, startIndex: Int) {
        val items = playlist["items"] as? List<Map<String, Any>> ?: return
        currentPlaylist = items
        currentIndex = startIndex.coerceIn(0, items.size - 1)
        
        if (items.isNotEmpty()) {
            loadMediaItem(items[currentIndex])
        }
    }

    fun play() {
        exoPlayer?.playWhenReady = true
    }

    fun pause() {
        exoPlayer?.playWhenReady = false
    }

    fun stop() {
        exoPlayer?.apply {
            stop()
            clearMediaItems()
        }
    }

    fun seekTo(position: Int) {
        exoPlayer?.seekTo(position.toLong())
    }

    fun setVolume(volume: Float) {
        val clampedVolume = volume.coerceIn(0f, 1f)
        originalVolume = clampedVolume
        exoPlayer?.volume = clampedVolume
    }

    fun setPlaybackSpeed(speed: Float) {
        exoPlayer?.setPlaybackSpeed(speed.coerceIn(0.25f, 4f))
    }

    fun setMuted(muted: Boolean) {
        exoPlayer?.volume = if (muted) 0f else originalVolume
    }

    fun setBoxFit(boxFit: String) {
        val resizeMode = when (boxFit.lowercase()) {
            "cover" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            "fill" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
            "fitwidth" -> AspectRatioFrameLayout.RESIZE_MODE_FIT_WIDTH
            "fitheight" -> AspectRatioFrameLayout.RESIZE_MODE_FIT_HEIGHT
            "none" -> AspectRatioFrameLayout.RESIZE_MODE_NONE
            "scaledown" -> AspectRatioFrameLayout.RESIZE_MODE_FIT
            else -> AspectRatioFrameLayout.RESIZE_MODE_FIT // "contain" and default
        }
        
        playerView?.setResizeMode(resizeMode)
    }

    fun setSubtitleTrack(subtitleTrack: Map<String, Any>?) {
        // Subtitle track selection will be implemented in Phase 2
        // For now, just acknowledge the call
    }

    fun setQualityTrack(qualityTrack: Map<String, Any>) {
        // Quality track selection - Phase 2 stub
        // In a full implementation, this would select a specific quality from HLS/DASH manifest
        android.util.Log.d("MediaPlayerInstance", "Quality track set: ${qualityTrack["name"]}")
    }

    fun setAudioTrack(audioTrack: Map<String, Any>) {
        // Audio track selection - Phase 2 stub
        // In a full implementation, this would select a specific audio track
        android.util.Log.d("MediaPlayerInstance", "Audio track set: ${audioTrack["name"]}")
    }

    fun enableAutoQuality() {
        // Enable automatic quality selection - Phase 2 stub
        // In a full implementation, this would enable ExoPlayer's adaptive track selection
        android.util.Log.d("MediaPlayerInstance", "Auto quality enabled")
    }

    fun skipToIndex(index: Int) {
        currentPlaylist?.let { playlist ->
            if (index in 0 until playlist.size) {
                currentIndex = index
                loadMediaItem(playlist[index])
            }
        }
    }

    fun updateConfig(newConfig: Map<String, Any>) {
        config = newConfig
        applyConfig(newConfig)
    }

    fun getPlayerView(): MediaPlayerView? {
        if (playerView == null) {
            android.util.Log.d("MediaPlayerInstance", "Creating new player view with player: ${exoPlayer != null}")
            playerView = MediaPlayerView(context, exoPlayer)
        } else {
            // Ensure the existing player view has the current player
            android.util.Log.d("MediaPlayerInstance", "Returning existing player view")
        }
        return playerView
    }

    fun dispose() {
        // Stop position updates
        stopPositionUpdates()
        
        exoPlayer?.apply {
            removeListener(playerListener)
            release()
        }
        exoPlayer = null
        playerView = null
    }

    private fun createMediaSource(uri: Uri, dataSourceFactory: DataSource.Factory = this.dataSourceFactory): MediaSource {
        return when {
            uri.toString().contains(".m3u8") -> {
                HlsMediaSource.Factory(dataSourceFactory)
                    .createMediaSource(MediaItem.fromUri(uri))
            }
            uri.toString().contains(".mpd") -> {
                DashMediaSource.Factory(dataSourceFactory)
                    .createMediaSource(MediaItem.fromUri(uri))
            }
            else -> {
                ProgressiveMediaSource.Factory(dataSourceFactory)
                    .createMediaSource(MediaItem.fromUri(uri))
            }
        }
    }

    private fun applyConfig(config: Map<String, Any>) {
        exoPlayer?.apply {
            // Apply volume
            (config["volume"] as? Double)?.let { 
                val vol = it.toFloat()
                originalVolume = vol
                volume = vol
            }
            
            // Apply playback speed
            (config["speed"] as? Double)?.let { setPlaybackSpeed(it.toFloat()) }
            
            // Apply muted state
            (config["startMuted"] as? Boolean)?.let { 
                if (it) volume = 0f 
            }
            
            // Apply looping
            (config["looping"] as? Boolean)?.let {
                repeatMode = if (it) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
            }
        }
        
        // Apply BoxFit
        (config["boxFit"] as? String)?.let { setBoxFit(it) }
    }

    private fun startPositionUpdates() {
        stopPositionUpdates() // Ensure we don't have multiple runnables
        
        positionUpdateHandler = Handler(Looper.getMainLooper())
        positionUpdateRunnable = object : Runnable {
            override fun run() {
                exoPlayer?.let { player ->
                    if (player.isPlaying) {
                        notifyPositionChanged(player.currentPosition)
                    }
                }
                positionUpdateHandler?.postDelayed(this, 500)
            }
        }
        positionUpdateHandler?.post(positionUpdateRunnable!!)
    }
    
    private fun stopPositionUpdates() {
        positionUpdateRunnable?.let { runnable ->
            positionUpdateHandler?.removeCallbacks(runnable)
        }
        positionUpdateRunnable = null
        positionUpdateHandler = null
    }

    private fun notifyStateChanged(state: String, isBuffering: Boolean) {
        try {
            android.util.Log.d("MediaPlayerInstance", "State changed: $state, isBuffering: $isBuffering")
            val arguments = mapOf(
                "playerId" to playerId,
                "state" to state,
                "isBuffering" to isBuffering,
                "bufferPercentage" to (exoPlayer?.bufferedPercentage ?: 0)
            )
            methodChannel.invokeMethod("onStateChanged", arguments)
        } catch (e: Exception) {
            // Handle potential exceptions when invoking method channel
            android.util.Log.e("MediaPlayerInstance", "Error notifying state change", e)
            e.printStackTrace()
        }
    }

    private fun notifyPositionChanged(position: Long) {
        try {
            val arguments = mapOf(
                "playerId" to playerId,
                "position" to position.toInt()
            )
            methodChannel.invokeMethod("onPositionChanged", arguments)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun notifyDurationChanged() {
        try {
            val duration = exoPlayer?.duration ?: 0L
            if (duration > 0) {
                val arguments = mapOf(
                    "playerId" to playerId,
                    "duration" to duration.toInt()
                )
                methodChannel.invokeMethod("onDurationChanged", arguments)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun notifyError(error: String) {
        try {
            val arguments = mapOf(
                "playerId" to playerId,
                "error" to error
            )
            methodChannel.invokeMethod("onError", arguments)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}