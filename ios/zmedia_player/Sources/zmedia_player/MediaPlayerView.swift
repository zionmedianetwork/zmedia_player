import UIKit
import AVFoundation
import AVKit
import Flutter

// MARK: - PlayerContainerView

/// A UIView subclass whose sole job is to keep the AVPlayerLayer's frame
/// exactly equal to its own bounds on every layout pass, including during
/// device rotation and any animated size change.
///
/// Using layoutSubviews() is the canonical iOS pattern for this; KVO on
/// "bounds" is unreliable during rotation because the bounds change arrives
/// inside a Core Animation transaction that has already begun, so the
/// synchronous KVO callback races the animation and the layer ends up with
/// the old (portrait) frame.
private final class PlayerContainerView: UIView {
    let playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        // The playerLayer must NOT clip to the view's bounds — PiP requires
        // the layer to be part of the full presentation tree.
        playerLayer.masksToBounds = false
        playerLayer.backgroundColor = UIColor.black.cgColor
        playerLayer.needsDisplayOnBoundsChange = true
        playerLayer.contentsGravity = .resizeAspect
        playerLayer.videoGravity = .resizeAspect
        playerLayer.isHidden = false
        playerLayer.opacity = 1.0
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("PlayerContainerView does not support Storyboard/NIB instantiation")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Disable implicit Core Animation resize animation so the layer
        // snaps to the new size instantly — no shrink/stretch artefact.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - MediaPlayerView

class MediaPlayerView: NSObject, FlutterPlatformView {
    // Public read-only accessor kept for PiP and AirPlay callers that do:
    //     playerManager.getPlayerLayer(playerId:) → instance.currentPlayerLayer()
    //                                             → activePlayerView?.playerLayer
    var playerLayer: AVPlayerLayer { container.playerLayer }

    /// Invoked from `deinit` (main thread) so the owning `MediaPlayerInstance`
    /// can promote the next-topmost view to be the sole active render target.
    ///
    /// Without this, disposing the active host (e.g. leaving fullscreen, or the
    /// inline→MiniPlayer swap) would leave every remaining `AVPlayerLayer`
    /// detached — a grey surface — because nothing re-binds the shared
    /// `AVPlayer` to a surviving layer.
    var onDeinit: (() -> Void)?

    /// True while this view's layer is the one bound to the shared `AVPlayer`.
    ///
    /// Only the active view may re-attach on foreground (see
    /// `handleAppDidBecomeActive`); inactive views must stay unbound so a
    /// single `AVPlayer` never drives more than one `AVPlayerLayer` at a time
    /// (multiple simultaneous layers on one player is undefined behaviour and
    /// renders grey).
    private(set) var isActiveRenderTarget = false

    private let container: PlayerContainerView

    private var player: AVPlayer? {
        didSet {
            container.playerLayer.player = player
        }
    }

    init(player: AVPlayer?) {
        container = PlayerContainerView()
        self.player = player

        super.init()

        // Wire the player into the layer now that super.init() has run.
        container.playerLayer.player = player

        // Re-attach the AVPlayerLayer's player whenever the app returns to the
        // foreground. iOS releases the layer's render surface while the app is
        // backgrounded / the device is locked, leaving a blank (grey) surface on
        // resume. Re-setting the layer's player forces a fresh render pass.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        print("MediaPlayerView.init(): Configured — player: \(player != nil)")
    }

    // MARK: - Active-render-target binding

    /// Binds the shared `AVPlayer` to THIS view's layer and marks it active.
    /// Call on the most-recently-created (topmost) host only.
    func activate(with player: AVPlayer?) {
        isActiveRenderTarget = true
        updatePlayer(player)
    }

    /// Unbinds the shared `AVPlayer` from this view's layer so it stops being a
    /// render target. Leaves the container in the tree (Flutter still owns it)
    /// but with no player — preventing the multi-layer grey.
    func deactivate() {
        isActiveRenderTarget = false
        updatePlayer(nil)
    }

    /// Forces the AVPlayerLayer to re-render after returning from background /
    /// device standby (otherwise the layer can come back grey/blank).
    @objc private func handleAppDidBecomeActive() {
        // Only the active render target may re-grab the player on foreground;
        // inactive views must stay unbound (single-layer-per-player rule).
        guard isActiveRenderTarget else { return }
        guard let activePlayer = container.playerLayer.player else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.container.playerLayer.player = nil
            self.container.playerLayer.player = activePlayer
            self.container.playerLayer.isHidden = false
            self.container.playerLayer.opacity = 1.0
            self.container.setNeedsLayout()
            self.container.layoutIfNeeded()
            self.container.playerLayer.setNeedsDisplay()
        }
    }

    // MARK: - FlutterPlatformView

    func view() -> UIView {
        // layoutSubviews handles all sizing; no asyncAfter nudge needed.
        // A single setNeedsLayout ensures we get a pass when the platform view
        // host has finished measuring and placed the view.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.container.setNeedsLayout()
            self.container.layoutIfNeeded()
            print("MediaPlayerView.view(): frame=\(self.container.frame), layerFrame=\(self.container.playerLayer.frame)")
        }
        return container
    }

    // MARK: - Video Gravity

    func setVideoGravity(boxFit: String) {
        let gravity = videoGravity(from: boxFit)
        print("MediaPlayerView: setVideoGravity '\(boxFit)' → \(gravity.rawValue)")

        if Thread.isMainThread {
            container.playerLayer.videoGravity = gravity
            container.playerLayer.setNeedsDisplay()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.container.playerLayer.videoGravity = gravity
                self?.container.playerLayer.setNeedsDisplay()
            }
        }
    }

    private func videoGravity(from boxFit: String) -> AVLayerVideoGravity {
        switch boxFit.lowercased() {
        case "cover":
            return .resizeAspectFill
        case "fill":
            return .resize
        case "contain", "fitwidth", "fitheight", "none", "scaledown", "":
            return .resizeAspect
        default:
            print("MediaPlayerView: Unknown boxFit '\(boxFit)', defaulting to .resizeAspect")
            return .resizeAspect
        }
    }

    // MARK: - Player Update

    func updatePlayer(_ newPlayer: AVPlayer?) {
        print("MediaPlayerView: updatePlayer — player: \(newPlayer != nil), hasItem: \(newPlayer?.currentItem != nil)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.player = newPlayer

            if newPlayer != nil {
                self.container.playerLayer.isHidden = false
                self.container.playerLayer.opacity = 1.0
                // Trigger a layout pass so the layer frame is up to date.
                self.container.setNeedsLayout()
                self.container.layoutIfNeeded()
                self.container.playerLayer.setNeedsDisplay()
                print("MediaPlayerView: updatePlayer done — layerFrame=\(self.container.playerLayer.frame)")
            } else {
                self.container.playerLayer.isHidden = true
                print("MediaPlayerView: Player set to nil")
            }
        }
    }

    // MARK: - Cleanup

    deinit {
        print("MediaPlayerView: Deallocating")
        NotificationCenter.default.removeObserver(self)
        container.playerLayer.player = nil
        player = nil
        // Let the instance promote the next-topmost view to active so the
        // shared AVPlayer keeps a live layer after this host is torn down.
        onDeinit?()
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
