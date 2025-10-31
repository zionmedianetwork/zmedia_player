package com.zionmedianetwork.zmedia_player

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.google.android.exoplayer2.*
import com.google.android.exoplayer2.source.MediaSource
import com.google.android.exoplayer2.source.ProgressiveMediaSource
import com.google.android.exoplayer2.source.hls.HlsMediaSource
import com.google.android.exoplayer2.source.dash.DashMediaSource
import com.google.android.exoplayer2.trackselection.TrackSelectionOverride
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
    private val crashHandler = CrashHandler(methodChannel)

    // Activity tracking for memory leak prevention
    private val lastActivity = ConcurrentHashMap<String, Long>()
    private val cleanupRunnable = object : Runnable {
        override fun run() {
            cleanupStaleInstances()
            mainHandler.postDelayed(this, CLEANUP_INTERVAL_MS)
        }
    }

    companion object {
        private const val CLEANUP_INTERVAL_MS = 5 * 60 * 1000L // 5 minutes
        private const val STALE_THRESHOLD_MS = 15 * 60 * 1000L // 15 minutes
    }

    init {
        mainHandler.postDelayed(cleanupRunnable, CLEANUP_INTERVAL_MS)
    }

    private fun markActivity(playerId: String) {
        lastActivity[playerId] = System.currentTimeMillis()
    }

    private fun cleanupStaleInstances() {
        val now = System.currentTimeMillis()
        val stalePlayers = mutableListOf<String>()

        lastActivity.forEach { (playerId, lastUsed) ->
            if (now - lastUsed > STALE_THRESHOLD_MS) {
                players[playerId]?.let { instance ->
                    if (!instance.isPlaying()) {
                        stalePlayers.add(playerId)
                    }
                }
            }
        }

        stalePlayers.forEach { playerId ->
            android.util.Log.d("MediaPlayerManager", "Auto-cleaning stale instance: $playerId")
            players[playerId]?.dispose()
            players.remove(playerId)
            lastActivity.remove(playerId)
        }
    }

    fun initializePlayer(playerId: String, config: Map<String, Any>?) {
        android.util.Log.d("MediaPlayerManager", "initializePlayer called for playerId: $playerId")
        markActivity(playerId)

        // Initialize synchronously on main thread to avoid timing issues with platform view creation
        if (Looper.myLooper() == Looper.getMainLooper()) {
            val playerInstance = MediaPlayerInstance(context, playerId, methodChannel, config)
            players[playerId] = playerInstance
            android.util.Log.d("MediaPlayerManager", "Player instance created synchronously")
        } else {
            mainHandler.post {
                val playerInstance = MediaPlayerInstance(context, playerId, methodChannel, config)
                players[playerId] = playerInstance
                android.util.Log.d("MediaPlayerManager", "Player instance created via handler post")
            }
        }
    }

    fun loadMediaItem(playerId: String, mediaItem: Map<String, Any>) {
        markActivity(playerId)
        mainHandler.post {
            crashHandler.wrapOperation("loadMediaItem", playerId, mapOf("url" to (mediaItem["url"] ?: "unknown"))) {
                players[playerId]?.loadMediaItem(mediaItem)
            }
        }
    }

    fun setPlaylist(playerId: String, playlist: Map<String, Any>, startIndex: Int) {
        markActivity(playerId)
        mainHandler.post {
            players[playerId]?.setPlaylist(playlist, startIndex)
        }
    }

    fun play(playerId: String) {
        markActivity(playerId)
        mainHandler.post {
            crashHandler.wrapOperation("play", playerId) {
                players[playerId]?.play()
            }
        }
    }

    fun pause(playerId: String) {
        markActivity(playerId)
        mainHandler.post {
            crashHandler.wrapOperation("pause", playerId) {
                players[playerId]?.pause()
            }
        }
    }

    fun stop(playerId: String) {
        markActivity(playerId)
        mainHandler.post {
            players[playerId]?.stop()
        }
    }

    fun seekTo(playerId: String, position: Int) {
        markActivity(playerId)
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
        android.util.Log.d("MediaPlayerManager", "getPlayerView called for playerId: $playerId, player exists: ${players.containsKey(playerId)}")

        // If player doesn't exist yet, wait for it to be initialized
        val playerInstance = players[playerId]
        if (playerInstance == null) {
            android.util.Log.e("MediaPlayerManager", "Player instance not found for $playerId - ensure initialize() was called first")
            return null
        }

        return playerInstance.getPlayerView()
    }

    fun getBufferHealth(playerId: String): Map<String, Any> {
        markActivity(playerId)
        return players[playerId]?.getBufferHealth() ?: mapOf(
            "bufferedDurationMs" to 0,
            "currentPositionMs" to 0,
            "totalDurationMs" to 0,
            "downloadSpeed" to 0
        )
    }

    fun disposePlayer(playerId: String) {
        mainHandler.post {
            players[playerId]?.dispose()
            players.remove(playerId)
            lastActivity.remove(playerId)
        }
    }

    fun dispose() {
        mainHandler.post {
            players.values.forEach { it.dispose() }
            players.clear()
            lastActivity.clear()
        }
    }

    fun shutdown() {
        mainHandler.removeCallbacks(cleanupRunnable)
        dispose()
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
    private val bufferingHandler: BufferingHandler = BufferingHandler()
    private var currentMediaSource: MediaSource? = null
    private var currentPlaylist: List<Map<String, Any>>? = null
    private var currentIndex = 0
    private var positionUpdateHandler: Handler? = null
    private var positionUpdateRunnable: Runnable? = null
    private var bandwidthUpdateHandler: Handler? = null
    private var bandwidthUpdateRunnable: Runnable? = null
    private var originalVolume: Float = 1f
    private var currentMediaItem: Map<String, Any>? = null

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

            // Notify duration when player is ready
            if (playbackState == Player.STATE_READY) {
                notifyDurationChanged()
            }
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

        override fun onTracksChanged(tracks: Tracks) {
            android.util.Log.d("MediaPlayerInstance", "Tracks changed")
            extractAndNotifyQualityTracks()
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
        // Get buffer configuration from config
        val bufferConfig = config?.get("bufferConfig") as? Map<String, Any>
        val loadControl = BufferingHandler.createFromDartConfig(bufferConfig)

        exoPlayer = ExoPlayer.Builder(context)
            .setLoadControl(loadControl)
            .build()
            .apply {
                addListener(playerListener)
                // Apply initial configuration
                config?.let { applyConfig(it) }
            }

        // Start position updates
        startPositionUpdates()

        // Start bandwidth monitoring
        startBandwidthMonitoring()
    }

    fun loadMediaItem(mediaItem: Map<String, Any>) {
        val url = mediaItem["url"] as? String ?: return
        val httpHeaders = mediaItem["httpHeaders"] as? Map<String, String>

        // Store current media item (for live stream detection)
        currentMediaItem = mediaItem

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

            // Set playWhenReady based on autoPlay - explicitly set false if not auto-playing
            playWhenReady = config?.get("autoPlay") as? Boolean ?: false
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
            "fitwidth" -> AspectRatioFrameLayout.RESIZE_MODE_FIXED_WIDTH
            "fitheight" -> AspectRatioFrameLayout.RESIZE_MODE_FIXED_HEIGHT
            "none" -> AspectRatioFrameLayout.RESIZE_MODE_FIT
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
        val trackId = qualityTrack["id"] as? String ?: return
        android.util.Log.d("MediaPlayerInstance", "Setting quality track: ${qualityTrack["name"]}, id: $trackId")

        exoPlayer?.let { player ->
            val currentTracks = player.currentTracks
            var targetGroup: Tracks.Group? = null
            var targetTrackIndex = -1

            // Find the video track group and index matching the requested quality
            for (group in currentTracks.groups) {
                if (group.type == C.TRACK_TYPE_VIDEO) {
                    for (i in 0 until group.length) {
                        val format = group.getTrackFormat(i)
                        val formatId = "${format.width}x${format.height}_${format.bitrate}"
                        if (formatId == trackId) {
                            targetGroup = group
                            targetTrackIndex = i
                            break
                        }
                    }
                    if (targetGroup != null) break
                }
            }

            if (targetGroup != null && targetTrackIndex >= 0) {
                // Override track selection to the specific quality
                val override = TrackSelectionOverride(
                    targetGroup.mediaTrackGroup,
                    listOf(targetTrackIndex)
                )

                player.trackSelectionParameters = player.trackSelectionParameters
                    .buildUpon()
                    .setOverrideForType(override)
                    .build()

                android.util.Log.d("MediaPlayerInstance", "Quality track override applied")
            } else {
                android.util.Log.w("MediaPlayerInstance", "Quality track not found: $trackId")
            }
        }
    }

    fun setAudioTrack(audioTrack: Map<String, Any>) {
        // Audio track selection - Phase 2 stub
        // In a full implementation, this would select a specific audio track
        android.util.Log.d("MediaPlayerInstance", "Audio track set: ${audioTrack["name"]}")
    }

    fun enableAutoQuality() {
        android.util.Log.d("MediaPlayerInstance", "Enabling auto quality (ABR)")

        exoPlayer?.let { player ->
            // Clear all track overrides to enable adaptive bitrate selection
            player.trackSelectionParameters = player.trackSelectionParameters
                .buildUpon()
                .clearOverridesOfType(C.TRACK_TYPE_VIDEO)
                .build()

            android.util.Log.d("MediaPlayerInstance", "Auto quality enabled - track overrides cleared")
        }
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

    fun isPlaying(): Boolean {
        return exoPlayer?.isPlaying ?: false
    }

    fun getBufferHealth(): Map<String, Any> {
        return bufferingHandler.getBufferHealth(exoPlayer)
    }

    fun dispose() {
        // Stop position updates
        stopPositionUpdates()

        // Stop bandwidth monitoring
        stopBandwidthMonitoring()

        exoPlayer?.apply {
            removeListener(playerListener)
            release()
        }
        exoPlayer = null
        playerView = null
        currentMediaItem = null
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

    private fun startBandwidthMonitoring() {
        stopBandwidthMonitoring() // Ensure we don't have multiple runnables

        bandwidthUpdateHandler = Handler(Looper.getMainLooper())
        bandwidthUpdateRunnable = object : Runnable {
            override fun run() {
                exoPlayer?.let { player ->
                    // Get current bandwidth estimate from ExoPlayer
                    val currentBandwidth = getCurrentBandwidthEstimate(player)
                    if (currentBandwidth > 0) {
                        notifyBandwidthChanged(currentBandwidth)
                    }
                }
                // Update every 2 seconds
                bandwidthUpdateHandler?.postDelayed(this, 2000)
            }
        }
        bandwidthUpdateHandler?.post(bandwidthUpdateRunnable!!)
    }

    private fun stopBandwidthMonitoring() {
        bandwidthUpdateRunnable?.let { runnable ->
            bandwidthUpdateHandler?.removeCallbacks(runnable)
        }
        bandwidthUpdateRunnable = null
        bandwidthUpdateHandler = null
    }

    private fun getCurrentBandwidthEstimate(player: ExoPlayer): Long {
        // ExoPlayer's bandwidth estimate is available through the LoadControl
        // We can access it via the player's current tracks selection
        try {
            // Get bandwidth estimate from current adaptive track selection
            val trackSelector = player.currentTracks
            // ExoPlayer internally maintains bandwidth estimates
            // For now, we'll use a workaround by checking video/audio bitrate
            var estimatedBandwidth: Long = 0

            for (trackGroup in trackSelector.groups) {
                if (trackGroup.isSelected) {
                    val format = trackGroup.getTrackFormat(0)
                    if (format.bitrate != com.google.android.exoplayer2.Format.NO_VALUE) {
                        estimatedBandwidth += format.bitrate.toLong()
                    }
                }
            }

            // If we have a valid estimate, return it; otherwise return 0
            return if (estimatedBandwidth > 0) estimatedBandwidth else 0
        } catch (e: Exception) {
            android.util.Log.e("MediaPlayerInstance", "Error getting bandwidth estimate: ${e.message}")
            return 0
        }
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
                val isLive = currentMediaItem?.get("isLive") as? Boolean ?: false
                val arguments = mapOf(
                    "playerId" to playerId,
                    "duration" to duration.toInt(),
                    "isLive" to isLive
                )
                methodChannel.invokeMethod("onDurationChanged", arguments)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun notifyBandwidthChanged(bandwidth: Long) {
        try {
            val arguments = mapOf(
                "playerId" to playerId,
                "bandwidth" to bandwidth
            )
            methodChannel.invokeMethod("onBandwidthChanged", arguments)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun extractAndNotifyQualityTracks() {
        exoPlayer?.let { player ->
            val qualityTracks = mutableListOf<Map<String, Any>>()
            val currentTracks = player.currentTracks

            // Extract video tracks
            for (group in currentTracks.groups) {
                if (group.type == C.TRACK_TYPE_VIDEO && group.length > 0) {
                    for (i in 0 until group.length) {
                        val format = group.getTrackFormat(i)

                        // Skip if format doesn't have valid dimensions or bitrate
                        if (format.width <= 0 || format.height <= 0 || format.bitrate <= 0) {
                            continue
                        }

                        val trackId = "${format.width}x${format.height}_${format.bitrate}"
                        val trackName = "${format.height}p (${(format.bitrate / 1000)}kbps)"

                        qualityTracks.add(mapOf(
                            "id" to trackId,
                            "name" to trackName,
                            "bitrate" to format.bitrate,
                            "width" to format.width,
                            "height" to format.height,
                            "frameRate" to (format.frameRate.takeIf { it > 0 } ?: 30.0),
                            "isSelected" to group.isTrackSelected(i),
                            "isAvailable" to true,
                            "codec" to (format.codecs ?: "unknown")
                        ))
                    }
                }
            }

            // Sort by bitrate (highest first for better UX)
            qualityTracks.sortByDescending { it["bitrate"] as Int }

            if (qualityTracks.isNotEmpty()) {
                android.util.Log.d("MediaPlayerInstance", "Found ${qualityTracks.size} quality tracks")
                notifyQualityTracksChanged(qualityTracks)
            }
        }
    }

    private fun notifyQualityTracksChanged(tracks: List<Map<String, Any>>) {
        try {
            val arguments = mapOf(
                "playerId" to playerId,
                "tracks" to tracks
            )
            methodChannel.invokeMethod("onQualityTracksChanged", arguments)
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
