package com.example.flutter_media_player

import android.content.Context
import android.view.View
import com.google.android.exoplayer2.ExoPlayer
import com.google.android.exoplayer2.ui.AspectRatioFrameLayout
import com.google.android.exoplayer2.ui.PlayerView
import io.flutter.plugin.platform.PlatformView

class MediaPlayerView(
    private val context: Context,
    private val exoPlayer: ExoPlayer?
) : PlatformView {
    
    private val playerView: PlayerView = PlayerView(context).apply {
        // Only attach player if it's not null
        if (exoPlayer != null) {
            player = exoPlayer
            android.util.Log.d("MediaPlayerView", "PlayerView created with player attached")
        } else {
            android.util.Log.e("MediaPlayerView", "WARNING: PlayerView created with null ExoPlayer!")
        }
        
        useController = false // We handle controls in Flutter
        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
        
        // Ensure view is visible and properly configured
        setBackgroundColor(android.graphics.Color.BLACK)
        setKeepScreenOn(true)
        
        // Force the video surface to be visible
        useArtwork = false
        defaultArtwork = null
        controllerShowTimeoutMs = 0
        controllerHideOnTouch = false
        
        // Post a delayed task to ensure the surface is created
        post {
            android.util.Log.d("MediaPlayerView", "PlayerView posted - requesting layout, player: ${player != null}")
            requestLayout()
            invalidate()
        }
    }
    
    // Allow setting the player later if it was null during construction
    fun setPlayer(player: ExoPlayer?) {
        android.util.Log.d("MediaPlayerView", "setPlayer called, player: ${player != null}")
        playerView.player = player
    }

    override fun getView(): View {
        android.util.Log.d("MediaPlayerView", "getView() called, player attached: ${playerView.player != null}")
        return playerView
    }

    override fun dispose() {
        playerView.player = null
    }

    fun setResizeMode(resizeMode: Int) {
        playerView.resizeMode = resizeMode
    }

    fun setResizeModeFromString(boxFit: String) {
        val resizeMode = when (boxFit.lowercase()) {
            "cover" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            "fill" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
            "fitwidth" -> AspectRatioFrameLayout.RESIZE_MODE_FIXED_WIDTH
            "fitheight" -> AspectRatioFrameLayout.RESIZE_MODE_FIXED_HEIGHT
            "none" -> AspectRatioFrameLayout.RESIZE_MODE_FIT
            "scaledown" -> AspectRatioFrameLayout.RESIZE_MODE_FIT
            else -> AspectRatioFrameLayout.RESIZE_MODE_FIT // "contain" and default
        }
        playerView.resizeMode = resizeMode
    }
}
