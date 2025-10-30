package com.zionmedianetwork.zmedia_player

import com.google.android.exoplayer2.ExoPlayer
import com.google.android.exoplayer2.DefaultLoadControl
import com.google.android.exoplayer2.LoadControl

/**
 * Handler for adaptive buffer management in ExoPlayer.
 *
 * Configures ExoPlayer's LoadControl to implement adaptive buffering
 * based on network conditions. Provides buffer health metrics for
 * predictive rebuffering.
 */
class BufferingHandler {

    companion object {
        // Default buffer configuration (milliseconds)
        private const val DEFAULT_MIN_BUFFER_MS = 2500
        private const val DEFAULT_MAX_BUFFER_MS = 50000
        private const val DEFAULT_TARGET_BUFFER_MS = 15000
        private const val DEFAULT_REBUFFER_MS = 5000

        // Fast startup configuration
        private const val FAST_MIN_BUFFER_MS = 1000
        private const val FAST_MAX_BUFFER_MS = 30000
        private const val FAST_TARGET_BUFFER_MS = 10000
        private const val FAST_REBUFFER_MS = 2500

        // Smooth playback configuration
        private const val SMOOTH_MIN_BUFFER_MS = 5000
        private const val SMOOTH_MAX_BUFFER_MS = 60000
        private const val SMOOTH_TARGET_BUFFER_MS = 20000
        private const val SMOOTH_REBUFFER_MS = 7500

        // Poor network configuration
        private const val POOR_MIN_BUFFER_MS = 10000
        private const val POOR_MAX_BUFFER_MS = 90000
        private const val POOR_TARGET_BUFFER_MS = 30000
        private const val POOR_REBUFFER_MS = 15000

        /**
         * Creates a LoadControl with default buffer configuration
         */
        fun createDefaultLoadControl(): LoadControl {
            return createLoadControl(
                minBufferMs = DEFAULT_MIN_BUFFER_MS,
                maxBufferMs = DEFAULT_MAX_BUFFER_MS,
                targetBufferMs = DEFAULT_TARGET_BUFFER_MS,
                rebufferMs = DEFAULT_REBUFFER_MS
            )
        }

        /**
         * Creates a LoadControl optimized for fast startup
         * Fast startup: Quick start (1s), maintain 10s buffer, max 30s
         */
        fun createFastStartupLoadControl(): LoadControl {
            return createLoadControl(
                minBufferMs = FAST_MIN_BUFFER_MS,        // 1000ms to start
                maxBufferMs = FAST_MAX_BUFFER_MS,        // 30000ms max
                targetBufferMs = FAST_TARGET_BUFFER_MS,  // 10000ms maintain
                rebufferMs = FAST_REBUFFER_MS            // 2500ms to resume
            )
        }

        /**
         * Creates a LoadControl optimized for smooth playback
         * Smooth: Slower start (5s), maintain 20s buffer, max 60s
         */
        fun createSmoothPlaybackLoadControl(): LoadControl {
            return createLoadControl(
                minBufferMs = SMOOTH_MIN_BUFFER_MS,        // 5000ms to start
                maxBufferMs = SMOOTH_MAX_BUFFER_MS,        // 60000ms max
                targetBufferMs = SMOOTH_TARGET_BUFFER_MS,  // 20000ms maintain
                rebufferMs = SMOOTH_REBUFFER_MS            // 7500ms to resume
            )
        }

        /**
         * Creates a LoadControl optimized for poor network conditions
         * Poor network: Large buffers (10s start, 30s maintain, 90s max)
         */
        fun createPoorNetworkLoadControl(): LoadControl {
            return createLoadControl(
                minBufferMs = POOR_MIN_BUFFER_MS,        // 10000ms to start
                maxBufferMs = POOR_MAX_BUFFER_MS,        // 90000ms max
                targetBufferMs = POOR_TARGET_BUFFER_MS,  // 30000ms maintain
                rebufferMs = POOR_REBUFFER_MS            // 15000ms to resume
            )
        }

        /**
         * Creates a LoadControl for live streaming with low latency
         * Live: Minimal buffers for low latency
         */
        fun createLiveStreamingLoadControl(targetLatencyMs: Int = 3000): LoadControl {
            return createLoadControl(
                minBufferMs = targetLatencyMs / 2,      // Half latency to start
                maxBufferMs = targetLatencyMs * 3,      // 3x latency max
                targetBufferMs = targetLatencyMs,       // Target latency maintain
                rebufferMs = targetLatencyMs            // Target latency to resume
            )
        }

        /**
         * Creates a LoadControl with custom buffer configuration
         *
         * Note: ExoPlayer parameter mapping:
         * - Dart targetBufferMs → ExoPlayer minBufferMs (maintain this buffer)
         * - Dart maxBufferMs → ExoPlayer maxBufferMs (don't exceed this)
         * - Dart minBufferMs → ExoPlayer bufferForPlaybackMs (start playback)
         * - Dart rebufferMs → ExoPlayer bufferForPlaybackAfterRebufferMs (resume after rebuffer)
         */
        fun createLoadControl(
            minBufferMs: Int,
            maxBufferMs: Int,
            targetBufferMs: Int,
            rebufferMs: Int
        ): LoadControl {
            return DefaultLoadControl.Builder()
                .setBufferDurationsMs(
                    targetBufferMs,   // ExoPlayer's minBufferMs - maintain this buffer during playback
                    maxBufferMs,      // ExoPlayer's maxBufferMs - maximum buffer allowed
                    minBufferMs,      // ExoPlayer's bufferForPlaybackMs - buffer needed to start
                    rebufferMs        // ExoPlayer's bufferForPlaybackAfterRebufferMs - buffer to resume
                )
                .build()
        }

        /**
         * Creates a LoadControl from Dart configuration map
         */
        fun createFromDartConfig(config: Map<String, Any>?): LoadControl {
            if (config == null) {
                return createDefaultLoadControl()
            }

            val minBufferMs = config["minBufferMs"] as? Int ?: DEFAULT_MIN_BUFFER_MS
            val maxBufferMs = config["maxBufferMs"] as? Int ?: DEFAULT_MAX_BUFFER_MS
            val targetBufferMs = config["targetBufferMs"] as? Int ?: DEFAULT_TARGET_BUFFER_MS
            val rebufferMs = config["rebufferMs"] as? Int ?: DEFAULT_REBUFFER_MS

            return createLoadControl(
                minBufferMs = minBufferMs,
                maxBufferMs = maxBufferMs,
                targetBufferMs = targetBufferMs,
                rebufferMs = rebufferMs
            )
        }
    }

    /**
     * Gets buffer health metrics from ExoPlayer
     */
    fun getBufferHealth(player: ExoPlayer?): Map<String, Any> {
        if (player == null) {
            return mapOf(
                "bufferedDurationMs" to 0,
                "currentPositionMs" to 0,
                "totalDurationMs" to 0,
                "downloadSpeed" to 0
            )
        }

        val bufferedPosition = player.bufferedPosition
        val currentPosition = player.currentPosition
        val duration = player.duration

        val bufferedDuration = (bufferedPosition - currentPosition).coerceAtLeast(0)

        // Get download speed estimate from bandwidth meter
        val downloadSpeed = try {
            // ExoPlayer's bandwidth estimate is in bits per second
            // Convert to bytes per second
            (player.currentTracks.groups.firstOrNull()?.mediaTrackGroup?.getFormat(0)?.bitrate ?: 0) / 8
        } catch (e: Exception) {
            0
        }

        return mapOf(
            "bufferedDurationMs" to bufferedDuration,
            "currentPositionMs" to currentPosition,
            "totalDurationMs" to if (duration >= 0) duration else 0,
            "downloadSpeed" to downloadSpeed
        )
    }

    /**
     * Determines if rebuffering is recommended based on current buffer status
     */
    fun shouldRebuffer(
        player: ExoPlayer?,
        minBufferMs: Int = DEFAULT_MIN_BUFFER_MS
    ): Boolean {
        if (player == null) return false

        val bufferedPosition = player.bufferedPosition
        val currentPosition = player.currentPosition
        val bufferedDuration = bufferedPosition - currentPosition

        return bufferedDuration < minBufferMs
    }
}
