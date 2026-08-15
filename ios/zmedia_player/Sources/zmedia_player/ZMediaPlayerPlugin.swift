import Flutter
import UIKit
import AVFoundation

public class ZMediaPlayerPlugin: NSObject, FlutterPlugin {
    private var playerManager: MediaPlayerManager!
    private var methodChannel: FlutterMethodChannel!

    /// M-16: wire protocol version for the MethodChannel contract with the
    /// Dart package (see `MediaPlayer.protocolVersion` in
    /// lib/src/core/media_player.dart). Bump alongside a matching Dart-side
    /// bump whenever a MethodChannel contract change requires native to be
    /// rebuilt to stay compatible. Mirrored on Android by
    /// `ZMediaPlayerPlugin.NATIVE_PROTOCOL_VERSION` in ZMediaPlayerPlugin.kt.
    private static let nativeProtocolVersion = 1

    /// Oldest Dart `protocolVersion` this native implementation still
    /// accepts. The package is distributed by git ref (not pub.dev), so a
    /// host app can end up running a newer Dart package against a stale
    /// cached/compiled native build — `handleInitialize` rejects that
    /// combination explicitly instead of letting later calls fail
    /// ambiguously via a raw `MissingPluginException`.
    private static let minSupportedDartProtocolVersion = 1

    // Phase 3: Handler maps
    private var notificationHandlers: [String: NotificationHandler] = [:]
    private var pipHandlers: [String: PipHandler] = [:]
    private var airPlayHandlers: [String: AirPlayHandler] = [:]

    // Phase 1: Secure storage
    private var secureStorageChannel: FlutterMethodChannel!
    private var secureStorageHandler: SecureStorageHandler!

    // H-06: single, plugin-lifetime NetworkMonitor (not one per playerId —
    // connectivity is a device-global signal, not a per-player one, so a
    // per-player NWPathMonitor would just be N redundant registrations of
    // the same system monitor). Started in `register(with:)`, stopped in
    // `detachFromEngine(for:)`, mirroring how `playerManager` is created in
    // `register(with:)` — the closest thing this file has to an
    // "attach"/"detach" pair for plugin-lifetime resources.
    private var networkMonitor: NetworkMonitor!

    // Player ids currently between a successful `initialize` and `dispose`
    // call, used to fan the single NetworkMonitor's events out to every live
    // MediaPlayer instance on the Dart side (each event is dispatched by
    // playerId — see MediaPlayer._staticMethodCallHandler).
    private var activePlayerIds: Set<String> = []

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "zmedia_player", binaryMessenger: registrar.messenger())
        let instance = ZMediaPlayerPlugin()

        // Initialize player manager
        instance.methodChannel = channel
        instance.playerManager = MediaPlayerManager(methodChannel: channel)

        registrar.addMethodCallDelegate(instance, channel: channel)

        // Phase 1: Initialize secure storage channel
        let secureStorageChannel = FlutterMethodChannel(
            name: "zmedia_player/secure_storage",
            binaryMessenger: registrar.messenger()
        )
        instance.secureStorageChannel = secureStorageChannel
        instance.secureStorageHandler = SecureStorageHandler()
        registrar.addMethodCallDelegate(instance.secureStorageHandler, channel: secureStorageChannel)

        // Register platform view factories
        registrar.register(
            MediaPlayerViewFactory(playerManager: instance.playerManager),
            withId: "zmedia_player_view"
        )

        // Register AirPlay button factory
        registrar.register(
            AirPlayButtonFactory(messenger: registrar.messenger()),
            withId: "zmedia_player/airplay_button"
        )

        // H-06: start device-wide connectivity monitoring for the lifetime
        // of the plugin (see the `networkMonitor` field doc for why this is
        // one instance rather than one per player).
        instance.networkMonitor = NetworkMonitor(callback: instance)
        instance.networkMonitor.startMonitoring()
    }

    /// H-06: unregisters the `NWPathMonitor` when the plugin detaches from
    /// the engine. `NetworkMonitor.deinit` also calls `stopMonitoring()`,
    /// but that only runs once nothing still retains this instance — this
    /// explicit call ensures the monitor stops promptly on detach rather
    /// than depending on `ZMediaPlayerPlugin` itself being deallocated.
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        networkMonitor?.stopMonitoring()
        activePlayerIds.removeAll()
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

        // Surface reclaim — no-op on iOS because AVPlayer supports multiple
        // AVPlayerLayers simultaneously.  Each new UiKitView host creates its
        // own MediaPlayerView with a fresh AVPlayerLayer wired to the shared
        // AVPlayer, so no explicit re-attachment is required.  Returning nil
        // (success) prevents the Dart caller from receiving a PlatformException.
        case "reclaimVideoSurface":
            result(nil)

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
        let dartProtocolVersion = args["protocolVersion"] as? Int

        // M-16: reject a Dart package too old for this native build before
        // doing anything else. A nil dartProtocolVersion means the Dart side
        // predates version negotiation entirely — allow it through unchanged
        // (nothing to compare against).
        if let dartProtocolVersion = dartProtocolVersion,
           dartProtocolVersion < ZMediaPlayerPlugin.minSupportedDartProtocolVersion {
            result(FlutterError(
                code: "PROTOCOL_VERSION_MISMATCH",
                message: "Dart package protocol v\(dartProtocolVersion) is older than the minimum "
                    + "v\(ZMediaPlayerPlugin.minSupportedDartProtocolVersion) this native plugin "
                    + "(v\(ZMediaPlayerPlugin.nativeProtocolVersion)) requires. Rebuild the app "
                    + "against a matching zmedia_player native version.",
                details: [
                    "nativeProtocolVersion": ZMediaPlayerPlugin.nativeProtocolVersion,
                    "minSupportedDartProtocolVersion": ZMediaPlayerPlugin.minSupportedDartProtocolVersion,
                    "dartProtocolVersion": dartProtocolVersion
                ]
            ))
            return
        }

        do {
            try playerManager.initializePlayer(playerId: playerId, config: config)
            // H-06: track this playerId so NetworkMonitor events (which are
            // device-global, not per-player) can be fanned out to it — see
            // the NetworkMonitor.NetworkCallback conformance below.
            activePlayerIds.insert(playerId)
            // H-06 snapshot fix: NetworkMonitor.startMonitoring() runs once,
            // at plugin attach, and only fans events out to players present
            // in activePlayerIds *at the moment an event fires*. A player
            // initialized after the last connectivity transition would
            // otherwise never learn the current status and would read
            // `networkStatus` as "unknown" indefinitely. Emit the
            // synchronously-queried current status to this player right now
            // so its Dart-side NetworkStatus starts correct instead of
            // waiting for the next transition. Mirrors the equivalent fix in
            // `ZMediaPlayerPlugin.kt`'s `handleInitialize`.
            if let channel = methodChannel {
                let currentStatus = networkMonitor.getCurrentNetworkStatus()
                var payload = currentStatus
                payload["playerId"] = playerId
                channel.invokeMethod("onNetworkStatusChanged", arguments: payload)
            }
            // Report our own version back so Dart can, symmetrically, detect
            // a native build too old for what it's about to call (see
            // MediaPlayer.initialize()'s minSupportedNativeProtocolVersion
            // check).
            result(["protocolVersion": ZMediaPlayerPlugin.nativeProtocolVersion])
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

        // H-06: stop fanning NetworkMonitor events to this playerId.
        activePlayerIds.remove(playerId)

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

        zlog("ZMediaPlayerPlugin: checkPipAvailability called for player: \(playerId)")

        // Get or create PiP handler
        var handler = pipHandlers[playerId]
        if handler == nil {
            zlog("ZMediaPlayerPlugin: Creating new PiP handler for \(playerId)")
            handler = PipHandler(playerId: playerId, channel: methodChannel)
            pipHandlers[playerId] = handler
        } else {
            zlog("ZMediaPlayerPlugin: Using existing PiP handler for \(playerId)")
        }

        let pipConfig = args["config"] as? [String: Any]

        // Always re-initialize with current player and player layer (in case media changed)
        do {
            if let player = try playerManager.getPlayer(playerId: playerId) {
                zlog("ZMediaPlayerPlugin: Got player: \(player)")

                if let playerLayer = try playerManager.getPlayerLayer(playerId: playerId) {
                    zlog("ZMediaPlayerPlugin: Got player layer: \(playerLayer)")
                    handler?.initialize(player: player, playerLayer: playerLayer, config: pipConfig)
                } else {
                    zlog("ZMediaPlayerPlugin: WARNING - Could not get player layer")
                }
            } else {
                zlog("ZMediaPlayerPlugin: WARNING - Could not get player")
            }
        } catch {
            zlog("ZMediaPlayerPlugin: ERROR getting player/layer: \(error)")
        }

        let isAvailable = handler?.checkAvailability() ?? false
        zlog("ZMediaPlayerPlugin: PiP availability result: \(isAvailable)")
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

        // Always re-initialize with current player and player layer before entering PiP,
        // forwarding the PiP config so autoEnterOnBackground is applied on every path.
        if let player = try? playerManager.getPlayer(playerId: playerId),
           let playerLayer = try? playerManager.getPlayerLayer(playerId: playerId) {
            handler?.initialize(player: player, playerLayer: playerLayer, config: config)
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

// MARK: - H-06: NetworkMonitor.NetworkCallback

extension ZMediaPlayerPlugin: NetworkMonitor.NetworkCallback {
    // All three events funnel through the same "onNetworkStatusChanged" wire
    // event — the Dart side (NetworkStatus/NetworkChangeEvent) derives
    // available/lost/quality-improved/quality-degraded by diffing
    // consecutive statuses rather than needing three distinct method names,
    // so no information is lost by unifying them here. See
    // MediaPlayer._handleNetworkStatusChanged in lib/src/core/media_player.dart.

    func onNetworkAvailable(status: [String: Any]) {
        broadcastNetworkStatus(status)
    }

    func onNetworkLost(status: [String: Any]) {
        broadcastNetworkStatus(status)
    }

    func onNetworkQualityChanged(status: [String: Any]) {
        broadcastNetworkStatus(status)
    }

    /// Forwards a NetworkMonitor status dictionary to every
    /// currently-initialized player. `NWPathMonitor`'s `pathUpdateHandler`
    /// fires on `NetworkMonitor`'s private background `queue`, not the main
    /// thread, and `FlutterMethodChannel.invokeMethod` must be called on the
    /// main thread — hence the explicit `DispatchQueue.main.async` hop
    /// (mirrors the pattern already used for `onDrmSessionUpdate` in
    /// `DrmHandler.swift`'s `notifyOnMainThread`).
    private func broadcastNetworkStatus(_ status: [String: Any]) {
        guard !activePlayerIds.isEmpty else { return }
        let ids = activePlayerIds
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let channel = self.methodChannel else { return }
            for id in ids {
                var payload = status
                payload["playerId"] = id
                channel.invokeMethod("onNetworkStatusChanged", arguments: payload)
            }
        }
    }
}
