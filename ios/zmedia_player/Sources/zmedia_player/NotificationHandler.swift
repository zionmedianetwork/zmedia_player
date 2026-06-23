import Foundation
import MediaPlayer
import AVFoundation
import Flutter

/// Handles media notifications using MPNowPlayingInfoCenter and MPRemoteCommandCenter
class NotificationHandler: NSObject {
    private let playerId: String
    private let channel: FlutterMethodChannel
    private var isShowing: Bool = false

    // Configuration
    private var config: [String: Any]?
    private var showPlayPause: Bool = true
    private var showNext: Bool = true
    private var showPrevious: Bool = true
    private var showStop: Bool = false
    private var seekInterval: Int = 10

    // Current media info
    private var currentTitle: String?
    private var currentArtist: String?
    private var currentAlbum: String?
    private var currentArtworkUrl: String?
    private var currentMediaUrl: String?
    private var currentArtwork: MPMediaItemArtwork?
    private var isPlaying: Bool = false
    private var position: Double = 0.0
    private var duration: Double = 0.0
    private var playbackRate: Float = 1.0

    private let remoteCommandCenter = MPRemoteCommandCenter.shared()
    private let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()

    init(playerId: String, channel: FlutterMethodChannel) {
        self.playerId = playerId
        self.channel = channel
        super.init()
    }

    // MARK: - Initialization

    func initialize(config: [String: Any]) {
        print("NotificationHandler: Initializing for player: \(playerId)")

        self.config = config

        // Parse configuration
        self.showPlayPause = config["showPlayPause"] as? Bool ?? true
        self.showNext = config["showNext"] as? Bool ?? true
        self.showPrevious = config["showPrevious"] as? Bool ?? true
        self.showStop = config["showStop"] as? Bool ?? false
        self.seekInterval = config["seekInterval"] as? Int ?? 10

        // Setup audio session
        setupAudioSession()

        // Setup remote command center
        setupRemoteCommandCenter()

        print("NotificationHandler: Initialized successfully")
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback)
            try audioSession.setActive(true)
            print("NotificationHandler: Audio session configured")
        } catch {
            print("NotificationHandler: Failed to setup audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Remote Command Center Setup

    private func setupRemoteCommandCenter() {
        print("NotificationHandler: Setting up remote command center")

        // Play command
        if showPlayPause {
            remoteCommandCenter.playCommand.isEnabled = true
            remoteCommandCenter.playCommand.addTarget { [weak self] event in
                print("NotificationHandler: Play command received")
                self?.sendActionToFlutter("play")
                return .success
            }

            // Pause command
            remoteCommandCenter.pauseCommand.isEnabled = true
            remoteCommandCenter.pauseCommand.addTarget { [weak self] event in
                print("NotificationHandler: Pause command received")
                self?.sendActionToFlutter("pause")
                return .success
            }

            // Toggle play/pause command
            remoteCommandCenter.togglePlayPauseCommand.isEnabled = true
            remoteCommandCenter.togglePlayPauseCommand.addTarget { [weak self] event in
                print("NotificationHandler: Toggle play/pause command received")
                if self?.isPlaying == true {
                    self?.sendActionToFlutter("pause")
                } else {
                    self?.sendActionToFlutter("play")
                }
                return .success
            }
        }

        // Next track command
        if showNext {
            remoteCommandCenter.nextTrackCommand.isEnabled = true
            remoteCommandCenter.nextTrackCommand.addTarget { [weak self] event in
                print("NotificationHandler: Next track command received")
                self?.sendActionToFlutter("next")
                return .success
            }
        }

        // Previous track command
        if showPrevious {
            remoteCommandCenter.previousTrackCommand.isEnabled = true
            remoteCommandCenter.previousTrackCommand.addTarget { [weak self] event in
                print("NotificationHandler: Previous track command received")
                self?.sendActionToFlutter("previous")
                return .success
            }
        }

        // Stop command
        if showStop {
            remoteCommandCenter.stopCommand.isEnabled = true
            remoteCommandCenter.stopCommand.addTarget { [weak self] event in
                print("NotificationHandler: Stop command received")
                self?.sendActionToFlutter("stop")
                return .success
            }
        }

        // Seek forward command
        remoteCommandCenter.skipForwardCommand.isEnabled = true
        remoteCommandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: seekInterval)]
        remoteCommandCenter.skipForwardCommand.addTarget { [weak self] event in
            print("NotificationHandler: Skip forward command received")
            self?.sendActionToFlutter("seekForward")
            return .success
        }

        // Seek backward command
        remoteCommandCenter.skipBackwardCommand.isEnabled = true
        remoteCommandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: seekInterval)]
        remoteCommandCenter.skipBackwardCommand.addTarget { [weak self] event in
            print("NotificationHandler: Skip backward command received")
            self?.sendActionToFlutter("seekBackward")
            return .success
        }

        // Change playback position command
        remoteCommandCenter.changePlaybackPositionCommand.isEnabled = true
        remoteCommandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                let position = event.positionTime
                print("NotificationHandler: Change playback position to: \(position)")
            }
            return .success
        }

        print("NotificationHandler: Remote command center configured")
    }

    // MARK: - Show/Update Notification

    func showNotification(mediaItem: [String: Any], state: [String: Any]) {
        print("NotificationHandler: Showing notification")

        let newArtworkUrl = mediaItem["artworkUrl"] as? String
        let newMediaUrl = mediaItem["url"] as? String

        // Detect when the media item changes so stale artwork is not reused.
        // A change is identified by either the artworkUrl or the media URL changing.
        let mediaChanged = (newArtworkUrl != currentArtworkUrl) || (newMediaUrl != currentMediaUrl)
        if mediaChanged {
            currentArtwork = nil
        }

        // Update media info
        currentTitle = mediaItem["title"] as? String ?? "Unknown Title"
        currentArtist = mediaItem["artist"] as? String
        currentAlbum = mediaItem["album"] as? String
        currentArtworkUrl = newArtworkUrl
        currentMediaUrl = newMediaUrl

        // Update playback state
        isPlaying = state["isPlaying"] as? Bool ?? false

        if let positionMs = state["position"] as? Int64 {
            position = Double(positionMs) / 1000.0
        } else if let positionMs = state["position"] as? Int {
            position = Double(positionMs) / 1000.0
        }

        if let durationMs = state["duration"] as? Int64 {
            duration = Double(durationMs) / 1000.0
        } else if let durationMs = state["duration"] as? Int {
            duration = Double(durationMs) / 1000.0
        }

        playbackRate = isPlaying ? 1.0 : 0.0

        // Artwork resolution:
        // 1. If an artworkUrl is provided, load from URL (takes priority).
        // 2. Otherwise, if the media URL is present, generate a thumbnail frame.
        if let artworkUrl = currentArtworkUrl, currentArtwork == nil {
            loadArtwork(from: artworkUrl)
        } else if (currentArtworkUrl == nil || currentArtworkUrl?.isEmpty == true),
                  currentArtwork == nil,
                  let mediaUrl = currentMediaUrl, !mediaUrl.isEmpty {
            generateThumbnail(from: mediaUrl)
        }

        // Update now playing info
        updateNowPlayingInfo()

        isShowing = true

        print("NotificationHandler: Notification updated - Title: \(currentTitle ?? "nil"), Playing: \(isPlaying)")
    }

    func updateState(state: [String: Any]) {
        guard isShowing else { return }

        print("NotificationHandler: Updating state")

        isPlaying = state["isPlaying"] as? Bool ?? false

        if let positionMs = state["position"] as? Int64 {
            position = Double(positionMs) / 1000.0
        } else if let positionMs = state["position"] as? Int {
            position = Double(positionMs) / 1000.0
        }

        if let durationMs = state["duration"] as? Int64 {
            duration = Double(durationMs) / 1000.0
        } else if let durationMs = state["duration"] as? Int {
            duration = Double(durationMs) / 1000.0
        }

        playbackRate = isPlaying ? 1.0 : 0.0

        updateNowPlayingInfo()
    }

    func updatePosition(position: Int64) {
        guard isShowing else { return }

        self.position = Double(position) / 1000.0
        updateNowPlayingInfo()
    }

    // MARK: - Update Now Playing Info

    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()

        // Media information
        if let title = currentTitle {
            nowPlayingInfo[MPMediaItemPropertyTitle] = title
        }

        if let artist = currentArtist {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }

        if let album = currentAlbum {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
        }

        // Artwork
        if let artwork = currentArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        // Playback information
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate

        // Default playback queue index (can be customized)
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = 0
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = 1

        // Media type
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue

        // Update
        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo

        print("NotificationHandler: Now playing info updated - Position: \(position)s / \(duration)s")
    }

    // MARK: - Artwork Loading

    private func loadArtwork(from urlString: String) {
        guard let url = URL(string: urlString) else {
            print("NotificationHandler: Invalid artwork URL")
            return
        }

        print("NotificationHandler: Loading artwork from: \(urlString)")

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            do {
                let data = try Data(contentsOf: url)

                if let image = UIImage(data: data) {
                    self.currentArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in
                        return image
                    }

                    DispatchQueue.main.async {
                        if self.isShowing {
                            self.updateNowPlayingInfo()
                            print("NotificationHandler: Artwork loaded and updated")
                        }
                    }
                }
            } catch {
                print("NotificationHandler: Failed to load artwork: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Video Thumbnail Generation

    /// Generates a thumbnail from the video at `urlString` and sets it as
    /// the Now Playing artwork.  Called only when artworkUrl is absent.
    /// Works with both local files and remote URLs; AVAssetImageGenerator
    /// reads just the range it needs so it does not download the whole file.
    ///
    /// Black-frame avoidance strategy
    /// ───────────────────────────────
    /// Many videos (e.g. Big Buck Bunny) open with a black fade-in.
    /// The previous implementation requested t=1s but left generator
    /// tolerances at their default of `.positiveInfinity`, which lets
    /// AVAssetImageGenerator snap all the way back to the nearest sync
    /// keyframe — often frame 0 (black).
    ///
    /// The fix has two parts:
    ///   1. Load the asset duration *before* generating so we can pick a
    ///      meaningful target time that is well inside real content.
    ///   2. Set tight tolerances (±1 s) so the generator stays close to
    ///      the requested time instead of snapping back to keyframe 0.
    ///
    /// Target time calculation
    /// ───────────────────────
    ///   • duration ≥ 3 s  → clamp(duration × 0.1, min: 3 s, max: 10 s)
    ///   • 0 < duration < 3 s → duration × 0.5   (short clip, meet in the middle)
    ///   • fallback (unknown duration) → 5 s fixed offset
    private func generateThumbnail(from urlString: String) {
        guard let url = URL(string: urlString) else {
            print("NotificationHandler: Invalid media URL for thumbnail generation")
            return
        }

        print("NotificationHandler: Generating thumbnail from media: \(urlString)")

        let asset = AVURLAsset(url: url)

        // Load "duration" and "tracks" asynchronously so the asset is ready
        // before we attempt image generation.  For local files this is nearly
        // instant; for remote (HLS/MP4) assets it fetches only the headers /
        // moov atom, not the whole file.
        asset.loadValuesAsynchronously(forKeys: ["duration", "tracks"]) { [weak self] in
            guard let self = self else { return }

            // If the media changed while we were loading, discard this work.
            guard self.currentMediaUrl == urlString else {
                print("NotificationHandler: Thumbnail load cancelled — media changed while loading asset")
                return
            }

            // Determine asset readiness; fall back to a fixed 5-second target
            // if the duration key failed to load (e.g. live streams).
            let durationStatus = asset.statusOfValue(forKey: "duration", error: nil)
            let assetDurationSeconds: Double
            if durationStatus == .loaded {
                let d = CMTimeGetSeconds(asset.duration)
                assetDurationSeconds = (d.isFinite && d > 0) ? d : 0
            } else {
                assetDurationSeconds = 0
                print("NotificationHandler: Asset duration not loaded (status \(durationStatus.rawValue)); using fallback target time")
            }

            // Compute a target time well into real content.
            let targetSeconds: Double
            if assetDurationSeconds >= 3.0 {
                // 10 % of duration, clamped to [3 s, 10 s]
                targetSeconds = min(max(assetDurationSeconds * 0.1, 3.0), 10.0)
            } else if assetDurationSeconds > 0 {
                // Very short clip — use the midpoint
                targetSeconds = assetDurationSeconds * 0.5
            } else {
                // Unknown duration (live, or load failed) — fixed 5 s
                targetSeconds = 5.0
            }

            print("NotificationHandler: Asset duration \(assetDurationSeconds)s → thumbnail target \(targetSeconds)s")

            let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            // Limit the decode size to avoid excessive memory use.
            generator.maximumSize = CGSize(width: 600, height: 600)

            // Tight tolerances prevent the generator from snapping all the way
            // back to keyframe 0 (which is black on many videos).  Allowing ±1 s
            // gives it enough room to find the nearest keyframe around our target
            // without reaching the very beginning of the file.
            generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter  = CMTime(seconds: 1, preferredTimescale: 600)

            do {
                var actualTime = CMTime.zero
                let cgImage = try generator.copyCGImage(at: targetTime, actualTime: &actualTime)
                let image = UIImage(cgImage: cgImage)

                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in
                    return image
                }

                print("NotificationHandler: Frame captured at actual time \(CMTimeGetSeconds(actualTime))s (requested \(targetSeconds)s)")

                DispatchQueue.main.async {
                    // Only apply if the media item hasn't changed while we were
                    // generating (guard by comparing the url that was captured
                    // when the generation was triggered).
                    if self.currentMediaUrl == urlString, self.currentArtwork == nil {
                        self.currentArtwork = artwork
                        if self.isShowing {
                            self.updateNowPlayingInfo()
                            print("NotificationHandler: Video thumbnail generated and applied")
                        }
                    } else {
                        print("NotificationHandler: Thumbnail discarded — media changed during generation")
                    }
                }
            } catch {
                print("NotificationHandler: Failed to generate thumbnail: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Dismiss Notification

    func dismiss() {
        print("NotificationHandler: Dismissing notification")

        nowPlayingInfoCenter.nowPlayingInfo = nil

        isShowing = false
        currentArtwork = nil
    }

    // MARK: - Flutter Communication

    private func sendActionToFlutter(_ action: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.channel.invokeMethod("onNotificationAction", arguments: [
                "playerId": self.playerId,
                "action": action
            ])
        }
    }

    // MARK: - Cleanup

    func dispose() {
        print("NotificationHandler: Disposing")

        dismiss()

        // Disable all remote commands
        remoteCommandCenter.playCommand.isEnabled = false
        remoteCommandCenter.pauseCommand.isEnabled = false
        remoteCommandCenter.togglePlayPauseCommand.isEnabled = false
        remoteCommandCenter.nextTrackCommand.isEnabled = false
        remoteCommandCenter.previousTrackCommand.isEnabled = false
        remoteCommandCenter.stopCommand.isEnabled = false
        remoteCommandCenter.skipForwardCommand.isEnabled = false
        remoteCommandCenter.skipBackwardCommand.isEnabled = false
        remoteCommandCenter.changePlaybackPositionCommand.isEnabled = false

        // Remove all targets
        remoteCommandCenter.playCommand.removeTarget(nil)
        remoteCommandCenter.pauseCommand.removeTarget(nil)
        remoteCommandCenter.togglePlayPauseCommand.removeTarget(nil)
        remoteCommandCenter.nextTrackCommand.removeTarget(nil)
        remoteCommandCenter.previousTrackCommand.removeTarget(nil)
        remoteCommandCenter.stopCommand.removeTarget(nil)
        remoteCommandCenter.skipForwardCommand.removeTarget(nil)
        remoteCommandCenter.skipBackwardCommand.removeTarget(nil)
        remoteCommandCenter.changePlaybackPositionCommand.removeTarget(nil)
    }

    deinit {
        dispose()
    }
}

// MARK: - Notification Actions

class NotificationActions {
    static let play = "play"
    static let pause = "pause"
    static let next = "next"
    static let previous = "previous"
    static let stop = "stop"
    static let seekForward = "seek_forward"
    static let seekBackward = "seek_backward"
}
