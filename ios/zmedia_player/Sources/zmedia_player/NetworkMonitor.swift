import Foundation
import Network

/**
 * Network monitoring for real-time connection status and quality assessment.
 *
 * Uses NWPathMonitor to monitor network changes and estimate quality based on
 * available interfaces and path status. Provides callbacks for network
 * availability, loss, and quality changes.
 *
 * H-06: every `NetworkCallback` method is handed a full status dictionary
 * matching the shape `lib/src/models/network_status.dart`'s
 * `NetworkStatus.fromPlatform` expects (`quality`, `downloadSpeed`,
 * `isMetered`, `connectionType`) so `ZMediaPlayerPlugin` can forward it to
 * Dart unmodified — mirrors `NetworkMonitor.kt`'s `Callback` shape on
 * Android (see that file's doc comment).
 */
@available(iOS 12.0, *)
class NetworkMonitor {

    // MARK: - Quality Thresholds (Mbps)

    private static let excellentThreshold: Double = 5.0
    private static let goodThreshold: Double = 1.0
    private static let fairThreshold: Double = 0.5

    // MARK: - Properties

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.zionmedianetwork.zmedia_player.network_monitor")

    // H-06: weak to avoid a retain cycle with ZMediaPlayerPlugin, which owns
    // this monitor and is itself the callback.
    private weak var callback: NetworkCallback?
    private var isMonitoring = false
    private var currentPath: NWPath?
    private var lastQuality: String = "unknown"

    // MARK: - Callback Protocol

    protocol NetworkCallback: AnyObject {
        func onNetworkAvailable(status: [String: Any])
        func onNetworkLost(status: [String: Any])
        func onNetworkQualityChanged(status: [String: Any])
    }

    // MARK: - Initialization

    init(callback: NetworkCallback) {
        self.callback = callback
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Public Methods

    /**
     * Starts monitoring network status
     */
    func startMonitoring() {
        guard !isMonitoring else {
            zlog("NetworkMonitor: Already monitoring network")
            return
        }

        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }

        monitor.start(queue: queue)
        isMonitoring = true

        zlog("NetworkMonitor: Network monitoring started")
    }

    /**
     * Stops monitoring network status
     */
    func stopMonitoring() {
        guard isMonitoring else {
            return
        }

        monitor.cancel()
        isMonitoring = false
        currentPath = nil

        zlog("NetworkMonitor: Network monitoring stopped")
    }

    /**
     * Gets current network status
     */
    func getCurrentNetworkStatus() -> [String: Any] {
        let path = currentPath ?? monitor.currentPath
        return getNetworkStatus(from: path)
    }

    /**
     * Checks if network is currently available
     */
    func isNetworkAvailable() -> Bool {
        let path = currentPath ?? monitor.currentPath
        return path.status == .satisfied
    }

    // MARK: - Private Methods

    private func handlePathUpdate(_ path: NWPath) {
        currentPath = path

        if path.status == .satisfied {
            zlog("NetworkMonitor: Network available")
            let status = getNetworkStatus(from: path)
            callback?.onNetworkAvailable(status: status)

            // Check network quality (reuses the status just computed above
            // rather than recomputing it, but still only fires
            // onNetworkQualityChanged when the quality bucket actually
            // changed — mirrors NetworkMonitor.kt's onAvailable/
            // checkNetworkQuality split).
            checkNetworkQuality(path, precomputedStatus: status)
        } else {
            zlog("NetworkMonitor: Network lost")
            lastQuality = "offline"
            callback?.onNetworkLost(status: offlineStatus())
        }
    }

    private func checkNetworkQuality(_ path: NWPath, precomputedStatus: [String: Any]? = nil) {
        let status = precomputedStatus ?? getNetworkStatus(from: path)

        guard let quality = status["quality"] as? String else {
            zlog("NetworkMonitor: Unexpected shape in getNetworkStatus result — skipping quality update")
            return
        }

        if quality != lastQuality {
            lastQuality = quality
            callback?.onNetworkQualityChanged(status: status)
        }
    }

    /// Canonical "no connection" status dictionary, shared by every offline
    /// path — mirrors `NetworkMonitor.kt`'s `offlineStatus()`.
    private func offlineStatus() -> [String: Any] {
        return [
            "quality": "offline",
            "downloadSpeed": 0,
            "isMetered": false,
            "connectionType": "none"
        ]
    }

    private func getNetworkStatus(from path: NWPath) -> [String: Any] {
        guard path.status == .satisfied else {
            return [
                "quality": "offline",
                "downloadSpeed": 0,
                "isMetered": false,
                "connectionType": "none"
            ]
        }

        // Estimate bandwidth based on connection type
        let (estimatedMbps, connectionType) = estimateBandwidth(from: path)

        // Convert Mbps to bytes per second
        let downloadSpeed = Int(estimatedMbps * 1000000 / 8)

        // Determine quality
        let quality: String
        switch estimatedMbps {
        case NetworkMonitor.excellentThreshold...:
            quality = "excellent"
        case NetworkMonitor.goodThreshold..<NetworkMonitor.excellentThreshold:
            quality = "good"
        case NetworkMonitor.fairThreshold..<NetworkMonitor.goodThreshold:
            quality = "fair"
        case 0..<NetworkMonitor.fairThreshold:
            quality = "poor"
        default:
            quality = "offline"
        }

        // Check if metered (expensive)
        let isMetered = path.isExpensive

        return [
            "quality": quality,
            "downloadSpeed": downloadSpeed,
            "isMetered": isMetered,
            "connectionType": connectionType
        ]
    }

    private func estimateBandwidth(from path: NWPath) -> (mbps: Double, connectionType: String) {
        // Prioritize connection types (fastest first)
        if path.usesInterfaceType(.wiredEthernet) {
            return (50.0, "ethernet") // Assume 50 Mbps for ethernet
        }

        if path.usesInterfaceType(.wifi) {
            // Check if it's a strong WiFi connection
            if #available(iOS 13.0, *), path.availableInterfaces.count > 0 {
                // Multiple interfaces might indicate better connectivity
                return (10.0, "wifi") // Assume 10 Mbps for WiFi
            }
            return (5.0, "wifi") // Conservative WiFi estimate
        }

        if path.usesInterfaceType(.cellular) {
            // Estimate based on cellular technology
            // Note: iOS doesn't expose cellular generation directly via NWPath
            // This is a conservative estimate
            return (2.0, "cellular") // Assume 2 Mbps for cellular (covers 3G/4G/5G average)
        }

        if path.usesInterfaceType(.loopback) {
            return (1000.0, "loopback") // Local loopback is very fast
        }

        if path.usesInterfaceType(.other) {
            return (1.0, "unknown") // Conservative for unknown types
        }

        return (0.0, "none")
    }
}

// MARK: - iOS 11 Fallback

/**
 * Fallback network monitor for iOS 11 and below (without NWPathMonitor)
 * Uses legacy Reachability approach
 */
class LegacyNetworkMonitor {

    protocol NetworkCallback: AnyObject {
        func onNetworkAvailable()
        func onNetworkLost()
        func onNetworkQualityChanged(quality: String, downloadSpeed: Int, isMetered: Bool)
    }

    private weak var callback: NetworkCallback?
    private var isMonitoring = false

    init(callback: NetworkCallback) {
        self.callback = callback
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        zlog("LegacyNetworkMonitor: Network monitoring started (limited functionality)")
    }

    func stopMonitoring() {
        isMonitoring = false
        zlog("LegacyNetworkMonitor: Network monitoring stopped")
    }

    func getCurrentNetworkStatus() -> [String: Any] {
        // Fallback: assume network is available with good quality
        return [
            "quality": "good",
            "downloadSpeed": 1000000, // 1 Mbps estimate
            "isMetered": false,
            "connectionType": "unknown"
        ]
    }

    func isNetworkAvailable() -> Bool {
        return true // Assume available
    }
}
