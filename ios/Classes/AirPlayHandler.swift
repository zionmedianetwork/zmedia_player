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
    private var isObservingExternalPlayback: Bool = false  // Track KVO observation state

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

        // Remove observer from previous player
        if let oldPlayer = self.player, isObservingExternalPlayback {
            oldPlayer.removeObserver(self, forKeyPath: "externalPlaybackActive")
            isObservingExternalPlayback = false
        }

        self.player = player

        // Enable external playback on the player
        if let player = player {
            player.allowsExternalPlayback = true
            player.usesExternalPlaybackWhileExternalScreenIsActive = true

            // Add observer for external playback
            player.addObserver(self, forKeyPath: "externalPlaybackActive", options: [.new, .old], context: nil)
            isObservingExternalPlayback = true
        }

        // Check initial AirPlay availability
        checkAirPlayAvailability()

        print("AirPlayHandler: Initialized successfully")
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try audioSession.setActive(true)
            print("AirPlayHandler: Audio session configured for AirPlay")
        } catch {
            print("AirPlayHandler: Failed to setup audio session: \(error.localizedDescription)")
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

    // MARK: - KVO

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "externalPlaybackActive" {
            guard let player = object as? AVPlayer else { return }

            let isActive = player.isExternalPlaybackActive
            print("AirPlayHandler: External playback active changed: \(isActive)")

            isAirPlayActive = isActive

            if isActive {
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

        // Remove NotificationCenter observers
        NotificationCenter.default.removeObserver(self)

        // Remove KVO observer safely
        if let player = player, isObservingExternalPlayback {
            player.removeObserver(self, forKeyPath: "externalPlaybackActive")
            isObservingExternalPlayback = false
        }

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
