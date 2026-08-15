import Foundation
import AVFoundation
import AVKit
import Flutter

/// Handles Picture-in-Picture functionality for iOS
@available(iOS 9.0, *)
class PipHandler: NSObject {
    private let playerId: String
    private let channel: FlutterMethodChannel
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var pipController: AVPictureInPictureController?
    private var isInPipMode: Bool = false

    // Configuration
    private var config: [String: Any]?

    // M-03: bounds the "wait for controller / wait for layer readiness"
    // retry loops in enterPip() below. Without a cap, content that never
    // becomes ready for PiP (audio-only, a detached view, or the app
    // backgrounded before the first frame renders) retried forever at a
    // fixed interval. 10 attempts at up to 0.5s apart is an overall deadline
    // of ~5s, which is generous for "player item just needs a moment to
    // render" but finite.
    private static let maxPipEnterAttempts = 10

    init(playerId: String, channel: FlutterMethodChannel) {
        self.playerId = playerId
        self.channel = channel
        super.init()
    }

    // MARK: - Initialization

    func initialize(player: AVPlayer?, playerLayer: AVPlayerLayer?, config: [String: Any]? = nil) {
        print("PipHandler: Initializing for player: \(playerId)")
        print("PipHandler: Received player: \(player != nil)")
        print("PipHandler: Received playerLayer: \(playerLayer != nil)")

        // Persist config when provided so autoEnterOnBackground is available on
        // every code path, including the unchanged-layer branch below.
        if let config = config {
            self.config = config
        }

        // Log device info on first init
        if self.player == nil {
            let deviceModel = UIDevice.current.model
            let systemVersion = UIDevice.current.systemVersion
            print("PipHandler: Device: \(deviceModel), iOS: \(systemVersion)")
        }

        // Update references
        let playerChanged = self.player !== player
        let layerChanged = self.playerLayer !== playerLayer

        self.player = player
        self.playerLayer = playerLayer

        // Ensure player is configured for PiP
        if let player = player {
            player.allowsExternalPlayback = true
            player.usesExternalPlaybackWhileExternalScreenIsActive = false

            // CRITICAL: Ensure player layer's player is explicitly set
            // This is necessary for AVPictureInPictureController to recognize it
            if let layer = playerLayer {
                layer.player = player
                print("PipHandler: Explicitly set player on layer")
            }

            print("PipHandler: Configured player for PiP playback")
        }

        // Check if PiP is supported
        let isSupported = AVPictureInPictureController.isPictureInPictureSupported()
        print("PipHandler: AVPictureInPictureController.isPictureInPictureSupported() = \(isSupported)")

        guard isSupported else {
            print("PipHandler: Picture-in-Picture not supported on this device")
            notifyPipStatusChanged(
                state: "unavailable",
                isSupported: false,
                isActive: false,
                errorMessage: "PiP not supported on this device"
            )
            return
        }

        // Setup or update PiP controller if we have a player layer
        if let playerLayer = playerLayer {
            // Only recreate controller if layer changed or controller doesn't exist
            if pipController == nil || layerChanged {
                print("PipHandler: Setting up PiP controller with player layer (changed: \(layerChanged))")
                setupPipController(with: playerLayer)
            } else {
                print("PipHandler: PiP controller already exists and layer unchanged")

                // Re-apply autoEnterOnBackground in case config was updated without
                // a layer change (setupPipController is skipped on this branch).
                if #available(iOS 14.2, *), let controller = pipController {
                    let autoEnter = (self.config?["autoEnterOnBackground"] as? Bool) ?? false
                    controller.canStartPictureInPictureAutomaticallyFromInline = autoEnter
                    print("PipHandler: Re-applied autoEnterOnBackground=\(autoEnter) on unchanged-layer path")
                }

                // Still notify available status
                notifyPipStatusChanged(
                    state: "available",
                    isSupported: true,
                    isActive: isInPipMode
                )
            }
        } else {
            print("PipHandler: WARNING - No player layer provided, cannot setup PiP controller")
            notifyPipStatusChanged(
                state: "unavailable",
                isSupported: true,
                isActive: false,
                errorMessage: "No player layer available"
            )
        }

        print("PipHandler: Initialization complete")
    }

    // MARK: - PiP Controller Setup

    private func setupPipController(with playerLayer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("PipHandler: Cannot setup PiP controller - not supported")
            return
        }

        // Configure audio session for PiP
        configureAudioSessionForPiP()

        do {
            // Create PiP controller
            pipController = try AVPictureInPictureController(playerLayer: playerLayer)
            pipController?.delegate = self

            // Configure PiP controller
            if #available(iOS 14.2, *) {
                pipController?.canStartPictureInPictureAutomaticallyFromInline = config?["autoEnterOnBackground"] as? Bool ?? false
            }

            // Notify that PiP is available
            notifyPipStatusChanged(
                state: "available",
                isSupported: true,
                isActive: false
            )

            print("PipHandler: PiP controller created successfully")
        } catch {
            print("PipHandler: Failed to create PiP controller: \(error.localizedDescription)")
            notifyPipStatusChanged(
                state: "unavailable",
                isSupported: false,
                isActive: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    /// Sets ONLY the audio session category (not activation) required for
    /// `AVPictureInPictureController` — Apple requires the app's session
    /// category to support background audio (`.playback`) for PiP to work,
    /// but does not require it to be ACTIVE ahead of time.
    ///
    /// B-05: this used to also call `setActive(true)` here, which meant
    /// simply setting up the PiP controller (which happens during
    /// `initialize()`, independent of whether the user has pressed play)
    /// seized the process-wide audio session and interrupted any other
    /// app's audio. Setting the category alone does not interrupt other
    /// apps — only activation does — so it's safe to do unconditionally.
    /// Activation itself is owned exclusively by `AudioSessionCoordinator`,
    /// driven by `MediaPlayerInstance.play()`/`pause()`, which shares the
    /// same `AVPlayer` this controller is wrapping.
    private func configureAudioSessionForPiP() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
            print("PipHandler: Audio session category configured for PiP (activation is owned by AudioSessionCoordinator)")
        } catch {
            print("PipHandler: Failed to configure audio session category: \(error.localizedDescription)")
        }
    }

    // MARK: - PiP Availability

    func checkAvailability() -> Bool {
        let isSupported = AVPictureInPictureController.isPictureInPictureSupported()
        print("PipHandler: PiP system support check: \(isSupported)")
        print("PipHandler: Has player: \(player != nil)")
        print("PipHandler: Has playerLayer: \(playerLayer != nil)")
        print("PipHandler: Has pipController: \(pipController != nil)")

        if let controller = pipController {
            print("PipHandler: PiP controller isPictureInPicturePossible: \(controller.isPictureInPicturePossible)")
        }

        notifyPipStatusChanged(
            state: isSupported ? "available" : "unavailable",
            isSupported: isSupported,
            isActive: isInPipMode
        )

        return isSupported
    }

    // MARK: - Enter/Exit PiP

    /// - Parameter attempt: internal retry counter (M-03). Always starts at
    ///   0 for a fresh, externally-triggered call (the default); recursive
    ///   retries below increment it. Capped by `maxPipEnterAttempts` across
    ///   BOTH retry points below (controller creation and layer-readiness),
    ///   so the total wait is bounded regardless of which stage is slow.
    func enterPip(config: [String: Any]?, attempt: Int = 0) -> Bool {
        print("PipHandler: Attempting to enter PiP mode (attempt \(attempt))")

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("PipHandler: Cannot enter PiP - not supported")
            return false
        }

        self.config = config

        // Verify player state
        print("PipHandler: Player status check:")
        print("  - Has player: \(player != nil)")
        print("  - Has player layer: \(playerLayer != nil)")
        print("  - Player has current item: \(player?.currentItem != nil)")
        print("  - Player item status: \(player?.currentItem?.status.rawValue ?? -1)")
        print("  - Player rate: \(player?.rate ?? 0)")

        // Ensure player has a valid item and is ready
        guard let playerItem = player?.currentItem else {
            print("PipHandler: Cannot enter PiP - no current player item")
            notifyPipStatusChanged(
                state: "failed",
                isSupported: true,
                isActive: false,
                errorMessage: "No media loaded. Load and play a video first."
            )
            return false
        }

        // Check if player item is ready
        guard playerItem.status == .readyToPlay else {
            print("PipHandler: Cannot enter PiP - player item not ready (status: \(playerItem.status.rawValue))")
            notifyPipStatusChanged(
                state: "failed",
                isSupported: true,
                isActive: false,
                errorMessage: "Video not ready. Wait for playback to start."
            )
            return false
        }

        // Ensure player layer's player is set (critical for PiP)
        if let layer = playerLayer, let p = player {
            layer.player = p
            print("PipHandler: Ensured player is set on layer before PiP attempt")
        }

        // Create PiP controller if not exists
        if pipController == nil {
            if let playerLayer = playerLayer {
                print("PipHandler: Creating PiP controller...")
                setupPipController(with: playerLayer)

                guard attempt < PipHandler.maxPipEnterAttempts else {
                    print("PipHandler: Gave up waiting for PiP controller to become ready after \(PipHandler.maxPipEnterAttempts) attempts")
                    notifyPipStatusChanged(
                        state: "failed",
                        isSupported: true,
                        isActive: false,
                        errorMessage: "Picture-in-Picture could not start: the controller never became ready after \(PipHandler.maxPipEnterAttempts) attempts."
                    )
                    return false
                }

                // Schedule retry instead of blocking sleep
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self else { return }
                    _ = self.enterPip(config: config, attempt: attempt + 1)
                }

                notifyPipStatusChanged(
                    state: "pending",
                    isSupported: true,
                    isActive: false,
                    errorMessage: "Initializing PiP controller..."
                )

                return false
            } else {
                print("PipHandler: Cannot enter PiP - no player layer available")
                notifyPipStatusChanged(
                    state: "unavailable",
                    isSupported: true,
                    isActive: false,
                    errorMessage: "No player layer available"
                )
                return false
            }
        }

        guard let pipController = pipController else {
            print("PipHandler: Cannot enter PiP - controller not available")
            return false
        }

        print("PipHandler: PiP controller exists")
        print("PipHandler: Player layer frame: \(playerLayer?.frame ?? .zero)")
        print("PipHandler: Player layer superlayer: \(playerLayer?.superlayer != nil)")
        print("PipHandler: Player layer isReadyForDisplay: \(playerLayer?.isReadyForDisplay ?? false)")
        print("PipHandler: isPictureInPicturePossible = \(pipController.isPictureInPicturePossible)")

        // Check if player layer is ready for display
        if let layer = playerLayer, !layer.isReadyForDisplay {
            guard attempt < PipHandler.maxPipEnterAttempts else {
                print("PipHandler: Gave up waiting for player layer to become ready for display after \(PipHandler.maxPipEnterAttempts) attempts")
                notifyPipStatusChanged(
                    state: "failed",
                    isSupported: true,
                    isActive: false,
                    errorMessage: "Picture-in-Picture could not start: the video layer never became ready to display after \(PipHandler.maxPipEnterAttempts) attempts."
                )
                return false
            }

            print("PipHandler: Player layer not ready for display yet, will retry asynchronously")

            // Schedule async retry instead of blocking
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                _ = self.enterPip(config: config, attempt: attempt + 1)
            }

            notifyPipStatusChanged(
                state: "pending",
                isSupported: true,
                isActive: false,
                errorMessage: "Waiting for video to render..."
            )

            return false
        }

        // Re-check if PiP is possible after waiting
        let isPossible = pipController.isPictureInPicturePossible
        print("PipHandler: Final isPictureInPicturePossible check: \(isPossible)")

        guard isPossible else {
            print("PipHandler: Cannot enter PiP - not possible at this time")
            print("PipHandler: Diagnostics:")
            print("  - Player layer isReadyForDisplay: \(playerLayer?.isReadyForDisplay ?? false)")
            print("  - Player layer has presentation: \(playerLayer?.presentation() != nil)")

            notifyPipStatusChanged(
                state: "failed",
                isSupported: true,
                isActive: false,
                errorMessage: "PiP not ready. Wait a moment for video to render."
            )
            return false
        }

        // Start PiP
        pipController.startPictureInPicture()
        print("PipHandler: PiP start requested")

        return true
    }

    func exitPip() {
        print("PipHandler: Exiting PiP mode")

        guard let pipController = pipController else {
            print("PipHandler: Cannot exit PiP - controller not available")
            return
        }

        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
            print("PipHandler: PiP stop requested")
        } else {
            print("PipHandler: PiP is not active")
        }
    }

    // MARK: - Status

    func getStatus() -> [String: Any] {
        let isSupported = AVPictureInPictureController.isPictureInPictureSupported()

        return [
            "state": isInPipMode ? "active" : (isSupported ? "available" : "unavailable"),
            "isSupported": isSupported,
            "isActive": isInPipMode
        ]
    }

    func isActive() -> Bool {
        return isInPipMode
    }

    func isPossible() -> Bool {
        return pipController?.isPictureInPicturePossible ?? false
    }

    // MARK: - Flutter Communication

    private func notifyPipStatusChanged(
        state: String,
        isSupported: Bool,
        isActive: Bool,
        errorMessage: String? = nil
    ) {
        let statusMap: [String: Any?] = [
            "playerId": playerId,
            "state": state,
            "isSupported": isSupported,
            "isActive": isActive,
            "errorMessage": errorMessage
        ]

        DispatchQueue.main.async { [weak self] in
            self?.channel.invokeMethod("onPipStatusChanged", arguments: statusMap)
        }
    }

    // MARK: - Cleanup

    func dispose() {
        print("PipHandler: Disposing")

        // Stop PiP if active
        if isInPipMode {
            exitPip()
        }

        pipController?.delegate = nil
        pipController = nil
        playerLayer = nil
        player = nil
        config = nil
    }

    deinit {
        dispose()
    }
}

// MARK: - AVPictureInPictureControllerDelegate

@available(iOS 9.0, *)
extension PipHandler: AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PipHandler: Will start Picture-in-Picture")

        notifyPipStatusChanged(
            state: "active",
            isSupported: true,
            isActive: false
        )
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PipHandler: Did start Picture-in-Picture")

        isInPipMode = true

        notifyPipStatusChanged(
            state: "active",
            isSupported: true,
            isActive: true
        )
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        print("PipHandler: Failed to start Picture-in-Picture: \(error.localizedDescription)")

        isInPipMode = false

        notifyPipStatusChanged(
            state: "failed",
            isSupported: true,
            isActive: false,
            errorMessage: error.localizedDescription
        )
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PipHandler: Will stop Picture-in-Picture")

        notifyPipStatusChanged(
            state: "exiting",
            isSupported: true,
            isActive: true
        )
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PipHandler: Did stop Picture-in-Picture")

        isInPipMode = false

        notifyPipStatusChanged(
            state: "available",
            isSupported: true,
            isActive: false
        )
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        print("PipHandler: Restore user interface for Picture-in-Picture stop")

        // Restore the player UI when returning from PiP
        // The app should restore its UI to show the video player

        // Call completion handler to indicate success
        completionHandler(true)
    }

    // iOS 14.0+
    @available(iOS 14.0, *)
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStop completionHandler: @escaping (Bool) -> Void
    ) {
        print("PipHandler: Restore user interface for Picture-in-Picture stop (iOS 14+)")

        // Restore the player UI when returning from PiP
        completionHandler(true)
    }
}

// MARK: - PiP Configuration Extension

extension PipHandler {
    /// Update PiP configuration
    func updateConfig(_ config: [String: Any]) {
        self.config = config

        // Update auto-start configuration if available
        if #available(iOS 14.2, *) {
            let autoStart = config["autoEnterOnBackground"] as? Bool ?? false
            pipController?.canStartPictureInPictureAutomaticallyFromInline = autoStart
            print("PipHandler: Updated auto-start configuration: \(autoStart)")
        }
    }

    /// Set whether PiP can start automatically
    @available(iOS 14.2, *)
    func setAutoStartEnabled(_ enabled: Bool) {
        pipController?.canStartPictureInPictureAutomaticallyFromInline = enabled
        print("PipHandler: Auto-start enabled: \(enabled)")
    }

    /// Check if PiP controller requires linear playback
    @available(iOS 14.0, *)
    func requiresLinearPlayback() -> Bool {
        return pipController?.requiresLinearPlayback ?? false
    }
}
