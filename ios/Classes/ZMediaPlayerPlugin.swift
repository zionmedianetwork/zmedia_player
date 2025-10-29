import Flutter
import UIKit
import AVFoundation

public class ZMediaPlayerPlugin: NSObject, FlutterPlugin {
    private var playerManager: MediaPlayerManager!
    private var methodChannel: FlutterMethodChannel!
    
    // Phase 3: Handler maps
    private var notificationHandlers: [String: NotificationHandler] = [:]
    private var pipHandlers: [String: PipHandler] = [:]
    private var airPlayHandlers: [String: AirPlayHandler] = [:]
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "zmedia_player", binaryMessenger: registrar.messenger())
        let instance = ZMediaPlayerPlugin()
        
        // Initialize player manager
        instance.methodChannel = channel
        instance.playerManager = MediaPlayerManager(methodChannel: channel)
        
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        // Register platform view factory
        registrar.register(
            MediaPlayerViewFactory(playerManager: instance.playerManager),
            withId: "zmedia_player_view"
        )
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            handleInitialize(call, result: result)
        case "load":
            handleLoad(call, result: result)
        case "setPlaylist":
            handleSetPlaylist(call, result: result)
        case "play":
            handlePlay(call, result: result)
        case "pause":
            handlePause(call, result: result)
        case "stop":
            handleStop(call, result: result)
        case "seekTo":
            handleSeekTo(call, result: result)
        case "setVolume":
            handleSetVolume(call, result: result)
        case "setSpeed":
            handleSetSpeed(call, result: result)
        case "setMuted":
            handleSetMuted(call, result: result)
        case "setBoxFit":
            handleSetBoxFit(call, result: result)
        case "setSubtitleTrack":
            handleSetSubtitleTrack(call, result: result)
        case "setQualityTrack":
            handleSetQualityTrack(call, result: result)
        case "setAudioTrack":
            handleSetAudioTrack(call, result: result)
        case "enableAutoQuality":
            handleEnableAutoQuality(call, result: result)
        case "skipToIndex":
            handleSkipToIndex(call, result: result)
        case "updateConfig":
            handleUpdateConfig(call, result: result)
        case "dispose":
            handleDispose(call, result: result)

        // Phase 1: Buffering handlers
        case "getBufferHealth":
            handleGetBufferHealth(call, result: result)

        // Phase 3: Notification handlers
        case "initializeNotification":
            handleInitializeNotification(call, result: result)
        case "showNotification":
            handleShowNotification(call, result: result)
        case "updateNotificationState":
            handleUpdateNotificationState(call, result: result)
        case "updateNotificationPosition":
            handleUpdateNotificationPosition(call, result: result)
        case "dismissNotification":
            handleDismissNotification(call, result: result)
            
        // Phase 3: PiP handlers
        case "checkPipAvailability":
            handleCheckPipAvailability(call, result: result)
        case "enterPictureInPicture":
            handleEnterPictureInPicture(call, result: result)
        case "exitPictureInPicture":
            handleExitPictureInPicture(call, result: result)
            
        // Phase 3: Cast/AirPlay handlers
        case "initializeCast":
            handleInitializeCast(call, result: result)
        case "startCastDiscovery":
            handleStartCastDiscovery(call, result: result)
        case "stopCastDiscovery":
            handleStopCastDiscovery(call, result: result)
        case "connectToCastDevice":
            handleConnectToCastDevice(call, result: result)
        case "disconnectFromCastDevice":
            handleDisconnectFromCastDevice(call, result: result)
        case "loadMediaOnCastDevice":
            handleLoadMediaOnCastDevice(call, result: result)
        case "castPlay":
            handleCastPlay(call, result: result)
        case "castPause":
            handleCastPause(call, result: result)
        case "castSeekTo":
            handleCastSeekTo(call, result: result)
        case "castSetVolume":
            handleCastSetVolume(call, result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handleInitialize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID is required", details: nil))
            return
        }
        
        let config = args["config"] as? [String: Any]
        
        do {
            try playerManager.initializePlayer(playerId: playerId, config: config)
            result(nil)
        } catch {
            result(FlutterError(code: "INITIALIZATION_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handleLoad(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let mediaItem = args["mediaItem"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and media item are required", details: nil))
            return
        }
        
        do {
            try playerManager.loadMediaItem(playerId: playerId, mediaItem: mediaItem)
            result(nil)
        } catch {
            result(FlutterError(code: "LOAD_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handleSetPlaylist(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let playlist = args["playlist"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and playlist are required", details: nil))
            return
        }
        
        let startIndex = args["startIndex"] as? Int ?? 0
        
        do {
            try playerManager.setPlaylist(playerId: playerId, playlist: playlist, startIndex: startIndex)
            result(nil)
        } catch {
            result(FlutterError(code: "PLAYLIST_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handlePlay(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID is required", details: nil))
            return
        }
        
        do {
            try playerManager.play(playerId: playerId)
            result(nil)
        } catch {
            result(FlutterError(code: "PLAY_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handlePause(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID is required", details: nil))
            return
        }
        
        do {
            try playerManager.pause(playerId: playerId)
            result(nil)
        } catch {
            result(FlutterError(code: "PAUSE_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handleStop(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID is required", details: nil))
            return
        }
        
        do {
            try playerManager.stop(playerId: playerId)
            result(nil)
        } catch {
            result(FlutterError(code: "STOP_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handleSeekTo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let position = args["position"] as? Int64 else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and position are required", details: nil))
            return
        }
        
        do {
            try playerManager.seekTo(playerId: playerId, position: position)
            result(nil)
        } catch {
            result(FlutterError(code: "SEEK_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handleSetVolume(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let volume = args["volume"] as? Double else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and volume are required", details: nil))
            return
        }
        
        do {
            try playerManager.setVolume(playerId: playerId, volume: Float(volume))
            result(nil)
        } catch {
            result(FlutterError(code: "VOLUME_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handleSetSpeed(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let speed = args["speed"] as? Double else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and speed are required", details: nil))
            return
        }
        
        do {
            try playerManager.setPlaybackSpeed(playerId: playerId, speed: Float(speed))
            result(nil)
        } catch {
            result(FlutterError(code: "SPEED_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handleSetMuted(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let muted = args["muted"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and muted state are required", details: nil))
            return
        }
        
        do {
            try playerManager.setMuted(playerId: playerId, muted: muted)
            result(nil)
        } catch {
            result(FlutterError(code: "MUTE_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handleSetBoxFit(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let boxFit = args["boxFit"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and box fit are required", details: nil))
            return
        }
        
        do {
            try playerManager.setBoxFit(playerId: playerId, boxFit: boxFit)
            result(nil)
        } catch {
            result(FlutterError(code: "BOXFIT_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handleSetSubtitleTrack(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID is required", details: nil))
            return
        }
        
        let subtitleTrack = args["subtitleTrack"] as? [String: Any]
        
        do {
            try playerManager.setSubtitleTrack(playerId: playerId, subtitleTrack: subtitleTrack)
            result(nil)
        } catch {
            result(FlutterError(code: "SUBTITLE_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handleSetQualityTrack(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let qualityTrack = args["qualityTrack"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and quality track are required", details: nil))
            return
        }
        
        do {
            try playerManager.setQualityTrack(playerId: playerId, qualityTrack: qualityTrack)
            result(nil)
        } catch {
            result(FlutterError(code: "QUALITY_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handleSetAudioTrack(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let audioTrack = args["audioTrack"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and audio track are required", details: nil))
            return
        }
        
        do {
            try playerManager.setAudioTrack(playerId: playerId, audioTrack: audioTrack)
            result(nil)
        } catch {
            result(FlutterError(code: "AUDIO_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handleEnableAutoQuality(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID is required", details: nil))
            return
        }
        
        do {
            try playerManager.enableAutoQuality(playerId: playerId)
            result(nil)
        } catch {
            result(FlutterError(code: "AUTO_QUALITY_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handleSkipToIndex(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let index = args["index"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and index are required", details: nil))
            return
        }
        
        do {
            try playerManager.skipToIndex(playerId: playerId, index: index)
            result(nil)
        } catch {
            result(FlutterError(code: "SKIP_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handleUpdateConfig(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let config = args["config"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and config are required", details: nil))
            return
        }
        
        do {
            try playerManager.updateConfig(playerId: playerId, config: config)
            result(nil)
        } catch {
            result(FlutterError(code: "CONFIG_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func handleDispose(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID is required", details: nil))
            return
        }
        
        // Dispose Phase 3 handlers
        notificationHandlers[playerId]?.dispose()
        notificationHandlers.removeValue(forKey: playerId)
        
        pipHandlers[playerId]?.dispose()
        pipHandlers.removeValue(forKey: playerId)
        
        airPlayHandlers[playerId]?.dispose()
        airPlayHandlers.removeValue(forKey: playerId)
        
        do {
            try playerManager.disposePlayer(playerId: playerId)
            result(nil)
        } catch {
            result(FlutterError(code: "DISPOSE_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Phase 1: Buffering Handlers

    private func handleGetBufferHealth(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID is required", details: nil))
            return
        }

        let bufferHealth = playerManager.getBufferHealth(playerId: playerId)
        result(bufferHealth)
    }

    // MARK: - Phase 3: Notification Handlers
    
    private func handleInitializeNotification(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let config = args["config"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and config are required", details: nil))
            return
        }
        
        let handler = NotificationHandler(playerId: playerId, channel: methodChannel)
        handler.initialize(config: config)
        notificationHandlers[playerId] = handler
        
        result(nil)
    }
    
    private func handleShowNotification(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let mediaItem = args["mediaItem"] as? [String: Any],
              let state = args["state"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID, media item, and state are required", details: nil))
            return
        }
        
        guard let handler = notificationHandlers[playerId] else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Notification handler not initialized", details: nil))
            return
        }
        
        handler.showNotification(mediaItem: mediaItem, state: state)
        result(nil)
    }
    
    private func handleUpdateNotificationState(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let state = args["state"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and state are required", details: nil))
            return
        }
        
        guard let handler = notificationHandlers[playerId] else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Notification handler not initialized", details: nil))
            return
        }
        
        handler.updateState(state: state)
        result(nil)
    }
    
    private func handleUpdateNotificationPosition(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let position = args["position"] as? Int64 else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and position are required", details: nil))
            return
        }
        
        guard let handler = notificationHandlers[playerId] else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Notification handler not initialized", details: nil))
            return
        }
        
        handler.updatePosition(position: position)
        result(nil)
    }
    
    private func handleDismissNotification(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID is required", details: nil))
            return
        }
        
        guard let handler = notificationHandlers[playerId] else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Notification handler not initialized", details: nil))
            return
        }
        
        handler.dismiss()
        result(nil)
    }
    
    // MARK: - Phase 3: PiP Handlers
    
    private func handleCheckPipAvailability(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID is required", details: nil))
            return
        }
        
        print("ZMediaPlayerPlugin: checkPipAvailability called for player: \(playerId)")
        
        // Get or create PiP handler
        var handler = pipHandlers[playerId]
        if handler == nil {
            print("ZMediaPlayerPlugin: Creating new PiP handler for \(playerId)")
            handler = PipHandler(playerId: playerId, channel: methodChannel)
            pipHandlers[playerId] = handler
        } else {
            print("ZMediaPlayerPlugin: Using existing PiP handler for \(playerId)")
        }
        
        // Always re-initialize with current player and player layer (in case media changed)
        do {
            if let player = try playerManager.getPlayer(playerId: playerId) {
                print("ZMediaPlayerPlugin: Got player: \(player)")
                
                if let playerLayer = try playerManager.getPlayerLayer(playerId: playerId) {
                    print("ZMediaPlayerPlugin: Got player layer: \(playerLayer)")
                    handler?.initialize(player: player, playerLayer: playerLayer)
                } else {
                    print("ZMediaPlayerPlugin: WARNING - Could not get player layer")
                }
            } else {
                print("ZMediaPlayerPlugin: WARNING - Could not get player")
            }
        } catch {
            print("ZMediaPlayerPlugin: ERROR getting player/layer: \(error)")
        }
        
        let isAvailable = handler?.checkAvailability() ?? false
        print("ZMediaPlayerPlugin: PiP availability result: \(isAvailable)")
        result(isAvailable)
    }
    
    private func handleEnterPictureInPicture(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID is required", details: nil))
            return
        }
        
        let config = args["config"] as? [String: Any]
        
        // Get or create PiP handler
        var handler = pipHandlers[playerId]
        if handler == nil {
            handler = PipHandler(playerId: playerId, channel: methodChannel)
            pipHandlers[playerId] = handler
        }
        
        // Always re-initialize with current player and player layer before entering PiP
        if let player = try? playerManager.getPlayer(playerId: playerId),
           let playerLayer = try? playerManager.getPlayerLayer(playerId: playerId) {
            handler?.initialize(player: player, playerLayer: playerLayer)
        }
        
        let success = handler?.enterPip(config: config) ?? false
        result(success)
    }
    
    private func handleExitPictureInPicture(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID is required", details: nil))
            return
        }
        
        guard let handler = pipHandlers[playerId] else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "PiP handler not initialized", details: nil))
            return
        }
        
        handler.exitPip()
        result(nil)
    }
    
    // MARK: - Phase 3: Cast/AirPlay Handlers
    
    private func handleInitializeCast(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let config = args["config"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and config are required", details: nil))
            return
        }
        
        let handler = AirPlayHandler(playerId: playerId, channel: methodChannel)
        
        // Get player from manager
        if let player = try? playerManager.getPlayer(playerId: playerId),
           let playerLayer = try? playerManager.getPlayerLayer(playerId: playerId) {
            handler.initialize(config: config, player: player)
        }
        
        airPlayHandlers[playerId] = handler
        result(nil)
    }
    
    private func handleStartCastDiscovery(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID is required", details: nil))
            return
        }
        
        guard let handler = airPlayHandlers[playerId] else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "AirPlay handler not initialized", details: nil))
            return
        }
        
        handler.startDiscovery()
        result(nil)
    }
    
    private func handleStopCastDiscovery(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID is required", details: nil))
            return
        }
        
        guard let handler = airPlayHandlers[playerId] else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "AirPlay handler not initialized", details: nil))
            return
        }
        
        handler.stopDiscovery()
        result(nil)
    }
    
    private func handleConnectToCastDevice(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let deviceId = args["deviceId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and device ID are required", details: nil))
            return
        }
        
        guard let handler = airPlayHandlers[playerId] else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "AirPlay handler not initialized", details: nil))
            return
        }
        
        let success = handler.connect(deviceId: deviceId)
        result(success)
    }
    
    private func handleDisconnectFromCastDevice(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID is required", details: nil))
            return
        }
        
        guard let handler = airPlayHandlers[playerId] else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "AirPlay handler not initialized", details: nil))
            return
        }
        
        handler.disconnect()
        result(nil)
    }
    
    private func handleLoadMediaOnCastDevice(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let mediaItem = args["mediaItem"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and media item are required", details: nil))
            return
        }
        
        guard let handler = airPlayHandlers[playerId] else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "AirPlay handler not initialized", details: nil))
            return
        }
        
        handler.loadMedia(mediaItem: mediaItem)
        result(nil)
    }
    
    private func handleCastPlay(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID is required", details: nil))
            return
        }
        
        guard let handler = airPlayHandlers[playerId] else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "AirPlay handler not initialized", details: nil))
            return
        }
        
        handler.play()
        result(nil)
    }
    
    private func handleCastPause(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID is required", details: nil))
            return
        }
        
        guard let handler = airPlayHandlers[playerId] else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "AirPlay handler not initialized", details: nil))
            return
        }
        
        handler.pause()
        result(nil)
    }
    
    private func handleCastSeekTo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let position = args["position"] as? Int64 else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and position are required", details: nil))
            return
        }
        
        guard let handler = airPlayHandlers[playerId] else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "AirPlay handler not initialized", details: nil))
            return
        }
        
        handler.seekTo(position: position)
        result(nil)
    }
    
    private func handleCastSetVolume(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? String,
              let volume = args["volume"] as? Double else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Player ID and volume are required", details: nil))
            return
        }
        
        guard let handler = airPlayHandlers[playerId] else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "AirPlay handler not initialized", details: nil))
            return
        }
        
        handler.setVolume(volume: volume)
        result(nil)
    }
}
