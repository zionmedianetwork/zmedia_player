import Flutter
import UIKit
import AVFoundation

public class FlutterMediaPlayerPlugin: NSObject, FlutterPlugin {
    private var playerManager: MediaPlayerManager!
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_media_player", binaryMessenger: registrar.messenger())
        let instance = FlutterMediaPlayerPlugin()
        
        // Initialize player manager
        instance.playerManager = MediaPlayerManager(methodChannel: channel)
        
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        // Register platform view factory
        registrar.register(
            MediaPlayerViewFactory(playerManager: instance.playerManager),
            withId: "flutter_media_player_view"
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
        case "skipToIndex":
            handleSkipToIndex(call, result: result)
        case "updateConfig":
            handleUpdateConfig(call, result: result)
        case "dispose":
            handleDispose(call, result: result)
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
        
        do {
            try playerManager.disposePlayer(playerId: playerId)
            result(nil)
        } catch {
            result(FlutterError(code: "DISPOSE_ERROR", message: error.localizedDescription, details: nil))
        }
    }
}
