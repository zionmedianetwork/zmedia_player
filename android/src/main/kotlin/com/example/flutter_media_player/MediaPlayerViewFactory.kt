package com.example.flutter_media_player

import android.content.Context
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Factory for creating MediaPlayerView instances
 * Uses Hybrid Composition (null codec) for better performance and stability with video playback
 * 
 * IMPORTANT: Passing null as the codec parameter enables Hybrid Composition mode,
 * which is required for proper video playback without SurfaceProducer crashes
 */
class MediaPlayerViewFactory(
    private val playerManager: MediaPlayerManager
) : PlatformViewFactory(null) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        android.util.Log.d("MediaPlayerViewFactory", "Creating platform view with viewId: $viewId, args: $args")
        
        val creationParams = args as? Map<String, Any>
        val playerId = creationParams?.get("playerId") as? String
            ?: throw IllegalArgumentException("Player ID is required")
        
        android.util.Log.d("MediaPlayerViewFactory", "Getting player view for playerId: $playerId")
        
        val playerView = playerManager.getPlayerView(playerId)
            ?: throw IllegalStateException("Player not found for ID: $playerId")
        
        android.util.Log.d("MediaPlayerViewFactory", "Platform view created successfully")
        return playerView
    }
}
