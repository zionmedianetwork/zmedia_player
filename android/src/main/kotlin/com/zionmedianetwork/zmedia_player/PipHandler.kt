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
    private val activity: Activity?,
    private val playerId: String,
    private val methodChannel: MethodChannel
) {
    companion object {
        private const val TAG = "PipHandler"
    }

    private var config: Map<String, Any>? = null
    private var isInPipMode = false

    /**
     * Check if PiP is available on this device
     */
    fun checkAvailability(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            android.util.Log.d(TAG, "PiP not available: Android version < O")
            return false
        }
        
        if (activity == null) {
            android.util.Log.d(TAG, "PiP not available: No activity context")
            return false
        }
        
        val hasPipFeature = activity.packageManager.hasSystemFeature(
            PackageManager.FEATURE_PICTURE_IN_PICTURE
        )
        
        android.util.Log.d(TAG, "PiP availability: $hasPipFeature")
        return hasPipFeature
    }

    /**
     * Enter Picture-in-Picture mode
     */
    fun enterPip(config: Map<String, Any>?): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            android.util.Log.w(TAG, "PiP not supported on Android version < O")
            return false
        }
        
        if (activity == null) {
            android.util.Log.w(TAG, "Cannot enter PiP: No activity context")
            return false
        }
        
        if (!checkAvailability()) {
            android.util.Log.w(TAG, "Cannot enter PiP: Feature not available")
            return false
        }
        
        this.config = config
        
        return try {
            val params = buildPipParams(config)
            val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.enterPictureInPictureMode(params)
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
                android.util.Log.w(TAG, "Failed to enter PiP mode")
            }
            
            result
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error entering PiP mode: ${e.message}", e)
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

