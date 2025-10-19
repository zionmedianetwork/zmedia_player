package com.example.flutter_media_player

import android.content.Context
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.platform.PlatformViewRegistry

/**
 * FlutterMediaPlayerPlugin
 */
class FlutterMediaPlayerPlugin: FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var playerManager: MediaPlayerManager

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_media_player")
        channel.setMethodCallHandler(this)
        
        // Initialize player manager
        playerManager = MediaPlayerManager(context, channel)
        
        // Register platform view
        flutterPluginBinding
            .platformViewRegistry
            .registerViewFactory(
                "flutter_media_player_view",
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
            else -> result.notImplemented()
        }
    }

    private fun handleInitialize(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val config = call.argument<Map<String, Any>>("config")
            
            if (playerId != null) {
                playerManager.initializePlayer(playerId, config)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            result.error("INITIALIZATION_ERROR", e.message, null)
        }
    }

    private fun handleLoad(call: MethodCall, result: Result) {
        try {
            val playerId = call.argument<String>("playerId")
            val mediaItem = call.argument<Map<String, Any>>("mediaItem")
            
            if (playerId != null && mediaItem != null) {
                playerManager.loadMediaItem(playerId, mediaItem)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID and media item are required", null)
            }
        } catch (e: Exception) {
            result.error("LOAD_ERROR", e.message, null)
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
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENT", "Player ID is required", null)
            }
        } catch (e: Exception) {
            result.error("DISPOSE_ERROR", e.message, null)
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        playerManager.dispose()
    }
}
