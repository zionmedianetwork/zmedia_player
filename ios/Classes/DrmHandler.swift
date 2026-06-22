import Foundation
import AVFoundation
import Flutter

/// Handles DRM (Digital Rights Management) for iOS media playback
/// Supports FairPlay Streaming (FPS)
@available(iOS 10.0, *)
class DrmHandler: NSObject {
    private let playerId: String
    private let channel: FlutterMethodChannel

    // FairPlay content key session
    private var contentKeySession: AVContentKeySession?
    private var contentKeyDelegate: ContentKeyDelegate?

    // DRM configuration
    private var drmConfig: [String: Any]?
    private var certificateData: Data?

    init(playerId: String, channel: FlutterMethodChannel) {
        self.playerId = playerId
        self.channel = channel
        super.init()
    }

    // MARK: - Configuration

    /// Configure DRM with provided settings
    func configure(drmConfig: [String: Any]) -> Bool {
        self.drmConfig = drmConfig

        guard let scheme = drmConfig["scheme"] as? String else {
            notifyDrmError("DRM scheme is required")
            return false
        }

        // Only FairPlay is supported on iOS
        guard scheme.lowercased() == "fairplay" else {
            notifyDrmError("Only FairPlay DRM is supported on iOS")
            return false
        }

        guard let licenseUrl = drmConfig["licenseUrl"] as? String else {
            notifyDrmError("License URL is required for FairPlay")
            return false
        }

        guard let certificateUrl = drmConfig["certificateUrl"] as? String else {
            notifyDrmError("Certificate URL is required for FairPlay")
            return false
        }

        // Load FairPlay certificate
        loadCertificate(from: certificateUrl) { [weak self] success in
            if success {
                print("DrmHandler: FairPlay certificate loaded successfully")
                self?.notifyDrmSessionState(state: "idle")
            } else {
                self?.notifyDrmError("Failed to load FairPlay certificate")
            }
        }

        return true
    }

    /// Create content key session for FairPlay
    func createContentKeySession(for player: AVPlayer) -> AVContentKeySession {
        if let existingSession = contentKeySession {
            return existingSession
        }

        // Create content key session
        let keySession = AVContentKeySession(keySystem: .fairPlayStreaming)

        // Create and set delegate
        let delegate = ContentKeyDelegate(
            playerId: playerId,
            drmHandler: self,
            certificateData: certificateData
        )
        self.contentKeyDelegate = delegate

        // Set delegate on background queue
        let delegateQueue = DispatchQueue(label: "com.zmedia_player.drm.content_key")
        keySession.setDelegate(delegate, queue: delegateQueue)

        // Note: We don't add the player as recipient here.
        // Instead, we'll add the AVURLAsset when creating the player item

        self.contentKeySession = keySession

        print("DrmHandler: Content key session created")
        return keySession
    }

    // MARK: - Certificate Loading

    /// Load FairPlay certificate from URL
    private func loadCertificate(from urlString: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: urlString) else {
            print("DrmHandler: Invalid certificate URL")
            completion(false)
            return
        }

        print("DrmHandler: Loading FairPlay certificate from: \\(urlString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Add custom headers if provided
        if let headers = drmConfig?["headers"] as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("DrmHandler: Certificate loading error: \\(error.localizedDescription)")
                completion(false)
                return
            }

            guard let data = data, !data.isEmpty else {
                print("DrmHandler: No certificate data received")
                completion(false)
                return
            }

            self.certificateData = data
            print("DrmHandler: Certificate loaded successfully (\\(data.count) bytes)")
            completion(true)
        }

        task.resume()
    }

    // MARK: - License Acquisition

    /// Request license from FairPlay license server
    func requestLicense(
        spcData: Data,
        assetId: String,
        completion: @escaping (Data?, Error?) -> Void
    ) {
        guard let licenseUrl = drmConfig?["licenseUrl"] as? String else {
            completion(nil, DrmError.missingLicenseUrl)
            return
        }

        guard let url = URL(string: licenseUrl) else {
            completion(nil, DrmError.invalidLicenseUrl)
            return
        }

        print("DrmHandler: Requesting license for asset: \\(assetId)")
        notifyDrmSessionState(state: "acquiringLicense")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = spcData

        // Add custom headers
        if let headers = drmConfig?["headers"] as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Add token if provided
        if let token = drmConfig?["token"] as? String {
            request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")
        }

        // Content-Type for FairPlay SPC
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("DrmHandler: License request error: \\(error.localizedDescription)")
                self.notifyDrmError("License request failed: \\(error.localizedDescription)")
                completion(nil, error)
                return
            }

            guard let data = data, !data.isEmpty else {
                print("DrmHandler: No license data received")
                self.notifyDrmError("No license data received")
                completion(nil, DrmError.noLicenseData)
                return
            }

            print("DrmHandler: License received successfully (\\(data.count) bytes)")
            self.notifyDrmSessionState(state: "licensed")
            completion(data, nil)
        }

        task.resume()
    }

    // MARK: - Utility Methods

    /// Extract content identifier from URL
    func extractContentIdentifier(from url: URL) -> String? {
        // Get the scheme-specific part (everything after "skd://")
        guard url.scheme == "skd" else {
            return nil
        }

        // Use the host and path as content ID
        if let host = url.host {
            return host + (url.path.isEmpty ? "" : url.path)
        }

        return url.absoluteString.replacingOccurrences(of: "skd://", with: "")
    }

    /// Check if FairPlay is supported
    static func isFairPlaySupported() -> Bool {
        if #available(iOS 10.0, *) {
            // FairPlay is available on iOS 10.0+
            return true
        }
        return false
    }

    /// Get DRM system info
    func getDrmSystemInfo() -> [String: Any] {
        var info: [String: Any] = [:]

        info["fairplaySupported"] = DrmHandler.isFairPlaySupported()
        info["deviceModel"] = UIDevice.current.model
        info["systemVersion"] = UIDevice.current.systemVersion
        info["certificateLoaded"] = (certificateData != nil)

        return info
    }

    // MARK: - Flutter Communication

    /// Notify Flutter of DRM errors.
    ///
    /// Emits an ``onDrmSessionUpdate`` with state=error so the Dart
    /// ``drmSessionStream`` surfaces the failure.  Also emits the legacy
    /// ``onDrmError`` event for any other consumers.
    func notifyDrmError(_ message: String) {
        print("DrmHandler Error: \(message)")
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        // Primary: onDrmSessionUpdate so Dart drmSessionStream receives it.
        channel.invokeMethod(
            "onDrmSessionUpdate",
            arguments: buildDrmSessionPayload(
                state: "error",
                license: nil,
                errorMessage: message,
                nowMs: nowMs
            )
        )
        // Secondary: legacy onDrmError for other consumers.
        channel.invokeMethod("onDrmError", arguments: [
            "playerId": playerId,
            "error": message,
            "timestamp": nowMs
        ])
    }

    /// Notify Flutter of DRM session state changes via ``onDrmSessionUpdate``.
    ///
    /// The payload matches ``DrmSession.fromMap`` exactly:
    ///   - ``id``          String  – session identifier (playerId-scoped)
    ///   - ``state``       String  – DrmSessionState.name:
    ///                               idle|acquiringLicense|licensed|renewing|error|closed
    ///   - ``license``     Map?    – DrmLicense fields or nil
    ///   - ``errorMessage``String? – nil unless state=error
    ///   - ``createdAt``   Int     – epoch milliseconds
    ///   - ``updatedAt``   Int     – epoch milliseconds
    ///   - ``playerId``    String  – required by the Dart static dispatcher
    func notifyDrmSessionState(state: String, license: [String: Any]? = nil) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        channel.invokeMethod(
            "onDrmSessionUpdate",
            arguments: buildDrmSessionPayload(
                state: state,
                license: license,
                errorMessage: nil,
                nowMs: nowMs
            )
        )
    }

    /// Build the argument dictionary that matches ``DrmSession.fromMap``.
    ///
    /// Uses ``[String: Any]`` (non-optional values) so the StandardMessageCodec
    /// serialises the map correctly through the Flutter method channel.
    /// Nullable fields are included only when non-nil; ``DrmSession.fromMap``
    /// handles missing nullable keys with ``as String?`` / ``as Map?`` casts.
    private func buildDrmSessionPayload(
        state: String,
        license: [String: Any]?,
        errorMessage: String?,
        nowMs: Int64
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "playerId": playerId,
            "id": "drm-session-\(playerId)",
            "state": state,
            "createdAt": Int(nowMs),
            "updatedAt": Int(nowMs)
        ]
        if let license = license {
            payload["license"] = license
        }
        if let errorMessage = errorMessage {
            payload["errorMessage"] = errorMessage
        }
        return payload
    }

    // MARK: - Cleanup

    func dispose() {
        // Invalidate content key session
        // Note: We don't call invalidateAllPersistableContentKeys as it requires app-specific data
        // The session will be cleaned up when set to nil
        contentKeySession = nil
        contentKeyDelegate = nil
        certificateData = nil
        print("DrmHandler: Disposed")
    }
}

// MARK: - Content Key Delegate

@available(iOS 10.0, *)
private class ContentKeyDelegate: NSObject, AVContentKeySessionDelegate {
    private let playerId: String
    private weak var drmHandler: DrmHandler?
    private let certificateData: Data?

    init(playerId: String, drmHandler: DrmHandler, certificateData: Data?) {
        self.playerId = playerId
        self.drmHandler = drmHandler
        self.certificateData = certificateData
    }

    func contentKeySession(
        _ session: AVContentKeySession,
        didProvide keyRequest: AVContentKeyRequest
    ) {
        print("ContentKeyDelegate: Content key requested")
        handleStreamingContentKeyRequest(keyRequest)
    }

    func contentKeySession(
        _ session: AVContentKeySession,
        didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest
    ) {
        print("ContentKeyDelegate: Renewing content key requested")
        handleStreamingContentKeyRequest(keyRequest)
    }

    func contentKeySession(
        _ session: AVContentKeySession,
        contentKeyRequest keyRequest: AVContentKeyRequest,
        didFailWithError err: Error
    ) {
        print("ContentKeyDelegate: Content key request failed: \\(err.localizedDescription)")
        drmHandler?.notifyDrmError("Content key request failed: \\(err.localizedDescription)")
    }

    private func handleStreamingContentKeyRequest(_ keyRequest: AVContentKeyRequest) {
        guard let certificateData = certificateData else {
            drmHandler?.notifyDrmError("Certificate not loaded")
            // DrmError already conforms to Error via LocalizedError — no force-cast needed.
            keyRequest.processContentKeyResponseError(DrmError.certificateNotLoaded)
            return
        }

        // Extract content identifier
        guard let contentIdentifier = keyRequest.identifier as? String else {
            drmHandler?.notifyDrmError("Invalid content identifier")
            keyRequest.processContentKeyResponseError(DrmError.invalidContentIdentifier)
            return
        }

        print("ContentKeyDelegate: Processing key request for: \(contentIdentifier)")

        // Prepare SPC (Server Playback Context) request
        // Create data from content identifier
        let contentIdentifierData = contentIdentifier.data(using: .utf8)!

        // Make SPC request
        keyRequest.makeStreamingContentKeyRequestData(
            forApp: certificateData,
            contentIdentifier: contentIdentifierData,
            options: nil
        ) { [weak self] spcData, error in
            guard let self = self else { return }

            if let error = error {
                print("ContentKeyDelegate: SPC request error: \(error.localizedDescription)")
                self.drmHandler?.notifyDrmError("SPC request failed: \(error.localizedDescription)")
                keyRequest.processContentKeyResponseError(error)
                return
            }

            guard let spcData = spcData else {
                self.drmHandler?.notifyDrmError("No SPC data")
                keyRequest.processContentKeyResponseError(DrmError.noSpcData)
                return
            }

            print("ContentKeyDelegate: SPC data generated (\(spcData.count) bytes)")

            // Request CKC (Content Key Context) from license server
            self.drmHandler?.requestLicense(
                spcData: spcData,
                assetId: contentIdentifier
            ) { ckcData, error in
                if let error = error {
                    keyRequest.processContentKeyResponseError(error)
                    return
                }

                guard let ckcData = ckcData else {
                    keyRequest.processContentKeyResponseError(DrmError.noCkcData)
                    return
                }

                // Create content key response
                let keyResponse = AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckcData)
                keyRequest.processContentKeyResponse(keyResponse)

                print("ContentKeyDelegate: Content key processed successfully")
            }
        }
    }
}

// MARK: - DRM Errors

enum DrmError: Error, LocalizedError {
    case missingLicenseUrl
    case invalidLicenseUrl
    case noLicenseData
    case certificateNotLoaded
    case invalidContentIdentifier
    case noSpcData
    case noCkcData

    var errorDescription: String? {
        switch self {
        case .missingLicenseUrl:
            return "License URL is missing"
        case .invalidLicenseUrl:
            return "Invalid license URL"
        case .noLicenseData:
            return "No license data received"
        case .certificateNotLoaded:
            return "FairPlay certificate not loaded"
        case .invalidContentIdentifier:
            return "Invalid content identifier"
        case .noSpcData:
            return "No SPC data generated"
        case .noCkcData:
            return "No CKC data received from server"
        }
    }
}
