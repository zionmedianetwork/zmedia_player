import Foundation
import MediaPlayer
import AVFoundation
import Flutter

/// Handles media notifications using MPNowPlayingInfoCenter and MPRemoteCommandCenter.
///
/// ## Ownership of the shared OS singletons
///
/// `MPRemoteCommandCenter.shared()` and `MPNowPlayingInfoCenter.default()` are
/// process-wide singletons: there is exactly one of each per app, no matter how
/// many `NotificationHandler` instances exist (one is created per player — see
/// `ZMediaPlayerPlugin.notificationHandlers`). Without coordination, every
/// instance would register its own remote-command targets on the same shared
/// commands (so a single lock-screen "pause" tap would fire every player's
/// handler), and any instance's `dispose()`/`dismiss()` would wipe Now Playing
/// info and detach command handling for every other player.
///
/// `Ownership` (below) fixes this by tracking exactly one *owning* instance at
/// a time:
///
/// - **Claiming ownership is last-writer-wins.** Calling `initialize(config:)`
///   makes that instance the current owner, superseding whoever owned it
///   before. This matches the existing UX expectation that the most recently
///   (re)initialized player drives the lock screen / Control Center.
/// - **Remote command targets are registered with the OS exactly once per
///   process**, the first time any instance initializes. Their closures do not
///   capture a specific instance; they look up `Ownership.shared.currentOwner()`
///   at the moment the event fires and forward to *whichever* instance
///   currently owns the session. This sidesteps `removeTarget(nil)` entirely
///   for normal ownership changes — there is only ever one target per command
///   for the life of the process, so no instance ever needs to remove another
///   instance's target.
/// - **Only the owner publishes to `MPNowPlayingInfoCenter`.** Non-owning
///   instances still track their own title/position/etc. locally (so they can
///   republish correctly if they later become the owner) but never write to
///   the shared center, and never clear it on `dismiss()`/`dispose()`.
/// - **When the owner disposes**, ownership is handed to another still-live
///   instance if one exists (the most recently registered one); that successor
///   reapplies its own command-availability configuration and republishes its
///   own Now Playing info if it was showing one. If no other instance remains,
///   this is a full teardown: Now Playing info is cleared, all commands are
///   disabled, and the specific target tokens returned by `addTarget` are
///   removed individually (never via `removeTarget(nil)`) so a later
///   `initialize()` call starts from a clean slate.
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

    private var remoteCommandCenter: MPRemoteCommandCenter { Ownership.shared.remoteCommandCenter }
    private var nowPlayingInfoCenter: MPNowPlayingInfoCenter { Ownership.shared.nowPlayingInfoCenter }

    /// `true` when this instance currently owns Now Playing / remote command
    /// handling. Only the owner is allowed to write to the shared singletons.
    private var isOwner: Bool { Ownership.shared.isOwner(self) }

    // MARK: - Process-wide ownership coordinator
    //
    // All mutable ownership bookkeeping (who owns the session, which instances
    // are alive, which command targets have been registered) lives here, keyed
    // by nothing but the process itself — matching the fact that
    // MPRemoteCommandCenter/MPNowPlayingInfoCenter are themselves process-wide.
    // Access is serialized with `lock` because `initialize()`/`dispose()` can
    // race across player instances and because `deinit` (which calls
    // `dispose()`) can in principle run on a thread other than the one that
    // triggered deallocation.
    fileprivate final class Ownership {
        static let shared = Ownership()

        let remoteCommandCenter = MPRemoteCommandCenter.shared()
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()

        private let lock = NSLock()
        private weak var owner: NotificationHandler?
        private var liveInstances: [WeakHandler] = []
        private var commandTargets: [(MPRemoteCommand, Any)] = []

        private struct WeakHandler {
            weak var handler: NotificationHandler?
        }

        private init() {}

        /// Registers `handler` in the live-instance registry (used to pick a
        /// successor owner later) and reports whether the shared remote
        /// command targets still need to be configured. The caller performs
        /// the actual `addTarget` calls (a MediaPlayer-framework / main-thread
        /// operation) outside the lock and reports the resulting tokens back
        /// via `recordCommandTargets`.
        func registerAndNeedsCommandSetup(_ handler: NotificationHandler) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            liveInstances.removeAll { $0.handler == nil }
            if !liveInstances.contains(where: { $0.handler === handler }) {
                liveInstances.append(WeakHandler(handler: handler))
            }
            return commandTargets.isEmpty
        }

        /// Stores the target tokens returned by `addTarget` so a future full
        /// teardown can remove exactly those, never `removeTarget(nil)`.
        func recordCommandTargets(_ targets: [(MPRemoteCommand, Any)]) {
            lock.lock()
            commandTargets.append(contentsOf: targets)
            lock.unlock()
        }

        /// Last-writer-wins: makes `handler` the current owner of the shared
        /// singletons.
        func claimOwnership(for handler: NotificationHandler) {
            lock.lock()
            owner = handler
            lock.unlock()
        }

        func isOwner(_ handler: NotificationHandler) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return owner === handler
        }

        func currentOwner() -> NotificationHandler? {
            lock.lock()
            defer { lock.unlock() }
            return owner
        }

        enum ReleaseResult {
            /// `handler` was not the owner; nothing to do.
            case notOwner
            /// `handler` was the owner; `successor` is the new owner and must
            /// reapply its own configuration / republish its own info.
            case handedOff(to: NotificationHandler)
            /// `handler` was the owner and no other instance is alive; the
            /// caller must fully tear down the shared singletons.
            case tornDown(targetsToRemove: [(MPRemoteCommand, Any)])
        }

        /// Removes `handler` from the live registry and, if it was the owner,
        /// either hands ownership to another live instance or reports that a
        /// full teardown is required.
        func release(_ handler: NotificationHandler) -> ReleaseResult {
            lock.lock()
            defer { lock.unlock() }
            liveInstances.removeAll { $0.handler == nil || $0.handler === handler }
            guard owner === handler else {
                return .notOwner
            }
            if let successor = liveInstances.last?.handler {
                owner = successor
                return .handedOff(to: successor)
            }
            owner = nil
            let targets = commandTargets
            commandTargets.removeAll()
            return .tornDown(targetsToRemove: targets)
        }
    }

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

        // The remote command center is a process-wide singleton: only wire up
        // its targets once, ever. Every later `initialize()` call (from this
        // or any other player instance) just registers for the live-instance
        // registry and claims ownership below.
        if Ownership.shared.registerAndNeedsCommandSetup(self) {
            setupRemoteCommandCenter()
        }

        // Last-writer-wins: this instance now drives Now Playing / remote
        // commands. Command availability (showPlayPause/showNext/... and
        // seekInterval) can differ per player, so re-apply it for the new
        // owner.
        Ownership.shared.claimOwnership(for: self)
        applyCommandAvailability()

        print("NotificationHandler: Initialized successfully")
    }

    // MARK: - Audio Session Setup

    /// B-05: this previously also called `setActive(true)` — meaning simply
    /// initializing the notification/lock-screen integration (which happens
    /// independent of whether the associated player has ever played
    /// anything; see `ZMediaPlayerPlugin.notificationHandlers`) seized the
    /// process-wide audio session and interrupted any other app's audio.
    /// Session ACTIVATION is now owned exclusively by
    /// `AudioSessionCoordinator`, driven by `MediaPlayerInstance.play()`/
    /// `pause()`/`dispose()` in MediaPlayerManager.swift. Setting the
    /// category alone (no activation) is harmless — it does not interrupt
    /// other apps' audio — and keeps this instance's session-category intent
    /// consistent in case it's queried before the player ever plays.
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback)
            print("NotificationHandler: Audio session category configured (activation is owned by AudioSessionCoordinator)")
        } catch {
            print("NotificationHandler: Failed to configure audio session category: \(error.localizedDescription)")
        }
    }

    // MARK: - Remote Command Center Setup

    /// Registers a target on every remote command exactly once for the life
    /// of the process. Handlers do not close over `self`; they resolve
    /// `Ownership.shared.currentOwner()` at the moment the event fires and
    /// forward to whichever instance currently owns the session (or do
    /// nothing if there is no owner). Enabling/disabling individual commands
    /// per player's configuration is handled separately by
    /// `applyCommandAvailability()`, which runs whenever ownership changes.
    private func setupRemoteCommandCenter() {
        print("NotificationHandler: Setting up remote command center (process-wide, first initialization)")

        var addedTargets: [(MPRemoteCommand, Any)] = []

        let playTarget = remoteCommandCenter.playCommand.addTarget { _ in
            print("NotificationHandler: Play command received")
            Ownership.shared.currentOwner()?.sendActionToFlutter("play")
            return .success
        }
        addedTargets.append((remoteCommandCenter.playCommand, playTarget))

        let pauseTarget = remoteCommandCenter.pauseCommand.addTarget { _ in
            print("NotificationHandler: Pause command received")
            Ownership.shared.currentOwner()?.sendActionToFlutter("pause")
            return .success
        }
        addedTargets.append((remoteCommandCenter.pauseCommand, pauseTarget))

        let toggleTarget = remoteCommandCenter.togglePlayPauseCommand.addTarget { _ in
            print("NotificationHandler: Toggle play/pause command received")
            if let owner = Ownership.shared.currentOwner() {
                owner.sendActionToFlutter(owner.isPlaying ? "pause" : "play")
            }
            return .success
        }
        addedTargets.append((remoteCommandCenter.togglePlayPauseCommand, toggleTarget))

        let nextTarget = remoteCommandCenter.nextTrackCommand.addTarget { _ in
            print("NotificationHandler: Next track command received")
            Ownership.shared.currentOwner()?.sendActionToFlutter("next")
            return .success
        }
        addedTargets.append((remoteCommandCenter.nextTrackCommand, nextTarget))

        let previousTarget = remoteCommandCenter.previousTrackCommand.addTarget { _ in
            print("NotificationHandler: Previous track command received")
            Ownership.shared.currentOwner()?.sendActionToFlutter("previous")
            return .success
        }
        addedTargets.append((remoteCommandCenter.previousTrackCommand, previousTarget))

        let stopTarget = remoteCommandCenter.stopCommand.addTarget { _ in
            print("NotificationHandler: Stop command received")
            Ownership.shared.currentOwner()?.sendActionToFlutter("stop")
            return .success
        }
        addedTargets.append((remoteCommandCenter.stopCommand, stopTarget))

        let skipForwardTarget = remoteCommandCenter.skipForwardCommand.addTarget { _ in
            print("NotificationHandler: Skip forward command received")
            Ownership.shared.currentOwner()?.sendActionToFlutter("seekForward")
            return .success
        }
        addedTargets.append((remoteCommandCenter.skipForwardCommand, skipForwardTarget))

        let skipBackwardTarget = remoteCommandCenter.skipBackwardCommand.addTarget { _ in
            print("NotificationHandler: Skip backward command received")
            Ownership.shared.currentOwner()?.sendActionToFlutter("seekBackward")
            return .success
        }
        addedTargets.append((remoteCommandCenter.skipBackwardCommand, skipBackwardTarget))

        // Change playback position (lock-screen scrub bar). Previously this
        // logged the requested position and returned `.success` without ever
        // forwarding it to Flutter, so dragging the scrubber was a silent
        // no-op. Forward it the same way every other transport action is
        // forwarded, via `sendActionToFlutter`, with the requested position
        // (in milliseconds, matching this package's convention elsewhere)
        // attached to the event.
        let changePositionTarget = remoteCommandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let positionSeconds = positionEvent.positionTime
            print("NotificationHandler: Change playback position to: \(positionSeconds)")
            let positionMs = Int64((positionSeconds * 1000.0).rounded())
            Ownership.shared.currentOwner()?.sendActionToFlutter("seekTo", position: positionMs)
            return .success
        }
        addedTargets.append((remoteCommandCenter.changePlaybackPositionCommand, changePositionTarget))

        Ownership.shared.recordCommandTargets(addedTargets)

        print("NotificationHandler: Remote command center configured")
    }

    /// Enables/disables each remote command and configures skip intervals
    /// according to *this* instance's configuration. Only meaningful (and
    /// only called) while this instance is the current owner.
    private func applyCommandAvailability() {
        remoteCommandCenter.playCommand.isEnabled = showPlayPause
        remoteCommandCenter.pauseCommand.isEnabled = showPlayPause
        remoteCommandCenter.togglePlayPauseCommand.isEnabled = showPlayPause

        remoteCommandCenter.nextTrackCommand.isEnabled = showNext
        remoteCommandCenter.previousTrackCommand.isEnabled = showPrevious
        remoteCommandCenter.stopCommand.isEnabled = showStop

        remoteCommandCenter.skipForwardCommand.isEnabled = true
        remoteCommandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: seekInterval)]

        remoteCommandCenter.skipBackwardCommand.isEnabled = true
        remoteCommandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: seekInterval)]

        remoteCommandCenter.changePlaybackPositionCommand.isEnabled = true
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

        isShowing = true

        // This instance's local state is always kept up to date (above) so it
        // can republish correctly if it later becomes the owner, but only the
        // current owner is allowed to write to the shared Now Playing center.
        if isOwner {
            updateNowPlayingInfo()
        }

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

        if isOwner {
            updateNowPlayingInfo()
        }
    }

    func updatePosition(position: Int64) {
        guard isShowing else { return }

        self.position = Double(position) / 1000.0

        if isOwner {
            updateNowPlayingInfo()
        }
    }

    // MARK: - Update Now Playing Info

    /// Writes this instance's current media/playback info to the shared
    /// `MPNowPlayingInfoCenter`. Callers must only invoke this while `isOwner`
    /// is `true`.
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
                        if self.isShowing && self.isOwner {
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
                        if self.isShowing && self.isOwner {
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

    /// Hides this instance's notification. Only the current owner is allowed
    /// to clear the shared `MPNowPlayingInfoCenter` — a non-owning instance
    /// dismissing its own (already invisible, since it isn't the owner)
    /// notification must not collaterally wipe the owner's Now Playing info.
    func dismiss() {
        print("NotificationHandler: Dismissing notification")

        if isOwner {
            nowPlayingInfoCenter.nowPlayingInfo = nil
        }

        isShowing = false
        currentArtwork = nil
    }

    // MARK: - Flutter Communication

    private func sendActionToFlutter(_ action: String, position: Int64? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            var arguments: [String: Any] = [
                "playerId": self.playerId,
                "action": action
            ]
            if let position = position {
                arguments["position"] = position
            }

            self.channel.invokeMethod("onNotificationAction", arguments: arguments)
        }
    }

    // MARK: - Cleanup

    /// Disposes this instance. If it currently owns the shared singletons,
    /// ownership is handed to another live instance (which reapplies its own
    /// configuration and republishes its own info) or, if none remain, the
    /// shared singletons are fully torn down: Now Playing info cleared, all
    /// commands disabled, and exactly the target tokens this class registered
    /// are removed (never `removeTarget(nil)`, which would also remove
    /// targets belonging to a future instance that might reuse the same
    /// command objects). A non-owning instance's dispose only clears its own
    /// local state and never touches the shared singletons.
    func dispose() {
        print("NotificationHandler: Disposing")

        // Always clear this instance's own visible state first. `dismiss()`
        // itself only touches the shared center if `self` is (still) the
        // owner, which is checked before the ownership release below runs.
        dismiss()

        switch Ownership.shared.release(self) {
        case .notOwner:
            // Nothing further to do — this instance never owned the shared
            // singletons, so no other player is affected by its disposal.
            break

        case .handedOff(to: let successor):
            print("NotificationHandler: Ownership handed off to player \(successor.playerId)")
            successor.applyCommandAvailability()
            if successor.isShowing {
                successor.updateNowPlayingInfo()
            }

        case .tornDown(let targetsToRemove):
            print("NotificationHandler: No other player active — tearing down shared Now Playing / remote commands")

            nowPlayingInfoCenter.nowPlayingInfo = nil

            remoteCommandCenter.playCommand.isEnabled = false
            remoteCommandCenter.pauseCommand.isEnabled = false
            remoteCommandCenter.togglePlayPauseCommand.isEnabled = false
            remoteCommandCenter.nextTrackCommand.isEnabled = false
            remoteCommandCenter.previousTrackCommand.isEnabled = false
            remoteCommandCenter.stopCommand.isEnabled = false
            remoteCommandCenter.skipForwardCommand.isEnabled = false
            remoteCommandCenter.skipBackwardCommand.isEnabled = false
            remoteCommandCenter.changePlaybackPositionCommand.isEnabled = false

            // Remove exactly the targets this class added — never
            // `removeTarget(nil)`, which removes *every* target registered on
            // the command by anyone.
            for (command, token) in targetsToRemove {
                command.removeTarget(token)
            }
        }
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
    static let seekTo = "seekTo"
}
