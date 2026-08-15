package com.zionmedianetwork.zmedia_player

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.util.Rational
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodChannel

/**
 * Handles Picture-in-Picture mode for Android O and above
 */
class PipHandler(
    activity: Activity?,
    private val playerId: String,
    private val methodChannel: MethodChannel
) {
    companion object {
        private const val TAG = "PipHandler"
    }

    // Mutable so the plugin can refresh it on activity lifecycle callbacks
    // (rotation/config change). PipHandler instances are cached in a long-lived
    // map keyed by playerId, so the Activity captured at construction time can
    // otherwise become stale/destroyed after a configuration change while the
    // handler itself lives on. See updateActivity().
    private var activity: Activity? = activity

    private var config: Map<String, Any>? = null
    private var isInPipMode = false

    /**
     * Refresh the Activity reference held by this handler.
     *
     * Must be called by the owner (ZMediaPlayerPlugin) whenever its own
     * activity reference changes - i.e. from [ActivityAware.onAttachedToActivity]
     * and [ActivityAware.onReattachedToActivityForConfigChanges], and with `null`
     * from [ActivityAware.onDetachedFromActivity] - so that a cached PipHandler
     * never operates against a destroyed pre-rotation Activity.
     */
    fun updateActivity(activity: Activity?) {
        this.activity = activity
    }

    /**
     * Persist the PiP config map so that subsequent [enterPip] calls (and
     * [buildPipParams]) can read autoEnterOnBackground even if the caller
     * does not pass the config again at that point.
     */
    fun applyConfig(config: Map<String, Any>?) {
        if (config != null) {
            this.config = config
        }
    }

    /**
     * Check if PiP is available on this device
     */
    fun checkAvailability(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            android.util.Log.d(TAG, "PiP not available: Android version ${Build.VERSION.SDK_INT} < O (26)")
            notifyPipStatusChanged(
                state = "unavailable",
                isSupported = false,
                isActive = false,
                errorMessage = "PiP requires Android 8.0 (API 26) or higher"
            )
            return false
        }

        val currentActivity = activity
        if (currentActivity == null) {
            android.util.Log.d(TAG, "PiP not available: No activity context")
            notifyPipStatusChanged(
                state = "unavailable",
                isSupported = false,
                isActive = false,
                errorMessage = "No activity available"
            )
            return false
        }

        val hasPipFeature = currentActivity.packageManager.hasSystemFeature(
            PackageManager.FEATURE_PICTURE_IN_PICTURE
        )

        android.util.Log.d(TAG, "PiP availability check: SDK=${Build.VERSION.SDK_INT}, hasFeature=$hasPipFeature, activity=true")

        // Notify status
        notifyPipStatusChanged(
            state = if (hasPipFeature) "available" else "unavailable",
            isSupported = hasPipFeature,
            isActive = isInPipMode
        )

        return hasPipFeature
    }

    /**
     * Enter Picture-in-Picture mode
     */
    fun enterPip(config: Map<String, Any>?): Boolean {
        android.util.Log.d(TAG, "Attempting to enter PiP mode")

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            android.util.Log.w(TAG, "PiP not supported on Android version < O")
            notifyPipStatusChanged(
                state = "failed",
                isSupported = false,
                isActive = false,
                errorMessage = "PiP requires Android 8.0 or higher"
            )
            return false
        }

        val currentActivity = activity
        if (currentActivity == null) {
            android.util.Log.w(TAG, "Cannot enter PiP: No activity context")
            notifyPipStatusChanged(
                state = "failed",
                isSupported = true,
                isActive = false,
                errorMessage = "No activity available"
            )
            return false
        }

        // Merge: caller-supplied config takes precedence; fall back to previously
        // stored config (primed by applyConfig during checkPipAvailability).
        val effectiveConfig = config ?: this.config
        this.config = effectiveConfig

        return try {
            val params = buildPipParams(effectiveConfig)
            android.util.Log.d(TAG, "Built PiP params, entering PiP mode...")

            val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                currentActivity.enterPictureInPictureMode(params)
            } else {
                false
            }

            if (result) {
                isInPipMode = true
                notifyPipStatusChanged(
                    state = "active",
                    isSupported = true,
                    isActive = true
                )
                android.util.Log.d(TAG, "Entered PiP mode successfully")
            } else {
                android.util.Log.w(TAG, "Activity.enterPictureInPictureMode() returned false")
                notifyPipStatusChanged(
                    state = "failed",
                    isSupported = true,
                    isActive = false,
                    errorMessage = "Failed to enter PiP mode"
                )
            }

            result
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error entering PiP mode: ${e.message}", e)
            notifyPipStatusChanged(
                state = "failed",
                isSupported = true,
                isActive = false,
                errorMessage = e.message
            )
            false
        }
    }

    /**
     * Exit Picture-in-Picture mode
     */
    fun exitPip() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        if (activity == null || !isInPipMode) {
            return
        }

        // The activity will automatically exit PiP when we request it
        // We can't programmatically exit PiP, but we can notify the state change
        isInPipMode = false
        notifyPipStatusChanged(
            state = "available",
            isSupported = true,
            isActive = false
        )

        android.util.Log.d(TAG, "Exited PiP mode")
    }

    /**
     * Handle PiP mode changed (called from activity)
     */
    fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
        android.util.Log.d(TAG, "PiP mode changed: $isInPictureInPictureMode")

        isInPipMode = isInPictureInPictureMode

        notifyPipStatusChanged(
            state = if (isInPictureInPictureMode) "active" else "available",
            isSupported = true,
            isActive = isInPictureInPictureMode
        )
    }

    /**
     * Build PiP parameters
     */
    @RequiresApi(Build.VERSION_CODES.O)
    private fun buildPipParams(config: Map<String, Any>?): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()

        // Set aspect ratio
        val aspectRatio = config?.get("aspectRatio") as? Double ?: (16.0 / 9.0)
        val rational = Rational(
            (aspectRatio * 100).toInt(),
            100
        )
        builder.setAspectRatio(rational)

        // For Android 12+, we can add additional features
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Set auto-enter enabled
            val autoEnter = config?.get("autoEnterOnBackground") as? Boolean ?: false
            builder.setAutoEnterEnabled(autoEnter)

            // Set seamless resize enabled for smoother transitions
            builder.setSeamlessResizeEnabled(true)
        }

        return builder.build()
    }

    /**
     * Notify Flutter of PiP status changes
     */
    private fun notifyPipStatusChanged(
        state: String,
        isSupported: Boolean,
        isActive: Boolean,
        errorMessage: String? = null
    ) {
        val statusMap = mapOf(
            "playerId" to playerId,
            "state" to state,
            "isSupported" to isSupported,
            "isActive" to isActive,
            "errorMessage" to errorMessage
        )

        activity?.runOnUiThread {
            methodChannel.invokeMethod("onPipStatusChanged", statusMap)
        }
    }

    /**
     * Get current PiP status
     */
    fun getStatus(): Map<String, Any> {
        return mapOf(
            "state" to if (isInPipMode) "active" else if (checkAvailability()) "available" else "unavailable",
            "isSupported" to checkAvailability(),
            "isActive" to isInPipMode
        )
    }

    /**
     * Dispose the PiP handler
     */
    fun dispose() {
        android.util.Log.d(TAG, "Disposing PiP handler")
        config = null
        isInPipMode = false
    }
}
