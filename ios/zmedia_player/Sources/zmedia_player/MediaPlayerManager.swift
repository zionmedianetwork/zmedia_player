import Foundation
import AVFoundation
import AVKit
import Flutter

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
            print("MediaPlayerManager: Auto-cleaning stale instance: \(playerId)")
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

    func loadMediaItem(playerId: String, mediaItem: [String: Any]) throws {
        markActivity(playerId: playerId)
        try crashHandler.wrapOperation(
            operation: "loadMediaItem",
            playerId: playerId,
            context: ["url": mediaItem["url"] ?? "unknown"]
        ) {
            guard let playerInstance = players[playerId] else {
                throw MediaPlayerError.playerNotFound
            }
            playerInstance.loadMediaItem(mediaItem: mediaItem)
        }
    }

    func setPlaylist(playerId: String, playlist: [String: Any], startIndex: Int) throws {
        markActivity(playerId: playerId)
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.setPlaylist(playlist: playlist, startIndex: startIndex)
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

    func skipToIndex(playerId: String, index: Int) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.skipToIndex(index: index)
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
            print("MediaPlayerManager: Player instance not found for \(playerId)")
            throw MediaPlayerError.playerNotFound
        }

        // Use currentPlayerLayer() which reads the active view WITHOUT creating a new one.
        let layer = playerInstance.currentPlayerLayer()
        print("MediaPlayerManager: getPlayerLayer - returning active player layer: \(layer != nil)")
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
    private var rateObserver: NSKeyValueObservation?
    private var bandwidthTimer: Timer?

    // Modern KVO observers for player item (auto-cleanup, no exceptions)
    private var itemDurationObserver: NSKeyValueObservation?
    private var itemStatusObserver: NSKeyValueObservation?

    private var currentPlaylist: [[String: Any]]?
    private var currentIndex = 0
    private var currentMediaItem: [String: Any]?
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
            self?.notifyPositionChanged(position: Int64(time.seconds * 1000))
        }

        // Status observer
        statusObserver = player.observe(\.status, options: [.new]) { [weak self] player, _ in
            self?.handleStatusChange(status: player.status)
        }

        // Rate observer for play/pause state
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            self?.handleRateChange(rate: player.rate)
        }

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

    func loadMediaItem(mediaItem: [String: Any]) {
        guard let urlString = mediaItem["url"] as? String,
              let url = URL(string: urlString) else {
            notifyError(error: "Invalid media URL")
            return
        }

        // Store current media item (for live stream detection)
        currentMediaItem = mediaItem

        // Reset access log event counter for new media
        previousAccessLogEventCount = 0

        print("MediaPlayerInstance.loadMediaItem(): Loading URL: \(urlString)")

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
                        print("MediaPlayerInstance: HTTPCookie construction failed for cookie \(name)")
                    }
                }
                if !cookies.isEmpty {
                    options["AVURLAssetHTTPCookiesKey"] = cookies
                    // Remove the Cookie HTTP header: when BOTH the header and the
                    // cookies key are set, AVFoundation prefers the header (which it
                    // drops on some out-of-process requests). Using only the cookies
                    // key applies the cookies to every request.
                    headerFields.removeValue(forKey: "Cookie")
                    print("MediaPlayerInstance: forwarding \(cookies.count) cookie(s) via AVURLAssetHTTPCookiesKey for host \(host)")
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
        if #available(iOS 10.0, *),
           let drmConfig = mediaItem["drmConfig"] as? [String: Any],
           let player = avPlayer {
            print("MediaPlayerInstance.loadMediaItem(): DRM config found, initializing DrmHandler")
            let handler = DrmHandler(playerId: playerId, channel: methodChannel)
            let configured = handler.configure(drmConfig: drmConfig)
            if configured {
                let session = handler.createContentKeySession(for: player)
                // Register the asset as a content key recipient BEFORE creating AVPlayerItem.
                session.addContentKeyRecipient(asset)
                drmHandler = handler
                print("MediaPlayerInstance.loadMediaItem(): DRM content key session configured")
            } else {
                print("MediaPlayerInstance.loadMediaItem(): DrmHandler.configure() failed, loading without DRM")
            }
        }

        let playerItem = AVPlayerItem(asset: asset)

        // Apply buffer configuration if available
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
            self.handlePlayerItemStatusChange(status: item.status)
        }

        // Ensure we're on main thread for player operations
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Notify buffering state when starting to load
            self.notifyStateChanged(state: "buffering", isBuffering: true)

            self.avPlayer?.replaceCurrentItem(with: playerItem)

            print("MediaPlayerInstance.loadMediaItem(): Item replaced, player: \(self.avPlayer != nil)")

            // Re-bind ONLY the topmost live view to the (new) current item;
            // every other view stays unbound (single-layer-per-player rule).
            let liveCount = self.playerViews.filter { $0.view != nil }.count
            if liveCount > 0 {
                print("MediaPlayerInstance.loadMediaItem(): Re-activating topmost of \(liveCount) live view(s)")
                self.activateTopmostView()
            } else {
                print("MediaPlayerInstance.loadMediaItem(): No player views exist yet")
            }

            // Auto play if configured. Route through play() (not a bare
            // avPlayer?.play()) so autoplay honours the requested speed and
            // configures the audio session the same way an explicit play() would.
            if self.config?["autoPlay"] as? Bool == true {
                print("MediaPlayerInstance.loadMediaItem(): Auto-playing")
                self.play()
            }
        }
    }

    func setPlaylist(playlist: [String: Any], startIndex: Int) {
        guard let items = playlist["items"] as? [[String: Any]] else { return }

        currentPlaylist = items
        currentIndex = max(0, min(startIndex, items.count - 1))

        if !items.isEmpty {
            loadMediaItem(mediaItem: items[currentIndex])
        }
    }

    func play() {
        // Configure the audio session for media playback so audio is audible
        // even when the ring/silent switch is on, and continues in the background
        // (the host app declares UIBackgroundModes: audio). Without this the
        // default .soloAmbient category mutes audio on silent and stops in background.
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback)
            try audioSession.setActive(true)
        } catch {
            print("MediaPlayerInstance.play(): Failed to activate playback audio session: \(error)")
        }

        guard let player = avPlayer else { return }
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
    }

    func stop() {
        avPlayer?.pause()
        avPlayer?.seek(to: .zero)
    }

    func seekTo(position: Int64) {
        let time = CMTime(value: position, timescale: 1000) // position in milliseconds
        avPlayer?.seek(to: time)
    }

    func setVolume(volume: Float) {
        avPlayer?.volume = max(0.0, min(1.0, volume))
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
    }

    func setBoxFit(boxFit: String) {
        forEachLiveView { $0.setVideoGravity(boxFit: boxFit) }
    }

    func setSubtitleTrack(subtitleTrack: [String: Any]?) {
        guard let playerItem = avPlayer?.currentItem,
              let asset = playerItem.asset as? AVURLAsset else {
            print("MediaPlayerInstance: Cannot set subtitle track - no player item or not AVURLAsset")
            return
        }

        // Get subtitle selection group
        guard let subtitleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else {
            print("MediaPlayerInstance: No subtitle selection group found")
            return
        }

        // If nil, disable subtitles
        if subtitleTrack == nil {
            print("MediaPlayerInstance: Disabling subtitles")
            playerItem.select(nil, in: subtitleGroup)
            return
        }

        guard let trackId = subtitleTrack?["id"] as? String else {
            print("MediaPlayerInstance: Invalid subtitle track data - no id")
            return
        }

        print("MediaPlayerInstance: Setting subtitle track: \(subtitleTrack?["title"] ?? "unknown"), id: \(trackId)")

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
            print("MediaPlayerInstance: Subtitle track found, selecting")
            playerItem.select(option, in: subtitleGroup)
        } else {
            print("MediaPlayerInstance: Subtitle track not found: \(trackId)")
        }
    }

    func setQualityTrack(qualityTrack: [String: Any]) {
        guard let bitrate = qualityTrack["bitrate"] as? Int,
              let name = qualityTrack["name"] as? String else {
            print("MediaPlayerInstance: Invalid quality track data")
            return
        }

        print("MediaPlayerInstance: Setting quality track: \(name), bitrate: \(bitrate)")

        // Set preferred peak bitrate to limit maximum quality
        // AVPlayer will select the best track that doesn't exceed this bitrate
        avPlayer?.currentItem?.preferredPeakBitRate = Double(bitrate)

        print("MediaPlayerInstance: Quality track set with preferredPeakBitRate: \(bitrate)")
    }

    func setAudioTrack(audioTrack: [String: Any]) {
        guard let playerItem = avPlayer?.currentItem,
              let asset = playerItem.asset as? AVURLAsset else {
            print("MediaPlayerInstance: Cannot set audio track - no player item or not AVURLAsset")
            return
        }

        // Get audio selection group
        guard let audioGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else {
            print("MediaPlayerInstance: No audio selection group found")
            return
        }

        guard let trackId = audioTrack["id"] as? String else {
            print("MediaPlayerInstance: Invalid audio track data - no id")
            return
        }

        print("MediaPlayerInstance: Setting audio track: \(audioTrack["name"] ?? "unknown"), id: \(trackId)")

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
            print("MediaPlayerInstance: Audio track found, selecting")
            playerItem.select(option, in: audioGroup)
        } else {
            print("MediaPlayerInstance: Audio track not found: \(trackId)")
        }
    }

    func enableAutoQuality() {
        print("MediaPlayerInstance: Enabling auto quality (ABR)")

        // Clear preferred peak bitrate to enable full adaptive bitrate
        avPlayer?.currentItem?.preferredPeakBitRate = 0

        print("MediaPlayerInstance: Auto quality enabled - preferredPeakBitRate cleared")
    }

    func skipToIndex(index: Int) {
        guard let playlist = currentPlaylist,
              index >= 0 && index < playlist.count else { return }

        currentIndex = index
        loadMediaItem(mediaItem: playlist[index])
    }

    func updateConfig(config: [String: Any]) {
        self.config = config
        applyConfig()
    }

    /// Creates a NEW MediaPlayerView for each UiKitView host.
    /// Only the platform-view factory should call this method.
    /// All other code that needs the active layer must use currentPlayerLayer().
    func getPlayerView() -> MediaPlayerView {
        print("MediaPlayerInstance.getPlayerView(): Creating new player view with player: \(avPlayer != nil), has item: \(avPlayer?.currentItem != nil)")
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
                print("MediaPlayerInstance: New access log events detected (\(previousAccessLogEventCount) -> \(currentEventCount)), re-extracting quality tracks")
                extractAndNotifyQualityTracks()
                previousAccessLogEventCount = currentEventCount
            }
        }
    }

    func dispose() {
        // Stop bandwidth monitoring
        stopBandwidthMonitoring()

        // Remove time observer
        if let observer = timeObserver, let player = avPlayer {
            player.removeTimeObserver(observer)
            timeObserver = nil  // Set to nil after removal
        }

        // Remove KVO observers
        statusObserver?.invalidate()
        statusObserver = nil
        rateObserver?.invalidate()
        rateObserver = nil

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

        // Configure the AVAudioSession for background playback when requested.
        // PipHandler.configureAudioSessionForPiP() also sets .playback, so both
        // paths converge on the same category — no conflict.  The host app must
        // still declare UIBackgroundModes: audio in Info.plist for this to work.
        if config["allowBackgroundPlayback"] as? Bool == true {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
                try audioSession.setActive(true)
                print("MediaPlayerInstance: Audio session configured for background playback")
            } catch {
                print("MediaPlayerInstance: Failed to configure background-playback audio session: \(error)")
            }
        }
    }

    private func handleStatusChange(status: AVPlayer.Status) {
        switch status {
        case .unknown:
            notifyStateChanged(state: "idle", isBuffering: false)
        case .readyToPlay:
            print("MediaPlayerInstance: Player status changed to readyToPlay")
            notifyStateChanged(state: "ready", isBuffering: false)
            notifyDurationChanged()

            // Re-bind only the topmost live view when ready (others stay
            // unbound to avoid multiple layers on one AVPlayer → grey).
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                print("MediaPlayerInstance: Re-activating topmost live view on ready state")
                self.activateTopmostView()
            }
        case .failed:
            print("MediaPlayerInstance: Player failed with error: \(avPlayer?.error?.localizedDescription ?? "Unknown")")
            notifyError(error: avPlayer?.error?.localizedDescription ?? "Unknown error")
        @unknown default:
            break
        }
    }

    private func handleRateChange(rate: Float) {
        if rate > 0 {
            notifyStateChanged(state: "playing", isBuffering: false)
        } else {
            notifyStateChanged(state: "paused", isBuffering: false)
        }
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
            notifyError(error: error.localizedDescription)
        }
    }

    // Note: observeValue is no longer needed - we use modern KVO (NSKeyValueObservation)
    // which handles observation via closures. The old-style KVO that required this method
    // has been replaced with modern Swift observers in loadMediaItem().

    private func handlePlayerItemStatusChange(status: AVPlayerItem.Status) {
        print("MediaPlayerInstance: PlayerItem status changed to: \(status.rawValue)")

        switch status {
        case .unknown:
            print("MediaPlayerInstance: PlayerItem status = unknown")
            notifyStateChanged(state: "buffering", isBuffering: true)
        case .readyToPlay:
            print("MediaPlayerInstance: PlayerItem status = readyToPlay")
            // Check if player is currently playing to set correct state.
            // Uses timeControlStatus (not `rate > 0`) for the same reason as
            // isPlaying(): a player that has been told to play but is still
            // buffering has rate == 0 yet is not "ready but not playing".
            if let player = avPlayer, player.timeControlStatus != .paused {
                print("MediaPlayerInstance: Player is playing (rate: \(player.rate))")
                notifyStateChanged(state: "playing", isBuffering: false)
            } else {
                print("MediaPlayerInstance: Player is ready but not playing")
                notifyStateChanged(state: "ready", isBuffering: false)
            }
            notifyDurationChanged()

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
            print("MediaPlayerInstance: PlayerItem status = failed")
            if let error = avPlayer?.currentItem?.error {
                notifyError(error: error.localizedDescription)
            } else {
                notifyError(error: "Player item failed to load")
            }
        @unknown default:
            print("MediaPlayerInstance: PlayerItem status = unknown default")
            break
        }
    }

    private func notifyStateChanged(state: String, isBuffering: Bool) {
        let arguments: [String: Any] = [
            "playerId": playerId,
            "state": state,
            "isBuffering": isBuffering,
            "bufferPercentage": 0 // iOS doesn't provide easy access to buffer percentage
        ]
        methodChannel.invokeMethod("onStateChanged", arguments: arguments)
    }

    private func notifyPositionChanged(position: Int64) {
        let arguments: [String: Any] = [
            "playerId": playerId,
            "position": Int(position)
        ]
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
            print("MediaPlayerInstance: Cannot extract tracks - no player item or not AVURLAsset")
            return
        }

        var qualityTracks: [[String: Any]] = []
        var seenBitrates = Set<Int>()

        // Try to parse HLS manifest directly for the most accurate results
        parseHLSManifest(url: asset.url) { [weak self] manifestTracks in
            guard let self = self else { return }

            if !manifestTracks.isEmpty {
                print("MediaPlayerInstance: Parsed \(manifestTracks.count) quality tracks from HLS manifest")
                self.notifyQualityTracksChanged(tracks: manifestTracks)
                return
            }

            // Fallback: For iOS 15+, use AVAssetVariant API
            if #available(iOS 15.0, *) {
                if let variants = asset.variants as? [AVAssetVariant] {
                    print("MediaPlayerInstance: Found \(variants.count) variants from AVAsset")

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
                print("MediaPlayerInstance: Trying access log fallback")

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
                print("MediaPlayerInstance: Notifying \(qualityTracks.count) quality tracks")
                self.notifyQualityTracksChanged(tracks: qualityTracks)
            } else {
                print("MediaPlayerInstance: No quality tracks found")
            }
        }
    }

    private func parseHLSManifest(url: URL, completion: @escaping ([[String: Any]]) -> Void) {
        // Only parse if it's an HLS URL (.m3u8)
        guard url.absoluteString.contains(".m3u8") else {
            print("MediaPlayerInstance: Not an HLS URL, skipping manifest parsing")
            completion([])
            return
        }

        print("MediaPlayerInstance: Fetching HLS manifest from: \(url)")

        // Parse HLS master playlist to extract all variant streams
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("MediaPlayerInstance: Failed to fetch HLS manifest: \(error.localizedDescription)")
                completion([])
                return
            }

            guard let data = data,
                  let manifestString = String(data: data, encoding: .utf8) else {
                print("MediaPlayerInstance: Failed to decode HLS manifest data")
                completion([])
                return
            }

            print("MediaPlayerInstance: Fetched HLS manifest (\(manifestString.count) chars), parsing...")
            var tracks: [[String: Any]] = []
            var seenBitrates = Set<Int>()

            // Parse #EXT-X-STREAM-INF lines
            let lines = manifestString.components(separatedBy: .newlines)

            for (lineNum, line) in lines.enumerated() {
                if line.hasPrefix("#EXT-X-STREAM-INF:") {
                    print("MediaPlayerInstance: Found STREAM-INF at line \(lineNum): \(line)")

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

                                print("MediaPlayerInstance: Parsed variant: \(finalHeight)p @ \(bandwidth / 1000)kbps, resolution: \(finalWidth)x\(finalHeight)")
                            }
                        }
                    }
                }
            }

            print("MediaPlayerInstance: Parsed \(tracks.count) tracks from manifest")
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
            print("MediaPlayerInstance: Cannot extract audio tracks - no player item or not AVURLAsset")
            return
        }

        var audioTracks: [[String: Any]] = []

        // Get audio media selection group
        if let audioGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            print("MediaPlayerInstance: Found \(audioGroup.options.count) audio options")

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
            print("MediaPlayerInstance: No audio selection group found")
        }

        // ALWAYS notify, even with empty list (to clear UI when switching videos)
        print("MediaPlayerInstance: Found \(audioTracks.count) audio tracks")
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
            print("MediaPlayerInstance: Cannot extract subtitle tracks - no player item or not AVURLAsset")
            return
        }

        var subtitleTracks: [[String: Any]] = []

        // Get legible (subtitle/caption) media selection group
        if let subtitleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
            print("MediaPlayerInstance: Found \(subtitleGroup.options.count) subtitle options")

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
            print("MediaPlayerInstance: No subtitle selection group found")
        }

        // ALWAYS notify, even with empty list (to clear UI when switching to video without subtitles)
        print("MediaPlayerInstance: Found \(subtitleTracks.count) subtitle tracks")
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

    private func notifyError(error: String) {
        let arguments: [String: Any] = [
            "playerId": playerId,
            "error": error
        ]
        methodChannel.invokeMethod("onError", arguments: arguments)
    }
}

enum MediaPlayerError: Error {
    case playerNotFound
    case invalidConfiguration
    case loadFailed(String)
}
