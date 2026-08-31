package com.zionmedianetwork.zmedia_player

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.*
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.ui.AspectRatioFrameLayout
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

class MediaPlayerManager(
    private val context: Context,
    private val methodChannel: MethodChannel
) {
    private val players = ConcurrentHashMap<String, MediaPlayerInstance>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val crashHandler = CrashHandler(methodChannel)

    // C-03b: this MediaPlayerManager's own handle onto the process-wide
    // shared adaptive-stream SimpleCache (see AdaptiveCacheHolder). Null
    // until the first player lazily enables adaptive caching; non-null
    // exactly once acquired, so shutdown() knows whether it owes a matching
    // AdaptiveCacheHolder.release() call.
    @Volatile
    private var sharedAdaptiveCache: SimpleCache? = null

    /**
     * Lazily acquires (idempotently, per this manager instance) and returns
     * the shared adaptive-stream [SimpleCache]. Called from
     * [MediaPlayerInstance.loadMediaItem] only when that player's config has
     * adaptive caching enabled for the item currently being loaded.
     */
    @Synchronized
    fun acquireSharedAdaptiveCache(maxSizeBytes: Long): SimpleCache {
        val existing = sharedAdaptiveCache
        if (existing != null) return existing
        val created = AdaptiveCacheHolder.acquire(context, maxSizeBytes)
        sharedAdaptiveCache = created
        return created
    }

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
            val playerInstance = MediaPlayerInstance(
                context, playerId, methodChannel, config, this::acquireSharedAdaptiveCache
            )
            players[playerId] = playerInstance
            android.util.Log.d("MediaPlayerManager", "Player instance created synchronously")
        } else {
            mainHandler.post {
                val playerInstance = MediaPlayerInstance(
                    context, playerId, methodChannel, config, this::acquireSharedAdaptiveCache
                )
                players[playerId] = playerInstance
                android.util.Log.d("MediaPlayerManager", "Player instance created via handler post")
            }
        }
    }

    fun loadMediaItem(playerId: String, mediaItem: Map<String, Any>, config: Map<String, Any>? = null) {
        markActivity(playerId)
        mainHandler.post {
            crashHandler.wrapOperation("loadMediaItem", playerId, mapOf("url" to (mediaItem["url"] ?: "unknown"))) {
                players[playerId]?.loadMediaItem(mediaItem, config)
            }
        }
    }

    fun setPlaylist(
        playerId: String,
        playlist: Map<String, Any>,
        startIndex: Int,
        config: Map<String, Any>? = null
    ) {
        markActivity(playerId)
        mainHandler.post {
            players[playerId]?.setPlaylist(playlist, startIndex, config)
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

    fun skipToIndex(playerId: String, index: Int, config: Map<String, Any>? = null) {
        mainHandler.post {
            players[playerId]?.skipToIndex(index, config)
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

    fun reclaimVideoSurface(playerId: String) {
        android.util.Log.d("MediaPlayerManager", "reclaimVideoSurface: re-attaching player for $playerId")
        players[playerId]?.reclaimVideoSurface()
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
        // C-03b: release this manager's reference (if any was ever acquired)
        // on the process-wide shared adaptive-stream cache. Pairs 1:1 with
        // acquireSharedAdaptiveCache() — see AdaptiveCacheHolder for why this
        // is reference-counted rather than a hard release.
        if (sharedAdaptiveCache != null) {
            AdaptiveCacheHolder.release()
            sharedAdaptiveCache = null
        }
    }
}

class MediaPlayerInstance(
    private val context: Context,
    private val playerId: String,
    private val methodChannel: MethodChannel,
    private var config: Map<String, Any>?,
    // C-03b: lazily acquires (idempotently, at the MediaPlayerManager level)
    // the process-wide shared adaptive-stream SimpleCache. Only invoked when
    // this instance's config opts into adaptive caching for the item
    // currently being loaded — see loadMediaItem().
    private val acquireAdaptiveCache: (Long) -> SimpleCache
) {
    companion object {
        // C-03b: fallback only — normally the Dart side always sends
        // maxCacheSizeBytes alongside adaptiveCacheConfig.enabled (see
        // AdaptiveCacheConfig's default in lib/src/core/media_config.dart,
        // which matches this value).
        private const val DEFAULT_ADAPTIVE_CACHE_MAX_SIZE_BYTES = 250L * 1024 * 1024

        // Issue #87: the wire values of Dart's `StreamingFormat` enum, as
        // sent in the `streamingFormat` key of the `mediaItem` payload
        // (`MediaItem.streamingFormat?.name`). Kept as plain strings so an
        // unknown/absent value can degrade to URL inference rather than
        // failing to decode — see [streamingFormatOf].
        internal const val FORMAT_HLS = "hls"
        internal const val FORMAT_DASH = "dash"
        internal const val FORMAT_PROGRESSIVE = "progressive"
    }

    private var exoPlayer: ExoPlayer? = null
    private var playerView: MediaPlayerView? = null
    // Shared bandwidth meter — passed to ExoPlayer.Builder so that ExoPlayer
    // uses it for adaptive track selection AND we can read its bitrateEstimate
    // (measured bits/sec) at any time.  This replaces the previous approach of
    // reading format.bitrate (declared bitrate of the current track), which
    // never reflects actual network throughput.
    // NOTE: requires device verification — bitrateEstimate returns 0 until the
    // meter has observed at least one download chunk.
    private val bandwidthMeter: DefaultBandwidthMeter =
        DefaultBandwidthMeter.getSingletonInstance(context)
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
    // Tracks whether this instance is currently muted (via setMuted() or the initial
    // config's "startMuted"). Used to decide whether this instance should participate in
    // Android audio focus / becoming-noisy handling — see updateAudioFocusHandling().
    private var isMuted: Boolean = false
    private var currentMediaItem: Map<String, Any>? = null
    // DRM handler — non-null only when the current media item has a drmConfig.
    private var drmHandler: DrmHandler? = null

    // H-01: reason for the most recent playWhenReady change, so that when
    // onIsPlayingChanged subsequently reports isPlaying == false we can tell
    // an explicit user/API pause apart from one the OS forced by revoking
    // audio focus (e.g. another app started playing audio). onIsPlayingChanged
    // alone cannot distinguish these — both drive playWhenReady to false —
    // which previously made a focus-loss pause indistinguishable from a user
    // pause on the Dart side. Mirrors, in spirit, how Phase 2 disambiguated
    // stall-vs-pause on iOS via timeControlStatus/reasonForWaitingToPlay.
    private var lastPlayWhenReadyChangeReason: Int =
        Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST

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

        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
            lastPlayWhenReadyChangeReason = reason
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            android.util.Log.d("MediaPlayerInstance", "IsPlaying changed: $isPlaying")
            val state = if (isPlaying) "playing" else "paused"
            // Only a "paused" transition caused by the OS revoking audio focus
            // gets a reason attached; a normal user/API pause or any other
            // playWhenReady-change reason leaves pauseReason null so the Dart
            // side's default ("user pause") interpretation stands.
            val pauseReason = if (!isPlaying &&
                lastPlayWhenReadyChangeReason == Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_FOCUS_LOSS
            ) {
                "audioFocusLoss"
            } else {
                null
            }
            notifyStateChanged(state, false, pauseReason)
        }

        override fun onPlayerError(error: PlaybackException) {
            // error.message frequently embeds the failing request URI (HttpDataSource /
            // manifest fetch failures), which may carry signed-cookie or DRM token query
            // params. Log.e is not stripped from release builds (see H-03), so redact it.
            android.util.Log.e(
                "MediaPlayerInstance",
                "Player error: ${LogSanitizer.redactUrls(error.message)} " +
                    "(errorCode=${error.errorCode}/${error.errorCodeName})"
            )
            val category = categorizeExoPlayerError(error.errorCode)
            val httpStatusCode = extractHttpStatusCode(error)
            notifyError(
                message = error.message ?: "Unknown playback error",
                category = category,
                nativeErrorCode = error.errorCodeName,
                httpStatusCode = httpStatusCode
            )
        }

        override fun onMediaMetadataChanged(mediaMetadata: MediaMetadata) {
            android.util.Log.d("MediaPlayerInstance", "Media metadata changed")
            notifyDurationChanged()
        }

        override fun onTimelineChanged(timeline: Timeline, reason: Int) {
            // Wave E (DVR window duration): a live window's durationUs can
            // grow (or, once known, change) independently of a
            // playbackState/mediaMetadata transition -- e.g. as more
            // segments become available in the DVR window. Re-derive and
            // report it here too so a long-idle-in-STATE_READY live stream
            // doesn't get stuck reporting the window length it had at the
            // moment playback became ready. See notifyDurationChanged's doc.
            notifyDurationChanged()
        }

        override fun onTracksChanged(tracks: Tracks) {
            android.util.Log.d("MediaPlayerInstance", "Tracks changed")
            extractAndNotifyQualityTracks()
            extractAndNotifyAudioTracks()
            extractAndNotifySubtitleTracks()
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
            .setBandwidthMeter(bandwidthMeter)
            .build()
            .apply {
                addListener(playerListener)
                // Apply initial configuration
                config?.let { applyConfig(it) }
            }

        // Apply audio attributes / focus / becoming-noisy handling. Must run after
        // applyConfig() (above) so that isMuted already reflects "startMuted" from the
        // initial config, and must also run when config is null (applyConfig only runs
        // when config != null, but every instance still needs its attributes set).
        updateAudioFocusHandling()

        // Start position updates
        startPositionUpdates()

        // Start bandwidth monitoring
        startBandwidthMonitoring()
    }

    /**
     * Config staleness fix: [newConfig], when present, is the current
     * top-level (per-player) config snapshot from `MediaPlayer.load()` on
     * the Dart side -- the same wire shape `initialize`/`updateConfig`
     * already send (see [updateConfig]). Replaces [config] wholesale
     * *before* any of the config-dependent work below runs
     * ([activeStreamingConfig] for [applyStreamingTrackSelectionConstraints]
     * and [buildMediaItem]'s liveLatency, the `adaptiveCacheConfig` read,
     * and the `autoPlay` read at the bottom of this method), so all of them
     * see the item currently being loaded's actual config rather than
     * whatever was current at `initialize()`/the last explicit
     * `updateConfig()` call.
     *
     * Deliberately does NOT call [applyConfig] (unlike [updateConfig], which
     * does) -- `applyConfig`'s volume/speed/looping/`startMuted` writes are
     * meant for an explicit, intentional config change, not an implicit
     * side effect of every single item load. In particular, re-applying
     * `startMuted` here would silently undo a runtime `setMuted()` call:
     * `config`'s `startMuted` key is never updated when
     * [MediaPlayerManager.setMuted] runs (only [isMuted] is), unlike
     * `volume`/`speed`/`boxFit`, which the *Dart* `_config` field this map
     * is serialized from IS kept in sync with by `setVolume`/`setSpeed`/
     * `setBoxFit` (see those methods in media_player.dart) -- so
     * reapplying only the config-derived reads below, and leaving
     * `applyConfig`'s runtime-state-affecting writes untouched here, is
     * what keeps a user's in-progress mute state (or any other
     * `applyConfig`-driven state this config snapshot doesn't authoritatively
     * own) intact across a reload.
     *
     * Every Dart entry point that reaches this method now carries that
     * snapshot: `load`, and -- as of the playlist-path fix -- `setPlaylist`
     * and `skipToIndex` too (the latter being what `skipToNext`,
     * `skipToPrevious` and playlist auto-advance funnel through). [newConfig]
     * is therefore only `null` when an older cached Dart build, predating
     * that wiring, is talking to this native build; in that case [config]
     * (whatever it already was) is left untouched, exactly as before.
     */
    fun loadMediaItem(mediaItem: Map<String, Any>, newConfig: Map<String, Any>? = null) {
        if (newConfig != null) {
            config = newConfig
        }

        val url = mediaItem["url"] as? String ?: return
        val httpHeaders = mediaItem["httpHeaders"] as? Map<String, String>

        // Store current media item (for live stream detection)
        currentMediaItem = mediaItem

        android.util.Log.d("MediaPlayerInstance", "Loading media: $url")

        // Release any previous DRM handler before loading new media.
        drmHandler = null

        // Clear previous track data immediately to prevent stale UI
        notifyQualityTracksChanged(emptyList())
        notifyAudioTracksChanged(emptyList())
        notifySubtitleTracksChanged(emptyList())

        val uri = Uri.parse(url)

        // Wave D: HlsConfig/DashConfig wiring. Whichever config applies to
        // this item (HlsConfig when its resolved streaming format is HLS,
        // DashConfig when DASH — the item's explicit `streamingFormat` hint
        // if it carries one, else path-based inference; same resolution as
        // the media-source selection a few lines below) drives the
        // ExoPlayer track-selector's bitrate constraints regardless of
        // media-source type.
        applyStreamingTrackSelectionConstraints(activeStreamingConfig(mediaItem))

        // Determine which DataSource.Factory to use (custom headers or default).
        val activeDataSourceFactory: androidx.media3.datasource.DataSource.Factory =
            if (httpHeaders != null && httpHeaders.isNotEmpty()) {
                val customHttpFactory = DefaultHttpDataSource.Factory()
                    .setUserAgent("Flutter Media Player")
                httpHeaders.forEach { (key, value) ->
                    customHttpFactory.setDefaultRequestProperties(mapOf(key to value))
                }
                DefaultDataSource.Factory(context, customHttpFactory)
            } else {
                dataSourceFactory
            }

        // If the media item carries a drmConfig, create a DrmHandler and obtain a
        // DrmSessionManager so that ExoPlayer can decrypt the content. Read here
        // (ahead of the C-03b block below) because the caching decision itself
        // depends on drmConfig being absent.
        @Suppress("UNCHECKED_CAST")
        val drmConfig = mediaItem["drmConfig"] as? Map<String, Any>

        // --- C-03b: transparent adaptive-stream segment caching (Android only) ---
        // Wraps activeDataSourceFactory in a CacheDataSource.Factory backed by the
        // shared, process-wide SimpleCache — but ONLY when ALL of: this player's
        // config opted in (AdaptiveCacheConfig.enabled), the URL is HLS/DASH, and
        // the item carries no drmConfig. A DRM-configured item must never have its
        // segments written to the plaintext on-disk cache — see
        // AdaptiveCacheConfig's dartdoc for the full rationale — so drmConfig !=
        // null short-circuits this entirely (the shared cache isn't even
        // acquired). Progressive (non-HLS/DASH) media is intentionally excluded
        // too: C-03a already covers progressive caching via explicit
        // download-then-play through CacheService, and mixing that with a second,
        // transparent caching path for the same file would be confusing and
        // redundant.
        @Suppress("UNCHECKED_CAST")
        val adaptiveCacheConfig = config?.get("adaptiveCacheConfig") as? Map<String, Any>
        val adaptiveCachingEnabled = adaptiveCacheConfig?.get("enabled") as? Boolean ?: false
        val cacheAwareDataSourceFactory: androidx.media3.datasource.DataSource.Factory =
            if (adaptiveCachingEnabled && drmConfig == null && isAdaptiveStreamItem(mediaItem)) {
                try {
                    val maxSizeBytes = (adaptiveCacheConfig?.get("maxCacheSizeBytes") as? Number)
                        ?.toLong() ?: DEFAULT_ADAPTIVE_CACHE_MAX_SIZE_BYTES
                    val simpleCache = acquireAdaptiveCache(maxSizeBytes)
                    CacheDataSource.Factory()
                        .setCache(simpleCache)
                        .setUpstreamDataSourceFactory(activeDataSourceFactory)
                        // A corrupt/unreadable cache entry falls back to the
                        // upstream factory rather than failing playback outright —
                        // this is an opt-in performance/offline convenience, not a
                        // feature playback correctness should ever depend on.
                        .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
                } catch (e: Exception) {
                    android.util.Log.e(
                        "MediaPlayerInstance",
                        "Failed to enable adaptive segment cache, falling back to " +
                            "uncached playback: ${e.message}",
                        e
                    )
                    activeDataSourceFactory
                }
            } else {
                activeDataSourceFactory
            }

        // --- DRM wiring ---
        val mediaSource: MediaSource

        if (drmConfig != null) {
            android.util.Log.d("MediaPlayerInstance", "DRM config found, initializing DrmHandler")
            val handler = DrmHandler(context, playerId, methodChannel)
            val drmSessionManager = handler.createDrmSessionManager(drmConfig)

            if (drmSessionManager != null) {
                // Attach the DRM session manager directly to the per-format factory so that
                // HlsMediaSource / DashMediaSource / ProgressiveMediaSource all acquire a
                // Widevine or ClearKey license automatically during prepare().
                mediaSource = when (streamingFormatOf(mediaItem)) {
                    FORMAT_HLS ->
                        androidx.media3.exoplayer.hls.HlsMediaSource.Factory(
                            activeDataSourceFactory
                        ).setDrmSessionManagerProvider { _ -> drmSessionManager }
                            .createMediaSource(buildMediaItem(uri))

                    FORMAT_DASH ->
                        androidx.media3.exoplayer.dash.DashMediaSource.Factory(
                            activeDataSourceFactory
                        ).setDrmSessionManagerProvider { _ -> drmSessionManager }
                            .createMediaSource(buildMediaItem(uri))

                    else ->
                        androidx.media3.exoplayer.source.ProgressiveMediaSource.Factory(
                            activeDataSourceFactory
                        ).setDrmSessionManagerProvider { _ -> drmSessionManager }
                            .createMediaSource(buildMediaItem(uri))
                }

                drmHandler = handler
                android.util.Log.d("MediaPlayerInstance", "DRM media source created successfully")
            } else {
                // Fail-closed (wave 2 security hardening): a DRM-configured item
                // whose DrmSessionManager could not be created — invalid config,
                // unsupported scheme, or the minWidevineSecurityLevel policy
                // rejecting this device (see DrmHandler.createDrmSessionManager /
                // validateDrmConfig) — must never fall back to unprotected
                // playback. DrmHandler has already emitted
                // onDrmSessionUpdate(state=error) via notifyDrmError(), so the
                // Dart-side errorStream/drmSessionStream already knows why.
                // Refuse to build ANY media source and stop whatever was
                // previously loaded so nothing plays.
                android.util.Log.e(
                    "MediaPlayerInstance",
                    "Failed to create DRM session manager - refusing to load DRM-configured media without protection"
                )
                currentMediaItem = null
                exoPlayer?.apply {
                    stop()
                    clearMediaItems()
                }
                currentMediaSource = null
                return
            }
        } else {
            // Non-DRM path. cacheAwareDataSourceFactory is either
            // activeDataSourceFactory unchanged (adaptive caching off, not an
            // HLS/DASH URL, or wrapping failed) or that same factory wrapped in
            // the shared CacheDataSource — see the C-03b block above.
            mediaSource = createMediaSource(uri, cacheAwareDataSourceFactory)
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

        // Ensure the active PlayerView has the (possibly freshly created) ExoPlayer
        // attached.  If getPlayerView() was called by a new host (e.g. fullscreen)
        // after the player was created, playerView.setPlayer(exoPlayer) may not yet
        // have been called on the new view — re-attach here to be safe.
        playerView?.setPlayer(exoPlayer)

        currentMediaSource = mediaSource
    }

    /**
     * Config staleness fix (playlist path): [newConfig], when present, is the
     * current top-level (per-player) config snapshot sent by
     * `MediaPlayer.setPlaylist()` on the Dart side -- the same wire shape
     * `initialize`/`updateConfig`/`load` already send. It replaces [config]
     * wholesale *before* any config-dependent work runs (see the inline
     * comment below), and is forwarded to [loadMediaItem], which -- exactly
     * as on the `load` path -- deliberately does NOT re-run [applyConfig]:
     * see [loadMediaItem]'s doc for why reapplying volume/speed/`startMuted`
     * on every item load would undo an in-progress runtime [setMuted] call.
     *
     * `null` when an older cached Dart build (that sends only
     * playerId/playlist/startIndex) is talking to this native build; in that
     * case [config] is left untouched, exactly as before this fix.
     */
    fun setPlaylist(
        playlist: Map<String, Any>,
        startIndex: Int,
        newConfig: Map<String, Any>? = null
    ) {
        // Replace the stored config first, unconditionally, so it is in
        // place before ANY config-dependent work below -- including the
        // early-return paths (malformed/empty payload), where silently
        // dropping the caller's freshest snapshot would reintroduce exactly
        // the staleness this fix exists to remove. [loadMediaItem] performs
        // the same replacement itself from [newConfig] (that is where the
        // contract is documented); doing it here too is an idempotent no-op
        // on the normal path, not a second, divergent way to apply config.
        if (newConfig != null) {
            config = newConfig
        }

        val items = playlist["items"] as? List<Map<String, Any>> ?: return
        currentPlaylist = items
        currentIndex = startIndex.coerceIn(0, items.size - 1)

        if (items.isNotEmpty()) {
            loadMediaItem(items[currentIndex], newConfig)
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
        isMuted = muted
        exoPlayer?.volume = if (muted) 0f else originalVolume
        // Re-evaluate audio focus / becoming-noisy handling now that mute state changed:
        // muting drops focus handling (see updateAudioFocusHandling()), unmuting restores it.
        updateAudioFocusHandling()
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
        if (subtitleTrack == null) {
            // Disable subtitles
            exoPlayer?.let { player ->
                player.trackSelectionParameters = player.trackSelectionParameters
                    .buildUpon()
                    .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                    .build()
                android.util.Log.d("MediaPlayerInstance", "Subtitles disabled")
            }
            return
        }

        val trackId = subtitleTrack["id"] as? String ?: return
        android.util.Log.d("MediaPlayerInstance", "Setting subtitle track: ${subtitleTrack["title"]}, id: $trackId")

        exoPlayer?.let { player ->
            val currentTracks = player.currentTracks
            var targetGroup: Tracks.Group? = null
            var targetTrackIndex = -1

            // Find the text track group and index matching the requested subtitle
            for (group in currentTracks.groups) {
                if (group.type == C.TRACK_TYPE_TEXT) {
                    for (i in 0 until group.length) {
                        val format = group.getTrackFormat(i)
                        val formatId = format.id ?: "subtitle_$i"
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
                // Override track selection to the specific subtitle
                val override = TrackSelectionOverride(
                    targetGroup.mediaTrackGroup,
                    listOf(targetTrackIndex)
                )

                player.trackSelectionParameters = player.trackSelectionParameters
                    .buildUpon()
                    .setOverrideForType(override)
                    .build()

                android.util.Log.d("MediaPlayerInstance", "Subtitle track override applied")
            } else {
                android.util.Log.w("MediaPlayerInstance", "Subtitle track not found: $trackId")
            }
        }
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
        val trackId = audioTrack["id"] as? String ?: return
        android.util.Log.d("MediaPlayerInstance", "Setting audio track: ${audioTrack["name"]}, id: $trackId")

        exoPlayer?.let { player ->
            val currentTracks = player.currentTracks
            var targetGroup: Tracks.Group? = null
            var targetTrackIndex = -1

            // Find the audio track group and index matching the requested audio track
            for (group in currentTracks.groups) {
                if (group.type == C.TRACK_TYPE_AUDIO) {
                    for (i in 0 until group.length) {
                        val format = group.getTrackFormat(i)
                        val formatId = format.id ?: "audio_$i"
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
                // Override track selection to the specific audio track
                val override = TrackSelectionOverride(
                    targetGroup.mediaTrackGroup,
                    listOf(targetTrackIndex)
                )

                player.trackSelectionParameters = player.trackSelectionParameters
                    .buildUpon()
                    .setOverrideForType(override)
                    .build()

                android.util.Log.d("MediaPlayerInstance", "Audio track override applied")
            } else {
                android.util.Log.w("MediaPlayerInstance", "Audio track not found: $trackId")
            }
        }
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

    /**
     * Config staleness fix (playlist path): [newConfig] carries the current
     * config snapshot sent by `MediaPlayer.skipToIndex()` on the Dart side
     * (which is also what `skipToNext`/`skipToPrevious`/playlist auto-advance
     * route through) and is forwarded to [loadMediaItem] on exactly the same
     * terms as [setPlaylist] -- see that method's and [loadMediaItem]'s docs.
     * `null` from an older cached Dart build leaves [config] untouched.
     */
    fun skipToIndex(index: Int, newConfig: Map<String, Any>? = null) {
        currentPlaylist?.let { playlist ->
            if (index in 0 until playlist.size) {
                currentIndex = index
                loadMediaItem(playlist[index], newConfig)
            }
        }
    }

    /**
     * Config staleness fix: shares one source of truth with the `config`
     * parameter [loadMediaItem] now also accepts (see that method's doc) --
     * both simply overwrite [config] wholesale. There is nothing to
     * reconcile between "the config sent with the last `load()`" and "the
     * config sent via the last explicit `updateConfig()` call": whichever
     * happened most recently is what [config] holds, exactly mirroring the
     * Dart-side `MediaPlayer._config` field both wire payloads are
     * serialized from (a call to either one, on the Dart side, is what
     * updates `_config` in the first place). Unlike [loadMediaItem],
     * this DOES call [applyConfig] -- an explicit `updateConfig()` call is
     * exactly the "intentional config change, apply it now" case that
     * method's doc says [loadMediaItem] deliberately avoids.
     */
    fun updateConfig(newConfig: Map<String, Any>) {
        config = newConfig
        applyConfig(newConfig)
    }

    fun getPlayerView(): MediaPlayerView {
        // Always create a NEW MediaPlayerView for the requesting host so that
        // each UiKitView / AndroidView host gets its own PlayerView wired to the
        // same ExoPlayer instance.  ExoPlayer supports rendering to multiple
        // PlayerViews as long as only one is active at a time: we detach the
        // previous view's player reference before returning the new view so the
        // old host shows a black frame instead of contending for the surface.
        //
        // This mirrors the iOS approach where MediaPlayerInstance.getPlayerView()
        // creates a new AVPlayerLayer per host and AVPlayer supports multiple
        // layers simultaneously.  ExoPlayer does NOT support multiple PlayerViews
        // simultaneously, so we must detach the old one.
        android.util.Log.d(
            "MediaPlayerInstance",
            "getPlayerView(): creating new PlayerView for host; detaching previous view (had player: ${playerView?.let { true } ?: false})"
        )

        // Detach the ExoPlayer from whichever PlayerView is the current live
        // host.  This prevents the "single View parent" crash and ensures the
        // old inline host goes black cleanly while the new host (e.g. fullscreen)
        // renders immediately.
        playerView?.setPlayer(null)

        val newView = MediaPlayerView(context, exoPlayer)
        playerView = newView
        return newView
    }

    fun isPlaying(): Boolean {
        return exoPlayer?.isPlaying ?: false
    }

    /// Re-attach the ExoPlayer to the most recently created PlayerView.
    /// Called when the Dart side sends `reclaimVideoSurface` (i.e. when a new
    /// AndroidView host mounts and [_onPlatformViewCreated] fires).  The latest
    /// [getPlayerView()] call already created a fresh [MediaPlayerView] and stored
    /// it in [playerView]; here we just ensure ExoPlayer is re-wired to it.
    fun reclaimVideoSurface() {
        android.util.Log.d(
            "MediaPlayerInstance",
            "reclaimVideoSurface: (re)attaching exoPlayer to current playerView (view=${playerView != null}, player=${exoPlayer != null})"
        )
        playerView?.setPlayer(exoPlayer)
    }

    fun getBufferHealth(): Map<String, Any> {
        return bufferingHandler.getBufferHealth(exoPlayer, bandwidthMeter)
    }

    fun dispose() {
        // Stop position updates
        stopPositionUpdates()

        // Stop bandwidth monitoring
        stopBandwidthMonitoring()

        // Detach the player from the active view before releasing ExoPlayer so
        // the PlayerView surface is cleanly released and does not hold a dangling
        // player reference.
        playerView?.setPlayer(null)

        exoPlayer?.apply {
            removeListener(playerListener)
            release()
        }
        exoPlayer = null
        playerView = null
        currentMediaItem = null

        // Release DRM resources.
        drmHandler = null
    }

    /**
     * C-03b: true when the item currently being loaded is an adaptive-manifest
     * format (HLS or DASH — see [streamingFormatOf]); progressive media is the
     * only case this returns false for. These are the only formats the shared
     * segment cache is wired for.
     */
    private fun isAdaptiveStreamItem(mediaItem: Map<String, Any>?): Boolean {
        val format = streamingFormatOf(mediaItem)
        return format == FORMAT_HLS || format == FORMAT_DASH
    }

    /**
     * Issue #87: resolves the streaming format of [mediaItem] — the explicit
     * `streamingFormat` hint the Dart layer sends (`MediaItem.streamingFormat`,
     * one of `"hls"`/`"dash"`/`"progressive"`) when present, otherwise
     * inference from the URL. An unknown/absent hint falls back to inference,
     * so an older Dart build that never sends the key behaves exactly as
     * before.
     *
     * Mirrors `MediaItem.resolvedStreamingFormat` on the Dart side and
     * `MediaPlayerManager.swift`'s `streamingFormat(of:)` on iOS — all three
     * MUST stay in lockstep, since Dart decides `isSeekable`/`dvrEnabled` from
     * its answer while native decides the media-source type and which of
     * hlsConfig/dashConfig applies from this one.
     */
    private fun streamingFormatOf(mediaItem: Map<String, Any>?): String {
        when ((mediaItem?.get("streamingFormat") as? String)?.lowercase()) {
            FORMAT_HLS -> return FORMAT_HLS
            FORMAT_DASH -> return FORMAT_DASH
            FORMAT_PROGRESSIVE -> return FORMAT_PROGRESSIVE
        }
        val url = mediaItem?.get("url") as? String ?: return FORMAT_PROGRESSIVE
        return inferStreamingFormat(url)
    }

    /**
     * Issue #87: infers the streaming format from [url]'s PATH only —
     * query string and fragment are stripped first, and the test is
     * `endsWith` (case-insensitive), not `contains`. A signed URL such as
     * `…/manifest.mpd?token=…` is therefore DASH, and a rewritten path such
     * as `/hls.m3u8-archive/eu/manifest.mpd` is DASH rather than being
     * captured by the HLS branch as it was before this fix. Never throws:
     * `Uri.parse` is lenient on Android, and a null/blank path degrades to a
     * plain truncation at the first `?`/`#`.
     */
    private fun inferStreamingFormat(url: String): String {
        val path = (
            try {
                Uri.parse(url).path
            } catch (e: Exception) {
                null
            } ?: url.substringBefore('?').substringBefore('#')
            ).lowercase()
        return when {
            path.endsWith(".m3u8") -> FORMAT_HLS
            path.endsWith(".mpd") -> FORMAT_DASH
            else -> FORMAT_PROGRESSIVE
        }
    }

    /**
     * Wave D / issue #87: returns the top-level (per-player) HlsConfig/
     * DashConfig map that applies to [mediaItem] — HlsConfig when its
     * resolved format is HLS, DashConfig when it is DASH, `null` for
     * progressive media (which has no streaming config). Configs are never
     * cross-applied: a player configured with only `hlsConfig` that loads a
     * DASH item gets `null` here, exactly as if neither were configured
     * (Dart emits a debug-only diagnostic for that case — see
     * `MediaPlayer._warnMissingStreamingConfig`). Both configs are
     * serialized unconditionally by MediaPlayer._configToMap on the Dart
     * side (see streaming_config.dart's toMap()); this mirrors that same
     * format -> config resolution on the native side.
     */
    private fun activeStreamingConfig(mediaItem: Map<String, Any>?): Map<String, Any>? {
        val topConfig = config ?: return null
        return when (streamingFormatOf(mediaItem)) {
            FORMAT_HLS -> {
                @Suppress("UNCHECKED_CAST")
                topConfig["hlsConfig"] as? Map<String, Any>
            }
            FORMAT_DASH -> {
                @Suppress("UNCHECKED_CAST")
                topConfig["dashConfig"] as? Map<String, Any>
            }
            else -> null
        }
    }

    /**
     * Wave E (DVR window duration): whether DVR is enabled for the item
     * currently loaded ([currentMediaItem]'s `url`), i.e.
     * `HlsConfig.enableDvr`/`DashConfig.enableDvr` — whichever config
     * applies, via [activeStreamingConfig]. `false` (and therefore "not
     * seekable") for anything without a loaded item or without a matching
     * streaming config, matching every other DVR-gated default in this file
     * and in `NotificationHandler.kt`'s `isSeekable`.
     *
     * Used by [notifyDurationChanged] to decide whether a live window's
     * duration may be reported at all — see that method's doc for why this
     * must be re-derived from the same config both [applyStreamingTrackSelectionConstraints]
     * and `NotificationHandler.isSeekable` already read, rather than
     * invented as a new source of truth.
     */
    private fun currentDvrEnabled(): Boolean {
        val mediaItem = currentMediaItem ?: return false
        val streamingConfig = activeStreamingConfig(mediaItem)
        return streamingConfig?.get("enableDvr") as? Boolean ?: false
    }

    /**
     * Wave D: builds the Media3 [MediaItem] for [uri], applying
     * `HlsConfig.liveLatency`/`DashConfig.liveLatency` (whichever applies —
     * see [activeStreamingConfig]) as a [MediaItem.LiveConfiguration] target
     * offset when present. Used in place of a bare `MediaItem.fromUri(uri)`
     * everywhere a media source is built (both the DRM and non-DRM paths in
     * [loadMediaItem]) so the live-latency target applies regardless of
     * whether the item is DRM-protected.
     */
    private fun buildMediaItem(uri: Uri): MediaItem {
        // currentMediaItem is assigned at the top of loadMediaItem(), before
        // any media source is built, so it is always the item this URI
        // belongs to — which is what carries the explicit `streamingFormat`
        // hint that decides which streaming config applies.
        val streamingConfig = activeStreamingConfig(currentMediaItem)
        val liveLatencyMs = (streamingConfig?.get("liveLatencyMs") as? Number)?.toLong()

        val builder = MediaItem.Builder().setUri(uri)
        if (liveLatencyMs != null) {
            builder.setLiveConfiguration(
                MediaItem.LiveConfiguration.Builder()
                    .setTargetOffsetMs(liveLatencyMs)
                    .build()
            )
        }
        return builder.build()
    }

    /**
     * Wave D: applies `StreamingConfig.enableAdaptiveBitrate`/`maxBitrate`/
     * `minBitrate` (from whichever of HlsConfig/DashConfig [streamingConfig]
     * is) to the player's [DefaultTrackSelector]. When adaptive bitrate is
     * disabled, `forceHighestSupportedBitrate` locks selection onto a single
     * fixed video track (the highest bitrate within the configured bounds)
     * instead of letting ExoPlayer adapt between renditions — there is no
     * dedicated Media3 API to "disable ABR" directly, so this is the standard
     * technique for it. No-op when the player's track selector is not a
     * [DefaultTrackSelector] (should not happen — ExoPlayer.Builder creates
     * one by default and this instance never overrides it).
     */
    private fun applyStreamingTrackSelectionConstraints(streamingConfig: Map<String, Any>?) {
        val trackSelector = exoPlayer?.trackSelector as? DefaultTrackSelector ?: return

        val enableAdaptiveBitrate = streamingConfig?.get("enableAdaptiveBitrate") as? Boolean ?: true
        val maxBitrate = (streamingConfig?.get("maxBitrate") as? Number)?.toInt()
        val minBitrate = (streamingConfig?.get("minBitrate") as? Number)?.toInt()

        val parameters = trackSelector.buildUponParameters()
            .setMaxVideoBitrate(maxBitrate ?: Int.MAX_VALUE)
            .setMinVideoBitrate(minBitrate ?: 0)
            .setForceHighestSupportedBitrate(!enableAdaptiveBitrate)
            .build()

        trackSelector.setParameters(parameters)
        android.util.Log.d(
            "MediaPlayerInstance",
            "applyStreamingTrackSelectionConstraints: enableAdaptiveBitrate=$enableAdaptiveBitrate " +
                "maxBitrate=$maxBitrate minBitrate=$minBitrate"
        )
    }

    /**
     * Builds the Media3 [MediaSource] for [uri]. The source type follows the
     * currently-loading item's resolved streaming format ([streamingFormatOf]
     * on [currentMediaItem]) — the host's explicit `MediaItem.streamingFormat`
     * when it set one, else path-based inference — so a DASH manifest behind
     * an HLS-looking path, or an extension-less manifest endpoint, is loaded
     * with the right source instead of being sniffed out of the raw URL
     * string (issue #87).
     */
    private fun createMediaSource(uri: Uri, dataSourceFactory: DataSource.Factory = this.dataSourceFactory): MediaSource {
        return when (streamingFormatOf(currentMediaItem)) {
            FORMAT_HLS -> {
                HlsMediaSource.Factory(dataSourceFactory)
                    .createMediaSource(buildMediaItem(uri))
            }
            FORMAT_DASH -> {
                DashMediaSource.Factory(dataSourceFactory)
                    .createMediaSource(buildMediaItem(uri))
            }
            else -> {
                ProgressiveMediaSource.Factory(dataSourceFactory)
                    .createMediaSource(buildMediaItem(uri))
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
                isMuted = it
                if (it) volume = 0f
            }

            // Apply looping
            (config["looping"] as? Boolean)?.let {
                repeatMode = if (it) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
            }
        }

        // Apply BoxFit
        (config["boxFit"] as? String)?.let { setBoxFit(it) }

        // Enable ExoPlayer wake-lock and wi-fi lock so playback continues when the
        // screen is off.  Full background-audio support on Android additionally
        // requires the host app to run a foreground service with a media notification
        // (ExoPlayer's MediaSessionService or a custom Service); this flag is the
        // minimum necessary player-side configuration.
        val allowBackground = config["allowBackgroundPlayback"] as? Boolean ?: false
        exoPlayer?.setWakeMode(
            if (allowBackground) C.WAKE_MODE_NETWORK else C.WAKE_MODE_NONE
        )
        android.util.Log.d("MediaPlayerInstance", "allowBackgroundPlayback=$allowBackground, wakeMode=${if (allowBackground) "NETWORK" else "NONE"}")
    }

    /**
     * (Re)applies ExoPlayer's audio attributes, audio-focus handling, and
     * becoming-noisy handling based on the current [isMuted] state.
     *
     * - [AudioAttributes] with `USAGE_MEDIA` / `CONTENT_TYPE_MOVIE` tell Android (and other
     *   apps) what kind of audio stream this is, which is required for the system to make
     *   correct ducking/interruption decisions. This is the same classification ExoPlayer's
     *   own demo app uses for a general-purpose media player handling both audio and video.
     * - `handleAudioFocus = true` (ExoPlayer's `setAudioAttributes(attrs, handleAudioFocus)`)
     *   is what makes ExoPlayer request audio focus on play(), duck/pause on transient loss,
     *   and pause on permanent loss, per the standard `AudioManager` contract. ExoPlayer does
     *   NOT do any of this by default — `ExoPlayer.Builder` defaults to no focus handling
     *   unless this is explicitly opted into (documented ExoPlayer behavior, unchanged across
     *   2.x releases including 2.19.1); ExoPlayer.Builder.setAudioAttributes() was never
     *   called at all in this file previously (see initializeExoPlayer()), so prior to this
     *   change focus was not handled at all.
     * - `setHandleAudioBecomingNoisy` is gated the same way: a muted instance has no audible
     *   output, so pausing it when headphones are unplugged serves no purpose and would be a
     *   surprising side effect (e.g. for a muted autoplay preview that should keep advancing).
     *
     * When [isMuted] is true we pass `handleAudioFocus = false` and disable becoming-noisy
     * handling: a silent player has nothing to lose by not holding focus, and — because
     * Android audio focus is granted to one listener at a time system-wide, not scoped per
     * app — this also prevents a muted preview instance from stealing focus away from (or
     * being paused by focus loss from) another *audible* instance of this same plugin, e.g.
     * a real player elsewhere in the same app. Multiple concurrent *audible* instances of
     * this plugin will still contend for focus with each other exactly as they would with any
     * other app, since each MediaPlayerInstance owns an independent ExoPlayer with its own
     * focus request; this is a known, accepted limitation of per-instance focus handling and
     * is not addressed by this change (see report).
     */
    private fun updateAudioFocusHandling() {
        val handleAudioFocus = !isMuted
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.CONTENT_TYPE_MOVIE)
            .build()
        exoPlayer?.setAudioAttributes(audioAttributes, handleAudioFocus)
        exoPlayer?.setHandleAudioBecomingNoisy(handleAudioFocus)
        android.util.Log.d(
            "MediaPlayerInstance",
            "updateAudioFocusHandling: isMuted=$isMuted handleAudioFocus=$handleAudioFocus"
        )
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

    private fun getCurrentBandwidthEstimate(@Suppress("UNUSED_PARAMETER") player: ExoPlayer): Long {
        // Read measured network throughput from the DefaultBandwidthMeter that
        // was supplied to ExoPlayer.Builder.  bitrateEstimate is in bits/sec,
        // which matches what the Dart side expects (onBandwidthChanged delivers
        // bits/sec and StreamingService.updateBandwidth() stores it as-is).
        //
        // The estimate returns 0 until the meter has observed at least one
        // download; that is expected and matches previous behaviour.
        //
        // DEVICE VERIFICATION REQUIRED: confirm bitrateEstimate tracks actual
        // network changes (e.g. simulate throttling) on a real device.
        return try {
            bandwidthMeter.bitrateEstimate
        } catch (e: Exception) {
            android.util.Log.e("MediaPlayerInstance", "Error getting bandwidth estimate: ${e.message}")
            0L
        }
    }

    private fun notifyStateChanged(state: String, isBuffering: Boolean, pauseReason: String? = null) {
        try {
            android.util.Log.d("MediaPlayerInstance", "State changed: $state, isBuffering: $isBuffering, pauseReason: $pauseReason")
            val arguments = mutableMapOf<String, Any>(
                "playerId" to playerId,
                "state" to state,
                "isBuffering" to isBuffering,
                "bufferPercentage" to (exoPlayer?.bufferedPercentage ?: 0)
            )
            // H-01: only attached for a "paused" event caused by the OS
            // revoking audio focus — see onIsPlayingChanged/onPlayWhenReadyChanged
            // above and MediaPlayer._handleStateChanged / pauseReasonStream on
            // the Dart side.
            pauseReason?.let { arguments["pauseReason"] = it }
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

    /**
     * Wave E (DVR window duration): for VOD, `player.duration` (the total
     * media duration) is reported unchanged from before this change. For a
     * live item, `player.duration`/the current [Timeline.Window]'s
     * `durationUs` is ExoPlayer's own notion of the *currently known
     * seekable span* — buffer start to live edge — not the total elapsed
     * time the stream has been broadcasting, which is unbounded/unknowable
     * for a genuine live source and would be misleading to report as
     * "duration". That span is exactly the DVR window: reporting it here is
     * what lets `PlaybackState.duration` (and, downstream,
     * `NotificationHandler`'s `METADATA_KEY_DURATION`) carry a real
     * scrubber range instead of staying unknown for the lifetime of a live
     * item — the bug this method exists to fix.
     *
     * Deliberately gated on [currentDvrEnabled] even though the window's
     * `durationUs` is a native ExoPlayer property independent of that app
     * config flag: reporting *any* duration for a live-without-DVR item
     * would hand `NotificationHandler` (and any other consumer of
     * `PlaybackState.duration`) a scrubbable range while
     * `MediaPlayer.isSeekable`/`ACTION_SEEK_TO` still (correctly) withhold
     * seek permission — precisely the half-wired "permission without a
     * range, or a range without permission" defect class this fix removes.
     * `NotificationHandler.isSeekable` independently re-derives and
     * enforces the same gate from `isLive`/`dvrEnabled` before trusting
     * whatever is sent here, so this is belt-and-braces, not the only
     * guard — but there is no reason to *originate* a value that must then
     * be suppressed downstream.
     *
     * `durationUs` can be `C.TIME_UNSET` (nothing known yet, e.g. the
     * playlist has only just loaded) or can legitimately grow across
     * repeated calls as more of the DVR window becomes available. This
     * method makes no attempt to predict or estimate a not-yet-known
     * value — it simply reports whatever is currently known, and is
     * invoked again on every `onTimelineChanged` (see `playerListener`
     * below) as well as the existing `onPlaybackStateChanged`/
     * `onMediaMetadataChanged` triggers, so a live window's duration is
     * kept current as it grows. `NotificationHandler`'s anti-regression
     * guard (see its `updateState` doc) means a later, larger value is
     * always accepted; a transient unknown (0) is not.
     *
     * Position remains window-relative already — `player.currentPosition`
     * (see `notifyPositionChanged`/`startPositionUpdates`) is documented by
     * ExoPlayer as the position within the *current window*, i.e. the same
     * offset-from-window-start basis as `durationUs` — so no separate
     * position translation is needed for a DVR window: position and
     * duration already share the same zero point.
     *
     * The `isLive` value in the reported event now comes from
     * [Timeline.Window.isLive] (ExoPlayer's own manifest-derived
     * detection) rather than the Dart-supplied [MediaItem.isLive] flag this
     * method previously echoed back unchanged. The two should agree for any
     * correctly configured live item; where they don't (e.g. a live URL
     * loaded without `MediaItem.isLive: true`), the native value is the
     * more trustworthy source for a *duration* event specifically, since
     * it's what actually decided whether `durationUs` means "total media
     * duration" or "current DVR window length" a few lines above.
     */
    private fun notifyDurationChanged() {
        try {
            val player = exoPlayer ?: return
            val timeline = player.currentTimeline
            if (timeline.isEmpty) return

            val window = Timeline.Window()
            timeline.getWindow(player.currentMediaItemIndex, window)
            val isLive = window.isLive()

            val durationMs: Long = when {
                !isLive ->
                    if (player.duration != C.TIME_UNSET) player.duration else 0L
                isLive && window.isSeekable && window.durationUs != C.TIME_UNSET &&
                    currentDvrEnabled() ->
                    window.durationMs
                else -> 0L
            }

            if (durationMs > 0) {
                val arguments = mapOf(
                    "playerId" to playerId,
                    "duration" to durationMs.toInt(),
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

    private fun extractAndNotifyAudioTracks() {
        exoPlayer?.let { player ->
            val audioTracks = mutableListOf<Map<String, Any>>()
            val currentTracks = player.currentTracks

            // Extract audio tracks
            for (group in currentTracks.groups) {
                if (group.type == C.TRACK_TYPE_AUDIO && group.length > 0) {
                    for (i in 0 until group.length) {
                        val format = group.getTrackFormat(i)

                        // Build track ID
                        val trackId = format.id ?: "audio_$i"

                        // Build track name from label or language
                        val trackName = format.label
                            ?: format.language?.let { getLanguageName(it) }
                            ?: "Audio Track ${i + 1}"

                        audioTracks.add(mapOf(
                            "id" to trackId,
                            "name" to trackName,
                            "language" to (format.language ?: ""),
                            "codec" to (format.codecs ?: "unknown"),
                            "channels" to (format.channelCount.takeIf { it > 0 } ?: 2),
                            "sampleRate" to (format.sampleRate.takeIf { it > 0 } ?: 48000),
                            "bitrate" to format.bitrate,
                            "isSelected" to group.isTrackSelected(i),
                            "isAvailable" to true
                        ))
                    }
                }
            }

            // ALWAYS notify, even with empty list (to clear UI when switching videos)
            android.util.Log.d("MediaPlayerInstance", "Found ${audioTracks.size} audio tracks")
            notifyAudioTracksChanged(audioTracks)
        }
    }

    private fun notifyAudioTracksChanged(tracks: List<Map<String, Any>>) {
        try {
            val arguments = mapOf(
                "playerId" to playerId,
                "tracks" to tracks
            )
            methodChannel.invokeMethod("onAudioTracksChanged", arguments)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun extractAndNotifySubtitleTracks() {
        exoPlayer?.let { player ->
            val subtitleTracks = mutableListOf<Map<String, Any>>()
            val currentTracks = player.currentTracks

            // Extract text/subtitle tracks
            for (group in currentTracks.groups) {
                if (group.type == C.TRACK_TYPE_TEXT && group.length > 0) {
                    for (i in 0 until group.length) {
                        val format = group.getTrackFormat(i)

                        // Build track ID
                        val trackId = format.id ?: "subtitle_$i"

                        // Build track title from label or language
                        val trackTitle = format.label
                            ?: format.language?.let { getLanguageName(it) }
                            ?: "Subtitle ${i + 1}"

                        // Detect subtitle format from MIME type
                        val subtitleFormat = when (format.sampleMimeType) {
                            "application/x-subrip", "text/x-ssa" -> "srt"
                            "text/vtt" -> "webvtt"
                            "text/x-ass" -> "ass"
                            "text/x-ssa" -> "ssa"
                            "application/ttml+xml" -> "ttml"
                            else -> "srt"
                        }

                        subtitleTracks.add(mapOf(
                            "id" to trackId,
                            "title" to trackTitle,
                            "language" to (format.language ?: ""),
                            "format" to subtitleFormat,
                            "isSelected" to group.isTrackSelected(i),
                            "isDefault" to ((format.selectionFlags and C.SELECTION_FLAG_DEFAULT) != 0)
                        ))
                    }
                }
            }

            // ALWAYS notify, even with empty list (to clear UI when switching to video without subtitles)
            android.util.Log.d("MediaPlayerInstance", "Found ${subtitleTracks.size} subtitle tracks")
            notifySubtitleTracksChanged(subtitleTracks)
        }
    }

    private fun notifySubtitleTracksChanged(tracks: List<Map<String, Any>>) {
        try {
            val arguments = mapOf(
                "playerId" to playerId,
                "tracks" to tracks
            )
            methodChannel.invokeMethod("onSubtitleTracksChanged", arguments)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun getLanguageName(languageCode: String): String {
        return when (languageCode.lowercase()) {
            "en" -> "English"
            "es" -> "Spanish"
            "fr" -> "French"
            "de" -> "German"
            "it" -> "Italian"
            "pt" -> "Portuguese"
            "ru" -> "Russian"
            "ja" -> "Japanese"
            "ko" -> "Korean"
            "zh" -> "Chinese"
            "ar" -> "Arabic"
            "hi" -> "Hindi"
            "tr" -> "Turkish"
            "nl" -> "Dutch"
            "pl" -> "Polish"
            "sv" -> "Swedish"
            "da" -> "Danish"
            "fi" -> "Finnish"
            "no" -> "Norwegian"
            "cs" -> "Czech"
            else -> languageCode.uppercase()
        }
    }

    /**
     * H-01: maps ExoPlayer's [PlaybackException.errorCode] onto the small,
     * cross-platform error-category vocabulary shared with the Dart mapper
     * (see `MediaErrorCategory` in lib/src/core/exceptions.dart) and mirrored
     * on iOS by `MediaPlayerInstance.categorize(_:)` in MediaPlayerManager.swift.
     * All three call sites must stay in lockstep — the Dart test suite
     * (test/exceptions/error_category_vocabulary_test.dart) parses this
     * file's category string literals as text and fails if they drift from
     * the Dart vocabulary, since ExoPlayer's Kotlin constants can't be
     * introspected from a pure-Dart test.
     *
     * Range groupings below follow ExoPlayer 2.19's documented
     * PlaybackException error-code space (general: 1000s, I/O: 2000s,
     * parsing/content: 3000s, decoder: 4000s, audio track: 5000s,
     * DRM: 6000s). NEEDS BUILD/ON-DEVICE VERIFICATION — this file is not
     * compiled as part of this change.
     */
    private fun categorizeExoPlayerError(errorCode: Int): String {
        return when {
            // Bad HTTP status / missing resource — the server responded, just
            // not with usable content.
            errorCode == PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS ||
                errorCode == PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND -> "HTTP"
            // Remaining 2000-2999 I/O errors: connection failures, timeouts,
            // permission/cleartext issues — could not reach/read the source.
            errorCode in 2000..2999 -> "NETWORK"
            // 3000-3999 container/manifest parsing errors, plus
            // BEHIND_LIVE_WINDOW (1002) and out-of-range reads: the source
            // itself is malformed/unsupported, not a network condition.
            errorCode in 3000..3999 ||
                errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW ||
                errorCode == PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE -> "SOURCE"
            // 4000-5999: decoder + audio track errors — codec/hardware cannot
            // play this content.
            errorCode in 4000..5999 -> "DECODER"
            // 6000-6999: DRM/license errors.
            errorCode in 6000..6999 -> "DRM"
            else -> "UNKNOWN"
        }
    }

    /**
     * Walks the error's cause chain looking for ExoPlayer's
     * [androidx.media3.datasource.HttpDataSource.InvalidResponseCodeException]
     * to surface the actual HTTP status code to Dart (mirrors
     * `httpStatusCode` in the iOS notifyError payload). Bounded depth guards
     * against a pathological/cyclical cause chain.
     */
    private fun extractHttpStatusCode(error: Throwable): Int? {
        var cause: Throwable? = error
        var depth = 0
        while (cause != null && depth < 10) {
            if (cause is androidx.media3.datasource.HttpDataSource.InvalidResponseCodeException) {
                return cause.responseCode
            }
            cause = cause.cause
            depth++
        }
        return null
    }

    private fun notifyError(
        message: String,
        category: String = "UNKNOWN",
        nativeErrorCode: String? = null,
        httpStatusCode: Int? = null
    ) {
        try {
            val arguments = mutableMapOf<String, Any>(
                "playerId" to playerId,
                "error" to message,
                "category" to category
            )
            nativeErrorCode?.let { arguments["nativeErrorCode"] = it }
            httpStatusCode?.let { arguments["httpStatusCode"] = it }
            methodChannel.invokeMethod("onError", arguments)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
