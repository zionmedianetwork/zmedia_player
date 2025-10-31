package com.zionmedianetwork.zmedia_player

import android.content.Context
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider
import com.google.android.gms.cast.framework.media.CastMediaOptions
import com.google.android.gms.cast.framework.media.NotificationOptions

/**
 * Provides configuration for Google Cast Framework
 */
class CastOptionsProvider : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions {
        // Default Cast Receiver App ID (use your own for production)
        val receiverApplicationId = DEFAULT_APP_ID

        // Build notification options
        val notificationOptions = NotificationOptions.Builder()
            .setActions(
                listOf(
                    MediaIntentReceiver.ACTION_TOGGLE_PLAYBACK,
                    MediaIntentReceiver.ACTION_STOP_CASTING
                ),
                intArrayOf(0, 1)
            )
            .setTargetActivityClassName(expandedControllerActivityClassName)
            .build()

        // Build cast media options
        val mediaOptions = CastMediaOptions.Builder()
            .setNotificationOptions(notificationOptions)
            .setExpandedControllerActivityClassName(expandedControllerActivityClassName)
            .build()

        // Build and return cast options
        return CastOptions.Builder()
            .setReceiverApplicationId(receiverApplicationId)
            .setCastMediaOptions(mediaOptions)
            .build()
    }

    override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? {
        return null
    }

    companion object {
        // Default Google Cast Receiver App ID
        // For production, register your own at: https://cast.google.com/publish/
        private const val DEFAULT_APP_ID = "CC1AD845"

        // Activity to be launched when notification is tapped
        private const val expandedControllerActivityClassName =
            "com.google.android.gms.cast.framework.media.widget.ExpandedControllerActivity"
    }
}

/**
 * Broadcast receiver for media intent actions
 */
class MediaIntentReceiver {
    companion object {
        const val ACTION_TOGGLE_PLAYBACK = "action_toggle_playback"
        const val ACTION_STOP_CASTING = "action_stop_casting"
    }
}
