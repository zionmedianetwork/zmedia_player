import Foundation
import AVFoundation
import AVKit
import Flutter

/// Coordinates activation/deactivation of the process-wide `AVAudioSession`
/// across every `MediaPlayerInstance` (and the other handlers — Pip,
/// AirPlay, Notification — that used to poke the session independently).
///
/// ## Why this exists (B-05)
///
/// `AVAudioSession.sharedInstance()` is a single, process-wide resource —
/// exactly like `MPRemoteCommandCenter`/`MPNowPlayingInfoCenter`, which
/// `NotificationHandler.Ownership` already coordinates for the same reason.
/// This type follows the same shape (a private lock-guarded singleton that
/// every instance registers with/unregisters from) but a different policy,
/// because audio-session activation is not "one owner at a time" the way
/// Now Playing info is — it is a **reference count**: the session must stay
/// active as long as ANY live instance still needs it, and must not be
/// deactivated just because one particular instance paused or disposed while
/// others are still playing.
///
/// ## Policy
///
/// - An instance that is actually **audible** (not muted, volume > 0) needs
///   the session active and EXCLUSIVE (`.playback`, no `.mixWithOthers`) —
///   this is what lets audio play with the ring/silent switch on and
///   continue in the background, but it also interrupts other apps' audio
///   (e.g. Spotify), which is the correct, expected behaviour for audible
///   playback.
/// - An instance that is playing but **muted or at zero volume** (e.g. a
///   silently autoplaying preview in a feed) must NOT interrupt other apps'
///   audio. It still registers a request (so the category/activation state
///   is recomputed correctly when it later becomes audible, or when it
///   disposes), but the aggregate policy only asks for `.mixWithOthers` on
///   its behalf, never exclusive activation.
/// - The **aggregate** state across all live requesters determines the
///   actual category: if ANY requester is audible, the session is exclusive
///   (audible always wins — muting one preview must not silently downgrade a
///   different, genuinely-playing instance to `.mixWithOthers`). Otherwise,
///   if only silent requesters exist, the session is active with
///   `.mixWithOthers`. If no requester remains, the session is deactivated
///   with `.notifyOthersOnDeactivation` so a backgrounded app like Spotify
///   resumes.
/// - Release happens explicitly (`play()`'s counterpart `pause()`/`stop()`,
///   and `dispose()`) rather than being inferred from `rate`/
///   `timeControlStatus` transitions, because a transient stall
///   (`waitingToPlayAtSpecifiedRate`) or an OS-driven interruption must NOT
///   cause this instance to release its slot — only an explicit
///   pause/stop/dispose means "no longer needed."
///
/// All AVAudioSession mutation is funnelled through here; `MediaPlayerInstance`,
/// `PipHandler`, `AirPlayHandler` and `NotificationHandler` no longer call
/// `setActive(true)` directly (only category hints, which — unlike
/// activation — do not interrupt other apps' audio).
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    private let lock = NSLock()
    /// Requesters (identified by object identity) whose output is currently
    /// audible and therefore require exclusive session activation.
    private var audibleRequesters: Set<ObjectIdentifier> = []
    /// Requesters that are playing but muted/silent — they need the session
    /// alive (so they don't glitch if unmuted) but must not interrupt others.
    private var silentRequesters: Set<ObjectIdentifier> = []
    private var sessionIsActive = false

    private init() {}

    /// Registers (or updates) `owner`'s need for the shared audio session.
    /// Call this from `play()` and whenever audibility changes
    /// (`setVolume`/`setMuted`) while the instance is still playing.
    func requestActive(for owner: AnyObject, audible: Bool) {
        lock.lock()
        let id = ObjectIdentifier(owner)
        if audible {
            audibleRequesters.insert(id)
            silentRequesters.remove(id)
        } else {
            silentRequesters.insert(id)
            audibleRequesters.remove(id)
        }
        let snapshot = currentPolicy()
        lock.unlock()

        apply(snapshot)
    }

    /// Removes `owner` from the requester set. Call from `pause()`, `stop()`
    /// and `dispose()`. Safe to call even if `owner` never requested
    /// activation (e.g. `dispose()` on an instance that was never played).
    func release(for owner: AnyObject) {
        lock.lock()
        let id = ObjectIdentifier(owner)
        audibleRequesters.remove(id)
        silentRequesters.remove(id)
        let snapshot = currentPolicy()
        lock.unlock()

        apply(snapshot)
    }

    private enum Policy: Equatable {
        case inactive
        case activeExclusive
        case activeMixWithOthers
    }

    /// Must be called with `lock` held.
    private func currentPolicy() -> Policy {
        if !audibleRequesters.isEmpty {
            return .activeExclusive
        } else if !silentRequesters.isEmpty {
            return .activeMixWithOthers
        } else {
            return .inactive
        }
    }

    /// Performs the actual `AVAudioSession` mutation. Dispatched to the main
    /// thread for consistency with the rest of this plugin's AVFoundation/UI
    /// interactions; `AVAudioSession` itself is thread-safe but session
    /// changes can trigger route/interruption side effects best observed
    /// from a consistent thread.
    private func apply(_ policy: Policy) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let audioSession = AVAudioSession.sharedInstance()

            switch policy {
            case .activeExclusive:
                do {
                    try audioSession.setCategory(.playback, mode: .moviePlayback)
                    try audioSession.setActive(true)
                    self.sessionIsActive = true
                    zlog("AudioSessionCoordinator: Session active (exclusive)")
                } catch {
                    zlog("AudioSessionCoordinator: Failed to activate session (exclusive): \(error)")
                }

            case .activeMixWithOthers:
                do {
                    try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
                    try audioSession.setActive(true)
                    self.sessionIsActive = true
                    zlog("AudioSessionCoordinator: Session active (mixWithOthers, muted/silent playback)")
                } catch {
                    zlog("AudioSessionCoordinator: Failed to activate session (mixWithOthers): \(error)")
                }

            case .inactive:
                guard self.sessionIsActive else { return }
                do {
                    try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
                    self.sessionIsActive = false
                    zlog("AudioSessionCoordinator: Session deactivated (no live requester) — notifying other apps")
                } catch {
                    zlog("AudioSessionCoordinator: Failed to deactivate session: \(error)")
                }
            }
        }
    }
}

class MediaPlayerManager {
    private var players: [String: MediaPlayerInstance] = [:]
    private let methodChannel: FlutterMethodChannel
    private let crashHandler: CrashHandler

    // Activity tracking for memory leak prevention
    private var lastActivity: [String: Date] = [:]
    private var cleanupTimer: Timer?

    // Cleanup configuration
    private static let cleanupInterval: TimeInterval = 5 * 60 // 5 minutes
    private static let staleThreshold: TimeInterval = 15 * 60 // 15 minutes

    init(methodChannel: FlutterMethodChannel) {
        self.methodChannel = methodChannel
        self.crashHandler = CrashHandler(methodChannel: methodChannel)
        startCleanupTimer()
    }

    // MARK: - Activity Tracking

    private func markActivity(playerId: String) {
        lastActivity[playerId] = Date()
    }

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(
            withTimeInterval: MediaPlayerManager.cleanupInterval,
            repeats: true
        ) { [weak self] _ in
            self?.cleanupStaleInstances()
        }
    }

    private func cleanupStaleInstances() {
        let now = Date()
        var stalePlayers: [String] = []

        for (playerId, lastUsed) in lastActivity {
            if now.timeIntervalSince(lastUsed) > MediaPlayerManager.staleThreshold {
                if let instance = players[playerId], !instance.isPlaying() {
                    stalePlayers.append(playerId)
                }
            }
        }

        for playerId in stalePlayers {
            zlog("MediaPlayerManager: Auto-cleaning stale instance: \(playerId)")
            players[playerId]?.dispose()
            players.removeValue(forKey: playerId)
            lastActivity.removeValue(forKey: playerId)
        }
    }

    func initializePlayer(playerId: String, config: [String: Any]?) throws {
        markActivity(playerId: playerId)
        let playerInstance = MediaPlayerInstance(playerId: playerId, methodChannel: methodChannel, config: config)
        players[playerId] = playerInstance
    }

    func loadMediaItem(playerId: String, mediaItem: [String: Any], config: [String: Any]? = nil) throws {
        markActivity(playerId: playerId)
        try crashHandler.wrapOperation(
            operation: "loadMediaItem",
            playerId: playerId,
            context: ["url": mediaItem["url"] ?? "unknown"]
        ) {
            guard let playerInstance = players[playerId] else {
                throw MediaPlayerError.playerNotFound
            }
            playerInstance.loadMediaItem(mediaItem: mediaItem, newConfig: config)
        }
    }

    func setPlaylist(
        playerId: String,
        playlist: [String: Any],
        startIndex: Int,
        config: [String: Any]? = nil
    ) throws {
        markActivity(playerId: playerId)
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.setPlaylist(playlist: playlist, startIndex: startIndex, newConfig: config)
    }

    func play(playerId: String) throws {
        markActivity(playerId: playerId)
        try crashHandler.wrapOperation(
            operation: "play",
            playerId: playerId
        ) {
            guard let playerInstance = players[playerId] else {
                throw MediaPlayerError.playerNotFound
            }
            playerInstance.play()
        }
    }

    func pause(playerId: String) throws {
        markActivity(playerId: playerId)
        try crashHandler.wrapOperation(
            operation: "pause",
            playerId: playerId
        ) {
            guard let playerInstance = players[playerId] else {
                throw MediaPlayerError.playerNotFound
            }
            playerInstance.pause()
        }
    }

    func stop(playerId: String) throws {
        markActivity(playerId: playerId)
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.stop()
    }

    func seekTo(playerId: String, position: Int64) throws {
        markActivity(playerId: playerId)
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.seekTo(position: position)
    }

    func setVolume(playerId: String, volume: Float) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.setVolume(volume: volume)
    }

    func setPlaybackSpeed(playerId: String, speed: Float) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.setPlaybackSpeed(speed: speed)
    }

    func setMuted(playerId: String, muted: Bool) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.setMuted(muted: muted)
    }

    func setBoxFit(playerId: String, boxFit: String) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.setBoxFit(boxFit: boxFit)
    }

    func setSubtitleTrack(playerId: String, subtitleTrack: [String: Any]?) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.setSubtitleTrack(subtitleTrack: subtitleTrack)
    }

    func setQualityTrack(playerId: String, qualityTrack: [String: Any]) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.setQualityTrack(qualityTrack: qualityTrack)
    }

    func setAudioTrack(playerId: String, audioTrack: [String: Any]) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.setAudioTrack(audioTrack: audioTrack)
    }

    func enableAutoQuality(playerId: String) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.enableAutoQuality()
    }

    func skipToIndex(playerId: String, index: Int, config: [String: Any]? = nil) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.skipToIndex(index: index, newConfig: config)
    }

    func updateConfig(playerId: String, config: [String: Any]) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.updateConfig(config: config)
    }

    func getPlayerView(playerId: String) -> MediaPlayerView? {
        return players[playerId]?.getPlayerView()
    }

    /// Diagnostic-only notification used by `MediaPlayerViewFactory.create()`
    /// when it could not resolve a live player for a platform-view creation
    /// request (see B-03 in the Phase 1 remediation plan). This is
    /// deliberately a distinct method name from `onError` — it is not a
    /// playback error and must not be able to flip a `MediaController`'s
    /// state to `PlayerState.error`. Presently unhandled Dart-side (falls
    /// through to the `default:` case in `_handleMethodCall`, which just
    /// debug-prints), so this is safe to call even though nothing consumes
    /// it yet.
    func notifyPlatformViewCreationFailed(playerId: String?, reason: String) {
        let arguments: [String: Any] = [
            "playerId": playerId ?? "",
            "reason": reason
        ]
        if Thread.isMainThread {
            methodChannel.invokeMethod("onPlatformViewError", arguments: arguments)
        } else {
            DispatchQueue.main.async { [methodChannel] in
                methodChannel.invokeMethod("onPlatformViewError", arguments: arguments)
            }
        }
    }

    // Phase 3: Helper methods for PiP and AirPlay handlers
    func getPlayer(playerId: String) throws -> AVPlayer? {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        return playerInstance.getAVPlayer()
    }

    func getPlayerLayer(playerId: String) throws -> AVPlayerLayer? {
        guard let playerInstance = players[playerId] else {
            zlog("MediaPlayerManager: Player instance not found for \(playerId)")
            throw MediaPlayerError.playerNotFound
        }

        // Use currentPlayerLayer() which reads the active view WITHOUT creating a new one.
        let layer = playerInstance.currentPlayerLayer()
        zlog("MediaPlayerManager: getPlayerLayer - returning active player layer: \(layer != nil)")
        return layer
    }

    func getBufferHealth(playerId: String) -> [String: Any] {
        markActivity(playerId: playerId)
        guard let playerInstance = players[playerId] else {
            return [
                "bufferedDurationMs": 0,
                "currentPositionMs": 0,
                "totalDurationMs": 0,
                "downloadSpeed": 0
            ]
        }
        return playerInstance.getBufferHealth()
    }

    func disposePlayer(playerId: String) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.dispose()
        players.removeValue(forKey: playerId)
        lastActivity.removeValue(forKey: playerId)
    }

    func dispose() {
        players.values.forEach { $0.dispose() }
        players.removeAll()
        lastActivity.removeAll()
    }

    func shutdown() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        dispose()
    }

    deinit {
        shutdown()
    }
}

class MediaPlayerInstance: NSObject {
    private let playerId: String
    private let methodChannel: FlutterMethodChannel
    private var config: [String: Any]?

    /// The playback speed the consumer has ASKED for, independent of whether the
    /// player is currently playing. `rate` cannot hold this: on AVPlayer a non-zero
    /// `rate` is a transport command, so storing a speed there starts playback.
    /// Applied on the next transition into playing — see `play()`.
    private var requestedSpeed: Float = 1.0

    private var avPlayer: AVPlayer?

    // Per-host view tracking — each UiKitView host gets its own MediaPlayerView
    // (its own containerView + its own AVPlayerLayer) all sharing the same avPlayer.
    // AVPlayer supports multiple AVPlayerLayers rendering simultaneously, so both
    // the embedded and fullscreen hosts show video without a black screen.
    //
    // The manager holds only WEAK references; Flutter (the UiKitView host) is the
    // strong owner.  Dead entries are pruned lazily in activePlayerView.
    private struct WeakPlayerView { weak var view: MediaPlayerView? }
    private var playerViews: [WeakPlayerView] = []

    /// The most-recently-created live view (the topmost/active host, e.g. fullscreen).
    /// Prunes dead entries as a side effect.
    private var activePlayerView: MediaPlayerView? {
        playerViews = playerViews.filter { $0.view != nil }
        return playerViews.last?.view
    }

    /// Apply an action to every currently-live view.
    private func forEachLiveView(_ body: (MediaPlayerView) -> Void) {
        for ref in playerViews {
            if let v = ref.view { body(v) }
        }
    }

    /// Enforces the single-active-layer rule: exactly ONE live view (the
    /// most-recently-created / topmost host) is bound to the shared `AVPlayer`;
    /// every other live view is unbound.
    ///
    /// A single `AVPlayer` driving more than one `AVPlayerLayer` at a time is
    /// undefined behaviour on iOS and renders the losing layer(s) grey. The app
    /// mounts the player at up to three hosts (inline / MiniPlayer / fullscreen)
    /// for one controller and swaps between them on tab-change, fullscreen
    /// enter/exit and recovery reloads, so this must run whenever the set of
    /// live views or the current item changes.
    private func activateTopmostView() {
        // Prune dead weak refs first.
        playerViews = playerViews.filter { $0.view != nil }
        guard let active = playerViews.last?.view else { return }
        for ref in playerViews {
            guard let v = ref.view else { continue }
            if v === active {
                if !v.isActiveRenderTarget || v.playerLayer.player == nil {
                    v.activate(with: avPlayer)
                }
            } else if v.isActiveRenderTarget || v.playerLayer.player != nil {
                v.deactivate()
            }
        }
    }

    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    /// Observes `timeControlStatus` rather than bare `rate` so a mid-playback
    /// stall (`.waitingToPlayAtSpecifiedRate`, rate == 0) is reported as
    /// `buffering`, not `paused` — see `handleTimeControlStatusChange` (B-06).
    private var timeControlStatusObserver: NSKeyValueObservation?
    private var bandwidthTimer: Timer?

    /// Whether this instance currently holds a live request with
    /// `AudioSessionCoordinator` (i.e. `play()` was called and neither
    /// `pause()`/`stop()`/`dispose()` nor an OS interruption has released it
    /// since). Used so `setVolume`/`setMuted` know whether an audibility
    /// change should refresh the in-flight session request (B-05).
    private var audioSessionRequested = false

    /// Set on `AVAudioSession.interruptionNotification` `.began` to whatever
    /// this instance's play state was at that moment, so `.ended` can decide
    /// whether to resume (B-06). Not persisted beyond one interruption cycle.
    private var wasPlayingBeforeInterruption = false

    // Modern KVO observers for player item (auto-cleanup, no exceptions)
    private var itemDurationObserver: NSKeyValueObservation?
    private var itemStatusObserver: NSKeyValueObservation?

    private var currentPlaylist: [[String: Any]]?
    private var currentIndex = 0
    private var currentMediaItem: [String: Any]?

    /// True once the currently loaded item has been played to the end, or
    /// `stop()`ed -- i.e. it is still attached to the `AVPlayer` but there is
    /// no longer any in-progress playback worth preserving.
    ///
    /// Exists purely to give `isAlreadyLoadedAndInProgress(_:)` (issue #79)
    /// the same "is anything actually in progress?" signal ExoPlayer hands
    /// Android for free via `playbackState`. This is the one structural
    /// difference between the two platforms' guards: on Android `stop()`
    /// leaves the player in `STATE_IDLE` with no media items and a finished
    /// item sits in `STATE_ENDED`, both trivially detectable; on iOS
    /// `stop()` is pause + `seek(to: .zero)` and finishing leaves the item
    /// attached and `.readyToPlay`, so neither is visible from `AVPlayer`
    /// state alone and has to be tracked explicitly.
    private var currentItemIsSpent = false
    private var previousAccessLogEventCount = 0
    // DRM handler — non-nil only when the current media item carries a drmConfig.
    private var drmHandler: DrmHandler?

    init(playerId: String, methodChannel: FlutterMethodChannel, config: [String: Any]?) {
        self.playerId = playerId
        self.methodChannel = methodChannel
        self.config = config

        super.init()
        initializeAVPlayer()
    }

    private func initializeAVPlayer() {
        avPlayer = AVPlayer()

        // Configure player for PiP and external playback
        avPlayer?.allowsExternalPlayback = true
        avPlayer?.usesExternalPlaybackWhileExternalScreenIsActive = false
        avPlayer?.preventsDisplaySleepDuringVideoPlayback = true

        setupObservers()
        applyConfig()
        startBandwidthMonitoring()
    }

    private func setupObservers() {
        guard let player = avPlayer else { return }

        // Time observer for position updates
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }

            // Wave E (DVR window duration): re-check the live DVR window's
            // length on every tick -- AVFoundation has no KVO notification
            // for `seekableTimeRanges` changing, so polling here (already
            // running every 0.5s for position) is how a growing/sliding
            // window's duration stays current. See checkLiveDvrWindowDuration.
            self.checkLiveDvrWindowDuration()

            // Issue #88: computed from the ABSOLUTE `time` below, before any
            // window-relative translation -- the live edge and `time` are both
            // expressed on the AVPlayerItem's own timeline, so subtracting a
            // window-relative position from an absolute edge would be
            // meaningless. See currentLiveEdgeOffsetMs(at:).
            let liveEdgeOffsetMs = self.currentLiveEdgeOffsetMs(at: time)

            if let window = self.currentLiveDvrWindow {
                // `time` is on the AVPlayerItem's own absolute timeline, the
                // same one `seekableTimeRanges` is expressed on -- NOT reset
                // to 0 at the window start, unlike ExoPlayer's
                // window-relative getCurrentPosition() on Android (see
                // MediaPlayerManager.kt's notifyDurationChanged doc). Translate
                // to window-relative here so `PlaybackState.position` and
                // `PlaybackState.duration` share the same zero point on both
                // platforms -- seekTo(position:) below applies the inverse
                // translation, so this pairing is self-consistent even though
                // it changes the "position" unit specifically for a live+DVR
                // item.
                let relativeSeconds = max(0, CMTimeGetSeconds(time) - CMTimeGetSeconds(window.start))
                self.notifyPositionChanged(
                    position: Int64(relativeSeconds * 1000),
                    // This branch IS the window-relative translation, so it is
                    // exactly the condition under which position stops being
                    // measured from a fixed zero point.
                    positionBasis: "liveWindow",
                    liveEdgeOffsetMs: liveEdgeOffsetMs
                )
            } else {
                self.notifyPositionChanged(
                    position: Int64(time.seconds * 1000),
                    positionBasis: "absolute",
                    liveEdgeOffsetMs: liveEdgeOffsetMs
                )
            }
        }

        // Status observer
        statusObserver = player.observe(\.status, options: [.new]) { [weak self] player, _ in
            self?.handleStatusChange(status: player.status)
        }

        // timeControlStatus observer for play/pause/buffering state (B-06).
        // `rate` alone cannot distinguish "user paused" from "stalled waiting
        // to play" — both report rate == 0. `timeControlStatus` can.
        timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            self?.handleTimeControlStatusChange(player: player)
        }

        // Audio session interruptions (phone calls, Siri, alarms, other apps
        // requesting the session) (B-06). Scoped to the shared instance,
        // same as every other consumer of this process-wide notification.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(notification:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )

        // Explicit stall signal (B-06). timeControlStatus normally already
        // reflects a stall via `.waitingToPlayAtSpecifiedRate`, but this
        // notification is delivered promptly and unambiguously the moment
        // AVFoundation detects an underrun, so it's kept as a belt-and-braces
        // "buffering" report alongside the KVO-driven one above. `object: nil`
        // + item-identity filtering follows the same B-02 convention as the
        // notifications immediately below.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidStall(notification:)),
            name: .AVPlayerItemPlaybackStalled,
            object: nil
        )

        // Notification observers.
        //
        // Registered with `object: nil` (rather than a specific `AVPlayerItem`)
        // because at this point in `initializeAVPlayer()` there is no
        // `currentItem` yet, and `loadMediaItem()` calls
        // `replaceCurrentItem(with:)` on every load — re-registering an
        // item-scoped observer per load would need to run in lockstep with
        // that replacement and is easy to get out of sync with (e.g. a
        // notification racing a re-registration). `object: nil` means these
        // fire for EVERY AVPlayerItem in the process, including ones owned by
        // other MediaPlayerInstance/MediaPlayerManager players — so the
        // handlers below filter by comparing the notification's item against
        // `avPlayer?.currentItem` at delivery time. This was previously
        // unguarded (B-02): one player's item finishing marked every live
        // player "completed", and one player's real failure was reported as
        // an error on every other player.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying(notification:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFailWithError(notification:)),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: nil
        )
    }

    /// Issue #87: the wire values of Dart's `StreamingFormat` enum, as sent
    /// in the `streamingFormat` key of the `mediaItem` payload
    /// (`MediaItem.streamingFormat?.name`). Modelled as a `String`-backed
    /// enum so an unknown/absent value decodes to `nil` and degrades to URL
    /// inference rather than failing.
    enum StreamingFormat: String {
        case hls
        case dash
        case progressive
    }

    /// Issue #87: resolves the streaming format of `mediaItem` — the explicit
    /// `streamingFormat` hint the Dart layer sends when present, otherwise
    /// inference from its URL. An absent/unknown hint falls back to
    /// inference, so an older Dart build that never sends the key behaves
    /// exactly as before.
    ///
    /// Mirrors `MediaItem.resolvedStreamingFormat` on the Dart side and
    /// `MediaPlayerManager.kt`'s `streamingFormatOf()` on Android — all
    /// three MUST stay in lockstep, since Dart decides
    /// `isSeekable`/`dvrEnabled` from its answer while native decides which
    /// of hlsConfig/dashConfig applies from this one.
    private func streamingFormat(of mediaItem: [String: Any]?) -> StreamingFormat {
        if let raw = (mediaItem?["streamingFormat"] as? String)?.lowercased(),
           let hinted = StreamingFormat(rawValue: raw) {
            return hinted
        }
        guard let urlString = mediaItem?["url"] as? String else { return .progressive }
        return inferStreamingFormat(from: urlString)
    }

    /// Issue #87: infers the streaming format from `urlString`'s PATH only —
    /// query string and fragment are stripped first, and the test is
    /// `hasSuffix` (case-insensitive), not `contains`. A signed URL such as
    /// `…/manifest.mpd?token=…` is therefore DASH, and a rewritten path such
    /// as `/hls.m3u8-archive/eu/manifest.mpd` is DASH rather than being
    /// captured by the HLS branch as it was before this fix. Never throws: an
    /// unparseable URL degrades to a plain truncation at the first `?`/`#`.
    private func inferStreamingFormat(from urlString: String) -> StreamingFormat {
        var path = URL(string: urlString)?.path ?? ""
        if path.isEmpty {
            path = urlString.components(separatedBy: "?")[0]
                .components(separatedBy: "#")[0]
        }
        let lowered = path.lowercased()
        if lowered.hasSuffix(".m3u8") { return .hls }
        if lowered.hasSuffix(".mpd") { return .dash }
        return .progressive
    }

    /// Wave D / issue #87: returns the top-level (per-player) HlsConfig/
    /// DashConfig map that applies to `mediaItem` — HlsConfig when its
    /// resolved format is HLS, DashConfig when it is DASH, `nil` for
    /// progressive media (which has no streaming config, and DASH itself has
    /// no iOS playback path at all). Configs are never cross-applied: a
    /// player configured with only `hlsConfig` that loads a DASH item gets
    /// `nil` here, exactly as if neither were configured (Dart emits a
    /// debug-only diagnostic for that case — see
    /// `MediaPlayer._warnMissingStreamingConfig`). Both are serialized
    /// unconditionally by MediaPlayer._configToMap on the Dart side (see
    /// streaming_config.dart's toMap()); this mirrors that same format ->
    /// config resolution on the Android side
    /// (MediaPlayerManager.kt's activeStreamingConfig).
    private func activeStreamingConfig(for mediaItem: [String: Any]?) -> [String: Any]? {
        guard let config = config else { return nil }
        switch streamingFormat(of: mediaItem) {
        case .hls:
            return config["hlsConfig"] as? [String: Any]
        case .dash:
            return config["dashConfig"] as? [String: Any]
        case .progressive:
            return nil
        }
    }

    /// Wave E (DVR window duration): whether DVR is enabled for the item
    /// currently loaded (`currentMediaItem`'s `url`), i.e.
    /// `HlsConfig.enableDvr`/`DashConfig.enableDvr` — whichever config
    /// applies, via `activeStreamingConfig(for:)`. Mirrors
    /// `MediaPlayerManager.kt`'s `currentDvrEnabled()` on Android exactly —
    /// see that method's doc.
    private var currentDvrEnabled: Bool {
        guard let mediaItem = currentMediaItem else { return false }
        let streamingConfig = activeStreamingConfig(for: mediaItem)
        return streamingConfig?["enableDvr"] as? Bool ?? false
    }

    /// The current `AVPlayerItem`'s live DVR seekable range, or `nil` when
    /// the loaded item isn't live, DVR isn't enabled for it, or nothing
    /// about the window is known yet (e.g. the playlist has only just
    /// loaded).
    ///
    /// `seekableTimeRanges` is AVFoundation's own notion of the currently
    /// known seekable span of a live item — the DVR window, buffer start to
    /// live edge — mirroring `MediaPlayerManager.kt`'s use of
    /// `Timeline.Window.durationUs` on Android for the same reason (see
    /// `notifyDurationChanged`'s Android counterpart for the full
    /// rationale, including why this is gated on DVR being enabled even
    /// though `seekableTimeRanges` itself is independent of that app
    /// config). Deliberately re-read on every access rather than cached: it
    /// can grow (or slide) across the lifetime of a live item as more of
    /// the window becomes available or older segments expire.
    ///
    /// `AVPlayerItem.duration` is `kCMTimeIndefinite` for a live item —
    /// that's why `itemDurationObserver`'s KVO never fires for one (see
    /// `loadMediaItem`) — `seekableTimeRanges` is the correct source for a
    /// live item's *known* span instead.
    private var currentLiveDvrWindow: CMTimeRange? {
        guard currentMediaItem?["isLive"] as? Bool ?? false, currentDvrEnabled else { return nil }
        guard let item = avPlayer?.currentItem,
              let range = item.seekableTimeRanges.last?.timeRangeValue,
              range.duration.isValid, !range.duration.isIndefinite,
              CMTimeGetSeconds(range.duration) > 0 else { return nil }
        return range
    }

    /// Reports the current live DVR window's length (see
    /// `currentLiveDvrWindow`) through the same `onDurationChanged` event
    /// `notifyDurationChanged` already uses for VOD, so
    /// `PlaybackState.duration` becomes the DVR window length instead of
    /// staying unknown for the lifetime of a live item — the bug this
    /// method exists to fix. A no-op when `currentLiveDvrWindow` is `nil`
    /// (not live, DVR not enabled, or nothing known yet) — the existing
    /// "duration stays unknown" behavior for that case, unchanged.
    ///
    /// Called on every periodic time-observer tick (`setupObservers`) as
    /// well as both `readyToPlay` transitions, since AVFoundation has no
    /// KVO notification for `seekableTimeRanges` changing, unlike
    /// `.duration`.
    private func checkLiveDvrWindowDuration() {
        guard let window = currentLiveDvrWindow else { return }
        let durationMs = Int64(CMTimeGetSeconds(window.duration) * 1000)
        notifyDurationChanged(duration: durationMs)
    }

    /// Issue #88 (no live-edge signal): how far behind the live edge the
    /// playhead is at `time`, in milliseconds, or `nil` when the question does
    /// not apply (VOD) or AVFoundation cannot answer it yet.
    ///
    /// Derived from `AVPlayerItem.seekableTimeRanges`: the live edge is the
    /// END of the last seekable range (`start + duration`), and the offset is
    /// that minus the item's current time. Both are on the AVPlayerItem's own
    /// absolute timeline, so the subtraction is well defined -- which is why
    /// this takes the raw observer `time` rather than the possibly
    /// window-relative value that gets reported as `position`.
    ///
    /// Two nearby AVFoundation properties were considered and rejected as the
    /// source, because neither answers "where is the playhead now":
    ///  - `AVPlayerItem.configuredTimeOffsetFromLive` is the offset the app
    ///    ASKED for (this plugin sets it from `HlsConfig/DashConfig.liveLatency`
    ///    -- see loadMediaItem), a target, not an observation.
    ///  - `AVPlayerItem.recommendedTimeOffsetFromLive` is the offset the
    ///    SERVER recommends for stable playback, likewise a target.
    /// Reporting either would make the value constant by construction and
    /// therefore useless as a stall signal -- precisely the defect this fixes.
    ///
    /// Deliberately NOT gated on `currentDvrEnabled`, unlike
    /// `currentLiveDvrWindow`: the DVR gate exists to avoid publishing a
    /// scrubbable range without matching seek permission, and that reasoning
    /// does not apply to a read-only health signal. A live stream without DVR
    /// gets this value too. It IS gated on the item being live at all
    /// (`currentMediaItem["isLive"]`), the same Dart-supplied source
    /// `notifyDurationChanged` already uses on iOS -- unlike Android, where
    /// ExoPlayer's `Timeline.Window.isLive()` provides manifest-derived
    /// detection that AVFoundation has no direct equivalent for.
    ///
    /// Clamped to >= 0: the playhead can transiently read a few milliseconds
    /// past the last observed edge between samples.
    private func currentLiveEdgeOffsetMs(at time: CMTime) -> Int64? {
        guard currentMediaItem?["isLive"] as? Bool ?? false else { return nil }
        guard let item = avPlayer?.currentItem,
              let range = item.seekableTimeRanges.last?.timeRangeValue,
              range.start.isValid, !range.start.isIndefinite,
              range.duration.isValid, !range.duration.isIndefinite,
              time.isValid, !time.isIndefinite else { return nil }

        let liveEdgeSeconds = CMTimeGetSeconds(range.start) + CMTimeGetSeconds(range.duration)
        let currentSeconds = CMTimeGetSeconds(time)
        guard liveEdgeSeconds.isFinite, currentSeconds.isFinite else { return nil }

        return Int64(max(0, liveEdgeSeconds - currentSeconds) * 1000)
    }

    /// Config staleness fix: `newConfig`, when present, is the current
    /// top-level (per-player) config snapshot from `MediaPlayer.load()` on
    /// the Dart side -- the same wire shape `initialize`/`updateConfig`
    /// already send (see `updateConfig(config:)`). Replaces `config`
    /// wholesale *before* any of the config-dependent work below runs
    /// (`activeStreamingConfig(for:)` for the `liveLatency`/`maxBitrate`
    /// wiring and the `autoPlay` read at the bottom of this method), so all
    /// of them see the item currently being loaded's actual config rather
    /// than whatever was current at `initializePlayer`/the last explicit
    /// `updateConfig(config:)` call. Mirrors
    /// `MediaPlayerManager.kt`'s `loadMediaItem` exactly, including NOT
    /// calling `applyConfig()` here -- see that method's doc for why
    /// (in short: `applyConfig()`'s `startMuted` write would silently undo
    /// a runtime `setMuted()` call, since `config`'s `startMuted` key is
    /// never kept in sync with it, unlike `volume`/`speed`/`boxFit`).
    /// Every Dart entry point that reaches this method now carries that
    /// snapshot: `load`, and -- as of the playlist-path fix -- `setPlaylist`
    /// and `skipToIndex` too (the latter being what `skipToNext`,
    /// `skipToPrevious` and playlist auto-advance funnel through).
    /// `newConfig` is therefore only `nil` when an older cached Dart build,
    /// predating that wiring, is talking to this native build; in that case
    /// `config` (whatever it already was) is left untouched, exactly as
    /// before.
    func loadMediaItem(mediaItem: [String: Any], newConfig: [String: Any]? = nil) {
        if let newConfig = newConfig {
            config = newConfig
        }

        guard let urlString = mediaItem["url"] as? String,
              let url = URL(string: urlString) else {
            notifyError(error: "Invalid media URL")
            return
        }

        // Store current media item (for live stream detection)
        currentMediaItem = mediaItem
        // Fresh item: nothing has been played to the end or stopped yet
        // (issue #79 -- see currentItemIsSpent).
        currentItemIsSpent = false

        // Reset access log event counter for new media
        previousAccessLogEventCount = 0

        zlog("MediaPlayerInstance.loadMediaItem(): Loading URL: \(redactedURL(urlString))")

        // Clear previous track data immediately to prevent stale UI
        notifyQualityTracksChanged(tracks: [])
        notifyAudioTracksChanged(tracks: [])
        notifySubtitleTracksChanged(tracks: [])

        // Note: No need to remove old observers - modern KVO (NSKeyValueObservation)
        // automatically cleans up when we invalidate or reassign the observer variables

        // Release any previous DRM handler before loading new media.
        drmHandler?.dispose()
        drmHandler = nil

        // Create AVURLAsset with custom headers / cookies if provided.
        var asset: AVURLAsset
        if let httpHeaders = mediaItem["httpHeaders"] as? [String: String] {
            var headerFields = httpHeaders
            var options: [String: Any] = [:]
            // Signed-cookie auth (e.g. CloudFront live/VOD): AVFoundation does NOT
            // reliably apply a custom "Cookie" HTTP header to every request the
            // AVPlayer makes — playlist refreshes and segment fetches run out of
            // process in mediaplaybackd and intermittently drop the header,
            // producing HTTP 403s (CoreMediaErrorDomain -12660), especially on long
            // or live streams. Forwarding the cookies via AVURLAssetHTTPCookiesKey
            // makes AVFoundation apply them to ALL requests.
            if let cookieHeader = httpHeaders["Cookie"], !cookieHeader.isEmpty {
                let host = url.host ?? ""
                var cookies: [HTTPCookie] = []
                for pair in cookieHeader.components(separatedBy: ";") {
                    let trimmed = pair.trimmingCharacters(in: .whitespaces)
                    guard let eq = trimmed.firstIndex(of: "="), !trimmed.isEmpty else { continue }
                    let name = String(trimmed[..<eq])
                    let value = String(trimmed[trimmed.index(after: eq)...])
                    if name.isEmpty { continue }
                    var props: [HTTPCookiePropertyKey: Any] = [
                        .name: name,
                        .value: value,
                        .domain: host,
                        .path: "/",
                        .version: "0",
                        .expires: Date(timeIntervalSinceNow: 6 * 3600),
                    ]
                    props[HTTPCookiePropertyKey("Secure")] = "TRUE"
                    if let cookie = HTTPCookie(properties: props) {
                        cookies.append(cookie)
                    } else {
                        zlog("MediaPlayerInstance: HTTPCookie construction failed for cookie \(name)")
                    }
                }
                if !cookies.isEmpty {
                    options["AVURLAssetHTTPCookiesKey"] = cookies
                    // Remove the Cookie HTTP header: when BOTH the header and the
                    // cookies key are set, AVFoundation prefers the header (which it
                    // drops on some out-of-process requests). Using only the cookies
                    // key applies the cookies to every request.
                    headerFields.removeValue(forKey: "Cookie")
                    zlog("MediaPlayerInstance: forwarding \(cookies.count) cookie(s) via AVURLAssetHTTPCookiesKey for host \(host)")
                }
            }
            if !headerFields.isEmpty {
                options["AVURLAssetHTTPHeaderFieldsKey"] = headerFields
            }
            asset = options.isEmpty ? AVURLAsset(url: url) : AVURLAsset(url: url, options: options)
        } else {
            asset = AVURLAsset(url: url)
        }

        // --- DRM wiring ---
        // If the media item carries a drmConfig, configure a DrmHandler and attach
        // the AVContentKeySession to the asset BEFORE creating the AVPlayerItem.
        // The AVContentKeySession MUST have the asset added as a recipient before
        // the item is created; otherwise the key request callback is never triggered.
        if let drmConfig = mediaItem["drmConfig"] as? [String: Any] {
            if #available(iOS 10.0, *), let player = avPlayer {
                zlog("MediaPlayerInstance.loadMediaItem(): DRM config found, initializing DrmHandler")
                let handler = DrmHandler(playerId: playerId, channel: methodChannel)
                let configured = handler.configure(drmConfig: drmConfig)
                if configured {
                    let session = handler.createContentKeySession(for: player)
                    // Register the asset as a content key recipient BEFORE creating AVPlayerItem.
                    session.addContentKeyRecipient(asset)
                    drmHandler = handler
                    zlog("MediaPlayerInstance.loadMediaItem(): DRM content key session configured")
                } else {
                    // Fail-closed (wave 2 security hardening, mirrors the equivalent
                    // fix in MediaPlayerManager.kt's loadMediaItem): a DRM-configured
                    // item whose DrmHandler.configure() rejected the config (missing
                    // license/certificate URL, unsupported scheme, etc.) must never
                    // fall back to unprotected playback. configure() has already
                    // called notifyDrmError() internally (emits
                    // onDrmSessionUpdate(state=error)), so the Dart-side
                    // errorStream/drmSessionStream already knows why. Refuse to
                    // create the AVPlayerItem at all and leave whatever was
                    // previously loaded untouched rather than silently playing this
                    // item unprotected.
                    zlog("MediaPlayerInstance.loadMediaItem(): DrmHandler.configure() failed - refusing to load DRM-configured media without protection")
                    currentMediaItem = nil
                    return
                }
            } else {
                // drmConfig was present but DRM cannot be enforced on this run —
                // either the AVContentKeySession API is unavailable (iOS < 10; the
                // package's own minimum is iOS 13, so this is effectively
                // unreachable but kept as a defensive fail-closed branch) or
                // `avPlayer` is nil (e.g. instance mid-teardown). Fail closed the
                // same way rather than silently falling through to unprotected
                // playback below.
                zlog("MediaPlayerInstance.loadMediaItem(): DRM config present but cannot be enforced (no AVContentKeySession support or no player) - refusing to load")
                notifyError(error: "DRM could not be enforced for this media item")
                currentMediaItem = nil
                return
            }
        }

        let playerItem = AVPlayerItem(asset: asset)

        // Wave D: HlsConfig/DashConfig wiring. Whichever config applies to
        // this item (HlsConfig when its resolved streaming format is HLS,
        // DashConfig when DASH — the item's explicit `streamingFormat` hint
        // if it carries one, else path-based inference) drives liveLatency
        // and maxBitrate below — see activeStreamingConfig(for:).
        let streamingConfig = activeStreamingConfig(for: mediaItem)

        // liveLatency -> configuredTimeOffsetFromLive. iOS 14+ only; on
        // earlier iOS this API does not exist, so liveLatency silently has
        // no effect there (the package's minimum is iOS 13 — see
        // HlsConfig.liveLatency's dartdoc).
        if let liveLatencyMs = (streamingConfig?["liveLatencyMs"] as? NSNumber)?.doubleValue {
            if #available(iOS 14.0, *) {
                playerItem.automaticallyPreservesTimeOffsetFromLive = false
                playerItem.configuredTimeOffsetFromLive = CMTime(
                    seconds: liveLatencyMs / 1000.0,
                    preferredTimescale: CMTimeScale(NSEC_PER_SEC)
                )
            }
        }

        // maxBitrate -> preferredPeakBitRate (bits/sec). There is no
        // faithful minBitrate, nor a way to force a single non-adaptive
        // track (enableAdaptiveBitrate: false), on AVPlayer — see
        // StreamingConfig's dartdoc for the full platform-parity notes. A
        // later explicit setQualityTrack()/enableAutoQuality() call
        // overrides this the same way it already overrides any other
        // preferredPeakBitRate value.
        if let maxBitrate = (streamingConfig?["maxBitrate"] as? NSNumber)?.doubleValue {
            playerItem.preferredPeakBitRate = maxBitrate
        }

        // Apply buffer configuration if available.
        //
        // Only `targetBufferMs` maps onto a real AVFoundation knob
        // (`preferredForwardBufferDuration` — a hint for how far ahead of
        // the playhead to buffer). `minBufferMs`, `maxBufferMs` and
        // `rebufferMs` — which Android's ExoPlayer-backed
        // `BufferingHandler.createFromDartConfig` honours in full via
        // `DefaultLoadControl.setBufferDurationsMs` — have no AVFoundation
        // equivalent: there is no API to require a minimum buffer before
        // starting playback, cap a maximum buffer, or set a distinct
        // resume-after-stall threshold. `AVPlayer` manages that internally
        // and does not expose it for tuning. See the file-level comment in
        // `BufferingHandler.swift` (M-17) for the full platform-parity
        // rationale. 15000ms mirrors `BufferingConfig.defaultConfig()`'s
        // `targetBufferMs` on the Dart side.
        if let bufferConfig = config?["bufferConfig"] as? [String: Any] {
            playerItem.preferredForwardBufferDuration = TimeInterval((bufferConfig["targetBufferMs"] as? Int ?? 15000)) / 1000.0
        }

        // Clean up previous observers (modern KVO auto-invalidates, no exceptions)
        itemDurationObserver?.invalidate()
        itemStatusObserver?.invalidate()

        // Add modern KVO observers (safe, auto-cleanup on dealloc)
        itemDurationObserver = playerItem.observe(\.duration, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            let duration = item.duration
            if duration.isNumeric && !duration.isIndefinite {
                let durationMs = Int64(CMTimeGetSeconds(duration) * 1000)
                self.notifyDurationChanged(duration: durationMs)
            }
        }

        itemStatusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            self.handlePlayerItemStatusChange(status: item.status, item: item)
        }

        // Ensure we're on main thread for player operations
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Notify buffering state when starting to load
            self.notifyStateChanged(state: "buffering", isBuffering: true)

            self.avPlayer?.replaceCurrentItem(with: playerItem)

            zlog("MediaPlayerInstance.loadMediaItem(): Item replaced, player: \(self.avPlayer != nil)")

            // Re-bind ONLY the topmost live view to the (new) current item;
            // every other view stays unbound (single-layer-per-player rule).
            let liveCount = self.playerViews.filter { $0.view != nil }.count
            if liveCount > 0 {
                zlog("MediaPlayerInstance.loadMediaItem(): Re-activating topmost of \(liveCount) live view(s)")
                self.activateTopmostView()
            } else {
                zlog("MediaPlayerInstance.loadMediaItem(): No player views exist yet")
            }

            // Auto play if configured. Route through play() (not a bare
            // avPlayer?.play()) so autoplay honours the requested speed and
            // configures the audio session the same way an explicit play() would.
            if self.config?["autoPlay"] as? Bool == true {
                zlog("MediaPlayerInstance.loadMediaItem(): Auto-playing")
                self.play()
            }
        }
    }

    /// True when `candidate` is, key for key, the item this instance already
    /// has loaded (`currentMediaItem`) AND that item is still live in the
    /// player (ready, not stopped, not finished) -- i.e. there is real
    /// in-progress playback that a reload would destroy.
    ///
    /// Mirrors `MediaPlayerManager.kt`'s `isAlreadyLoadedAndInProgress`
    /// exactly, including WHY the comparison is whole-dictionary structural
    /// equality rather than an `id` check (issue #79):
    ///
    ///  - An `id` match is not sufficient. A consumer may legitimately
    ///    re-issue the same `id` *expecting* a real reload: refreshed
    ///    signed-cookie / `Authorization` values in `httpHeaders`, a rotated
    ///    token or rotated `headers` inside `drmConfig`, or a re-signed `url`
    ///    for the same logical episode. Each of those changes some key of
    ///    this dictionary, so whole-dictionary equality lets them through as
    ///    the genuine reloads they are -- and it covers every key
    ///    `loadMediaItem` reads (`url`, `httpHeaders`, `drmConfig`) plus
    ///    `isLive`, without an enumerated list that could go stale.
    ///  - An `id` match is not necessary either, and a missing/null `id` must
    ///    never be self-identifying: two items are not "the same item" merely
    ///    by virtue of both being anonymous. Under whole-dictionary equality
    ///    a missing `id` only ever matches another missing `id` while the
    ///    rest of the dictionary still has to match -- and the `url` guard
    ///    below keeps that "rest" anchored on real content, since
    ///    `loadMediaItem` returns before assigning `currentMediaItem` when
    ///    `url` is absent.
    ///
    /// Note that the *config* plays no part in this comparison: a changed
    /// per-player config never by itself makes an unchanged item "different"
    /// and so never forces a reload (see `setPlaylist`).
    ///
    /// `[String: Any]` is not `Equatable` in Swift, so the comparison goes
    /// through `NSDictionary.isEqual(to:)`, which is a deep, structural
    /// compare over the `NSString`/`NSNumber`/`NSNull`/`NSArray`/
    /// `NSDictionary` values Flutter's `StandardMessageCodec` produces --
    /// the same semantics Kotlin's `Map.equals` gives on Android.
    ///
    /// The playback-state condition is where the two platforms have to
    /// differ in mechanism while matching in meaning: ExoPlayer exposes
    /// `STATE_IDLE` after a `stop()` and `STATE_ENDED` after an item
    /// finishes, but `AVPlayer` keeps a stopped and a finished item alike at
    /// `.readyToPlay`, so it cannot distinguish either from live playback.
    /// `currentItemIsSpent` is the flag this class maintains to close that
    /// gap; when it is set there is nothing in progress to preserve and the
    /// caller means "start this", so we fall through to a normal reload.
    private func isAlreadyLoadedAndInProgress(_ candidate: [String: Any]) -> Bool {
        guard let loaded = currentMediaItem else { return false }
        guard candidate["url"] as? String != nil else { return false }
        guard let item = avPlayer?.currentItem, item.status == .readyToPlay else { return false }
        guard !currentItemIsSpent else { return false }

        return (candidate as NSDictionary).isEqual(to: loaded)
    }

    /// Re-emits the events a load would have produced, for the case where
    /// `setPlaylist` skipped the load because the target item is already
    /// playing (issue #79). Mirrors `MediaPlayerManager.kt`'s
    /// `notifyCurrentStateAfterSkippedLoad`.
    ///
    /// The Dart side's `setPlaylist()` historically assumed a load always
    /// follows: it clears its cached quality/audio/subtitle track lists and
    /// moves to `buffering`, then waits for native to repopulate them.
    /// `MediaPlayer._isPlaylistReloadSkipped` now mirrors the guard above and
    /// skips that reset when it can tell the item is unchanged, but the two
    /// comparisons are made independently on either side of the channel -- so
    /// this re-emit is the safety net that keeps Dart coherent if they ever
    /// disagree (an older cached Dart build talking to a newer native build,
    /// most obviously). Sends current playback state, current duration and
    /// the current track lists: everything a consumer could be waiting on
    /// after a `setPlaylist` call.
    ///
    /// Deliberately does not touch playback itself -- position, rate and the
    /// play/pause state are exactly what the skipped reload was protecting.
    private func notifyCurrentStateAfterSkippedLoad() {
        guard let player = avPlayer else { return }

        // Reuses the same state derivation the KVO observer uses, so a
        // re-sync reports exactly what a genuine transition would have.
        handleTimeControlStatusChange(player: player)
        notifyDurationChanged()
        checkLiveDvrWindowDuration()
        extractAndNotifyQualityTracks()
        extractAndNotifyAudioTracks()
        extractAndNotifySubtitleTracks()
    }

    /// Declares (or refreshes) the native playlist, points it at
    /// `startIndex`, and loads that item -- unless it is already the item
    /// playing right now. Mirrors `MediaPlayerManager.kt`'s `setPlaylist`
    /// exactly.
    ///
    /// Config staleness fix (playlist path): `newConfig`, when present, is
    /// the current top-level (per-player) config snapshot sent by
    /// `MediaPlayer.setPlaylist()` on the Dart side -- the same wire shape
    /// `initialize`/`updateConfig`/`load` already send. It replaces `config`
    /// wholesale *before* any config-dependent work runs (see the inline
    /// comment below), and is forwarded to
    /// `loadMediaItem(mediaItem:newConfig:)`, which -- exactly as on the
    /// `load` path -- deliberately does NOT call `applyConfig()`: see that
    /// method's doc for why reapplying `startMuted` on every item load would
    /// undo a runtime `setMuted()` call. It is `nil` when an older cached
    /// Dart build (sending only playerId/playlist/startIndex) is talking to
    /// this native build; in that case `config` is left untouched, exactly
    /// as before that fix.
    ///
    /// Issue #79: the playlist contents and the position pointer ALWAYS
    /// refresh -- that is the whole point of re-issuing a playlist (extending
    /// a sliding window, changing `mode`/`repeatMode`). Only the *load* is
    /// conditional: when the item at `startIndex` is byte-for-byte the item
    /// already loaded and genuinely in progress
    /// (`isAlreadyLoadedAndInProgress`), playback is left running untouched
    /// and Dart is re-synced through `notifyCurrentStateAfterSkippedLoad`
    /// instead of being restarted.
    ///
    /// The two behaviours compose deliberately: storing `newConfig` never by
    /// itself forces a reload. A `setPlaylist` that carries a *changed*
    /// config for an unchanged, in-progress item stores that config -- so the
    /// next real load (a skip, an auto-advance, an explicit `load`) uses it
    /// -- but does NOT restart the item under the viewer. `updateConfig` is
    /// the API for applying config to live playback immediately; `load` is
    /// the API for applying it *and* reloading.
    func setPlaylist(playlist: [String: Any], startIndex: Int, newConfig: [String: Any]? = nil) {
        // Replace the stored config first, unconditionally, so it is in
        // place before ANY config-dependent work below -- including the
        // early-return paths (malformed/empty payload) and the issue-#79
        // skip path, where silently dropping the caller's freshest snapshot
        // would reintroduce exactly the staleness this fix exists to remove.
        // `loadMediaItem` performs the same replacement itself from
        // `newConfig` (that is where the contract is documented); doing it
        // here too is an idempotent no-op on the normal path, not a second,
        // divergent way to apply config.
        // Mirrors `MediaPlayerManager.kt`'s `setPlaylist`.
        if let newConfig = newConfig {
            config = newConfig
        }

        guard let items = playlist["items"] as? [[String: Any]] else { return }

        // The playlist contents and the position pointer ALWAYS refresh --
        // that is the whole point of re-issuing a playlist (extending the
        // window, changing mode/repeatMode). Only the load below is
        // conditional (issue #79).
        currentPlaylist = items
        currentIndex = max(0, min(startIndex, items.count - 1))

        guard !items.isEmpty else { return }

        let target = items[currentIndex]
        if isAlreadyLoadedAndInProgress(target) {
            zlog("MediaPlayerInstance.setPlaylist(): item at index \(currentIndex) is already loaded and playing - keeping playback and re-syncing Dart state instead of reloading")
            notifyCurrentStateAfterSkippedLoad()
            return
        }

        loadMediaItem(mediaItem: target, newConfig: newConfig)
    }

    func play() {
        // Request the shared audio session via AudioSessionCoordinator rather
        // than activating it directly (B-05). This still results in audio
        // playing with the ring/silent switch on and continuing in the
        // background (the host app declares UIBackgroundModes: audio) when
        // this instance is audible — but a muted/silent instance (e.g. an
        // autoplaying preview) will only request `.mixWithOthers`, so it does
        // not steal audio focus from another app (e.g. Spotify).
        audioSessionRequested = true
        AudioSessionCoordinator.shared.requestActive(for: self, audible: isCurrentlyAudible())

        guard let player = avPlayer else { return }
        // Playback is being (re)started -- the item is in progress again
        // (issue #79 -- see currentItemIsSpent).
        currentItemIsSpent = false
        if #available(iOS 16.0, *) {
            player.defaultRate = requestedSpeed
            player.play()                      // plays at defaultRate
        } else {
            // Pre-16 has no defaultRate: assigning `rate` is the only way to
            // start at a non-default speed, and here starting IS the intent.
            player.rate = requestedSpeed
        }
    }

    func pause() {
        avPlayer?.pause()
        // Explicit user/app pause — release the audio-session slot (B-05).
        // Deliberately NOT tied to timeControlStatus/rate transitions: a
        // transient stall or an OS interruption also drives rate to 0 and
        // must NOT release this instance's slot (that would let the session
        // be torn down mid-stall, or race the interruption's own recovery).
        audioSessionRequested = false
        AudioSessionCoordinator.shared.release(for: self)
    }

    func stop() {
        avPlayer?.pause()
        avPlayer?.seek(to: .zero)
        // Mirrors Android, where stop() clears ExoPlayer's media items and
        // leaves it in STATE_IDLE: after a stop there is no in-progress
        // playback for setPlaylist's issue-#79 guard to protect, so a
        // subsequent setPlaylist naming this same item must reload it.
        currentItemIsSpent = true
        audioSessionRequested = false
        AudioSessionCoordinator.shared.release(for: self)
    }

    func seekTo(position: Int64) {
        // Seeking moves the playhead back inside the item, so a previously
        // finished/stopped item is in progress again (issue #79 -- see
        // currentItemIsSpent).
        currentItemIsSpent = false

        // Wave E (DVR window duration): for a live item with DVR enabled,
        // `position` (from Dart) is window-relative -- see the periodic
        // time-observer doc in setupObservers() for why. Translate back to
        // the AVPlayerItem's own absolute timeline before seeking, and clamp
        // to the currently known window so a stale/out-of-range position
        // (e.g. captured just before the window slid forward) cannot seek
        // outside the available range. Every other case (VOD, or live
        // without DVR -- which MediaPlayer.seekTo already rejects before
        // this is ever reached, see media_player.dart's isSeekable guard)
        // is unaffected: `position` is already the correct absolute time.
        if let window = currentLiveDvrWindow {
            let requestedSeconds = CMTimeGetSeconds(window.start) + Double(position) / 1000.0
            let clampedSeconds = min(
                max(requestedSeconds, CMTimeGetSeconds(window.start)),
                CMTimeGetSeconds(window.end)
            )
            let time = CMTime(seconds: clampedSeconds, preferredTimescale: 1000)
            avPlayer?.seek(to: time)
            return
        }

        let time = CMTime(value: position, timescale: 1000) // position in milliseconds
        avPlayer?.seek(to: time)
    }

    func setVolume(volume: Float) {
        avPlayer?.volume = max(0.0, min(1.0, volume))
        // Audibility may have just changed while playing (e.g. fading a
        // preview up from 0) — refresh the session request so the aggregate
        // policy (exclusive vs mixWithOthers) is recomputed (B-05).
        if audioSessionRequested {
            AudioSessionCoordinator.shared.requestActive(for: self, audible: isCurrentlyAudible())
        }
    }

    /// Whether this instance's output is actually audible right now: not
    /// muted and volume above zero. Drives whether `AudioSessionCoordinator`
    /// must activate the shared session exclusively (interrupting other
    /// apps) or merely keep it alive via `.mixWithOthers` (B-05).
    private func isCurrentlyAudible() -> Bool {
        guard let player = avPlayer else { return false }
        return !player.isMuted && player.volume > 0
    }

    func setPlaybackSpeed(speed: Float) {
        let clamped = max(0.25, min(4.0, speed))
        requestedSpeed = clamped

        guard let player = avPlayer else { return }

        // iOS 16+: `defaultRate` is the rate `play()` will use. Setting it never
        // starts playback, which is precisely the separation this bug needs.
        if #available(iOS 16.0, *) {
            player.defaultRate = clamped
        }

        // Only touch `rate` when the player is already in a playing state.
        // `.waitingToPlayAtSpecifiedRate` counts: playback has been requested and
        // is merely stalled, so a speed change should apply to it.
        if player.timeControlStatus != .paused {
            player.rate = clamped
        }
    }

    func setMuted(muted: Bool) {
        avPlayer?.isMuted = muted
        // See setVolume() — muting/unmuting mid-playback changes audibility
        // and must be reflected in the aggregate session policy (B-05).
        if audioSessionRequested {
            AudioSessionCoordinator.shared.requestActive(for: self, audible: isCurrentlyAudible())
        }
    }

    func setBoxFit(boxFit: String) {
        forEachLiveView { $0.setVideoGravity(boxFit: boxFit) }
    }

    func setSubtitleTrack(subtitleTrack: [String: Any]?) {
        guard let playerItem = avPlayer?.currentItem,
              let asset = playerItem.asset as? AVURLAsset else {
            zlog("MediaPlayerInstance: Cannot set subtitle track - no player item or not AVURLAsset")
            return
        }

        // Get subtitle selection group
        guard let subtitleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else {
            zlog("MediaPlayerInstance: No subtitle selection group found")
            return
        }

        // If nil, disable subtitles
        if subtitleTrack == nil {
            zlog("MediaPlayerInstance: Disabling subtitles")
            playerItem.select(nil, in: subtitleGroup)
            return
        }

        guard let trackId = subtitleTrack?["id"] as? String else {
            zlog("MediaPlayerInstance: Invalid subtitle track data - no id")
            return
        }

        zlog("MediaPlayerInstance: Setting subtitle track: \(subtitleTrack?["title"] ?? "unknown"), id: \(trackId)")

        // Find the matching option
        var targetOption: AVMediaSelectionOption?

        for option in subtitleGroup.options {
            let optionId = option.displayName.isEmpty ? "subtitle_\(subtitleGroup.options.firstIndex(of: option) ?? 0)" : option.displayName
            if optionId == trackId {
                targetOption = option
                break
            }
        }

        if let option = targetOption {
            zlog("MediaPlayerInstance: Subtitle track found, selecting")
            playerItem.select(option, in: subtitleGroup)
        } else {
            zlog("MediaPlayerInstance: Subtitle track not found: \(trackId)")
        }
    }

    func setQualityTrack(qualityTrack: [String: Any]) {
        guard let bitrate = qualityTrack["bitrate"] as? Int,
              let name = qualityTrack["name"] as? String else {
            zlog("MediaPlayerInstance: Invalid quality track data")
            return
        }

        zlog("MediaPlayerInstance: Setting quality track: \(name), bitrate: \(bitrate)")

        // Set preferred peak bitrate to limit maximum quality
        // AVPlayer will select the best track that doesn't exceed this bitrate
        avPlayer?.currentItem?.preferredPeakBitRate = Double(bitrate)

        zlog("MediaPlayerInstance: Quality track set with preferredPeakBitRate: \(bitrate)")
    }

    func setAudioTrack(audioTrack: [String: Any]) {
        guard let playerItem = avPlayer?.currentItem,
              let asset = playerItem.asset as? AVURLAsset else {
            zlog("MediaPlayerInstance: Cannot set audio track - no player item or not AVURLAsset")
            return
        }

        // Get audio selection group
        guard let audioGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else {
            zlog("MediaPlayerInstance: No audio selection group found")
            return
        }

        guard let trackId = audioTrack["id"] as? String else {
            zlog("MediaPlayerInstance: Invalid audio track data - no id")
            return
        }

        zlog("MediaPlayerInstance: Setting audio track: \(audioTrack["name"] ?? "unknown"), id: \(trackId)")

        // Find the matching option
        var targetOption: AVMediaSelectionOption?

        for option in audioGroup.options {
            let optionId = option.displayName.isEmpty ? "audio_\(audioGroup.options.firstIndex(of: option) ?? 0)" : option.displayName
            if optionId == trackId {
                targetOption = option
                break
            }
        }

        if let option = targetOption {
            zlog("MediaPlayerInstance: Audio track found, selecting")
            playerItem.select(option, in: audioGroup)
        } else {
            zlog("MediaPlayerInstance: Audio track not found: \(trackId)")
        }
    }

    func enableAutoQuality() {
        zlog("MediaPlayerInstance: Enabling auto quality (ABR)")

        // Clear preferred peak bitrate to enable full adaptive bitrate
        avPlayer?.currentItem?.preferredPeakBitRate = 0

        zlog("MediaPlayerInstance: Auto quality enabled - preferredPeakBitRate cleared")
    }

    /// Restarts playback at `index` -- including when `index` is the index
    /// already playing. Mirrors `MediaPlayerManager.kt`'s `skipToIndex`.
    ///
    /// Config staleness fix (playlist path): `newConfig` carries the current
    /// config snapshot sent by `MediaPlayer.skipToIndex()` on the Dart side
    /// (which is also what `skipToNext`/`skipToPrevious`/playlist
    /// auto-advance route through) and is forwarded to
    /// `loadMediaItem(mediaItem:newConfig:)` on exactly the same terms as
    /// `setPlaylist` -- see that method's and `loadMediaItem`'s docs. `nil`
    /// from an older cached Dart build leaves `config` untouched.
    ///
    /// Issue #79: this method deliberately does NOT carry the "already
    /// loaded, skip the reload" guard `setPlaylist` gained, even when `index`
    /// is the current index.
    ///
    /// The two methods mean different things. `setPlaylist` declares or
    /// refreshes the queue, and "the item at startIndex happens to be the one
    /// playing" is incidental to that. `skipToIndex` means "(re)start the
    /// item at this index" -- and skipping to the index you are already on is
    /// a documented restart. Dart depends on exactly that:
    /// `Playlist.nextIndex` returns `currentIndex` under
    /// `MediaRepeatMode.single` (and under `MediaRepeatMode.all` for a
    /// single-item playlist), and `MediaPlayer._handlePlaybackCompleted`
    /// implements repeat-one by calling `skipToIndex(nextIndex)` on
    /// completion. Guarding this method would silently break repeat-one, and
    /// would also break the plain "replay the item I just finished" case.
    ///
    /// `skipToNext`/`skipToPrevious` are Dart-side wrappers over this method
    /// and inherit the same semantics.
    func skipToIndex(index: Int, newConfig: [String: Any]? = nil) {
        guard let playlist = currentPlaylist,
              index >= 0 && index < playlist.count else { return }

        currentIndex = index
        loadMediaItem(mediaItem: playlist[index], newConfig: newConfig)
    }

    /// Config staleness fix: shares one source of truth with the `newConfig`
    /// parameter `loadMediaItem(mediaItem:newConfig:)` now also accepts (see
    /// that method's doc) -- both simply overwrite `config` wholesale.
    /// There is nothing to reconcile between "the config sent with the last
    /// `load()`" and "the config sent via the last explicit
    /// `updateConfig()` call": whichever happened most recently is what
    /// `config` holds, exactly mirroring the Dart-side `MediaPlayer._config`
    /// field both wire payloads are serialized from. Unlike
    /// `loadMediaItem`, this DOES call `applyConfig()` -- an explicit
    /// `updateConfig()` call is exactly the "intentional config change,
    /// apply it now" case `loadMediaItem`'s doc says it deliberately avoids.
    func updateConfig(config: [String: Any]) {
        self.config = config
        applyConfig()
    }

    /// Creates a NEW MediaPlayerView for each UiKitView host.
    /// Only the platform-view factory should call this method.
    /// All other code that needs the active layer must use currentPlayerLayer().
    func getPlayerView() -> MediaPlayerView {
        zlog("MediaPlayerInstance.getPlayerView(): Creating new player view with player: \(avPlayer != nil), has item: \(avPlayer?.currentItem != nil)")
        let newView = MediaPlayerView(player: avPlayer)

        // Promote the next-topmost view when this host is torn down so the
        // shared AVPlayer never ends up without a bound layer (grey surface).
        newView.onDeinit = { [weak self] in
            guard let self = self else { return }
            if Thread.isMainThread {
                self.activateTopmostView()
            } else {
                DispatchQueue.main.async { self.activateTopmostView() }
            }
        }

        // Track weakly — Flutter (UiKitView host) owns the strong reference.
        playerViews.append(WeakPlayerView(view: newView))

        // The freshly-created host is now the topmost: bind the shared AVPlayer
        // to it and unbind every other live view (single-layer-per-player).
        // Deferred a frame so the UiKitView is laid out before the first bind.
        DispatchQueue.main.async { [weak self] in
            self?.activateTopmostView()
        }

        return newView
    }

    /// Returns the AVPlayerLayer of the active (most recently mounted) view,
    /// WITHOUT creating a new view.  Used by PiP/AirPlay/getPlayerLayer paths.
    func currentPlayerLayer() -> AVPlayerLayer? {
        return activePlayerView?.playerLayer
    }

    // Phase 3: Helper to expose AVPlayer for PiP and AirPlay
    func getAVPlayer() -> AVPlayer? {
        return avPlayer
    }

    func isPlaying() -> Bool {
        guard let player = avPlayer else { return false }
        return player.timeControlStatus != .paused
    }

    func getBufferHealth() -> [String: Any] {
        return BufferingHandler.getBufferHealth(from: avPlayer)
    }

    private func startBandwidthMonitoring() {
        // Start a timer that monitors bandwidth every 2 seconds
        bandwidthTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateBandwidth()
        }
    }

    private func stopBandwidthMonitoring() {
        bandwidthTimer?.invalidate()
        bandwidthTimer = nil
    }

    private func updateBandwidth() {
        guard let playerItem = avPlayer?.currentItem,
              let accessLog = playerItem.accessLog() else { return }

        let currentEventCount = accessLog.events.count

        // Get the most recent access log event
        if let lastEvent = accessLog.events.last {
            // observedBitrate is in bits per second
            let bandwidth = Int64(lastEvent.observedBitrate)

            // Only report if we have a valid bandwidth estimate
            if bandwidth > 0 {
                notifyBandwidthChanged(bandwidth: bandwidth)
            }

            // If new events were added (indicates bitrate switch), re-extract quality tracks
            if currentEventCount > previousAccessLogEventCount {
                zlog("MediaPlayerInstance: New access log events detected (\(previousAccessLogEventCount) -> \(currentEventCount)), re-extracting quality tracks")
                extractAndNotifyQualityTracks()
                previousAccessLogEventCount = currentEventCount
            }
        }
    }

    func dispose() {
        // Stop bandwidth monitoring
        stopBandwidthMonitoring()

        // Release this instance's audio-session slot (B-05). Must run
        // regardless of whether audioSessionRequested was true — release()
        // is a no-op if this instance never requested activation, and is
        // idempotent, so it's always safe to call on teardown.
        audioSessionRequested = false
        AudioSessionCoordinator.shared.release(for: self)

        // Remove time observer
        if let observer = timeObserver, let player = avPlayer {
            player.removeTimeObserver(observer)
            timeObserver = nil  // Set to nil after removal
        }

        // Remove KVO observers
        statusObserver?.invalidate()
        statusObserver = nil
        timeControlStatusObserver?.invalidate()
        timeControlStatusObserver = nil

        // Remove player item observers (modern KVO auto-cleanup)
        itemDurationObserver?.invalidate()
        itemDurationObserver = nil
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil

        NotificationCenter.default.removeObserver(self)

        // Clean up player
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)

        // Release DRM resources.
        drmHandler?.dispose()
        drmHandler = nil

        // Clear references
        currentMediaItem = nil
        avPlayer = nil
        playerViews.removeAll()
    }

    private func applyConfig() {
        guard let player = avPlayer, let config = config else { return }

        // Apply volume
        if let volume = config["volume"] as? Double {
            player.volume = Float(volume)
        }

        // Apply muted state
        if let startMuted = config["startMuted"] as? Bool {
            player.isMuted = startMuted
        }

        // Apply playback speed. MUST go through setPlaybackSpeed — assigning
        // `player.rate` here started playback on every initialize, defeating autoPlay.
        if let speed = config["speed"] as? Double {
            setPlaybackSpeed(speed: Float(speed))
        }

        // Apply BoxFit to all live views
        if let boxFit = config["boxFit"] as? String {
            forEachLiveView { $0.setVideoGravity(boxFit: boxFit) }
        }

        // NOTE (B-05): This used to unconditionally call
        // AVAudioSession.setActive(true) here — i.e. merely INITIALIZING a
        // player configured for background playback seized the process-wide
        // audio session and interrupted whatever else was playing, even if
        // this player never played anything. Session activation is now only
        // ever requested through AudioSessionCoordinator from play() (and
        // kept in sync by setVolume/setMuted), which happens when playback
        // actually starts. Background continuation via UIBackgroundModes:
        // audio still works: play() activates the same `.playback` category
        // before the app can be backgrounded, and the category/activation
        // persists until pause()/stop()/dispose() releases it.
    }

    private func handleStatusChange(status: AVPlayer.Status) {
        switch status {
        case .unknown:
            notifyStateChanged(state: "idle", isBuffering: false)
        case .readyToPlay:
            zlog("MediaPlayerInstance: Player status changed to readyToPlay")
            notifyStateChanged(state: "ready", isBuffering: false)
            notifyDurationChanged()
            checkLiveDvrWindowDuration()

            // Re-bind only the topmost live view when ready (others stay
            // unbound to avoid multiple layers on one AVPlayer → grey).
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                zlog("MediaPlayerInstance: Re-activating topmost live view on ready state")
                self.activateTopmostView()
            }
        case .failed:
            let nsError = avPlayer?.error as NSError?
            zlog("MediaPlayerInstance: Player failed with error: \(nsError?.localizedDescription ?? "Unknown")")
            if let nsError = nsError {
                let (category, httpStatusCode) = categorizeFailure(nsError, item: avPlayer?.currentItem)
                notifyError(
                    error: nsError.localizedDescription,
                    category: category,
                    nativeErrorCode: nsError.code,
                    httpStatusCode: httpStatusCode
                )
            } else {
                notifyError(error: "Unknown error")
            }
        @unknown default:
            break
        }
    }

    /// Replaces the old bare-`rate` observer (B-06). `rate == 0` is
    /// ambiguous: it means both "user paused" AND "stalled, waiting to
    /// resume at the requested rate". `timeControlStatus` disambiguates:
    /// `.waitingToPlayAtSpecifiedRate` means playback was requested and is
    /// merely stalled — that must surface to Dart as `buffering`, not
    /// `paused`, or a mid-playback rebuffer looks indistinguishable from the
    /// user tapping pause.
    private func handleTimeControlStatusChange(player: AVPlayer) {
        switch player.timeControlStatus {
        case .playing:
            notifyStateChanged(state: "playing", isBuffering: false)

        case .paused:
            notifyStateChanged(state: "paused", isBuffering: false)

        case .waitingToPlayAtSpecifiedRate:
            // `reasonForWaitingToPlay` further distinguishes a real
            // buffering wait from other wait reasons AVFoundation may
            // report; treat anything that isn't explicitly "no item" as a
            // buffering condition worth surfacing, since the most common
            // case by far is network-driven stalling.
            if player.reasonForWaitingToPlay == .noItemToPlay {
                notifyStateChanged(state: "idle", isBuffering: false)
            } else {
                notifyStateChanged(state: "buffering", isBuffering: true)
            }

        @unknown default:
            break
        }
    }

    /// Handles `AVAudioSession.interruptionNotification` (B-06): phone
    /// calls, Siri, alarms, or another app requesting the audio session all
    /// deliver this. This notification is process-wide (there is one shared
    /// `AVAudioSession`), so every live `MediaPlayerInstance` receives every
    /// interruption — each instance independently tracks and reacts based on
    /// its OWN play state, which is correct: an interruption should pause
    /// (and potentially later resume) every currently-playing instance, not
    /// just one.
    ///
    /// NEEDS ON-DEVICE VERIFICATION: interruption delivery/timing (phone
    /// calls, Siri, alarms) cannot be exercised in a simulator/unit-test
    /// environment.
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            zlog("MediaPlayerInstance: Audio session interruption began (playerId: \(playerId))")
            // The system silences/pauses playback itself; timeControlStatus
            // will transition to .paused and the observer above already
            // reports that to Dart via the existing notifyStateChanged path
            // — no separate "interrupted" state exists in the Dart model, and
            // "paused" is the correct, honest description of what the user
            // sees. What we additionally need is whether THIS instance was
            // actually playing, to decide on resumption below.
            wasPlayingBeforeInterruption = (avPlayer?.timeControlStatus == .playing
                || avPlayer?.timeControlStatus == .waitingToPlayAtSpecifiedRate)
            // The OS revokes activation for the whole process on .began, not
            // just this instance's slot — clear the local bookkeeping so a
            // subsequent pause()/dispose() doesn't try to "release" a
            // request the coordinator no longer considers active, and so a
            // resume in .ended goes through the normal play() path (which
            // re-requests activation) rather than assuming it's still held.
            audioSessionRequested = false

        case .ended:
            var shouldResume = false
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
            }

            zlog("MediaPlayerInstance: Audio session interruption ended (playerId: \(playerId), wasPlaying: \(wasPlayingBeforeInterruption), shouldResume: \(shouldResume))")

            if wasPlayingBeforeInterruption && shouldResume {
                // Route through play() (not a bare avPlayer?.play()) so the
                // resume re-requests the audio session via
                // AudioSessionCoordinator and re-applies requestedSpeed,
                // exactly like a fresh user-initiated play().
                DispatchQueue.main.async { [weak self] in
                    self?.play()
                }
            }
            wasPlayingBeforeInterruption = false

        @unknown default:
            break
        }
    }

    /// Handles `AVPlayerItemPlaybackStalled` (B-06) — see the comment where
    /// this is registered in `setupObservers()`. Follows the same B-02
    /// item-identity filtering as the notifications below, since this is
    /// also registered with `object: nil`.
    @objc private func playerItemDidStall(notification: Notification) {
        guard let stalledItem = notification.object as? AVPlayerItem,
              stalledItem === avPlayer?.currentItem else {
            return
        }
        zlog("MediaPlayerInstance: Playback stalled (playerId: \(playerId)) — reporting buffering")
        notifyStateChanged(state: "buffering", isBuffering: true)
    }

    @objc private func playerDidFinishPlaying(notification: Notification) {
        // `object: nil` registration (see setupObservers()) means this fires
        // for every AVPlayerItem in the process, including ones belonging to
        // other player instances and stale items this instance has since
        // replaced via replaceCurrentItem(). Only react if the notification
        // is actually about the item this instance is currently playing (B-02).
        guard let finishedItem = notification.object as? AVPlayerItem,
              finishedItem === avPlayer?.currentItem else {
            return
        }
        // Mirrors Android's STATE_ENDED for setPlaylist's issue-#79 guard:
        // a finished item is not "in progress", so re-issuing a playlist
        // that names it still restarts it.
        currentItemIsSpent = true
        notifyStateChanged(state: "completed", isBuffering: false)
    }

    @objc private func playerDidFailWithError(notification: Notification) {
        // See playerDidFinishPlaying(notification:) — same cross-instance /
        // stale-item filtering is required here (B-02).
        guard let failedItem = notification.object as? AVPlayerItem,
              failedItem === avPlayer?.currentItem else {
            return
        }
        if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
            let nsError = error as NSError
            let (category, httpStatusCode) = categorizeFailure(nsError, item: failedItem)
            notifyError(
                error: nsError.localizedDescription,
                category: category,
                nativeErrorCode: nsError.code,
                httpStatusCode: httpStatusCode
            )
        }
    }

    // Note: observeValue is no longer needed - we use modern KVO (NSKeyValueObservation)
    // which handles observation via closures. The old-style KVO that required this method
    // has been replaced with modern Swift observers in loadMediaItem().

    private func handlePlayerItemStatusChange(status: AVPlayerItem.Status, item: AVPlayerItem? = nil) {
        zlog("MediaPlayerInstance: PlayerItem status changed to: \(status.rawValue)")

        switch status {
        case .unknown:
            zlog("MediaPlayerInstance: PlayerItem status = unknown")
            notifyStateChanged(state: "buffering", isBuffering: true)
        case .readyToPlay:
            zlog("MediaPlayerInstance: PlayerItem status = readyToPlay")
            // Check if player is currently playing to set correct state.
            // Uses timeControlStatus (not `rate > 0`) for the same reason as
            // isPlaying(): a player that has been told to play but is still
            // buffering has rate == 0 yet is not "ready but not playing".
            if let player = avPlayer, player.timeControlStatus != .paused {
                zlog("MediaPlayerInstance: Player is playing (rate: \(player.rate))")
                notifyStateChanged(state: "playing", isBuffering: false)
            } else {
                zlog("MediaPlayerInstance: Player is ready but not playing")
                notifyStateChanged(state: "ready", isBuffering: false)
            }
            notifyDurationChanged()
            checkLiveDvrWindowDuration()

            // Extract and notify all tracks immediately
            extractAndNotifyQualityTracks()
            extractAndNotifyAudioTracks()
            extractAndNotifySubtitleTracks()

            // Retry after a delay to catch variants that load asynchronously
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.extractAndNotifyQualityTracks()
                self?.extractAndNotifyAudioTracks()
                self?.extractAndNotifySubtitleTracks()
            }
        case .failed:
            zlog("MediaPlayerInstance: PlayerItem status = failed")
            let failedItem = item ?? avPlayer?.currentItem
            if let error = failedItem?.error {
                let nsError = error as NSError
                let (category, httpStatusCode) = categorizeFailure(nsError, item: failedItem)
                notifyError(
                    error: nsError.localizedDescription,
                    category: category,
                    nativeErrorCode: nsError.code,
                    httpStatusCode: httpStatusCode
                )
            } else {
                notifyError(error: "Player item failed to load")
            }
        @unknown default:
            zlog("MediaPlayerInstance: PlayerItem status = unknown default")
            break
        }
    }

    private func notifyStateChanged(state: String, isBuffering: Bool) {
        let arguments: [String: Any] = [
            "playerId": playerId,
            "state": state,
            "isBuffering": isBuffering,
            "bufferPercentage": computeBufferPercentage()
        ]
        methodChannel.invokeMethod("onStateChanged", arguments: arguments)
    }

    /// Computes the percentage (0-100) of the current item's total duration
    /// that has been buffered, based on the furthest end of any loaded time
    /// range (B-06 — this was previously hardcoded to 0). Mirrors the
    /// semantics of ExoPlayer's `bufferedPercentage` on Android (percentage
    /// of the FULL duration reached by buffering, not remaining
    /// buffer-ahead-of-playhead) so the two platforms report comparable
    /// values. Returns 0 for live/unknown-duration content, where "percentage
    /// of duration buffered" isn't a meaningful concept.
    private func computeBufferPercentage() -> Int {
        guard let item = avPlayer?.currentItem else { return 0 }

        let durationSeconds = CMTimeGetSeconds(item.duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else { return 0 }

        var bufferedEndSeconds: Double = 0
        for value in item.loadedTimeRanges {
            let range = value.timeRangeValue
            let start = CMTimeGetSeconds(range.start)
            let duration = CMTimeGetSeconds(range.duration)
            guard start.isFinite, duration.isFinite else { continue }
            bufferedEndSeconds = max(bufferedEndSeconds, start + duration)
        }

        let percentage = (bufferedEndSeconds / durationSeconds) * 100.0
        return Int(min(100.0, max(0.0, percentage)))
    }

    /// Issue #88: `positionBasis` and `liveEdgeOffset` ride this existing
    /// 0.5s event (see `setupObservers`) rather than getting a channel event
    /// of their own -- they are sampled from the same tick that produces
    /// `position` and are only ever meaningful alongside it.
    ///
    /// `liveEdgeOffset` is omitted from the payload entirely (rather than sent
    /// as a sentinel) when unknown; `MediaPlayer._handlePositionChanged` on the
    /// Dart side reads a missing key as `nil`/`null`, the same as it does for
    /// an older native build that never sends it.
    private func notifyPositionChanged(
        position: Int64,
        positionBasis: String = "absolute",
        liveEdgeOffsetMs: Int64? = nil
    ) {
        var arguments: [String: Any] = [
            "playerId": playerId,
            "position": Int(position),
            "positionBasis": positionBasis
        ]
        if let liveEdgeOffsetMs = liveEdgeOffsetMs {
            arguments["liveEdgeOffset"] = Int(liveEdgeOffsetMs)
        }
        methodChannel.invokeMethod("onPositionChanged", arguments: arguments)
    }

    private func notifyDurationChanged(duration: Int64? = nil) {
        let durationMs: Int

        if let providedDuration = duration {
            durationMs = Int(providedDuration)
        } else {
            guard let itemDuration = avPlayer?.currentItem?.duration,
                  itemDuration.isValid && !itemDuration.isIndefinite else { return }
            durationMs = Int(itemDuration.seconds * 1000)
        }

        let isLive = currentMediaItem?["isLive"] as? Bool ?? false
        let arguments: [String: Any] = [
            "playerId": playerId,
            "duration": durationMs,
            "isLive": isLive
        ]
        methodChannel.invokeMethod("onDurationChanged", arguments: arguments)
    }

    private func notifyBandwidthChanged(bandwidth: Int64) {
        let arguments: [String: Any] = [
            "playerId": playerId,
            "bandwidth": bandwidth
        ]
        methodChannel.invokeMethod("onBandwidthChanged", arguments: arguments)
    }

    private func extractAndNotifyQualityTracks() {
        guard let playerItem = avPlayer?.currentItem,
              let asset = playerItem.asset as? AVURLAsset else {
            zlog("MediaPlayerInstance: Cannot extract tracks - no player item or not AVURLAsset")
            return
        }

        var qualityTracks: [[String: Any]] = []
        var seenBitrates = Set<Int>()

        // Try to parse HLS manifest directly for the most accurate results
        parseHLSManifest(url: asset.url) { [weak self] manifestTracks in
            guard let self = self else { return }

            if !manifestTracks.isEmpty {
                zlog("MediaPlayerInstance: Parsed \(manifestTracks.count) quality tracks from HLS manifest")
                self.notifyQualityTracksChanged(tracks: manifestTracks)
                return
            }

            // Fallback: For iOS 15+, use AVAssetVariant API
            if #available(iOS 15.0, *) {
                if let variants = asset.variants as? [AVAssetVariant] {
                    zlog("MediaPlayerInstance: Found \(variants.count) variants from AVAsset")

                    for (index, variant) in variants.enumerated() {
                        let peakBitRateValue = variant.peakBitRate ?? 0.0
                        let bitrate = Int(peakBitRateValue)

                        if bitrate > 0 && !seenBitrates.contains(bitrate) {
                            seenBitrates.insert(bitrate)

                            let videoAttributes = variant.videoAttributes
                            let widthValue = videoAttributes?.presentationSize.width ?? 0.0
                            let heightValue = videoAttributes?.presentationSize.height ?? 0.0

                            let (finalWidth, finalHeight) = (widthValue > 0 && heightValue > 0)
                                ? (Int(widthValue), Int(heightValue))
                                : self.estimateResolutionFromBitrate(bitrate: bitrate)

                            let trackId = "\(finalWidth)x\(finalHeight)_\(bitrate)"
                            let trackName = "\(finalHeight)p (\(bitrate / 1000)kbps)"

                            let frameRateValue = videoAttributes?.nominalFrameRate ?? 30.0

                            // Get codec type - CMVideoCodecType is UInt32, not an enum
                            var codecValue = "unknown"
                            if let codecTypes = videoAttributes?.codecTypes, let firstCodec = codecTypes.first {
                                codecValue = String(format: "%c%c%c%c",
                                    (firstCodec >> 24) & 0xFF,
                                    (firstCodec >> 16) & 0xFF,
                                    (firstCodec >> 8) & 0xFF,
                                    firstCodec & 0xFF)
                            }

                            qualityTracks.append([
                                "id": trackId,
                                "name": trackName,
                                "bitrate": bitrate,
                                "width": finalWidth,
                                "height": finalHeight,
                                "frameRate": Double(frameRateValue),
                                "isSelected": false,
                                "isAvailable": true,
                                "codec": codecValue
                            ])
                        }
                    }
                }
            }

            // Last resort: access log (only shows tracks used during playback)
            if qualityTracks.isEmpty {
                zlog("MediaPlayerInstance: Trying access log fallback")

                if let accessLog = playerItem.accessLog() {
                    for event in accessLog.events {
                        let bitrate = max(Int(event.indicatedBitrate), Int(event.switchBitrate))

                        if bitrate > 0 && !seenBitrates.contains(bitrate) {
                            seenBitrates.insert(bitrate)

                            let (finalWidth, finalHeight) = self.estimateResolutionFromBitrate(bitrate: bitrate)

                            qualityTracks.append([
                                "id": "\(finalWidth)x\(finalHeight)_\(bitrate)",
                                "name": "\(finalHeight)p (\(bitrate / 1000)kbps)",
                                "bitrate": bitrate,
                                "width": finalWidth,
                                "height": finalHeight,
                                "frameRate": 30.0,
                                "isSelected": false,
                                "isAvailable": true,
                                "codec": "unknown"
                            ])
                        }
                    }
                }
            }

            qualityTracks.sort { ($0["bitrate"] as? Int ?? 0) > ($1["bitrate"] as? Int ?? 0) }

            if !qualityTracks.isEmpty {
                zlog("MediaPlayerInstance: Notifying \(qualityTracks.count) quality tracks")
                self.notifyQualityTracksChanged(tracks: qualityTracks)
            } else {
                zlog("MediaPlayerInstance: No quality tracks found")
            }
        }
    }

    private func parseHLSManifest(url: URL, completion: @escaping ([[String: Any]]) -> Void) {
        // Only parse HLS. Issue #87: follows the loaded item's resolved
        // streaming format (explicit `MediaItem.streamingFormat` hint first,
        // else path-based inference) instead of a `contains(".m3u8")` scan of
        // the raw URL, so a manifest behind a rewritten/signed URL is still
        // parsed and a non-HLS URL that merely mentions `.m3u8` is not.
        guard streamingFormat(of: currentMediaItem) == .hls else {
            zlog("MediaPlayerInstance: Not an HLS URL, skipping manifest parsing")
            completion([])
            return
        }

        zlog("MediaPlayerInstance: Fetching HLS manifest from: \(redactedURL(url.absoluteString))")

        // Parse HLS master playlist to extract all variant streams
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                zlog("MediaPlayerInstance: Failed to fetch HLS manifest: \(error.localizedDescription)")
                completion([])
                return
            }

            guard let data = data,
                  let manifestString = String(data: data, encoding: .utf8) else {
                zlog("MediaPlayerInstance: Failed to decode HLS manifest data")
                completion([])
                return
            }

            zlog("MediaPlayerInstance: Fetched HLS manifest (\(manifestString.count) chars), parsing...")
            var tracks: [[String: Any]] = []
            var seenBitrates = Set<Int>()

            // Parse #EXT-X-STREAM-INF lines
            let lines = manifestString.components(separatedBy: .newlines)

            for (lineNum, line) in lines.enumerated() {
                if line.hasPrefix("#EXT-X-STREAM-INF:") {
                    zlog("MediaPlayerInstance: Found STREAM-INF at line \(lineNum): \(line)")

                    // Extract BANDWIDTH using regex
                    let bandwidthPattern = "BANDWIDTH=(\\d+)"
                    if let regex = try? NSRegularExpression(pattern: bandwidthPattern),
                       let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                       let range = Range(match.range(at: 1), in: line) {

                        if let bandwidth = Int(line[range]) {
                            if !seenBitrates.contains(bandwidth) {
                                seenBitrates.insert(bandwidth)

                                // Try to extract RESOLUTION
                                var width = 0
                                var height = 0

                                let resPattern = "RESOLUTION=(\\d+)x(\\d+)"
                                if let resRegex = try? NSRegularExpression(pattern: resPattern),
                                   let resMatch = resRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {

                                    if let widthRange = Range(resMatch.range(at: 1), in: line),
                                       let heightRange = Range(resMatch.range(at: 2), in: line) {
                                        width = Int(line[widthRange]) ?? 0
                                        height = Int(line[heightRange]) ?? 0
                                    }
                                }

                                let (finalWidth, finalHeight) = (width > 0 && height > 0)
                                    ? (width, height)
                                    : self.estimateResolutionFromBitrate(bitrate: bandwidth)

                                tracks.append([
                                    "id": "\(finalWidth)x\(finalHeight)_\(bandwidth)",
                                    "name": "\(finalHeight)p (\(bandwidth / 1000)kbps)",
                                    "bitrate": bandwidth,
                                    "width": finalWidth,
                                    "height": finalHeight,
                                    "frameRate": 30.0,
                                    "isSelected": false,
                                    "isAvailable": true,
                                    "codec": "unknown"
                                ])

                                zlog("MediaPlayerInstance: Parsed variant: \(finalHeight)p @ \(bandwidth / 1000)kbps, resolution: \(finalWidth)x\(finalHeight)")
                            }
                        }
                    }
                }
            }

            zlog("MediaPlayerInstance: Parsed \(tracks.count) tracks from manifest")
            DispatchQueue.main.async {
                completion(tracks)
            }
        }.resume()
    }

    private func estimateResolutionFromBitrate(bitrate: Int) -> (Int, Int) {
        // Rough estimation of resolution based on bitrate
        switch bitrate {
        case 0..<500_000:      return (426, 240)   // 240p
        case 500_000..<1_000_000:  return (640, 360)   // 360p
        case 1_000_000..<2_000_000: return (854, 480)   // 480p
        case 2_000_000..<4_000_000: return (1280, 720)  // 720p
        case 4_000_000..<8_000_000: return (1920, 1080) // 1080p
        default:                     return (3840, 2160) // 4K
        }
    }

    private func notifyQualityTracksChanged(tracks: [[String: Any]]) {
        let arguments: [String: Any] = [
            "playerId": playerId,
            "tracks": tracks
        ]
        methodChannel.invokeMethod("onQualityTracksChanged", arguments: arguments)
    }

    private func extractAndNotifyAudioTracks() {
        guard let playerItem = avPlayer?.currentItem,
              let asset = playerItem.asset as? AVURLAsset else {
            zlog("MediaPlayerInstance: Cannot extract audio tracks - no player item or not AVURLAsset")
            return
        }

        var audioTracks: [[String: Any]] = []

        // Get audio media selection group
        if let audioGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            zlog("MediaPlayerInstance: Found \(audioGroup.options.count) audio options")

            // Extract all audio tracks
            for (index, option) in audioGroup.options.enumerated() {
                let trackId = option.displayName.isEmpty ? "audio_\(index)" : option.displayName
                let language = option.extendedLanguageTag ?? option.locale?.languageCode ?? ""
                let trackName = option.displayName.isEmpty
                    ? (language.isEmpty ? "Audio Track \(index + 1)" : getLanguageName(languageCode: language))
                    : option.displayName

                // Determine if this track is currently selected
                let isSelected = playerItem.currentMediaSelection.selectedMediaOption(in: audioGroup) == option

                audioTracks.append([
                    "id": trackId,
                    "name": trackName,
                    "language": language,
                    "codec": "unknown", // iOS doesn't expose codec easily
                    "channels": 2, // Default, iOS doesn't expose channel count easily
                    "sampleRate": 48000, // Default, iOS doesn't expose sample rate easily
                    "bitrate": 0, // iOS doesn't expose audio bitrate easily
                    "isSelected": isSelected,
                    "isAvailable": true
                ])
            }
        } else {
            zlog("MediaPlayerInstance: No audio selection group found")
        }

        // ALWAYS notify, even with empty list (to clear UI when switching videos)
        zlog("MediaPlayerInstance: Found \(audioTracks.count) audio tracks")
        notifyAudioTracksChanged(tracks: audioTracks)
    }

    private func notifyAudioTracksChanged(tracks: [[String: Any]]) {
        let arguments: [String: Any] = [
            "playerId": playerId,
            "tracks": tracks
        ]
        methodChannel.invokeMethod("onAudioTracksChanged", arguments: arguments)
    }

    private func extractAndNotifySubtitleTracks() {
        guard let playerItem = avPlayer?.currentItem,
              let asset = playerItem.asset as? AVURLAsset else {
            zlog("MediaPlayerInstance: Cannot extract subtitle tracks - no player item or not AVURLAsset")
            return
        }

        var subtitleTracks: [[String: Any]] = []

        // Get legible (subtitle/caption) media selection group
        if let subtitleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
            zlog("MediaPlayerInstance: Found \(subtitleGroup.options.count) subtitle options")

            // Extract all subtitle tracks
            for (index, option) in subtitleGroup.options.enumerated() {
                let trackId = option.displayName.isEmpty ? "subtitle_\(index)" : option.displayName
                let language = option.extendedLanguageTag ?? option.locale?.languageCode ?? ""
                let trackTitle = option.displayName.isEmpty
                    ? (language.isEmpty ? "Subtitle \(index + 1)" : getLanguageName(languageCode: language))
                    : option.displayName

                // Determine if this track is currently selected
                let isSelected = playerItem.currentMediaSelection.selectedMediaOption(in: subtitleGroup) == option

                // Check if this is a default/forced subtitle
                let isDefault = option.hasMediaCharacteristic(.isMainProgramContent)

                // Determine format (iOS doesn't easily expose this, assume WebVTT for HLS)
                let format = "webvtt"

                subtitleTracks.append([
                    "id": trackId,
                    "title": trackTitle,
                    "language": language,
                    "format": format,
                    "isSelected": isSelected,
                    "isDefault": isDefault
                ])
            }
        } else {
            zlog("MediaPlayerInstance: No subtitle selection group found")
        }

        // ALWAYS notify, even with empty list (to clear UI when switching to video without subtitles)
        zlog("MediaPlayerInstance: Found \(subtitleTracks.count) subtitle tracks")
        notifySubtitleTracksChanged(tracks: subtitleTracks)
    }

    private func notifySubtitleTracksChanged(tracks: [[String: Any]]) {
        let arguments: [String: Any] = [
            "playerId": playerId,
            "tracks": tracks
        ]
        methodChannel.invokeMethod("onSubtitleTracksChanged", arguments: arguments)
    }

    private func getLanguageName(languageCode: String) -> String {
        let code = languageCode.lowercased()
        switch code {
        case "en": return "English"
        case "es": return "Spanish"
        case "fr": return "French"
        case "de": return "German"
        case "it": return "Italian"
        case "pt": return "Portuguese"
        case "ru": return "Russian"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "zh": return "Chinese"
        case "ar": return "Arabic"
        case "hi": return "Hindi"
        case "tr": return "Turkish"
        case "nl": return "Dutch"
        case "pl": return "Polish"
        case "sv": return "Swedish"
        case "da": return "Danish"
        case "fi": return "Finnish"
        case "no": return "Norwegian"
        case "cs": return "Czech"
        default: return code.uppercased()
        }
    }

    /// H-01: maps an `NSError` from AVPlayer/AVPlayerItem onto the small,
    /// cross-platform error-category vocabulary shared with the Dart mapper
    /// (see `MediaErrorCategory` in lib/src/core/exceptions.dart) and
    /// mirrored on Android by `MediaPlayerInstance.categorizeExoPlayerError`
    /// in MediaPlayerManager.kt. All three call sites must stay in lockstep
    /// — the Dart test suite (test/exceptions/error_category_vocabulary_test.dart)
    /// parses this file's category string literals as text and fails if they
    /// drift from the Dart vocabulary. That test also hard-matches this
    /// function's exact signature text, so it deliberately keeps taking a
    /// bare `NSError` — see `categorizeFailure(_:item:)` below for the
    /// item-aware entry point every call site actually uses.
    ///
    /// ON-DEVICE FINDING (confirmed against a physical iPhone, iOS 26.5,
    /// release build via the example app's Error Handling page): a genuine
    /// HTTP 404 (bad URL, server responds and refuses) was being reported as
    /// category NETWORK, not HTTP, while a bad host correctly reported
    /// NETWORK. The `NSError` AVFoundation hands back for the 404 case does
    /// NOT carry an embedded `NSErrorFailingURLResponseKey` `HTTPURLResponse`
    /// at the top level, and its domain/code is `NSURLErrorDomain` with a
    /// code that fell into the old unconditional `default:` (NETWORK)
    /// branch — almost certainly `NSURLErrorFileDoesNotExist` (-1100), which
    /// is the documented shape AVFoundation's HTTP resource loader produces
    /// for a 404 response on an http(s) URL (the server DID respond; it just
    /// refused the request). That inference (not confirmed on-device — see
    /// `categorizeFailure`) is what motivates the new `NSURLErrorFileDoesNotExist`
    /// case below; the underlying-error-chain walk and `categorizeFailure`'s
    /// errorLog-based lookup are the parts of the fix that recover the real
    /// status without depending on that inference.
    ///
    /// ON-DEVICE FOLLOW-UP (same device/build/page, GCS bucket 403 case
    /// specifically — a non-existent object in a public GCS bucket returns
    /// 403, not 404, since GCS can't reveal non-existence without granting
    /// list/read permission): the above -1100 fix was NOT sufficient. The
    /// top-level error for THIS failure is `NSURLErrorNoPermissionsToReadFile`
    /// (-1102), still falling into the `default:` (NETWORK) branch below, and
    /// `errorLog()` again produced no usable status (see the comment on
    /// `categorizeFailure(_:item:)`). Unlike -1100, -1102 is genuinely
    /// ambiguous: it is the correct, honest code for a real local
    /// `file://` permission problem too, so it is deliberately NOT added to
    /// the unconditional `NSURLErrorFileDoesNotExist` case below. Instead it
    /// is handled, scheme-gated, in `categorizeFailure(_:item:)` — the only
    /// place with access to the failing asset's URL scheme — which
    /// short-circuits to HTTP for http(s) assets before ever reaching this
    /// function's `default:` fallback, and leaves file:// (or
    /// scheme-unknown) failures reported as NETWORK here, unchanged.
    private func categorize(_ error: NSError) -> (category: String, httpStatusCode: Int?) {
        // Domain/code classification, usable at every level of the
        // underlying-error chain below (including the top-level error
        // itself). A local function so its literal returns are still part
        // of this function's own source text for the drift-guard test.
        // Returns nil when `err`'s domain/code isn't recognized, so the
        // caller can keep walking the chain or fall back to UNKNOWN.
        func classify(_ err: NSError) -> (category: String, httpStatusCode: Int?)? {
            if err.domain == NSURLErrorDomain {
                switch err.code {
                case NSURLErrorBadServerResponse, NSURLErrorZeroByteResource:
                    return ("HTTP", nil)
                case NSURLErrorFileDoesNotExist:
                    // AVFoundation's HTTP resource loader maps a 404
                    // response for an http(s):// URL onto this
                    // NSURLErrorDomain code rather than
                    // NSURLErrorBadServerResponse or an embedded
                    // HTTPURLResponse (see the on-device finding above) —
                    // the server DID respond and refused the request, so
                    // this is an HTTP failure, not a connectivity failure.
                    // `categorizeFailure`'s errorLog lookup is preferred and
                    // returns a concrete status when available; this is the
                    // fallback for when no AVPlayerItem was available at the
                    // call site, or its error log recorded no status.
                    return ("HTTP", nil)
                default:
                    // Everything else in NSURLErrorDomain (timeouts,
                    // offline, DNS/host failures, connection lost,
                    // cleartext/ATS rejections, etc.) means the request
                    // never got a response from a server to refuse it — a
                    // connectivity problem.
                    return ("NETWORK", nil)
                }
            }

            if err.domain == AVFoundationErrorDomain {
                switch err.code {
                case AVError.contentIsProtected.rawValue:
                    return ("DRM", nil)
                case AVError.decoderNotFound.rawValue,
                     AVError.decoderTemporarilyUnavailable.rawValue,
                     AVError.encoderNotFound.rawValue:
                    return ("DECODER", nil)
                case AVError.fileFormatNotRecognized.rawValue,
                     AVError.fileFailedToParse.rawValue,
                     AVError.noSourceTrack.rawValue,
                     AVError.invalidSourceMedia.rawValue,
                     AVError.mediaDiscontinuity.rawValue:
                    return ("SOURCE", nil)
                default:
                    return nil
                }
            }

            return nil
        }

        // An HTTPURLResponse embedded directly in the top-level error's
        // userInfo (when present) gives the most precise signal: the server
        // responded, so this is an HTTP failure with a concrete status
        // code, regardless of domain.
        if let response = error.userInfo["NSErrorFailingURLResponseKey"] as? HTTPURLResponse {
            return ("HTTP", response.statusCode)
        }

        // Walk the underlying-error chain: AVFoundation frequently wraps the
        // real cause (an embedded HTTPURLResponse, or a more specific
        // NSURLErrorDomain/AVFoundationErrorDomain code) one or more levels
        // down inside NSUnderlyingErrorKey rather than surfacing it at the
        // top level.
        var current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        var depth = 0
        while let err = current, depth < 5 {
            if let response = err.userInfo["NSErrorFailingURLResponseKey"] as? HTTPURLResponse {
                return ("HTTP", response.statusCode)
            }
            if let classified = classify(err) {
                return classified
            }
            current = err.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }

        // Fall back to classifying the top-level error's own domain/code.
        if let classified = classify(error) {
            return classified
        }

        return ("UNKNOWN", nil)
    }

    /// Item-aware entry point every call site uses instead of `categorize(_:)`
    /// directly. `item`, when available, is the `AVPlayerItem` whose failure
    /// produced `error`; it is optional because not every call site can
    /// cheaply recover one.
    ///
    /// `AVPlayerItem.errorLog()` is the most authoritative source available:
    /// it records the actual HTTP status code the server returned for every
    /// HTTP(S) resource-loading failure (manifest/playlist and segment
    /// requests) via `AVPlayerItemErrorLogEvent.errorStatusCode`, independent
    /// of whatever shape the NSError handed to KVO/notifications takes. This
    /// is what lets a real 404/500/etc. be recovered instead of falling back
    /// to `categorize(_:)`'s (necessarily category-only, or inferred-status)
    /// classification of the NSError alone.
    ///
    /// ON-DEVICE FOLLOW-UP FINDING (iPhone, iOS 26.5, release build, GCS 403
    /// "bad URL" scenario): `errorLog()` produced NO event with a non-zero
    /// `errorStatusCode` for this failure — `latestHTTPStatusCode(from:)`
    /// below returned `nil` and this fell through to `categorize(error)`,
    /// which is how the *inferred* -1100/-1102 mapping below ended up
    /// mattering at all despite the errorLog path being the preferred,
    /// inference-free source of truth. This is very likely not a bug in the
    /// errorLog lookup but a property of *when* this particular failure
    /// occurs: `AVPlayerItemAccessLog`/`AVPlayerItemErrorLog` events are
    /// recorded per HTTP resource-loading attempt (manifest/playlist/segment
    /// requests during an active load), and a bad `.mp4` URL that a 403
    /// response *before* any such request/response cycle completes (i.e.
    /// during the very first asset-metadata/HEAD-equivalent resolution) may
    /// fail before AVFoundation ever records a loggable HTTP event for this
    /// item. In other words: for this class of "fails immediately, before
    /// any segment is ever requested" failure, an empty errorLog is expected
    /// behavior, not a defect — which is exactly why the NSError-based
    /// fallback in `categorize(_:)` below still needs to carry a correct
    /// HTTP-vs-NETWORK classification rather than assuming errorLog will
    /// always cover it.
    private func categorizeFailure(_ error: NSError, item: AVPlayerItem?) -> (category: String, httpStatusCode: Int?) {
        if let item = item, let statusCode = latestHTTPStatusCode(from: item) {
            return ("HTTP", statusCode)
        }

        // NSURLErrorNoPermissionsToReadFile (-1102) is genuinely ambiguous by
        // domain/code alone, unlike -1100 (NSURLErrorFileDoesNotExist)
        // immediately below in `categorize(_:)`'s NSURLErrorDomain switch:
        //   - For an http(s) asset, AVFoundation's HTTP resource loader can
        //     surface a server-side refusal (403 being the common real-world
        //     case — see the GCS bucket example this fixes) as -1102 rather
        //     than as an embedded HTTPURLResponse/errorStatusCode. The
        //     server DID respond and refused; that's HTTP, exactly like the
        //     -1100 case.
        //   - For a genuine `file://` asset, -1102 means exactly what its
        //     name says: a local filesystem read-permission problem. There
        //     is no server involved at all, so reporting HTTP there would be
        //     actively wrong, not just imprecise.
        //
        // `categorize(_:)` cannot make this distinction itself: its exact
        // signature — `private func categorize(_ error: NSError) -> …` — is
        // pinned by the drift-guard test in
        // test/exceptions/error_category_vocabulary_test.dart (which parses
        // this file as text and locates the function by that literal
        // signature), so it cannot be given a scheme parameter. This is the
        // one call site with contextual access to the failing `AVPlayerItem`
        // (and therefore its asset URL's scheme), so the scheme-gated -1102
        // check lives here and short-circuits BEFORE falling back to
        // `categorize(error)`, rather than inside it.
        //
        // When the scheme can't be determined (no `item`, `item.asset` isn't
        // an `AVURLAsset`, or the URL has no scheme) this deliberately does
        // NOT assume http: it falls through to `categorize(error)`, whose
        // NSURLErrorDomain switch has no explicit -1102 case and therefore
        // reports NETWORK — the same conservative, non-guessing behavior as
        // before this fix for every scheme other than http(s).
        if errorChainContainsNoPermissionsToReadFile(error) && isHTTPScheme(of: item) == true {
            return ("HTTP", nil)
        }

        return categorize(error)
    }

    /// Walks `error` and its `NSUnderlyingErrorKey` chain (the same
    /// traversal `categorize(_:)` performs for its own classification) for
    /// an `NSURLErrorDomain` / `NSURLErrorNoPermissionsToReadFile` (-1102)
    /// code. Kept separate from `categorize(_:)`/`classify(_:)` because,
    /// unlike them, this needs to be combined with scheme information that
    /// only `categorizeFailure(_:item:)` has access to — see the call site
    /// there for the full rationale.
    private func errorChainContainsNoPermissionsToReadFile(_ error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorNoPermissionsToReadFile {
            return true
        }
        var current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        var depth = 0
        while let err = current, depth < 5 {
            if err.domain == NSURLErrorDomain && err.code == NSURLErrorNoPermissionsToReadFile {
                return true
            }
            current = err.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return false
    }

    /// Whether `item`'s asset URL uses an http/https scheme. Returns `nil`
    /// — "unknown", not "not http" — when that can't be determined: no
    /// `item`, `item.asset` isn't an `AVURLAsset`, or the URL has no scheme.
    /// Callers MUST treat `nil` as "don't know" and avoid inferring HTTP
    /// from it; see `categorizeFailure(_:item:)`.
    private func isHTTPScheme(of item: AVPlayerItem?) -> Bool? {
        guard let asset = item?.asset as? AVURLAsset,
              let scheme = asset.url.scheme?.lowercased() else {
            return nil
        }
        return scheme == "http" || scheme == "https"
    }

    /// Extracts the most recently recorded HTTP status code from an
    /// `AVPlayerItem`'s error log, if any. Per Apple's documentation,
    /// `AVPlayerItemErrorLogEvent.errorStatusCode` is "the HTTP status code
    /// most recently returned by the server" for that log event; `0` means
    /// no HTTP status was recorded for it (e.g. the failure never reached a
    /// server), which is why events reporting `0` are skipped rather than
    /// treated as a literal status. Walked newest-to-oldest since the most
    /// recent event is the one relevant to the failure that just occurred.
    private func latestHTTPStatusCode(from item: AVPlayerItem) -> Int? {
        guard let errorLog = item.errorLog() else { return nil }
        for event in errorLog.events.reversed() where event.errorStatusCode != 0 {
            return event.errorStatusCode
        }
        return nil
    }

    private func notifyError(
        error: String,
        category: String = "UNKNOWN",
        nativeErrorCode: Int? = nil,
        httpStatusCode: Int? = nil
    ) {
        var arguments: [String: Any] = [
            "playerId": playerId,
            "error": error,
            "category": category
        ]
        if let nativeErrorCode = nativeErrorCode {
            arguments["nativeErrorCode"] = nativeErrorCode
        }
        if let httpStatusCode = httpStatusCode {
            arguments["httpStatusCode"] = httpStatusCode
        }
        methodChannel.invokeMethod("onError", arguments: arguments)
    }
}

enum MediaPlayerError: Error {
    case playerNotFound
    case invalidConfiguration
    case loadFailed(String)
}
