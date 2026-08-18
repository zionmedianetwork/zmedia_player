package com.zionmedianetwork.zmedia_player

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.platform.PlatformViewRegistry

/**
 * ZMediaPlayerPlugin
 */
class ZMediaPlayerPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, NetworkMonitor.Callback {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var playerManager: MediaPlayerManager
    private var activity: Activity? = null

    // H-06: single, plugin-lifetime `NetworkMonitor` (not one per playerId —
    // connectivity is a device-global signal, not a per-player one, so a
    // per-player ConnectivityManager.NetworkCallback would just be N
    // redundant registrations of the same system callback). Started in
    // onAttachedToEngine, stopped in onDetachedFromEngine, mirroring
    // `playerManager`'s own lifecycle in this class.
    private lateinit var networkMonitor: NetworkMonitor

    // H-06 fix: NetworkMonitor.Callback methods run on ConnectivityManager's
    // internal `ConnectivityThread`, not the platform thread — see the doc on
    // `broadcastNetworkStatus` below. This posts `invokeMethod` calls back to
    // the main thread, which `MethodChannel` requires.
    private val mainHandler = Handler(Looper.getMainLooper())

    // Player ids currently between a successful `initialize` and `dispose`
    // call, used to fan the single NetworkMonitor's events out to every live
    // MediaPlayer instance on the Dart side (each event is dispatched by
    // playerId — see MediaPlayer._staticMethodCallHandler).
    private val activePlayerIds = mutableSetOf<String>()

    companion object {
        /**
         * M-16: wire protocol version for the MethodChannel contract with the
         * Dart package (see `MediaPlayer.protocolVersion` in
         * lib/src/core/media_player.dart). Bump this alongside a matching
         * Dart-side bump whenever a MethodChannel contract change requires
         * native to be rebuilt to stay compatible (new required arguments,
         * renamed methods, changed event payload shapes, etc.). Mirrored on
         * iOS by `ZMediaPlayerPlugin.nativeProtocolVersion` in
         * ZMediaPlayerPlugin.swift.
         */
        const val NATIVE_PROTOCOL_VERSION = 1

        /**
         * Oldest Dart `protocolVersion` this native implementation still
         * accepts. A host app can end up running a newer Dart package
         * against a stale cached/compiled native build (the package is
         * distributed by git ref, not pub.dev) — `handleInitialize` rejects
         * that combination explicitly instead of letting later calls fail
         * ambiguously (e.g. via a raw `MissingPluginException`).
         */
        const val MIN_SUPPORTED_DART_PROTOCOL_VERSION = 1
    }

    // Phase 3: Handler maps
    private val notificationHandlers = mutableMapOf<String, NotificationHandler>()
    private val pipHandlers = mutableMapOf<String, PipHandler>()
    private val castHandlers = mutableMapOf<String, CastHandler>()

    // Phase 1: Secure storage
    private lateinit var secureStorageChannel: MethodChannel
    private lateinit var secureStorageHandler: SecureStorageHandler

    // B-12 (wave 2): opt-in screen-capture protection. A single
    // plugin-lifetime instance (not one per playerId) because FLAG_SECURE is
    // scoped to the host Activity's *window*, which every player in this
    // Activity shares — see SecureSurfaceHandler's class doc.
    private lateinit var secureSurfaceHandler: SecureSurfaceHandler

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "zmedia_player")
        channel.setMethodCallHandler(this)

        // Initialize player manager
        playerManager = MediaPlayerManager(context, channel)

        // H-06: start device-wide connectivity monitoring for the lifetime of
        // the plugin (see the `networkMonitor` field doc for why this is one
        // instance rather than one per player).
        networkMonitor = NetworkMonitor(context, this)
        networkMonitor.startMonitoring()

        // Phase 1: Initialize secure storage channel
        secureStorageChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "zmedia_player/secure_storage")
        secureStorageHandler = SecureStorageHandler(context)
        secureStorageChannel.setMethodCallHandler(secureStorageHandler)

        // B-12 (wave 2): no Activity yet at engine-attach time (ActivityAware
        // callbacks fire separately) — SecureSurfaceHandler.applyFlag() defers
        // until updateActivity() supplies one, exactly like PipHandler.
        secureSurfaceHandler = SecureSurfaceHandler(activity)

        // Register platform view
        flutterPluginBinding
            .platformViewRegistry
            .registerViewFactory(
                "zmedia_player_view",
                MediaPlayerViewFactory(playerManager)
            )
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "initialize" -> handleInitialize(call, result)
            "load" -> handleLoad(call, result)
            "setPlaylist" -> handleSetPlaylist(call, result)
            "play" -> handlePlay(call, result)
            "pause" -> handlePause(call, result)
            "stop" -> handleStop(call, result)
            "seekTo" -> handleSeekTo(call, result)
            "setVolume" -> handleSetVolume(call, result)
            "setSpeed" -> handleSetSpeed(call, result)
            "setMuted" -> handleSetMuted(call, result)
            "setBoxFit" -> handleSetBoxFit(call, result)
            "setSubtitleTrack" -> handleSetSubtitleTrack(call, result)
            "setQualityTrack" -> handleSetQualityTrack(call, result)
            "setAudioTrack" -> handleSetAudioTrack(call, result)
            "enableAutoQuality" -> handleEnableAutoQuality(call, result)
            "skipToIndex" -> handleSkipToIndex(call, result)
            "updateConfig" -> handleUpdateConfig(call, result)
            "dispose" -> handleDispose(call, result)

            // B-12 (wave 2): opt-in screen-capture protection
            "setSecureSurface" -> handleSetSecureSurface(call, result)

            // Phase 1: Buffering methods
            "getBufferHealth" -> handleGetBufferHealth(call, result)

            // Phase 3: Notification methods
            "initializeNotification" -> handleInitializeNotification(call, result)
            "showNotification" -> handleShowNotification(call, result)
            "updateNotificationState" -> handleUpdateNotificationState(call, result)
            "updateNotificationPosition" -> handleUpdateNotificationPosition(call, result)
            "dismissNotification" -> handleDismissNotification(call, result)

            // Phase 3: PiP methods
            "checkPipAvailability" -> handleCheckPipAvailability(call, result)
            "enterPictureInPicture" -> handleEnterPictureInPicture(call, result)
            "exitPictureInPicture" -> handleExitPictureInPicture(call, result)
            "onPipModeChanged" -> handlePipModeChanged(call, result)

            // Surface reclaim: re-attach ExoPlayer to the newest platform-view host
            "reclaimVideoSurface" -> handleReclaimVideoSurface(call, result)

            // Phase 3: Cast methods
            "initializeCast" -> handleInitializeCast(call, result)
            "startCastDiscovery" -> handleStartCastDiscovery(call, result)
            "stopCastDiscovery" -> handleStopCastDiscovery(call, result)
            "connectToCastDevice" -> handleConnectToCastDevice(call, result)
            "disconnectFromCastDevice" -> handleDisconnectFromCastDevice(call, result)
            "loadMediaOnCastDevice" -> handleLoadMediaOnCastDevice(call, result)
            "castPlay" -> handleCastPlay(call, result)
            "castPause" -> handleCastPause(call, result)
            "castSeekTo" -> handleCastSeekTo(call, result)
            "castSetVolume" -> handleCastSetVolume(call, result)

            else -> result.notImplemented()
        }
    }

    private fun handleInitialize(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val config = call.argument<Map<String, Any>>("config")
            val dartProtocolVersion = call.argument<Int>("protocolVersion")

            if (playerId == null) {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
                return
            }

            // M-16: reject a Dart package too old for this native build
            // before doing anything else. A null dartProtocolVersion means
            // the Dart side predates version negotiation entirely — allow it
            // through unchanged (nothing to compare against).
            if (dartProtocolVersion != null && dartProtocolVersion < MIN_SUPPORTED_DART_PROTOCOL_VERSION) {
                result.error(
                    "PROTOCOL_VERSION_MISMATCH",
                    "Dart package protocol v$dartProtocolVersion is older than the minimum " +
                        "v$MIN_SUPPORTED_DART_PROTOCOL_VERSION this native plugin " +
                        "(v$NATIVE_PROTOCOL_VERSION) requires. Rebuild the app against a " +
                        "matching zmedia_player native version.",
                    mapOf(
                        "nativeProtocolVersion" to NATIVE_PROTOCOL_VERSION,
                        "minSupportedDartProtocolVersion" to MIN_SUPPORTED_DART_PROTOCOL_VERSION,
                        "dartProtocolVersion" to dartProtocolVersion
                    )
                )
                return
            }

            playerManager.initializePlayer(playerId, config)
            // H-06: track this playerId so NetworkMonitor events (which are
            // device-global, not per-player) can be fanned out to it — see
            // onNetworkAvailable/onNetworkLost/onNetworkQualityChanged below.
            activePlayerIds.add(playerId)
            // H-06 snapshot fix: NetworkMonitor.startMonitoring() runs once,
            // at plugin attach, and only fans events out to players present
            // in activePlayerIds *at the moment an event fires*. A player
            // initialized after the last connectivity transition would
            // otherwise never learn the current status and would read
            // `networkStatus` as "unknown" indefinitely. Emit the
            // synchronously-queried current status to this player right now
            // so its Dart-side NetworkStatus starts correct instead of
            // waiting for the next transition. Safe re: ordering — the Dart
            // `MediaPlayer` instance is registered in `_instances` by its
            // constructor before `initialize()` (which awaits this native
            // call) ever runs, so `_staticMethodCallHandler` can always
            // resolve this playerId whenever this event is actually
            // delivered to Dart, regardless of relative timing with the
            // `initialize` call's own result.
            try {
                val currentStatus = networkMonitor.getCurrentNetworkStatus()
                channel.invokeMethod(
                    "onNetworkStatusChanged",
                    currentStatus + mapOf("playerId" to playerId)
                )
            } catch (e: Exception) {
                android.util.Log.e(
                    "ZMediaPlayerPlugin",
                    "Failed to emit initial network status to $playerId: ${e.message}",
                    e
                )
            }
            // Report our own version back so Dart can, symmetrically, detect
            // a native build too old for what it's about to call (see
            // MediaPlayer.initialize()'s minSupportedNativeProtocolVersion
            // check).
            result.success(mapOf("protocolVersion" to NATIVE_PROTOCOL_VERSION))
        } catch (e: Exception) {
            result.error("INITIALIZATION_ERROR", e.message, null)
        }
    }

    private fun handleLoad(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val mediaItem = call.argument<Map<String, Any>>("mediaItem")
            // Config staleness fix: MediaPlayer.load() on the Dart side now
            // sends the current MediaConfig snapshot alongside every load,
            // not just 'initialize'/'updateConfig' -- see that method's doc.
            // Optional/nullable so an older cached Dart build (that only
            // sends playerId + mediaItem) still loads correctly with
            // whatever config this instance already holds.
            val config = call.argument<Map<String, Any>>("config")

            if (playerId != null && mediaItem != null) {
                playerManager.loadMediaItem(playerId, mediaItem, config)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and media item are required", null)
            }
        } catch (e: Exception) {
            // H-01: loadMediaItem() only builds the MediaSource graph
            // synchronously — actual network/DRM/decoder failures surface
            // later, asynchronously, via Player.Listener.onPlayerError ->
            // notifyError()'s "onError" event (already categorized there).
            // A synchronous exception here means source/DRM *configuration*
            // itself was rejected before ExoPlayer ever started loading.
            result.error("LOAD_ERROR", e.message, mapOf("category" to categorizeSynchronousLoadError(e)))
        }
    }

    /**
     * Best-effort categorization (see [MediaPlayerManager]'s
     * `categorizeExoPlayerError`) for exceptions thrown synchronously while
     * building the ExoPlayer MediaSource graph — i.e. before playback even
     * starts, so there is no [androidx.media3.common.PlaybackException]
     * with a proper error code to inspect yet.
     */
    private fun categorizeSynchronousLoadError(e: Exception): String {
        val message = e.message?.lowercase() ?: ""
        return when {
            e is IllegalStateException &&
                (message.contains("drm") || message.contains("license") || message.contains("https")) -> "DRM"
            e is java.io.IOException || e is java.net.UnknownHostException -> "NETWORK"
            e is IllegalArgumentException -> "SOURCE"
            else -> "UNKNOWN"
        }
    }

    private fun handleSetPlaylist(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val playlist = call.argument<Map<String, Any>>("playlist")
            val startIndex = call.argument<Int>("startIndex") ?: 0

            if (playerId != null && playlist != null) {
                playerManager.setPlaylist(playerId, playlist, startIndex)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and playlist are required", null)
            }
        } catch (e: Exception) {
            result.error("PLAYLIST_ERROR", e.message, null)
        }
    }

    private fun handlePlay(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            if (playerId != null) {
                playerManager.play(playerId)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            result.error("PLAY_ERROR", e.message, null)
        }
    }

    private fun handlePause(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            if (playerId != null) {
                playerManager.pause(playerId)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            result.error("PAUSE_ERROR", e.message, null)
        }
    }

    private fun handleStop(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            if (playerId != null) {
                playerManager.stop(playerId)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            result.error("STOP_ERROR", e.message, null)
        }
    }

    private fun handleSeekTo(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val position = call.argument<Int>("position")

            if (playerId != null && position != null) {
                playerManager.seekTo(playerId, position)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and position are required", null)
            }
        } catch (e: Exception) {
            result.error("SEEK_ERROR", e.message, null)
        }
    }

    private fun handleSetVolume(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val volume = call.argument<Double>("volume")

            if (playerId != null && volume != null) {
                playerManager.setVolume(playerId, volume.toFloat())
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and volume are required", null)
            }
        } catch (e: Exception) {
            result.error("VOLUME_ERROR", e.message, null)
        }
    }

    private fun handleSetSpeed(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val speed = call.argument<Double>("speed")

            if (playerId != null && speed != null) {
                playerManager.setPlaybackSpeed(playerId, speed.toFloat())
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and speed are required", null)
            }
        } catch (e: Exception) {
            result.error("SPEED_ERROR", e.message, null)
        }
    }

    private fun handleSetMuted(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val muted = call.argument<Boolean>("muted")

            if (playerId != null && muted != null) {
                playerManager.setMuted(playerId, muted)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and muted state are required", null)
            }
        } catch (e: Exception) {
            result.error("MUTE_ERROR", e.message, null)
        }
    }

    private fun handleSetBoxFit(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val boxFit = call.argument<String>("boxFit")

            if (playerId != null && boxFit != null) {
                playerManager.setBoxFit(playerId, boxFit)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and box fit are required", null)
            }
        } catch (e: Exception) {
            result.error("BOXFIT_ERROR", e.message, null)
        }
    }

    private fun handleSetSubtitleTrack(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val subtitleTrack = call.argument<Map<String, Any>?>("subtitleTrack")

            if (playerId != null) {
                playerManager.setSubtitleTrack(playerId, subtitleTrack)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            result.error("SUBTITLE_ERROR", e.message, null)
        }
    }

    private fun handleSetQualityTrack(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val qualityTrack = call.argument<Map<String, Any>>("qualityTrack")

            if (playerId != null && qualityTrack != null) {
                playerManager.setQualityTrack(playerId, qualityTrack)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and quality track are required", null)
            }
        } catch (e: Exception) {
            result.error("QUALITY_ERROR", e.message, null)
        }
    }

    private fun handleSetAudioTrack(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val audioTrack = call.argument<Map<String, Any>>("audioTrack")

            if (playerId != null && audioTrack != null) {
                playerManager.setAudioTrack(playerId, audioTrack)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and audio track are required", null)
            }
        } catch (e: Exception) {
            result.error("AUDIO_ERROR", e.message, null)
        }
    }

    private fun handleEnableAutoQuality(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")

            if (playerId != null) {
                playerManager.enableAutoQuality(playerId)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            result.error("AUTO_QUALITY_ERROR", e.message, null)
        }
    }

    private fun handleSkipToIndex(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val index = call.argument<Int>("index")

            if (playerId != null && index != null) {
                playerManager.skipToIndex(playerId, index)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and index are required", null)
            }
        } catch (e: Exception) {
            result.error("SKIP_ERROR", e.message, null)
        }
    }

    private fun handleUpdateConfig(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val config = call.argument<Map<String, Any>>("config")

            if (playerId != null && config != null) {
                playerManager.updateConfig(playerId, config)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and config are required", null)
            }
        } catch (e: Exception) {
            result.error("CONFIG_ERROR", e.message, null)
        }
    }

    private fun handleDispose(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            if (playerId != null) {
                playerManager.disposePlayer(playerId)
                // Also dispose Phase 3 handlers
                notificationHandlers.remove(playerId)?.dispose()
                pipHandlers.remove(playerId)?.dispose()
                castHandlers.remove(playerId)?.dispose()
                // H-06: stop fanning NetworkMonitor events to this playerId.
                activePlayerIds.remove(playerId)
                // B-12: stop this playerId requesting FLAG_SECURE; clears the
                // window flag if no other player in this Activity still wants it.
                secureSurfaceHandler.clear(playerId)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            result.error("DISPOSE_ERROR", e.message, null)
        }
    }

    // B-12 (wave 2): screen-capture protection handler

    private fun handleSetSecureSurface(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val enabled = call.argument<Boolean>("enabled")

            if (playerId != null && enabled != null) {
                secureSurfaceHandler.setSecure(playerId, enabled)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and enabled flag are required", null)
            }
        } catch (e: Exception) {
            result.error("SECURE_SURFACE_ERROR", e.message, null)
        }
    }

    // Surface reclaim handler

    private fun handleReclaimVideoSurface(call: MethodCall, result: Result) {
        // Called by the Dart layer when a new AndroidView host mounts for a
        // player that already has an ExoPlayer instance.  We ask the instance to
        // re-attach the ExoPlayer to its current (newest) PlayerView so the new
        // host renders video immediately.
        try {
            val playerId = call.argument<String>("playerId")
            if (playerId != null) {
                playerManager.reclaimVideoSurface(playerId)
                android.util.Log.d("ZMediaPlayerPlugin", "reclaimVideoSurface: re-attached player for $playerId")
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            android.util.Log.e("ZMediaPlayerPlugin", "reclaimVideoSurface error: ${e.message}", e)
            result.error("RECLAIM_ERROR", e.message, null)
        }
    }

    // Phase 1: Buffering method handlers

    private fun handleGetBufferHealth(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            if (playerId != null) {
                val bufferHealth = playerManager.getBufferHealth(playerId)
                result.success(bufferHealth)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            result.error("BUFFER_HEALTH_ERROR", e.message, null)
        }
    }

    // Phase 3: Notification method handlers

    private fun handleInitializeNotification(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val config = call.argument<Map<String, Any>>("config")

            if (playerId != null && config != null) {
                val handler = NotificationHandler(context, playerId, channel)
                handler.initialize(config)
                notificationHandlers[playerId] = handler
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and config are required", null)
            }
        } catch (e: Exception) {
            result.error("NOTIFICATION_INIT_ERROR", e.message, null)
        }
    }

    private fun handleShowNotification(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val mediaItem = call.argument<Map<String, Any>>("mediaItem")
            val state = call.argument<Map<String, Any>>("state")

            if (playerId != null && mediaItem != null && state != null) {
                val handler = notificationHandlers[playerId]
                if (handler != null) {
                    handler.showNotification(mediaItem, state)
                    result.success(null)
                } else {
                    result.error("NOT_INITIALIZED", "Notification handler not initialized", null)
                }
            } else {
                result.error("INVALID_ARGUMENT", "Player ID, media item and state are required", null)
            }
        } catch (e: Exception) {
            result.error("NOTIFICATION_SHOW_ERROR", e.message, null)
        }
    }

    private fun handleUpdateNotificationState(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val state = call.argument<Map<String, Any>>("state")

            if (playerId != null && state != null) {
                val handler = notificationHandlers[playerId]
                handler?.updateState(state)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and state are required", null)
            }
        } catch (e: Exception) {
            result.error("NOTIFICATION_UPDATE_ERROR", e.message, null)
        }
    }

    private fun handleUpdateNotificationPosition(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val position = call.argument<Number>("position")

            if (playerId != null && position != null) {
                val handler = notificationHandlers[playerId]
                handler?.updatePosition(position.toLong())
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and position are required", null)
            }
        } catch (e: Exception) {
            result.error("NOTIFICATION_POSITION_ERROR", e.message, null)
        }
    }

    private fun handleDismissNotification(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")

            if (playerId != null) {
                val handler = notificationHandlers[playerId]
                handler?.dismiss()
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            result.error("NOTIFICATION_DISMISS_ERROR", e.message, null)
        }
    }

    // Phase 3: PiP method handlers

    private fun handleCheckPipAvailability(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            // Forward the PiP config map so checkAvailability can prime autoEnterEnabled
            // on Android 12+ via PipHandler.applyConfig() before the user taps Enter.
            val pipConfig = call.argument<Map<String, Any>>("config")

            if (playerId != null) {
                // Use the actual activity from ActivityAware
                val handler = PipHandler(activity, playerId, channel)
                pipHandlers[playerId] = handler
                handler.applyConfig(pipConfig)
                val isAvailable = handler.checkAvailability()
                android.util.Log.d("ZMediaPlayerPlugin", "PiP availability check: $isAvailable (activity: ${activity != null})")
                result.success(isAvailable)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            android.util.Log.e("ZMediaPlayerPlugin", "PiP check error: ${e.message}", e)
            result.error("PIP_CHECK_ERROR", e.message, null)
        }
    }

    private fun handleEnterPictureInPicture(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val pipConfig = call.argument<Map<String, Any>>("config")

            if (playerId != null) {
                val handler = pipHandlers[playerId]
                if (handler != null) {
                    val success = handler.enterPip(pipConfig)
                    result.success(success)
                } else {
                    // Create handler if not exists - use actual activity from ActivityAware
                    val newHandler = PipHandler(activity, playerId, channel)
                    pipHandlers[playerId] = newHandler
                    val success = newHandler.enterPip(pipConfig)
                    android.util.Log.d("ZMediaPlayerPlugin", "PiP enter result: $success (activity: ${activity != null})")
                    result.success(success)
                }
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            android.util.Log.e("ZMediaPlayerPlugin", "PiP enter error: ${e.message}", e)
            result.error("PIP_ENTER_ERROR", e.message, null)
        }
    }

    private fun handleExitPictureInPicture(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")

            if (playerId != null) {
                val handler = pipHandlers[playerId]
                handler?.exitPip()
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            result.error("PIP_EXIT_ERROR", e.message, null)
        }
    }

    private fun handlePipModeChanged(call: MethodCall, result: Result) {
        try {
            val isInPictureInPictureMode = call.argument<Boolean>("isInPictureInPictureMode") ?: false

            android.util.Log.d("ZMediaPlayerPlugin", "PiP mode changed from MainActivity: $isInPictureInPictureMode")

            // Notify all active PiP handlers
            pipHandlers.values.forEach { handler ->
                handler.onPictureInPictureModeChanged(isInPictureInPictureMode)
            }

            result.success(null)
        } catch (e: Exception) {
            android.util.Log.e("ZMediaPlayerPlugin", "Error handling PiP mode change: ${e.message}", e)
            result.error("PIP_MODE_CHANGE_ERROR", e.message, null)
        }
    }

    // Phase 3: Cast method handlers

    private fun handleInitializeCast(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val config = call.argument<Map<String, Any>>("config")

            if (playerId != null && config != null) {
                val handler = CastHandler(context, playerId, channel)
                handler.initialize(config)
                castHandlers[playerId] = handler
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and config are required", null)
            }
        } catch (e: Exception) {
            result.error("CAST_INIT_ERROR", e.message, null)
        }
    }

    private fun handleStartCastDiscovery(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")

            if (playerId != null) {
                val handler = castHandlers[playerId]
                handler?.startDiscovery()
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            result.error("CAST_DISCOVERY_ERROR", e.message, null)
        }
    }

    private fun handleStopCastDiscovery(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")

            if (playerId != null) {
                val handler = castHandlers[playerId]
                handler?.stopDiscovery()
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            result.error("CAST_STOP_DISCOVERY_ERROR", e.message, null)
        }
    }

    private fun handleConnectToCastDevice(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val deviceId = call.argument<String>("deviceId")

            if (playerId != null && deviceId != null) {
                val handler = castHandlers[playerId]
                if (handler != null) {
                    val success = handler.connect(deviceId)
                    result.success(success)
                } else {
                    result.error("NOT_INITIALIZED", "Cast handler not initialized", null)
                }
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and device ID are required", null)
            }
        } catch (e: Exception) {
            result.error("CAST_CONNECT_ERROR", e.message, null)
        }
    }

    private fun handleDisconnectFromCastDevice(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")

            if (playerId != null) {
                val handler = castHandlers[playerId]
                handler?.disconnect()
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            result.error("CAST_DISCONNECT_ERROR", e.message, null)
        }
    }

    private fun handleLoadMediaOnCastDevice(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val mediaItem = call.argument<Map<String, Any>>("mediaItem")

            if (playerId != null && mediaItem != null) {
                val handler = castHandlers[playerId]
                handler?.loadMedia(mediaItem)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and media item are required", null)
            }
        } catch (e: Exception) {
            result.error("CAST_LOAD_ERROR", e.message, null)
        }
    }

    private fun handleCastPlay(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")

            if (playerId != null) {
                val handler = castHandlers[playerId]
                handler?.play()
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            result.error("CAST_PLAY_ERROR", e.message, null)
        }
    }

    private fun handleCastPause(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")

            if (playerId != null) {
                val handler = castHandlers[playerId]
                handler?.pause()
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            result.error("CAST_PAUSE_ERROR", e.message, null)
        }
    }

    private fun handleCastSeekTo(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val position = call.argument<Number>("position")

            if (playerId != null && position != null) {
                val handler = castHandlers[playerId]
                handler?.seekTo(position.toLong())
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and position are required", null)
            }
        } catch (e: Exception) {
            result.error("CAST_SEEK_ERROR", e.message, null)
        }
    }

    private fun handleCastSetVolume(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val volume = call.argument<Double>("volume")

            if (playerId != null && volume != null) {
                val handler = castHandlers[playerId]
                handler?.setVolume(volume)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and volume are required", null)
            }
        } catch (e: Exception) {
            result.error("CAST_VOLUME_ERROR", e.message, null)
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        playerManager.shutdown()  // Properly stops Handler runnable + disposes all players

        // H-06: unregister the ConnectivityManager.NetworkCallback. This is
        // exactly the kind of native callback that leaks if never
        // unregistered — see the class-level doc on NetworkMonitor.kt.
        networkMonitor.stopMonitoring()
        activePlayerIds.clear()

        // Phase 1: Cleanup secure storage channel
        secureStorageChannel.setMethodCallHandler(null)

        // Dispose all Phase 3 handlers
        notificationHandlers.values.forEach { it.dispose() }
        notificationHandlers.clear()

        pipHandlers.values.forEach { it.dispose() }
        pipHandlers.clear()

        castHandlers.values.forEach { it.dispose() }
        castHandlers.clear()
    }

    // H-06: NetworkMonitor.Callback implementation. All three events funnel
    // through the same "onNetworkStatusChanged" wire event — the Dart side
    // (NetworkStatus/NetworkChangeEvent) derives available/lost/
    // quality-improved/quality-degraded by diffing consecutive statuses
    // rather than needing three distinct method names, so no information is
    // lost by unifying them here. See MediaPlayer._handleNetworkStatusChanged
    // in lib/src/core/media_player.dart.

    override fun onNetworkAvailable(status: Map<String, Any>) {
        broadcastNetworkStatus(status)
    }

    override fun onNetworkLost(status: Map<String, Any>) {
        broadcastNetworkStatus(status)
    }

    override fun onNetworkQualityChanged(status: Map<String, Any>) {
        broadcastNetworkStatus(status)
    }

    /**
     * Forwards a NetworkMonitor status map to every currently-initialized
     * player.
     *
     * IMPORTANT: `ConnectivityManager.registerNetworkCallback(request,
     * callback)` — the 2-arg overload `NetworkMonitor.startMonitoring()`
     * uses — does **not** deliver callbacks on the registering thread. Per
     * the AOSP `ConnectivityManager` source, that overload posts to an
     * internal, lazily-created `ConnectivityThread` HandlerThread shared by
     * the whole process, not to the caller's `Looper`. (The registering
     * thread only matters for the 3-arg overload that takes an explicit
     * `Handler`, which requires API 26+ and isn't usable here unconditionally
     * since `minSdkVersion` is 21.) So every `NetworkMonitor.Callback` method
     * — and therefore this function — runs on that background thread, never
     * the platform/main thread `MethodChannel.invokeMethod` requires. Calling
     * it directly here silently threw internally and was swallowed by the
     * try/catch below, which is why no `onNetworkStatusChanged` event ever
     * reached Dart on-device despite the callback itself firing correctly.
     * `Handler(Looper.getMainLooper()).post` works on every API level >= 21,
     * unlike the 3-arg `registerNetworkCallback` overload, so it's used here
     * instead of switching `NetworkMonitor` to that overload.
     */
    private fun broadcastNetworkStatus(status: Map<String, Any>) {
        if (activePlayerIds.isEmpty()) return
        val playerIdsSnapshot = activePlayerIds.toList()
        mainHandler.post {
            for (id in playerIdsSnapshot) {
                try {
                    val payload: Map<String, Any> = status + mapOf("playerId" to id)
                    channel.invokeMethod("onNetworkStatusChanged", payload)
                } catch (e: Exception) {
                    android.util.Log.e("ZMediaPlayerPlugin", "Failed to broadcast network status to $id: ${e.message}", e)
                }
            }
        }
    }

    // ActivityAware implementation
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        refreshPipHandlersActivity()
        secureSurfaceHandler.updateActivity(activity)
        android.util.Log.d("ZMediaPlayerPlugin", "Activity attached: ${activity != null}")
    }

    override fun onDetachedFromActivityForConfigChanges() {
        // Keep activity reference during config changes. The Activity being torn down
        // here is about to be destroyed and recreated; onReattachedToActivityForConfigChanges
        // will supply the new instance for both `activity` and every cached PipHandler.
        android.util.Log.d("ZMediaPlayerPlugin", "Activity detached for config changes")
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        // Refresh cached PipHandler instances so a handler created before rotation
        // doesn't keep operating against the now-destroyed pre-rotation Activity
        // (see PipHandler.updateActivity).
        refreshPipHandlersActivity()
        // B-12: re-apply FLAG_SECURE to the new window after rotation if any
        // player still wants it — the pre-rotation window (and its flags) is
        // gone once the Activity is recreated.
        secureSurfaceHandler.updateActivity(activity)
        android.util.Log.d("ZMediaPlayerPlugin", "Activity reattached after config changes")
    }

    override fun onDetachedFromActivity() {
        activity = null
        refreshPipHandlersActivity()
        secureSurfaceHandler.updateActivity(activity)
        android.util.Log.d("ZMediaPlayerPlugin", "Activity detached")
    }

    /**
     * Keep every cached PipHandler's Activity reference in sync with this plugin's
     * own [activity] field. PipHandler instances live in [pipHandlers] keyed by
     * playerId and can outlive a single Activity instance across configuration
     * changes (rotation), so without this they would retain a stale/destroyed
     * Activity - see M-04 in docs/implementation/production-gate-assessment.md.
     */
    private fun refreshPipHandlersActivity() {
        pipHandlers.values.forEach { it.updateActivity(activity) }
    }
}
