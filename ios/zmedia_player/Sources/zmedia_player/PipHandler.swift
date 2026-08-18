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
        zlog("PipHandler: Initializing for player: \(playerId)")
        zlog("PipHandler: Received player: \(player != nil)")
        zlog("PipHandler: Received playerLayer: \(playerLayer != nil)")

        // Persist config when provided so autoEnterOnBackground is available on
        // every code path, including the unchanged-layer branch below.
        if let config = config {
            self.config = config
        }

        // Log device info on first init
        if self.player == nil {
            let deviceModel = UIDevice.current.model
            let systemVersion = UIDevice.current.systemVersion
            zlog("PipHandler: Device: \(deviceModel), iOS: \(systemVersion)")
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
                zlog("PipHandler: Explicitly set player on layer")
            }

            zlog("PipHandler: Configured player for PiP playback")
        }

        // Check if PiP is supported
        let isSupported = AVPictureInPictureController.isPictureInPictureSupported()
        zlog("PipHandler: AVPictureInPictureController.isPictureInPictureSupported() = \(isSupported)")

        guard isSupported else {
            zlog("PipHandler: Picture-in-Picture not supported on this device")
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
                zlog("PipHandler: Setting up PiP controller with player layer (changed: \(layerChanged))")
                setupPipController(with: playerLayer)
            } else {
                zlog("PipHandler: PiP controller already exists and layer unchanged")

                // Re-apply autoEnterOnBackground in case config was updated without
                // a layer change (setupPipController is skipped on this branch).
                if #available(iOS 14.2, *), let controller = pipController {
                    let autoEnter = (self.config?["autoEnterOnBackground"] as? Bool) ?? false
                    controller.canStartPictureInPictureAutomaticallyFromInline = autoEnter
                    zlog("PipHandler: Re-applied autoEnterOnBackground=\(autoEnter) on unchanged-layer path")
                }

                // Re-apply showPlaybackControls for the same reason.
                if #available(iOS 14.0, *), let controller = pipController {
                    applyShowPlaybackControls(to: controller)
                }

                // Still notify available status
                notifyPipStatusChanged(
                    state: "available",
                    isSupported: true,
                    isActive: isInPipMode
                )
            }
        } else {
            zlog("PipHandler: WARNING - No player layer provided, cannot setup PiP controller")
            notifyPipStatusChanged(
                state: "unavailable",
                isSupported: true,
                isActive: false,
                errorMessage: "No player layer available"
            )
        }

        zlog("PipHandler: Initialization complete")
    }

    // MARK: - PiP Controller Setup

    private func setupPipController(with playerLayer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            zlog("PipHandler: Cannot setup PiP controller - not supported")
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
            if #available(iOS 14.0, *), let controller = pipController {
                applyShowPlaybackControls(to: controller)
            }

            // Notify that PiP is available
            notifyPipStatusChanged(
                state: "available",
                isSupported: true,
                isActive: false
            )

            zlog("PipHandler: PiP controller created successfully")
        } catch {
            zlog("PipHandler: Failed to create PiP controller: \(error.localizedDescription)")
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
            zlog("PipHandler: Audio session category configured for PiP (activation is owned by AudioSessionCoordinator)")
        } catch {
            zlog("PipHandler: Failed to configure audio session category: \(error.localizedDescription)")
        }
    }

    /// Applies `PipConfig.showPlaybackControls` (Wave C, gate item
    /// "PipConfig.actions and PipConfig.showPlaybackControls are ignored
    /// natively") to a live [AVPictureInPictureController].
    ///
    /// **This is a partial, best-effort mapping, not a faithful one-to-one
    /// equivalent of the Android behaviour.** `AVPictureInPictureController`'s
    /// on-screen controls are entirely system-owned: there is no public API to
    /// hide/replace them, and Play/Pause specifically can never be hidden by
    /// an app. The one lever iOS exposes that overlaps with "playback
    /// controls" is `requiresLinearPlayback` (iOS 14+, normally used for live
    /// content): setting it `true` removes the skip-forward/skip-back buttons
    /// and the scrubbing bar from the system PiP overlay, leaving only
    /// Play/Pause. We set `requiresLinearPlayback = !showPlaybackControls`, so
    /// `showPlaybackControls: false` hides scrub/skip but Play/Pause always
    /// remains — unlike Android, where `showPlaybackControls: false` can
    /// suppress the custom PiP actions entirely (see `PipHandler.kt`).
    /// [PipConfig.actions] itself has no iOS equivalent at all: AVKit exposes
    /// no API for adding custom action buttons to the system PiP window, so
    /// `actions` is intentionally left unread on this platform.
    @available(iOS 14.0, *)
    private func applyShowPlaybackControls(to controller: AVPictureInPictureController) {
        let showPlaybackControls = (config?["showPlaybackControls"] as? Bool) ?? true
        controller.requiresLinearPlayback = !showPlaybackControls
        zlog("PipHandler: Applied showPlaybackControls=\(showPlaybackControls) via requiresLinearPlayback=\(!showPlaybackControls)")
    }

    // MARK: - PiP Availability

    func checkAvailability() -> Bool {
        let isSupported = AVPictureInPictureController.isPictureInPictureSupported()
        zlog("PipHandler: PiP system support check: \(isSupported)")
        zlog("PipHandler: Has player: \(player != nil)")
        zlog("PipHandler: Has playerLayer: \(playerLayer != nil)")
        zlog("PipHandler: Has pipController: \(pipController != nil)")

        if let controller = pipController {
            zlog("PipHandler: PiP controller isPictureInPicturePossible: \(controller.isPictureInPicturePossible)")
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
        zlog("PipHandler: Attempting to enter PiP mode (attempt \(attempt))")

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            zlog("PipHandler: Cannot enter PiP - not supported")
            return false
        }

        self.config = config

        // Verify player state
        zlog("PipHandler: Player status check:")
        zlog("  - Has player: \(player != nil)")
        zlog("  - Has player layer: \(playerLayer != nil)")
        zlog("  - Player has current item: \(player?.currentItem != nil)")
        zlog("  - Player item status: \(player?.currentItem?.status.rawValue ?? -1)")
        zlog("  - Player rate: \(player?.rate ?? 0)")

        // Ensure player has a valid item and is ready
        guard let playerItem = player?.currentItem else {
            zlog("PipHandler: Cannot enter PiP - no current player item")
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
            zlog("PipHandler: Cannot enter PiP - player item not ready (status: \(playerItem.status.rawValue))")
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
            zlog("PipHandler: Ensured player is set on layer before PiP attempt")
        }

        // Create PiP controller if not exists
        if pipController == nil {
            if let playerLayer = playerLayer {
                zlog("PipHandler: Creating PiP controller...")
                setupPipController(with: playerLayer)

                guard attempt < PipHandler.maxPipEnterAttempts else {
                    zlog("PipHandler: Gave up waiting for PiP controller to become ready after \(PipHandler.maxPipEnterAttempts) attempts")
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
                zlog("PipHandler: Cannot enter PiP - no player layer available")
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
            zlog("PipHandler: Cannot enter PiP - controller not available")
            return false
        }

        zlog("PipHandler: PiP controller exists")
        zlog("PipHandler: Player layer frame: \(playerLayer?.frame ?? .zero)")
        zlog("PipHandler: Player layer superlayer: \(playerLayer?.superlayer != nil)")
        zlog("PipHandler: Player layer isReadyForDisplay: \(playerLayer?.isReadyForDisplay ?? false)")
        zlog("PipHandler: isPictureInPicturePossible = \(pipController.isPictureInPicturePossible)")

        // Check if player layer is ready for display
        if let layer = playerLayer, !layer.isReadyForDisplay {
            guard attempt < PipHandler.maxPipEnterAttempts else {
                zlog("PipHandler: Gave up waiting for player layer to become ready for display after \(PipHandler.maxPipEnterAttempts) attempts")
                notifyPipStatusChanged(
                    state: "failed",
                    isSupported: true,
                    isActive: false,
                    errorMessage: "Picture-in-Picture could not start: the video layer never became ready to display after \(PipHandler.maxPipEnterAttempts) attempts."
                )
                return false
            }

            zlog("PipHandler: Player layer not ready for display yet, will retry asynchronously")

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
        zlog("PipHandler: Final isPictureInPicturePossible check: \(isPossible)")

        guard isPossible else {
            zlog("PipHandler: Cannot enter PiP - not possible at this time")
            zlog("PipHandler: Diagnostics:")
            zlog("  - Player layer isReadyForDisplay: \(playerLayer?.isReadyForDisplay ?? false)")
            zlog("  - Player layer has presentation: \(playerLayer?.presentation() != nil)")

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
        zlog("PipHandler: PiP start requested")

        return true
    }

    func exitPip() {
        zlog("PipHandler: Exiting PiP mode")

        guard let pipController = pipController else {
            zlog("PipHandler: Cannot exit PiP - controller not available")
            return
        }

        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
            zlog("PipHandler: PiP stop requested")
        } else {
            zlog("PipHandler: PiP is not active")
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
        zlog("PipHandler: Disposing")

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
        zlog("PipHandler: Will start Picture-in-Picture")

        notifyPipStatusChanged(
            state: "active",
            isSupported: true,
            isActive: false
        )
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        zlog("PipHandler: Did start Picture-in-Picture")

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
        zlog("PipHandler: Failed to start Picture-in-Picture: \(error.localizedDescription)")

        isInPipMode = false

        notifyPipStatusChanged(
            state: "failed",
            isSupported: true,
            isActive: false,
            errorMessage: error.localizedDescription
        )
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        zlog("PipHandler: Will stop Picture-in-Picture")

        notifyPipStatusChanged(
            state: "exiting",
            isSupported: true,
            isActive: true
        )
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        zlog("PipHandler: Did stop Picture-in-Picture")

        isInPipMode = false

        notifyPipStatusChanged(
            state: "available",
            isSupported: true,
            isActive: false
        )
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        zlog("PipHandler: Restore user interface for Picture-in-Picture stop")

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
        zlog("PipHandler: Restore user interface for Picture-in-Picture stop (iOS 14+)")

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
            zlog("PipHandler: Updated auto-start configuration: \(autoStart)")
        }

        if #available(iOS 14.0, *), let controller = pipController {
            applyShowPlaybackControls(to: controller)
        }
    }

    /// Set whether PiP can start automatically
    @available(iOS 14.2, *)
    func setAutoStartEnabled(_ enabled: Bool) {
        pipController?.canStartPictureInPictureAutomaticallyFromInline = enabled
        zlog("PipHandler: Auto-start enabled: \(enabled)")
    }

    /// Check if PiP controller requires linear playback
    @available(iOS 14.0, *)
    func requiresLinearPlayback() -> Bool {
        return pipController?.requiresLinearPlayback ?? false
    }
}
