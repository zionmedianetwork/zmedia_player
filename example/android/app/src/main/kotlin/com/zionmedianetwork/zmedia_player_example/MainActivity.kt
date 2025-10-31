package com.zionmedianetwork.zmedia_player_example

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.zionmedianetwork.zmedia_player/main"
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)

        android.util.Log.d("MainActivity", "PiP mode changed: $isInPictureInPictureMode")

        // Notify the plugin about PiP mode changes
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            val channel = MethodChannel(messenger, "com.zionmedianetwork.zmedia_player/method")
            channel.invokeMethod("onPipModeChanged", mapOf(
                "isInPictureInPictureMode" to isInPictureInPictureMode
            ))
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()

        // Optional: Auto-enter PiP when user presses home button
        // This can be controlled by the PiP configuration
        android.util.Log.d("MainActivity", "User leaving activity (home button pressed)")
    }
}
