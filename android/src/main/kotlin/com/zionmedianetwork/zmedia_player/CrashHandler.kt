package com.zionmedianetwork.zmedia_player

import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * Native crash handler for Android
 * 
 * Catches and reports native-layer crashes to the Flutter layer,
 * which can then forward them to the configured crash reporter.
 */
class CrashHandler(
    private val methodChannel: MethodChannel
) {
    companion object {
        private const val TAG = "ZMediaCrashHandler"
    }
    
    /**
     * Wrap a potentially failing operation with crash reporting
     */
    fun <T> wrapOperation(
        operation: String,
        playerId: String,
        context: Map<String, Any> = emptyMap(),
        block: () -> T
    ): T {
        return try {
            block()
        } catch (e: Exception) {
            reportNativeError(
                operation = operation,
                playerId = playerId,
                error = e,
                context = context
            )
            throw e
        }
    }
    
    /**
     * Wrap a suspend operation with crash reporting
     */
    suspend fun <T> wrapSuspendOperation(
        operation: String,
        playerId: String,
        context: Map<String, Any> = emptyMap(),
        block: suspend () -> T
    ): T {
        return try {
            block()
        } catch (e: Exception) {
            reportNativeError(
                operation = operation,
                playerId = playerId,
                error = e,
                context = context
            )
            throw e
        }
    }
    
    /**
     * Report a native error to Flutter layer
     */
    private fun reportNativeError(
        operation: String,
        playerId: String,
        error: Exception,
        context: Map<String, Any>
    ) {
        Log.e(TAG, "Native error in $operation for player $playerId: ${error.message}", error)
        
        try {
            val errorData = buildMap<String, Any?> {
                put("operation", operation)
                put("playerId", playerId)
                put("error", error.message ?: "Unknown error")
                put("errorType", error.javaClass.simpleName)
                put("stackTrace", error.stackTraceToString())
                put("timestamp", System.currentTimeMillis())
                putAll(context)
            }
            
            methodChannel.invokeMethod("onNativeError", errorData)
        } catch (e: Exception) {
            // Fallback logging if method channel fails
            Log.e(TAG, "Failed to report native error to Flutter: ${e.message}")
        }
    }
    
    /**
     * Report a non-fatal issue
     */
    fun reportWarning(
        operation: String,
        playerId: String,
        message: String,
        context: Map<String, Any> = emptyMap()
    ) {
        Log.w(TAG, "Warning in $operation for player $playerId: $message")
        
        try {
            val warningData = buildMap<String, Any?> {
                put("operation", operation)
                put("playerId", playerId)
                put("message", message)
                put("level", "warning")
                put("timestamp", System.currentTimeMillis())
                putAll(context)
            }
            
            methodChannel.invokeMethod("onNativeWarning", warningData)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to report warning to Flutter: ${e.message}")
        }
    }
    
    /**
     * Log a debug message
     */
    fun logDebug(operation: String, playerId: String, message: String) {
        Log.d(TAG, "[$playerId] $operation: $message")
    }
}

