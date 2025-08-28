import UIKit
import AVFoundation
import AVKit
import Flutter

class MediaPlayerView: NSObject, FlutterPlatformView {
    private let playerLayer: AVPlayerLayer
    private let containerView: UIView
    
    init(player: AVPlayer?) {
        containerView = UIView()
        playerLayer = AVPlayerLayer(player: player)
        
        super.init()
        
        setupPlayerLayer()
    }
    
    private func setupPlayerLayer() {
        containerView.backgroundColor = UIColor.black
        containerView.layer.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspect
        
        // Set initial frame
        playerLayer.frame = containerView.bounds
        
        // Ensure proper layout
        containerView.addObserver(self, forKeyPath: "bounds", options: [.new], context: nil)
    }
    
    func view() -> UIView {
        // Ensure the player layer is properly sized when view is returned
        DispatchQueue.main.async { [weak self] in
            self?.updatePlayerLayerFrame()
        }
        return containerView
    }
    
    func setVideoGravity(boxFit: String) {
        DispatchQueue.main.async { [weak self] in
            switch boxFit {
            case "contain":
                self?.playerLayer.videoGravity = .resizeAspect
            case "cover":
                self?.playerLayer.videoGravity = .resizeAspectFill
            case "fill":
                self?.playerLayer.videoGravity = .resize
            case "fitWidth":
                self?.playerLayer.videoGravity = .resizeAspect
            case "fitHeight":
                self?.playerLayer.videoGravity = .resizeAspect
            case "none":
                self?.playerLayer.videoGravity = .resizeAspect
            case "scaleDown":
                self?.playerLayer.videoGravity = .resizeAspect
            default:
                self?.playerLayer.videoGravity = .resizeAspect
            }
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "bounds" {
            DispatchQueue.main.async { [weak self] in
                self?.updatePlayerLayerFrame()
            }
        }
    }
    
    private func updatePlayerLayerFrame() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = containerView.bounds
        CATransaction.commit()
    }
    
    func updatePlayer(_ player: AVPlayer?) {
        playerLayer.player = player
        DispatchQueue.main.async { [weak self] in
            self?.updatePlayerLayerFrame()
        }
    }
    
    deinit {
        containerView.removeObserver(self, forKeyPath: "bounds")
    }
}

class MediaPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
    private let playerManager: MediaPlayerManager
    
    init(playerManager: MediaPlayerManager) {
        self.playerManager = playerManager
        super.init()
    }
    
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        guard let creationParams = args as? [String: Any],
              let playerId = creationParams["playerId"] as? String,
              let playerView = playerManager.getPlayerView(playerId: playerId) else {
            fatalError("Player not found or invalid parameters")
        }
        
        return playerView
    }
    
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
