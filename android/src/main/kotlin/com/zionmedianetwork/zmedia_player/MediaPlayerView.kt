package com.zionmedianetwork.zmedia_player

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import com.google.android.exoplayer2.ExoPlayer
import com.google.android.exoplayer2.ui.AspectRatioFrameLayout
import com.google.android.exoplayer2.ui.PlayerView
import io.flutter.plugin.platform.PlatformView

class MediaPlayerView(
    private val context: Context,
    private val exoPlayer: ExoPlayer?
) : PlatformView {

    // Inflate the PlayerView from XML so it is backed by a TextureView
    // (app:surface_type="texture_view"). A programmatically-constructed
    // PlayerView defaults to a SurfaceView, whose dedicated SurfaceFlinger
    // layer + BufferQueue is not reliably released on dispose() and leaks
    // across the frequent create/dispose churn (inline <-> MiniPlayer <->
    // fullscreen, tab switches, live recovery reloads) until SurfaceFlinger /
    // system_server crashes ("System UI has stopped"). TextureView renders in
    // the normal view tree and is freed with the view.
    private val playerView: PlayerView =
        (LayoutInflater.from(context)
            .inflate(R.layout.zmedia_player_view, null) as PlayerView).apply {
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
        android.util.Log.d("MediaPlayerView", "Disposing MediaPlayerView")
        // Ensure disposal happens on the main thread
        if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) {
            disposeInternal()
        } else {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                disposeInternal()
            }
        }
    }

    private fun disposeInternal() {
        try {
            // Detach the shared ExoPlayer so it stops driving this view's
            // TextureView surface, then stop holding the screen awake.
            playerView.player = null
            playerView.keepScreenOn = false
            playerView.removeCallbacks(null)

            // Detach from the parent so the backing TextureView is destroyed and
            // its SurfaceTexture released promptly (rather than lingering until
            // GC). TextureView frees its buffers on window-detach, so unlike the
            // old SurfaceView path no BufferQueue drain delay is required.
            (playerView.parent as? android.view.ViewGroup)?.removeView(playerView)

            android.util.Log.d("MediaPlayerView", "MediaPlayerView disposed successfully")
        } catch (e: Exception) {
            android.util.Log.e("MediaPlayerView", "Error disposing MediaPlayerView: ${e.message}")
        }
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
