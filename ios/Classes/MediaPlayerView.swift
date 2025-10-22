import UIKit
import AVFoundation
import AVKit
import Flutter

class MediaPlayerView: NSObject, FlutterPlatformView {
    let playerLayer: AVPlayerLayer
    private let containerView: UIView
    private var isObserving = false
    private var player: AVPlayer? {
        didSet {
            playerLayer.player = player
        }
    }
    
    init(player: AVPlayer?) {
        containerView = UIView()
        playerLayer = AVPlayerLayer(player: player)
        self.player = player
        
        super.init()
        
        setupPlayerLayer()
    }
    
    private func setupPlayerLayer() {
        // Ensure we're on the main thread for UI operations
        assert(Thread.isMainThread, "setupPlayerLayer must be called on main thread")
        
        containerView.backgroundColor = UIColor.black
        containerView.layer.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspect
        
        // Ensure player layer is part of the presentation tree (required for PiP)
        playerLayer.masksToBounds = false
        
        // Configure layer for proper video rendering
        playerLayer.isHidden = false
        playerLayer.opacity = 1.0
        playerLayer.backgroundColor = UIColor.black.cgColor
        playerLayer.needsDisplayOnBoundsChange = true
        playerLayer.contentsGravity = .resizeAspect
        
        // Set initial frame
        playerLayer.frame = containerView.bounds
        
        // Force a redraw
        playerLayer.setNeedsDisplay()
        playerLayer.setNeedsLayout()
        
        // Add KVO observer safely
        addBoundsObserver()
        
        print("MediaPlayerView.setupPlayerLayer(): Layer configured - frame: \(playerLayer.frame), player: \(player != nil)")
    }
    
    private func addBoundsObserver() {
        guard !isObserving else { return }
        
        do {
            containerView.addObserver(
                self,
                forKeyPath: "bounds",
                options: [.new],
                context: nil
            )
            isObserving = true
        } catch {
            print("MediaPlayerView: Failed to add bounds observer: \(error)")
        }
    }
    
    private func removeBoundsObserver() {
        guard isObserving else { return }
        
        do {
            containerView.removeObserver(self, forKeyPath: "bounds")
            isObserving = false
        } catch {
            print("MediaPlayerView: Failed to remove bounds observer: \(error)")
        }
    }
    
    func view() -> UIView {
        // Ensure the player layer is properly sized and visible when view is returned
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Force update of player layer frame
            self.updatePlayerLayerFrame()
            
            // Ensure the layer is visible and force redraw
            self.playerLayer.isHidden = false
            self.playerLayer.opacity = 1.0
            self.playerLayer.setNeedsDisplay()
            
            // Force container view layout
            self.containerView.setNeedsLayout()
            self.containerView.layoutIfNeeded()
            
            print("MediaPlayerView.view(): Frame set to \(self.playerLayer.frame), player: \(self.player != nil)")
        }
        return containerView
    }
    
    func setVideoGravity(boxFit: String) {
        // Ensure we're on the main thread for UI operations
        let gravity = videoGravity(from: boxFit)
        
        print("MediaPlayerView: Setting video gravity to '\(boxFit)' -> \(gravity.rawValue)")
        
        if Thread.isMainThread {
            playerLayer.videoGravity = gravity
            // Force a redraw to ensure the change takes effect
            playerLayer.setNeedsDisplay()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.playerLayer.videoGravity = gravity
                self?.playerLayer.setNeedsDisplay()
            }
        }
    }
    
    private func videoGravity(from boxFit: String) -> AVLayerVideoGravity {
        switch boxFit.lowercased() {
        case "cover":
            return .resizeAspectFill
        case "fill":
            return .resize
        case "fitwidth":
            return .resizeAspect
        case "fitheight":
            return .resizeAspect
        case "none":
            return .resizeAspect
        case "scaledown":
            return .resizeAspect
        case "contain", "":
            return .resizeAspect
        default:
            print("MediaPlayerView: Unknown boxFit value '\(boxFit)', using default .resizeAspect")
            return .resizeAspect
        }
    }
    
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == "bounds" else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.updatePlayerLayerFrame()
        }
    }
    
    private func updatePlayerLayerFrame() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updatePlayerLayerFrame()
            }
            return
        }
        
        // Use CATransaction to prevent implicit animations
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = containerView.bounds
        CATransaction.commit()
    }
    
    func updatePlayer(_ newPlayer: AVPlayer?) {
        print("MediaPlayerView: updatePlayer called with player: \(newPlayer != nil), has current item: \(newPlayer?.currentItem != nil)")
        
        // Update on main thread to ensure UI consistency
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Store reference and update layer
            self.player = newPlayer
            
            if let player = newPlayer {
                print("MediaPlayerView: Setting player and configuring layer, frame: \(self.containerView.bounds)")
                
                // Ensure the player layer is visible and properly configured
                self.playerLayer.isHidden = false
                self.playerLayer.opacity = 1.0
                self.playerLayer.backgroundColor = UIColor.black.cgColor
                
                // Update frame immediately
                self.updatePlayerLayerFrame()
                
                // Force a redraw of the layer
                self.playerLayer.setNeedsDisplay()
                self.playerLayer.setNeedsLayout()
                
                // Force container view to layout
                self.containerView.setNeedsLayout()
                self.containerView.layoutIfNeeded()
                
                // Multiple redraws with delays to ensure the video surface is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self = self else { return }
                    self.playerLayer.setNeedsDisplay()
                    self.updatePlayerLayerFrame()
                    print("MediaPlayerView: First redraw, frame: \(self.playerLayer.frame)")
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self = self else { return }
                    self.playerLayer.setNeedsDisplay()
                    self.updatePlayerLayerFrame()
                    self.containerView.layoutIfNeeded()
                    print("MediaPlayerView: Second redraw, frame: \(self.playerLayer.frame), player item: \(player.currentItem != nil)")
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self else { return }
                    self.playerLayer.setNeedsDisplay()
                    self.updatePlayerLayerFrame()
                    print("MediaPlayerView: Final redraw, frame: \(self.playerLayer.frame)")
                }
            } else {
                print("MediaPlayerView: Player set to nil")
                self.playerLayer.isHidden = true
            }
        }
    }
    
    deinit {
        print("MediaPlayerView: Deallocating")
        removeBoundsObserver()
        
        // Clean up player reference
        playerLayer.player = nil
        player = nil
    }
}

// MARK: - Factory

class MediaPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
    private let playerManager: MediaPlayerManager
    
    init(playerManager: MediaPlayerManager) {
        self.playerManager = playerManager
        super.init()
    }
    
    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        
        // Validate arguments
        guard let creationParams = args as? [String: Any] else {
            fatalError("MediaPlayerViewFactory: Invalid arguments - expected dictionary")
        }
        
        guard let playerId = creationParams["playerId"] as? String, !playerId.isEmpty else {
            fatalError("MediaPlayerViewFactory: Missing or invalid playerId")
        }
        
        guard let playerView = playerManager.getPlayerView(playerId: playerId) else {
            fatalError("MediaPlayerViewFactory: Player not found for id: \(playerId)")
        }
        
        print("MediaPlayerViewFactory: Created view for player \(playerId)")
        return playerView
    }
    
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}