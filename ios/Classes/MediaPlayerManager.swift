import Foundation
import AVFoundation
import AVKit
import Flutter

class MediaPlayerManager {
    private var players: [String: MediaPlayerInstance] = [:]
    private let methodChannel: FlutterMethodChannel
    
    init(methodChannel: FlutterMethodChannel) {
        self.methodChannel = methodChannel
    }
    
    func initializePlayer(playerId: String, config: [String: Any]?) throws {
        let playerInstance = MediaPlayerInstance(playerId: playerId, methodChannel: methodChannel, config: config)
        players[playerId] = playerInstance
    }
    
    func loadMediaItem(playerId: String, mediaItem: [String: Any]) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.loadMediaItem(mediaItem: mediaItem)
    }
    
    func setPlaylist(playerId: String, playlist: [String: Any], startIndex: Int) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.setPlaylist(playlist: playlist, startIndex: startIndex)
    }
    
    func play(playerId: String) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.play()
    }
    
    func pause(playerId: String) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.pause()
    }
    
    func stop(playerId: String) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.stop()
    }
    
    func seekTo(playerId: String, position: Int64) throws {
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
    
    func disposePlayer(playerId: String) throws {
        guard let playerInstance = players[playerId] else {
            throw MediaPlayerError.playerNotFound
        }
        playerInstance.dispose()
        players.removeValue(forKey: playerId)
    }
    
    func dispose() {
        players.values.forEach { $0.dispose() }
        players.removeAll()
    }
}

class MediaPlayerInstance: NSObject {
    private let playerId: String
    private let methodChannel: FlutterMethodChannel
    private var config: [String: Any]?
    
    private var avPlayer: AVPlayer?
    private var playerView: MediaPlayerView?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    
    private var currentPlaylist: [[String: Any]]?
    private var currentIndex = 0
    
    init(playerId: String, methodChannel: FlutterMethodChannel, config: [String: Any]?) {
        self.playerId = playerId
        self.methodChannel = methodChannel
        self.config = config
        
        super.init()
        initializeAVPlayer()
    }
    
    private func initializeAVPlayer() {
        avPlayer = AVPlayer()
        setupObservers()
        applyConfig()
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
        
        // Notification observers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFailWithError),
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
        
        // Create AVURLAsset with custom headers if provided
        var asset: AVURLAsset
        if let httpHeaders = mediaItem["httpHeaders"] as? [String: String] {
            let options = ["AVURLAssetHTTPHeaderFieldsKey": httpHeaders]
            asset = AVURLAsset(url: url, options: options)
        } else {
            asset = AVURLAsset(url: url)
        }
        
        let playerItem = AVPlayerItem(asset: asset)
        
        // Add observer for duration
        playerItem.addObserver(self, forKeyPath: "duration", options: [.new], context: nil)
        
        avPlayer?.replaceCurrentItem(with: playerItem)
        
        // Update the player view if it exists
        playerView?.updatePlayer(avPlayer)
        
        // Auto play if configured
        if config?["autoPlay"] as? Bool == true {
            avPlayer?.play()
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
        avPlayer?.play()
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
        let clampedSpeed = max(0.25, min(4.0, speed))
        avPlayer?.rate = clampedSpeed
    }
    
    func setMuted(muted: Bool) {
        avPlayer?.isMuted = muted
    }
    
    func setBoxFit(boxFit: String) {
        playerView?.setVideoGravity(boxFit: boxFit)
    }
    
    func setSubtitleTrack(subtitleTrack: [String: Any]?) {
        // Subtitle track selection will be implemented in Phase 2
        // For now, just acknowledge the call
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
    
    func getPlayerView() -> MediaPlayerView {
        if playerView == nil {
            print("MediaPlayerInstance.getPlayerView(): Creating new player view with player: \(avPlayer != nil)")
            playerView = MediaPlayerView(player: avPlayer)
        } else {
            // Ensure the existing player view has the current player
            print("MediaPlayerInstance.getPlayerView(): Updating existing player view")
            playerView?.updatePlayer(avPlayer)
        }
        return playerView!
    }
    
    func dispose() {
        // Remove observers
        if let timeObserver = timeObserver {
            avPlayer?.removeTimeObserver(timeObserver)
        }
        statusObserver?.invalidate()
        rateObserver?.invalidate()
        
        NotificationCenter.default.removeObserver(self)
        
        // Clean up player
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        avPlayer = nil
        playerView = nil
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
        
        // Apply playback speed
        if let speed = config["speed"] as? Double {
            player.rate = Float(speed)
        }
        
        // Apply BoxFit
        if let boxFit = config["boxFit"] as? String {
            playerView?.setVideoGravity(boxFit: boxFit)
        }
    }
    
    private func handleStatusChange(status: AVPlayer.Status) {
        switch status {
        case .unknown:
            notifyStateChanged(state: "idle", isBuffering: false)
        case .readyToPlay:
            notifyStateChanged(state: "ready", isBuffering: false)
            notifyDurationChanged()
        case .failed:
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
    
    @objc private func playerDidFinishPlaying() {
        notifyStateChanged(state: "completed", isBuffering: false)
    }
    
    @objc private func playerDidFailWithError(notification: Notification) {
        if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
            notifyError(error: error.localizedDescription)
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "duration" {
            notifyDurationChanged()
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
    
    private func notifyDurationChanged() {
        guard let duration = avPlayer?.currentItem?.duration,
              duration.isValid && !duration.isIndefinite else { return }
        
        let durationMs = Int(duration.seconds * 1000)
        let arguments: [String: Any] = [
            "playerId": playerId,
            "duration": durationMs
        ]
        methodChannel.invokeMethod("onDurationChanged", arguments: arguments)
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
