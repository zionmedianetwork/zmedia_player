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
    
    init(playerId: String, channel: FlutterMethodChannel) {
        self.playerId = playerId
        self.channel = channel
        super.init()
    }
    
    // MARK: - Initialization
    
    func initialize(player: AVPlayer?, playerLayer: AVPlayerLayer?) {
        print("PipHandler: Initializing for player: \(playerId)")
        
        self.player = player
        self.playerLayer = playerLayer
        
        // Check if PiP is supported
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("PipHandler: Picture-in-Picture not supported on this device")
            notifyPipStatusChanged(
                state: "unavailable",
                isSupported: false,
                isActive: false,
                errorMessage: "PiP not supported on this device"
            )
            return
        }
        
        // Setup PiP controller if we have a player layer
        if let playerLayer = playerLayer {
            setupPipController(with: playerLayer)
        }
        
        print("PipHandler: Initialized successfully")
    }
    
    // MARK: - PiP Controller Setup
    
    private func setupPipController(with playerLayer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("PipHandler: Cannot setup PiP controller - not supported")
            return
        }
        
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
    
    // MARK: - PiP Availability
    
    func checkAvailability() -> Bool {
        let isSupported = AVPictureInPictureController.isPictureInPictureSupported()
        print("PipHandler: PiP availability check - Supported: \(isSupported)")
        
        notifyPipStatusChanged(
            state: isSupported ? "available" : "unavailable",
            isSupported: isSupported,
            isActive: isInPipMode
        )
        
        return isSupported
    }
    
    // MARK: - Enter/Exit PiP
    
    func enterPip(config: [String: Any]?) -> Bool {
        print("PipHandler: Attempting to enter PiP mode")
        
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("PipHandler: Cannot enter PiP - not supported")
            return false
        }
        
        self.config = config
        
        // Create PiP controller if not exists
        if pipController == nil {
            if let playerLayer = playerLayer {
                setupPipController(with: playerLayer)
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
        
        // Check if PiP can be started
        guard pipController.isPictureInPicturePossible else {
            print("PipHandler: Cannot enter PiP - not possible at this time")
            notifyPipStatusChanged(
                state: "failed",
                isSupported: true,
                isActive: false,
                errorMessage: "PiP not possible at this time"
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
    
    func picture(_ pictureInPictureController: AVPictureInPictureController,
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

