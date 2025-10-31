package com.zionmedianetwork.zmedia_player

import android.content.Context
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Factory for creating MediaPlayerView instances
 * Uses StandardMessageCodec to properly decode creation parameters
 * Hybrid Composition is enabled on the Dart side via AndroidView
 */
class MediaPlayerViewFactory(
    private val playerManager: MediaPlayerManager
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

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
