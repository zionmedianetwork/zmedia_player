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
            self?.sendActionToFlutter("seek_forward")
            return .success
        }
        
        // Seek backward command
        remoteCommandCenter.skipBackwardCommand.isEnabled = true
        remoteCommandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: seekInterval)]
        remoteCommandCenter.skipBackwardCommand.addTarget { [weak self] event in
            print("NotificationHandler: Skip backward command received")
            self?.sendActionToFlutter("seek_backward")
            return .success
        }
        
        // Change playback position command
        remoteCommandCenter.changePlaybackPositionCommand.isEnabled = true
        remoteCommandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                let position = event.positionTime
                print("NotificationHandler: Change playback position to: \(position)")
                // Could send seek event to Flutter if needed
            }
            return .success
        }
        
        print("NotificationHandler: Remote command center configured")
    }
    
    // MARK: - Show/Update Notification
    
    func showNotification(mediaItem: [String: Any], state: [String: Any]) {
        print("NotificationHandler: Showing notification")
        
        // Update media info
        currentTitle = mediaItem["title"] as? String ?? "Unknown Title"
        currentArtist = mediaItem["artist"] as? String
        currentAlbum = mediaItem["album"] as? String
        currentArtworkUrl = mediaItem["artworkUrl"] as? String
        
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
        
        // Load artwork if needed
        if let artworkUrl = currentArtworkUrl, currentArtwork == nil {
            loadArtwork(from: artworkUrl)
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
                    // Create MPMediaItemArtwork
                    self.currentArtwork = MPMediaItemArtwork(boundsSize: image.size) { size in
                        return image
                    }
                    
                    // Update now playing info on main thread
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
    
    // MARK: - Dismiss Notification
    
    func dismiss() {
        print("NotificationHandler: Dismissing notification")
        
        // Clear now playing info
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

