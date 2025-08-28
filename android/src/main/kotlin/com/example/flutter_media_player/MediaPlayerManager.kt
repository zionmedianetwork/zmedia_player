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

    fun seekTo(playerId: String, position: Long) {
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
    
    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
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
            val state = if (isPlaying) "playing" else "paused"
            notifyStateChanged(state, false)
        }

        override fun onPlayerError(error: PlaybackException) {
            notifyError(error.message ?: "Unknown playback error")
        }

        override fun onMediaMetadataChanged(mediaMetadata: MediaMetadata) {
            notifyDurationChanged()
        }
    }

    init {
        // Initialize data source factory with custom headers support
        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
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
        
        // Update data source factory with custom headers
        if (httpHeaders != null) {
            val httpDataSourceFactory = DefaultHttpDataSource.Factory()
                .setUserAgent("Flutter Media Player")
            
            httpHeaders.forEach { (key, value) ->
                httpDataSourceFactory.setDefaultRequestProperty(key, value)
            }
            
            dataSourceFactory.setBaseDataSourceFactory(httpDataSourceFactory)
        }
        
        val uri = Uri.parse(url)
        val mediaSource = createMediaSource(uri)
        
        exoPlayer?.apply {
            setMediaSource(mediaSource)
            prepare()
            
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

    fun seekTo(position: Long) {
        exoPlayer?.seekTo(position)
    }

    fun setVolume(volume: Float) {
        exoPlayer?.volume = volume.coerceIn(0f, 1f)
    }

    fun setPlaybackSpeed(speed: Float) {
        exoPlayer?.setPlaybackSpeed(speed.coerceIn(0.25f, 4f))
    }

    fun setMuted(muted: Boolean) {
        exoPlayer?.volume = if (muted) 0f else (config?.get("volume") as? Double)?.toFloat() ?: 1f
    }

    fun setBoxFit(boxFit: String) {
        val resizeMode = when (boxFit) {
            "contain" -> AspectRatioFrameLayout.RESIZE_MODE_FIT
            "cover" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            "fill" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
            "fitWidth" -> AspectRatioFrameLayout.RESIZE_MODE_FIXED_WIDTH
            "fitHeight" -> AspectRatioFrameLayout.RESIZE_MODE_FIXED_HEIGHT
            else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
        }
        
        playerView?.setResizeMode(resizeMode)
    }

    fun setSubtitleTrack(subtitleTrack: Map<String, Any>?) {
        // Subtitle track selection will be implemented in Phase 2
        // For now, just acknowledge the call
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
            playerView = MediaPlayerView(context, exoPlayer)
        }
        return playerView
    }

    fun dispose() {
        exoPlayer?.apply {
            removeListener(playerListener)
            release()
        }
        exoPlayer = null
        playerView = null
    }

    private fun createMediaSource(uri: Uri): MediaSource {
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
            (config["volume"] as? Double)?.let { volume = it.toFloat() }
            
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
        val updateRunnable = object : Runnable {
            override fun run() {
                exoPlayer?.let { player ->
                    if (player.isPlaying) {
                        notifyPositionChanged(player.currentPosition)
                    }
                }
                Handler(Looper.getMainLooper()).postDelayed(this, 500)
            }
        }
        Handler(Looper.getMainLooper()).post(updateRunnable)
    }

    private fun notifyStateChanged(state: String, isBuffering: Boolean) {
        val arguments = mapOf(
            "playerId" to playerId,
            "state" to state,
            "isBuffering" to isBuffering,
            "bufferPercentage" to (exoPlayer?.bufferedPercentage ?: 0)
        )
        methodChannel.invokeMethod("onStateChanged", arguments)
    }

    private fun notifyPositionChanged(position: Long) {
        val arguments = mapOf(
            "playerId" to playerId,
            "position" to position.toInt()
        )
        methodChannel.invokeMethod("onPositionChanged", arguments)
    }

    private fun notifyDurationChanged() {
        val duration = exoPlayer?.duration ?: 0L
        if (duration > 0) {
            val arguments = mapOf(
                "playerId" to playerId,
                "duration" to duration.toInt()
            )
            methodChannel.invokeMethod("onDurationChanged", arguments)
        }
    }

    private fun notifyError(error: String) {
        val arguments = mapOf(
            "playerId" to playerId,
            "error" to error
        )
        methodChannel.invokeMethod("onError", arguments)
    }
}
