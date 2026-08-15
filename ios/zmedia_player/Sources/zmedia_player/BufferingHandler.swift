import Foundation
import AVFoundation

/**
 * Handler for buffer health reporting for AVPlayer.
 *
 * ## Why there is no "apply buffer config" side here (M-17)
 *
 * The public Dart `BufferConfig`/`BufferingConfig` model has four knobs —
 * `minBufferMs`, `maxBufferMs`, `targetBufferMs`, `rebufferMs` — modelled
 * after ExoPlayer's `DefaultLoadControl.setBufferDurationsMs(min, max,
 * bufferForPlayback, bufferForPlaybackAfterRebuffer)`, which Android's
 * `BufferingHandler.createFromDartConfig` honours in full.
 *
 * AVFoundation has no equivalent surface. The only buffering knob `AVPlayer`
 * exposes is `AVPlayerItem.preferredForwardBufferDuration` — a single hint
 * for how far ahead of the playhead to buffer, applied once per item. There
 * is no API to set a minimum buffer required before playback starts, a
 * maximum buffer ceiling, or a distinct "buffer to resume after a stall"
 * threshold; `AVPlayer` manages all of that internally and does not expose
 * it for tuning. So on iOS only `targetBufferMs` maps onto anything real —
 * `minBufferMs`, `maxBufferMs` and `rebufferMs` are accepted from Dart
 * (silently ignored) same as before, but this is a genuine platform
 * limitation, not a missing wiring.
 *
 * A previous version of this file had a `BufferConfig` struct, buffer
 * presets (`fastStartup`/`smoothPlayback`/`poorNetwork`/`liveStreaming`),
 * `applyBufferConfig`/`applyDartConfig`, and `shouldRebuffer` — all dead
 * code (zero call sites) that, even if wired up, would have done nothing
 * more than the single `preferredForwardBufferDuration` assignment that
 * `MediaPlayerInstance.loadMediaItem()` already performs inline: the struct
 * carried `minBuffer`/`maxBuffer`/`rebuffer` fields that `applyBufferConfig`
 * itself never read (see its old comment: "iOS doesn't expose min/max
 * buffer configuration like ExoPlayer"). Reintroducing that scaffolding
 * would not make the full `BufferConfig` real on iOS — it would just add an
 * indirection around the same one-line `targetBuffer`-only hint. It was
 * removed rather than wired up; the inline application in
 * `MediaPlayerManager.swift` remains the single implementation.
 *
 * This type now only reports buffer health metrics (used for `getBufferHealth`
 * / predictive-rebuffering signal to Dart).
 */
class BufferingHandler {

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
}
