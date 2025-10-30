import Foundation
import AVFoundation

/**
 * Handler for adaptive buffer management in AVPlayer.
 *
 * Configures AVPlayer's preferredForwardBufferDuration to implement adaptive
 * buffering based on network conditions. Provides buffer health metrics for
 * predictive rebuffering.
 */
class BufferingHandler {

    // MARK: - Buffer Configuration Constants (in seconds)

    // Default buffer configuration
    private static let defaultMinBuffer: TimeInterval = 2.5
    private static let defaultMaxBuffer: TimeInterval = 50.0
    private static let defaultTargetBuffer: TimeInterval = 15.0
    private static let defaultRebuffer: TimeInterval = 5.0

    // Fast startup configuration
    private static let fastMinBuffer: TimeInterval = 1.0
    private static let fastMaxBuffer: TimeInterval = 30.0
    private static let fastTargetBuffer: TimeInterval = 10.0
    private static let fastRebuffer: TimeInterval = 2.5

    // Smooth playback configuration
    private static let smoothMinBuffer: TimeInterval = 5.0
    private static let smoothMaxBuffer: TimeInterval = 60.0
    private static let smoothTargetBuffer: TimeInterval = 20.0
    private static let smoothRebuffer: TimeInterval = 7.5

    // Poor network configuration
    private static let poorMinBuffer: TimeInterval = 10.0
    private static let poorMaxBuffer: TimeInterval = 90.0
    private static let poorTargetBuffer: TimeInterval = 30.0
    private static let poorRebuffer: TimeInterval = 15.0

    // MARK: - Buffer Configuration

    struct BufferConfig {
        let minBuffer: TimeInterval
        let maxBuffer: TimeInterval
        let targetBuffer: TimeInterval
        let rebuffer: TimeInterval

        static let `default` = BufferConfig(
            minBuffer: defaultMinBuffer,
            maxBuffer: defaultMaxBuffer,
            targetBuffer: defaultTargetBuffer,
            rebuffer: defaultRebuffer
        )

        static let fastStartup = BufferConfig(
            minBuffer: fastMinBuffer,
            maxBuffer: fastMaxBuffer,
            targetBuffer: fastTargetBuffer,
            rebuffer: fastRebuffer
        )

        static let smoothPlayback = BufferConfig(
            minBuffer: smoothMinBuffer,
            maxBuffer: smoothMaxBuffer,
            targetBuffer: smoothTargetBuffer,
            rebuffer: smoothRebuffer
        )

        static let poorNetwork = BufferConfig(
            minBuffer: poorMinBuffer,
            maxBuffer: poorMaxBuffer,
            targetBuffer: poorTargetBuffer,
            rebuffer: poorRebuffer
        )

        static func liveStreaming(targetLatency: TimeInterval = 3.0) -> BufferConfig {
            return BufferConfig(
                minBuffer: targetLatency / 2.0,
                maxBuffer: targetLatency * 3.0,
                targetBuffer: targetLatency,
                rebuffer: targetLatency
            )
        }

        static func fromDartConfig(_ config: [String: Any]?) -> BufferConfig {
            guard let config = config else {
                return .default
            }

            // Dart sends milliseconds, convert to seconds
            let minBufferMs = config["minBufferMs"] as? Int ?? Int(defaultMinBuffer * 1000)
            let maxBufferMs = config["maxBufferMs"] as? Int ?? Int(defaultMaxBuffer * 1000)
            let targetBufferMs = config["targetBufferMs"] as? Int ?? Int(defaultTargetBuffer * 1000)
            let rebufferMs = config["rebufferMs"] as? Int ?? Int(defaultRebuffer * 1000)

            return BufferConfig(
                minBuffer: TimeInterval(minBufferMs) / 1000.0,
                maxBuffer: TimeInterval(maxBufferMs) / 1000.0,
                targetBuffer: TimeInterval(targetBufferMs) / 1000.0,
                rebuffer: TimeInterval(rebufferMs) / 1000.0
            )
        }
    }

    // MARK: - Apply Buffer Configuration

    /**
     * Applies buffer configuration to AVPlayer.
     *
     * Note: AVPlayer uses preferredForwardBufferDuration for iOS 10+.
     * The value is a hint to the system; actual buffer size may vary.
     */
    static func applyBufferConfig(_ config: BufferConfig, to player: AVPlayer) {
        guard let playerItem = player.currentItem else {
            return
        }

        // Set preferred forward buffer duration
        // iOS will attempt to buffer this much content ahead of current time
        playerItem.preferredForwardBufferDuration = config.targetBuffer

        // Note: iOS doesn't expose min/max buffer configuration like ExoPlayer.
        // The system manages buffer sizes automatically based on network conditions.
        // We primarily control the target buffer duration.
    }

    /**
     * Applies buffer configuration from Dart config map.
     */
    static func applyDartConfig(_ dartConfig: [String: Any]?, to player: AVPlayer) {
        let config = BufferConfig.fromDartConfig(dartConfig)
        applyBufferConfig(config, to: player)
    }

    // MARK: - Buffer Health Monitoring

    /**
     * Gets buffer health metrics from AVPlayer.
     */
    static func getBufferHealth(from player: AVPlayer?) -> [String: Any] {
        guard let player = player,
              let playerItem = player.currentItem else {
            return [
                "bufferedDurationMs": 0,
                "currentPositionMs": 0,
                "totalDurationMs": 0,
                "downloadSpeed": 0
            ]
        }

        // Get current time
        let currentTime = CMTimeGetSeconds(playerItem.currentTime())
        let currentPositionMs = Int(currentTime * 1000)

        // Get total duration
        let duration = CMTimeGetSeconds(playerItem.duration)
        let totalDurationMs = duration.isFinite ? Int(duration * 1000) : 0

        // Calculate buffered duration
        let bufferedDuration = getBufferedDuration(from: playerItem, currentTime: currentTime)
        let bufferedDurationMs = Int(bufferedDuration * 1000)

        // Estimate download speed (simplified)
        let downloadSpeed = estimateDownloadSpeed(from: playerItem)

        return [
            "bufferedDurationMs": bufferedDurationMs,
            "currentPositionMs": currentPositionMs,
            "totalDurationMs": totalDurationMs,
            "downloadSpeed": downloadSpeed
        ]
    }

    /**
     * Calculates buffered duration from AVPlayerItem's loaded time ranges.
     */
    private static func getBufferedDuration(from playerItem: AVPlayerItem, currentTime: TimeInterval) -> TimeInterval {
        let loadedTimeRanges = playerItem.loadedTimeRanges

        guard !loadedTimeRanges.isEmpty else {
            return 0
        }

        // Find the time range that contains or follows the current time
        var bufferedDuration: TimeInterval = 0

        for value in loadedTimeRanges {
            let timeRange = value.timeRangeValue
            let start = CMTimeGetSeconds(timeRange.start)
            let duration = CMTimeGetSeconds(timeRange.duration)
            let end = start + duration

            // If current time is within this range
            if currentTime >= start && currentTime <= end {
                bufferedDuration = end - currentTime
                break
            }
            // If this range is ahead of current time
            else if start > currentTime {
                bufferedDuration = end - currentTime
                break
            }
        }

        return max(0, bufferedDuration)
    }

    /**
     * Estimates download speed from AVPlayerItem's access log.
     * Returns bytes per second.
     */
    private static func estimateDownloadSpeed(from playerItem: AVPlayerItem) -> Int {
        guard let accessLog = playerItem.accessLog(),
              let lastEvent = accessLog.events.last else {
            return 0
        }

        // observedBitrate is in bits per second
        // Convert to bytes per second
        let bitsPerSecond = lastEvent.observedBitrate
        if bitsPerSecond > 0 {
            return Int(bitsPerSecond / 8)
        }

        // Fallback: use indicated bitrate
        let indicatedBitrate = lastEvent.indicatedBitrate
        if indicatedBitrate > 0 {
            return Int(indicatedBitrate / 8)
        }

        return 0
    }

    /**
     * Determines if rebuffering is recommended based on current buffer status.
     */
    static func shouldRebuffer(player: AVPlayer?, minBuffer: TimeInterval = defaultMinBuffer) -> Bool {
        guard let player = player,
              let playerItem = player.currentItem else {
            return false
        }

        let currentTime = CMTimeGetSeconds(playerItem.currentTime())
        let bufferedDuration = getBufferedDuration(from: playerItem, currentTime: currentTime)

        return bufferedDuration < minBuffer
    }
}
