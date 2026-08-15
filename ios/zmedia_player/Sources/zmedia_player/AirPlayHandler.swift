import Foundation
import AVFoundation
import AVKit
import Flutter

/// Handles AirPlay functionality for iOS
class AirPlayHandler: NSObject {
    private let playerId: String
    private let channel: FlutterMethodChannel
    private var player: AVPlayer?
    private var routePickerView: AVRoutePickerView?
    private var isAirPlayActive: Bool = false
    private var currentRoute: AVAudioSessionRouteDescription?

    // Block-based KVO token for AVPlayer.isExternalPlaybackActive.
    // Invalidated in dispose() and auto-invalidated on dealloc.
    private var externalPlaybackObservation: NSKeyValueObservation?

    // Configuration
    private var config: [String: Any]?

    init(playerId: String, channel: FlutterMethodChannel) {
        self.playerId = playerId
        self.channel = channel
        super.init()

        // Setup audio session for AirPlay
        setupAudioSession()

        // Setup route change notifications
        setupRouteChangeNotifications()
    }

    // MARK: - Initialization

    func initialize(config: [String: Any], player: AVPlayer?) {
        print("AirPlayHandler: Initializing for player: \(playerId)")

        self.config = config

        // Invalidate any existing block-based observation before switching players.
        externalPlaybackObservation?.invalidate()
        externalPlaybackObservation = nil

        self.player = player

        // Enable external playback on the player
        if let player = player {
            player.allowsExternalPlayback = true
            player.usesExternalPlaybackWhileExternalScreenIsActive = true

            // Block-based KVO — safer than string-keyPath KVO because:
            //   • The observation token self-invalidates on dealloc (no dangling observer crash).
            //   • The keypath is type-checked at compile time.
            //   • No need for an observeValue override or manual remove tracking.
            externalPlaybackObservation = player.observe(
                \.isExternalPlaybackActive,
                options: [.new, .old]
            ) { [weak self] _, change in
                guard let self = self else { return }

                let isActive = change.newValue ?? false
                print("AirPlayHandler: External playback active changed: \(isActive)")

                self.isAirPlayActive = isActive

                if isActive {
                    self.notifyCastStatusChanged(
                        state: "connected",
                        device: self.getCurrentDevice(),
                        isCasting: true
                    )
                } else {
                    self.notifyCastStatusChanged(
                        state: "disconnected",
                        device: nil,
                        isCasting: false
                    )
                }
            }
        }

        // Check initial AirPlay availability
        checkAirPlayAvailability()

        print("AirPlayHandler: Initialized successfully")
    }

    // MARK: - Audio Session Setup

    /// B-05: this previously also called `setActive(true)` — and ran from
    /// `init()`, i.e. the moment an `AirPlayHandler` object is constructed,
    /// well before any media has loaded or played. That seized the
    /// process-wide audio session and interrupted any other app's audio
    /// just from constructing this handler. `.allowAirPlay` is also already
    /// the default for the `.playback` category, so setting it explicitly
    /// here is a no-op in practice — kept for clarity/documentation intent.
    /// Session ACTIVATION is owned exclusively by `AudioSessionCoordinator`,
    /// driven by `MediaPlayerInstance.play()`/`pause()`/`dispose()`, which
    /// shares the same `AVPlayer` this handler wraps for AirPlay bookkeeping.
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            print("AirPlayHandler: Audio session category configured for AirPlay (activation is owned by AudioSessionCoordinator)")
        } catch {
            print("AirPlayHandler: Failed to configure audio session category: \(error.localizedDescription)")
        }
    }

    // MARK: - Route Change Notifications

    private func setupRouteChangeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )

        print("AirPlayHandler: Route change notifications setup")
    }

    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        print("AirPlayHandler: Route change detected - reason: \(reason.rawValue)")

        switch reason {
        case .newDeviceAvailable:
            print("AirPlayHandler: New device available")
            handleNewDeviceAvailable()

        case .oldDeviceUnavailable:
            print("AirPlayHandler: Old device unavailable")
            handleDeviceUnavailable()
            pausePlaybackIfWiredOrBluetoothOutputRemoved(notification: notification)

        case .routeConfigurationChange:
            print("AirPlayHandler: Route configuration changed")
            updateAirPlayStatus()

        default:
            updateAirPlayStatus()
        }

        // Notify Flutter of route changes
        notifyDevicesChanged()
    }

    private func handleNewDeviceAvailable() {
        updateAirPlayStatus()

        if isAirPlayActive {
            notifyCastStatusChanged(
                state: "connected",
                device: getCurrentDevice(),
                isCasting: true
            )
        }
    }

    private func handleDeviceUnavailable() {
        updateAirPlayStatus()

        if !isAirPlayActive {
            notifyCastStatusChanged(
                state: "disconnected",
                device: nil,
                isCasting: false
            )
        }
    }

    /// B-06: iOS does NOT automatically pause playback when the current
    /// audio output route disappears (e.g. the user physically unplugs
    /// wired headphones, or a Bluetooth headset/speaker drops out of
    /// range/powers off) — without explicit handling, audio would otherwise
    /// suddenly blast out of the built-in speaker. Apple's documented
    /// guidance (and an App Store review expectation) is to pause on this
    /// transition. This intentionally reuses the route-change observer this
    /// handler already has for AirPlay bookkeeping (`setupRouteChangeNotifications`)
    /// rather than registering a second, competing
    /// `AVAudioSession.routeChangeNotification` observer elsewhere in the
    /// plugin — see the call site above in `handleRouteChange`.
    ///
    /// AirPlay route changes are deliberately excluded here (AirPlay's own
    /// `isExternalPlaybackActive`/route bookkeeping above already handles
    /// that transition) so this does not fight with AirPlay's disconnect
    /// handling — an AirPlay disconnect should fall back to local playback,
    /// not pause it.
    ///
    /// NEEDS ON-DEVICE VERIFICATION: route-change delivery/timing for wired
    /// and Bluetooth accessories cannot be exercised in a simulator.
    ///
    /// A **muted** (or silent, volume == 0) player is skipped: "becoming
    /// noisy" exists to stop audio suddenly blasting out of the device
    /// speaker when headphones are removed. A muted player emits no audio,
    /// so there is nothing to leak, and pausing it is a surprise with no
    /// benefit — most notably for the muted-preview-in-a-feed case this
    /// package explicitly supports (e.g. `MediaListPlayer`). This mirrors
    /// Android's `MediaPlayerManager.updateAudioFocusHandling()`, which
    /// passes `handleAudioFocus = !isMuted` / `setHandleAudioBecomingNoisy(!isMuted)`
    /// so a muted player is exempt there too — the two platforms must agree
    /// per the MethodChannel symmetry rule in AGENTS.md. Do not "fix" this
    /// back to unconditional pausing.
    private func pausePlaybackIfWiredOrBluetoothOutputRemoved(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else {
            return
        }

        let outputRemovalPortTypes: Set<AVAudioSession.Port> = [
            .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio, .carAudio
        ]

        let removedWiredOrBluetoothOutput = previousRoute.outputs.contains { output in
            output.portType != .airPlay && outputRemovalPortTypes.contains(output.portType)
        }

        guard removedWiredOrBluetoothOutput else { return }

        // Same "audible" definition as `MediaPlayerInstance.isCurrentlyAudible()`
        // (not muted and volume > 0), reapplied here because `AirPlayHandler`
        // is a sibling object — constructed independently in
        // `ZMediaPlayerPlugin` and only ever handed a raw `AVPlayer` reference
        // via `initialize(config:player:)` — with no reference back to the
        // owning `MediaPlayerInstance` to call its private method on. Both
        // read the exact same underlying `AVPlayer.isMuted`/`.volume` on the
        // same shared player instance, so this cannot drift in practice; if
        // `MediaPlayerInstance` ever grows a fade/ducking concept beyond raw
        // `isMuted`/`volume`, this copy would need updating too.
        guard let player = player, !player.isMuted, player.volume > 0 else {
            print("AirPlayHandler: Wired/Bluetooth output route removed — player is muted/silent, skipping pause")
            return
        }

        print("AirPlayHandler: Wired/Bluetooth output route removed — pausing playback")

        // Mutate the shared AVPlayer on the main thread; route-change
        // notifications are not guaranteed to be delivered on main. Pausing
        // the shared AVPlayer (rather than duplicating state-notification
        // logic here) is sufficient: MediaPlayerManager's timeControlStatus
        // observer on this same AVPlayer already reports the resulting
        // "paused" state to Dart via the existing notifyStateChanged path.
        DispatchQueue.main.async { [weak self] in
            self?.player?.pause()
        }
    }

    // MARK: - AirPlay Status

    private func updateAirPlayStatus() {
        let audioSession = AVAudioSession.sharedInstance()
        currentRoute = audioSession.currentRoute

        // Check if AirPlay is active
        let wasActive = isAirPlayActive
        isAirPlayActive = isCurrentRouteAirPlay()

        // Check external playback status
        if let player = player {
            isAirPlayActive = isAirPlayActive || player.isExternalPlaybackActive
        }

        print("AirPlayHandler: AirPlay status updated - Active: \(isAirPlayActive)")

        // Notify if status changed
        if wasActive != isAirPlayActive {
            if isAirPlayActive {
                notifyCastStatusChanged(
                    state: "connected",
                    device: getCurrentDevice(),
                    isCasting: true
                )
            } else {
                notifyCastStatusChanged(
                    state: "disconnected",
                    device: nil,
                    isCasting: false
                )
            }
        }
    }

    private func isCurrentRouteAirPlay() -> Bool {
        guard let route = currentRoute else { return false }

        for output in route.outputs {
            let portType = output.portType
            print("AirPlayHandler: Checking port type: \(portType.rawValue)")

            // Check if it's an AirPlay output
            if portType == .airPlay {
                return true
            }
        }

        return false
    }

    private func checkAirPlayAvailability() {
        let isAvailable = AVAudioSession.sharedInstance().isOtherAudioPlaying == false

        notifyCastStatusChanged(
            state: isAirPlayActive ? "connected" : "disconnected",
            device: isAirPlayActive ? getCurrentDevice() : nil,
            isCasting: isAirPlayActive,
            isAvailable: isAvailable
        )
    }

    // MARK: - Device Discovery

    func startDiscovery() {
        print("AirPlayHandler: Starting device discovery")

        notifyCastStatusChanged(
            state: "discovering",
            device: nil,
            isCasting: false,
            isAvailable: true
        )

        // Discovery is automatic in iOS
        // Just update available devices
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.notifyDevicesChanged()
            self?.checkAirPlayAvailability()
        }
    }

    func stopDiscovery() {
        print("AirPlayHandler: Stopping device discovery")
        // Discovery management is automatic in iOS
    }

    // MARK: - Connection Management

    func connect(deviceId: String) -> Bool {
        print("AirPlayHandler: Connecting to device: \(deviceId)")

        // On iOS, AirPlay connection is managed through AVRoutePickerView
        // We can't programmatically connect to a specific device
        // User must select device through the system AirPlay picker

        // Show route picker if available
        if let routePicker = routePickerView {
            // Simulate button press to show picker
            for view in routePicker.subviews {
                if let button = view as? UIButton {
                    button.sendActions(for: .touchUpInside)
                    return true
                }
            }
        }

        return false
    }

    func disconnect() {
        print("AirPlayHandler: Disconnecting from AirPlay")

        // Reset to local playback
        if let player = player {
            player.allowsExternalPlayback = false

            // Re-enable external playback after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                player.allowsExternalPlayback = true
            }
        }

        notifyCastStatusChanged(
            state: "disconnecting",
            device: nil,
            isCasting: false
        )
    }

    // MARK: - Media Loading

    func loadMedia(mediaItem: [String: Any]) {
        print("AirPlayHandler: Loading media on AirPlay device")

        // Media loading is handled by AVPlayer automatically
        // when AirPlay is active

        guard let urlString = mediaItem["url"] as? String,
              let url = URL(string: urlString) else {
            print("AirPlayHandler: Invalid media URL")
            return
        }

        if let player = player {
            let playerItem = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: playerItem)
            print("AirPlayHandler: Media loaded successfully")
        }
    }

    // MARK: - Playback Control

    func play() {
        player?.play()
        print("AirPlayHandler: Play command sent")
    }

    func pause() {
        player?.pause()
        print("AirPlayHandler: Pause command sent")
    }

    func seekTo(position: Int64) {
        let time = CMTime(value: position, timescale: 1000)
        player?.seek(to: time)
        print("AirPlayHandler: Seek command sent to position: \(position)ms")
    }

    func setVolume(volume: Double) {
        player?.volume = Float(volume)
        print("AirPlayHandler: Volume set to: \(volume)")
    }

    // MARK: - Route Picker View

    func createRoutePickerView() -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .systemBlue
        picker.activeTintColor = .systemBlue
        picker.prioritizesVideoDevices = true

        self.routePickerView = picker

        print("AirPlayHandler: Route picker view created")
        return picker
    }

    func showRoutePicker() {
        guard let picker = routePickerView else {
            print("AirPlayHandler: Route picker not available")
            return
        }

        // Programmatically trigger the route picker
        for view in picker.subviews {
            if let button = view as? UIButton {
                button.sendActions(for: .touchUpInside)
                print("AirPlayHandler: Route picker shown")
                break
            }
        }
    }

    // MARK: - Device Information

    private func getCurrentDevice() -> [String: Any]? {
        guard let route = currentRoute, isAirPlayActive else {
            return nil
        }

        for output in route.outputs {
            if output.portType == .airPlay {
                return [
                    "id": output.uid,
                    "name": output.portName,
                    "type": "airplay",
                    "model": "",
                    "manufacturer": "Apple",
                    "isConnected": true
                ]
            }
        }

        // Check external playback
        if let player = player, player.isExternalPlaybackActive {
            return [
                "id": "airplay_device",
                "name": "AirPlay Device",
                "type": "airplay",
                "model": "",
                "manufacturer": "Apple",
                "isConnected": true
            ]
        }

        return nil
    }

    private func getAvailableDevices() -> [[String: Any]] {
        var devices: [[String: Any]] = []

        // In iOS, we can't enumerate AirPlay devices programmatically
        // They're discovered and shown by the system's AVRoutePickerView (native button)

        // Only return the currently connected device (if any)
        // The native AirPlayButton in MediaControls handles device discovery
        if let currentDevice = getCurrentDevice() {
            devices.append(currentDevice)
        }

        return devices
    }

    // MARK: - Flutter Communication

    private func notifyDevicesChanged() {
        let devices = getAvailableDevices()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.channel.invokeMethod("onCastDevicesChanged", arguments: [
                "playerId": self.playerId,
                "devices": devices
            ])
        }
    }

    private func notifyCastStatusChanged(
        state: String,
        device: [String: Any]?,
        isCasting: Bool,
        errorMessage: String? = nil,
        isAvailable: Bool = true
    ) {
        let statusMap: [String: Any?] = [
            "playerId": playerId,
            "state": state,
            "device": device,
            "isAvailable": isAvailable,
            "isCasting": isCasting,
            "errorMessage": errorMessage
        ]

        DispatchQueue.main.async { [weak self] in
            self?.channel.invokeMethod("onCastStatusChanged", arguments: statusMap)
        }
    }

    // MARK: - Status Getters

    func getStatus() -> [String: Any] {
        return [
            "state": isAirPlayActive ? "connected" : "disconnected",
            "device": getCurrentDevice() as Any,
            "isAvailable": true,
            "isCasting": isAirPlayActive
        ]
    }

    func isCasting() -> Bool {
        return isAirPlayActive
    }

    // MARK: - Cleanup

    func dispose() {
        print("AirPlayHandler: Disposing")

        // Remove NotificationCenter observers (route change notifications).
        NotificationCenter.default.removeObserver(self)

        // Invalidate block-based KVO observation for isExternalPlaybackActive.
        externalPlaybackObservation?.invalidate()
        externalPlaybackObservation = nil

        routePickerView = nil
        player = nil
        config = nil
    }

    deinit {
        dispose()
    }
}

// MARK: - AVAudioSession Extensions

extension AVAudioSession {
    /// Check if AirPlay is available
    var isAirPlayAvailable: Bool {
        return availableInputs?.contains(where: { $0.portType == .airPlay }) ?? false
    }
}
