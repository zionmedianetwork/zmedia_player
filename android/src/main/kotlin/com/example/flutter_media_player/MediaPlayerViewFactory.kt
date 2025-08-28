package com.example.flutter_media_player

import android.content.Context
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class MediaPlayerViewFactory(
    private val playerManager: MediaPlayerManager
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<String, Any>
        val playerId = creationParams?.get("playerId") as? String
            ?: throw IllegalArgumentException("Player ID is required")
        
        val playerView = playerManager.getPlayerView(playerId)
            ?: throw IllegalStateException("Player not found for ID: $playerId")
        
        return playerView
    }
}
