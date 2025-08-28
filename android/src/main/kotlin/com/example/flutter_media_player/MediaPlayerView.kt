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
        player = exoPlayer
        useController = false // We handle controls in Flutter
        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
    }

    override fun getView(): View = playerView

    override fun dispose() {
        playerView.player = null
    }

    fun setResizeMode(resizeMode: Int) {
        playerView.resizeMode = resizeMode
    }
}
