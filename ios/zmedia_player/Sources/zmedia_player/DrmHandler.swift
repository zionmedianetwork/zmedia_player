import Foundation
import AVFoundation
import CommonCrypto
import Flutter

/// Handles DRM (Digital Rights Management) for iOS media playback.
/// Supports FairPlay Streaming (FPS).
///
/// Certificate pinning is supported for licence requests when
/// `drmConfig["certificatePinning"]` is present.  Pins are expressed as
/// lowercase hex strings of SHA-256(DER SubjectPublicKeyInfo) — the same
/// format stored in `CertificatePinningConfig.pins` on the Dart side.
///
/// IMPORTANT — pin semantics on iOS:
/// iOS provides `SecCertificateCopyKey` (iOS 12+) to obtain the public key,
/// then `SecKeyCopyExternalRepresentation` to export it.  The bytes returned
/// by `SecKeyCopyExternalRepresentation` for RSA and EC keys are the raw
/// public key in a platform-specific encoding (X9.63 for EC, PKCS#1 for RSA)
/// — NOT the full DER SubjectPublicKeyInfo (SPKI).
///
/// To produce the same SHA-256(SPKI) value as Android/OpenSSL we need the
/// complete SPKI DER, which includes the AlgorithmIdentifier OID prefix.
/// We reconstruct it by prepending the well-known ASN.1 OID header for the
/// key type before hashing, following the same approach used by TrustKit and
/// mobile-security libraries.
///
/// Supported key types and their SPKI headers:
///   RSA-2048:  30 82 01 22 30 0d 06 09 2a 86 48 86 f7 0d 01 01 01 05 00 03 82 01 0f 00
///   RSA-4096:  30 82 02 22 30 0d 06 09 2a 86 48 86 f7 0d 01 01 01 05 00 03 82 02 0f 00
///   EC P-256:  30 59 30 13 06 07 2a 86 48 ce 3d 02 01 06 08 2a 86 48 ce 3d 03 01 07 03 42 00
///   EC P-384:  30 76 30 10 06 07 2a 86 48 ce 3d 02 01 06 05 2b 81 04 00 22 03 62 00
///
/// KEY VERIFICATION RISK: Matching is attempted only for the four key types
/// listed above.  If the server uses a different key type (e.g. EC P-521 or
/// RSA-3072) the SPKI header is unknown and the pin will NEVER match, causing
/// all licence requests for that host to be rejected.  The user must verify
/// that server certificates use one of the four supported key types when
/// configuring pins.  This limitation is flagged in the device-verification
/// checklist in the PR description.
@available(iOS 10.0, *)
class DrmHandler: NSObject {
    private let playerId: String
    private let channel: FlutterMethodChannel

    // FairPlay content key session
    private var contentKeySession: AVContentKeySession?
    private var contentKeyDelegate: ContentKeyDelegate?

    // DRM configuration
    private var drmConfig: [String: Any]?

    // MARK: - Certificate handoff (thread-safe)
    //
    // `configure()` kicks off an async certificate download and returns
    // immediately (its `Bool` result only reflects config *validation*, not
    // download completion) so that `createContentKeySession(for:)` can be
    // called right after it, per the existing DRM wiring order in
    // MediaPlayerManager. That means a content-key request can legitimately
    // arrive before the certificate has finished loading. `certificateState`
    // plus `pendingCertificateRequests` turn that into a queue-and-drain
    // instead of a permanent failure (see `certificate(completion:)` and
    // `resolveCertificateState(_:)` below).
    //
    // `certificateLock` guards both of the properties below because they are
    // written from `configure()`/`dispose()` (main thread) and read/written
    // from URLSession's completion queue (certificate + licence downloads)
    // and from the DRM content-key delegate's dedicated background queue
    // (`com.zmedia_player.drm.content_key`, see `createContentKeySession`).
    // A single `NSLock` is sufficient here — the critical sections are tiny
    // (state reads/enqueue/drain), and lock ownership never crosses into the
    // callback bodies themselves (see the `unlock()` placement below), so
    // there's no risk of holding the lock across arbitrary user callback
    // work or blocking the DRM background queue for any length of time.
    private let certificateLock = NSLock()

    private enum CertificateState {
        case pending
        case loaded(Data)
        case failed(Error)
        case disposed
    }

    private var certificateState: CertificateState = .pending
    private var pendingCertificateRequests: [(Result<Data, Error>) -> Void] = []

    // Certificate pinning: domain → list of 64-char lowercase hex pins.
    // Populated from drmConfig["certificatePinning"]["pins"] in configure().
    private var pinnedDomains: [String: [String]] = [:]

    // Dedicated URLSession used for pinned licence requests.
    // Owns the URLSession so the delegate (self) is retained correctly.
    private var pinnedSession: URLSession?

    init(playerId: String, channel: FlutterMethodChannel) {
        self.playerId = playerId
        self.channel = channel
        super.init()
    }

    // MARK: - Configuration

    /// Configure DRM with provided settings.
    ///
    /// Fail-closed by construction: every `guard` below that returns `false`
    /// already calls `notifyDrmError(_:)` first, and the caller
    /// (`MediaPlayerManager.swift`'s `loadMediaItem`) refuses to create an
    /// `AVPlayerItem` at all when this returns `false` — a DRM-configured
    /// item is never played back unprotected on `configure()` failure (wave
    /// 2 security hardening, mirrors `DrmHandler.validateDrmConfig` on
    /// Android).
    ///
    /// No `minWidevineSecurityLevel`-equivalent policy exists here
    /// deliberately: Widevine security levels (L1/L2/L3) are a
    /// Widevine-specific, Android-only concept queryable via
    /// `MediaDrm.getPropertyString("securityLevel")`. FairPlay — the only
    /// scheme this method accepts, enforced by the guard below — has no
    /// directly comparable, app-queryable device security tier; Apple's
    /// equivalent trust model (code-signing + hardware-backed key handling)
    /// is enforced by the OS/`AVContentKeySession` itself, not exposed as a
    /// value this handler could compare against a caller-supplied minimum.
    /// See `WidevineSecurityLevel`'s dartdoc (`lib/src/models/drm_config.dart`)
    /// for the full reasoning; inventing a fake iOS equivalent here would be
    /// exactly the "declared, never actually enforced" pattern this
    /// remediation wave exists to eliminate.
    func configure(drmConfig: [String: Any]) -> Bool {
        self.drmConfig = drmConfig

        // Read optional certificate pinning config
        if let pinningConfig = drmConfig["certificatePinning"] as? [String: Any],
           let pinsMap = pinningConfig["pins"] as? [String: [String]] {
            pinnedDomains = pinsMap
            if !pinnedDomains.isEmpty {
                // Build a dedicated URLSession whose delegate (self) enforces pins
                let config = URLSessionConfiguration.ephemeral
                pinnedSession = URLSession(
                    configuration: config,
                    delegate: self,
                    delegateQueue: nil
                )
                zlog("DrmHandler: Certificate pinning configured for \(pinnedDomains.count) domain(s)")
            }
        }

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

        // Suppress unused-variable warnings – these are validated above.
        _ = licenseUrl

        // Load FairPlay certificate
        loadCertificate(from: certificateUrl) { [weak self] success in
            if success {
                zlog("DrmHandler: FairPlay certificate loaded successfully")
                self?.notifyDrmSessionState(state: "idle")
            } else {
                self?.notifyDrmError("Failed to load FairPlay certificate")
            }
        }

        return true
    }

    /// Create content key session for FairPlay.
    func createContentKeySession(for player: AVPlayer) -> AVContentKeySession {
        if let existingSession = contentKeySession {
            return existingSession
        }

        // Create content key session
        let keySession = AVContentKeySession(keySystem: .fairPlayStreaming)

        // Create and set delegate. Note: the delegate deliberately does NOT
        // capture the certificate at construction time (that was the root
        // cause of B-01 — `certificateData` is frequently still `nil` here
        // because `configure()` returns before the async download
        // completes). Instead the delegate asks `drmHandler` for the
        // certificate at request time via `certificate(completion:)`, which
        // transparently queues the request if the download is still in
        // flight.
        let delegate = ContentKeyDelegate(
            playerId: playerId,
            drmHandler: self
        )
        self.contentKeyDelegate = delegate

        // Set delegate on background queue
        let delegateQueue = DispatchQueue(label: "com.zmedia_player.drm.content_key")
        keySession.setDelegate(delegate, queue: delegateQueue)

        self.contentKeySession = keySession

        zlog("DrmHandler: Content key session created")
        return keySession
    }

    // MARK: - Certificate Loading

    /// Load FairPlay certificate from URL.
    /// Certificate fetches use URLSession.shared (no pinning required here;
    /// the certificate endpoint is not the licence server).
    private func loadCertificate(from urlString: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: urlString) else {
            zlog("DrmHandler: Invalid certificate URL")
            resolveCertificateState(.failed(DrmError.invalidCertificateUrl))
            completion(false)
            return
        }

        zlog("DrmHandler: Loading FairPlay certificate from: \(redactedURL(urlString))")

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
                zlog("DrmHandler: Certificate loading error: \(error.localizedDescription)")
                self.resolveCertificateState(.failed(error))
                completion(false)
                return
            }

            guard let data = data, !data.isEmpty else {
                zlog("DrmHandler: No certificate data received")
                self.resolveCertificateState(.failed(DrmError.certificateNotLoaded))
                completion(false)
                return
            }

            zlog("DrmHandler: Certificate loaded successfully (\(data.count) bytes)")
            self.resolveCertificateState(.loaded(data))
            completion(true)
        }

        task.resume()
    }

    // MARK: - Certificate handoff helpers

    /// Resolve the FairPlay application certificate for a content-key
    /// request. If the certificate has already resolved (loaded, failed, or
    /// this handler was disposed), `completion` runs synchronously on the
    /// calling thread. Otherwise it is queued and drained by
    /// `resolveCertificateState(_:)` once `loadCertificate` finishes — see
    /// B-01 in the Phase 1 remediation plan. `completion` may therefore run
    /// on the caller's thread OR on whatever thread the pending download's
    /// `URLSession` completion handler runs on; callers must not assume main
    /// thread here.
    fileprivate func certificate(completion: @escaping (Result<Data, Error>) -> Void) {
        certificateLock.lock()
        switch certificateState {
        case .loaded(let data):
            certificateLock.unlock()
            completion(.success(data))
        case .failed(let error):
            certificateLock.unlock()
            completion(.failure(error))
        case .disposed:
            certificateLock.unlock()
            completion(.failure(DrmError.disposed))
        case .pending:
            pendingCertificateRequests.append(completion)
            certificateLock.unlock()
        }
    }

    /// Transitions `certificateState` out of `.pending` and drains any
    /// content-key requests that were queued while the certificate was still
    /// downloading. Called exactly once per handler lifetime from
    /// `loadCertificate`'s completion (success or failure), and again from
    /// `dispose()` to fail any requests still waiting when the handler is
    /// torn down (so a disposed handler never leaves a `keyRequest` hanging
    /// forever).
    private func resolveCertificateState(_ newState: CertificateState) {
        let waiters: [(Result<Data, Error>) -> Void]
        certificateLock.lock()
        // Only overwrite a still-pending state. `dispose()` may race a
        // late-arriving URLSession completion; whichever terminal state
        // lands first (loaded/failed from the network, or disposed from
        // teardown) wins, and the queue is only ever drained once.
        if case .pending = certificateState {
            certificateState = newState
            waiters = pendingCertificateRequests
            pendingCertificateRequests.removeAll()
        } else {
            waiters = []
        }
        certificateLock.unlock()

        guard !waiters.isEmpty else { return }
        let result: Result<Data, Error>
        switch newState {
        case .loaded(let data):
            result = .success(data)
        case .failed(let error):
            result = .failure(error)
        case .disposed:
            result = .failure(DrmError.disposed)
        case .pending:
            return
        }
        for waiter in waiters {
            waiter(result)
        }
    }

    /// Whether the FairPlay certificate has finished loading. Used only for
    /// diagnostics (`getDrmSystemInfo()`); does not affect request handling.
    private var isCertificateLoaded: Bool {
        certificateLock.lock()
        defer { certificateLock.unlock() }
        if case .loaded = certificateState {
            return true
        }
        return false
    }

    // MARK: - License Acquisition

    /// Request license from FairPlay license server.
    /// Uses the pinned URLSession when pins are configured, otherwise falls
    /// back to URLSession.shared (unchanged behaviour when no pins present).
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

        zlog("DrmHandler: Requesting license for asset: \(assetId)")
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
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Content-Type for FairPlay SPC
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        // Use the pinned session when pins are configured; fall back to shared session otherwise.
        let session: URLSession = pinnedSession ?? URLSession.shared

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                zlog("DrmHandler: License request error: \(error.localizedDescription)")
                self.notifyDrmError("License request failed: \(error.localizedDescription)")
                completion(nil, error)
                return
            }

            guard let data = data, !data.isEmpty else {
                zlog("DrmHandler: No license data received")
                self.notifyDrmError("No license data received")
                completion(nil, DrmError.noLicenseData)
                return
            }

            zlog("DrmHandler: License received successfully (\(data.count) bytes)")
            self.notifyDrmSessionState(state: "licensed")
            completion(data, nil)
        }

        task.resume()
    }

    // MARK: - Pin matching helpers

    /// Return the configured pins for [host], supporting exact and *.domain wildcards.
    /// Mirrors Dart CertificatePinningConfig.getPinsForDomain.
    private func pins(for host: String) -> [String]? {
        // Exact match
        if let exactPins = pinnedDomains[host] {
            return exactPins
        }
        // Wildcard match: *.parent.com matches sub.parent.com
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count >= 2 {
            let wildcard = "*." + parts.dropFirst().joined(separator: ".")
            if let wildcardPins = pinnedDomains[wildcard] {
                return wildcardPins
            }
        }
        return nil
    }

    /// Known SPKI DER prefixes for common key types.
    /// These are prepended to the raw public key bytes exported by
    /// SecKeyCopyExternalRepresentation to reconstruct the full SPKI DER,
    /// which is what `openssl x509 -pubkey | openssl pkey -pubin -outform der | openssl dgst -sha256`
    /// hashes (and what Android OkHttp/TrustKit pin against).
    private static let spkiHeaders: [(keyType: CFString, keySizeInBits: Int, header: [UInt8])] = [
        // RSA 2048
        (kSecAttrKeyTypeRSA, 2048, [
            0x30, 0x82, 0x01, 0x22,
            0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
            0x05, 0x00,
            0x03, 0x82, 0x01, 0x0f, 0x00
        ]),
        // RSA 4096
        (kSecAttrKeyTypeRSA, 4096, [
            0x30, 0x82, 0x02, 0x22,
            0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
            0x05, 0x00,
            0x03, 0x82, 0x02, 0x0f, 0x00
        ]),
        // EC P-256
        (kSecAttrKeyTypeECSECPrimeRandom, 256, [
            0x30, 0x59,
            0x30, 0x13,
            0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
            0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07,
            0x03, 0x42, 0x00
        ]),
        // EC P-384
        (kSecAttrKeyTypeECSECPrimeRandom, 384, [
            0x30, 0x76,
            0x30, 0x10,
            0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
            0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22,
            0x03, 0x62, 0x00
        ]),
    ]

    /// Compute hex(SHA-256(SPKI DER)) for a SecCertificate.
    /// Returns nil if the key type is not one of the four supported types.
    private func spkiSha256Hex(for certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return nil
        }

        let keyAttrs = SecKeyCopyAttributes(publicKey) as? [CFString: Any]
        let keyType = keyAttrs?[kSecAttrKeyType] as? String
        let keySize = keyAttrs?[kSecAttrKeySizeInBits] as? Int ?? 0

        // Find matching SPKI header
        var spkiHeader: [UInt8]?
        for entry in DrmHandler.spkiHeaders {
            if (keyType as CFString?) == entry.keyType && keySize == entry.keySizeInBits {
                spkiHeader = entry.header
                break
            }
        }

        guard let header = spkiHeader else {
            zlog("DrmHandler: Unsupported key type '\(String(describing: keyType))' size \(keySize) — pin cannot be computed")
            return nil
        }

        // Reconstruct SPKI DER = header bytes + raw public key bytes
        var spkiDer = Data(header)
        spkiDer.append(keyData)

        // SHA-256
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        spkiDer.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(spkiDer.count), &digest)
        }

        // Hex encode
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Utility Methods

    /// Extract content identifier from URL.
    func extractContentIdentifier(from url: URL) -> String? {
        guard url.scheme == "skd" else {
            return nil
        }

        if let host = url.host {
            return host + (url.path.isEmpty ? "" : url.path)
        }

        return url.absoluteString.replacingOccurrences(of: "skd://", with: "")
    }

    /// Check if FairPlay is supported.
    static func isFairPlaySupported() -> Bool {
        if #available(iOS 10.0, *) {
            return true
        }
        return false
    }

    /// Get DRM system info.
    func getDrmSystemInfo() -> [String: Any] {
        var info: [String: Any] = [:]

        info["fairplaySupported"] = DrmHandler.isFairPlaySupported()
        info["deviceModel"] = UIDevice.current.model
        info["systemVersion"] = UIDevice.current.systemVersion
        info["certificateLoaded"] = isCertificateLoaded

        return info
    }

    // MARK: - Flutter Communication

    /// Notify Flutter of DRM errors.
    ///
    /// Emits an ``onDrmSessionUpdate`` with state=error so the Dart
    /// ``drmSessionStream`` surfaces the failure. This is the single event
    /// for DRM failures - do not add a second/legacy ``onDrmError`` call
    /// here. The Dart side only handles ``onDrmSessionUpdate`` (see
    /// `MediaPlayer._handleDrmSessionUpdate`), which already carries a
    /// strictly richer payload (session id, timestamps, playerId) than a
    /// standalone error event would. A previous ``onDrmError`` call had no
    /// Dart handler and was removed (see C-09) - re-adding it would either
    /// be dead code again or, if wired up, would double-emit the same
    /// failure that ``onDrmSessionUpdate`` already reports.
    func notifyDrmError(_ message: String) {
        zlog("DrmHandler Error: \(message)")
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let sessionPayload = buildDrmSessionPayload(
            state: "error",
            license: nil,
            errorMessage: message,
            nowMs: nowMs
        )
        invokeOnMain { [channel] in
            channel.invokeMethod("onDrmSessionUpdate", arguments: sessionPayload)
        }
    }

    /// Notify Flutter of DRM session state changes via ``onDrmSessionUpdate``.
    func notifyDrmSessionState(state: String, license: [String: Any]? = nil) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let sessionPayload = buildDrmSessionPayload(
            state: state,
            license: license,
            errorMessage: nil,
            nowMs: nowMs
        )
        invokeOnMain { [channel] in
            channel.invokeMethod("onDrmSessionUpdate", arguments: sessionPayload)
        }
    }

    /// Hops to the main thread before invoking a Flutter method channel call.
    /// `FlutterMethodChannel.invokeMethod` requires the platform (main)
    /// thread; `DrmHandler`'s notify helpers are reached from URLSession
    /// completion queues (certificate + licence downloads) and the DRM
    /// content-key delegate's dedicated background queue, none of which are
    /// the main thread (see B-04 in the Phase 1 remediation plan).
    ///
    /// Centralised here (rather than at each `channel.invokeMethod` call
    /// site) so future call sites can't reintroduce the bug. Uses `async`
    /// unconditionally rather than checking `Thread.isMainThread` first:
    /// the ordering guarantee we actually need — DRM notifications observed
    /// in the order they were raised — only requires that hops enqueue in
    /// call order, which `async` alone already provides; conditionally
    /// short-circuiting on-main-thread invocations would risk publishing a
    /// same-thread caller's event ahead of an earlier cross-thread caller's
    /// still-enqueued one. Never `sync` — that would risk deadlocking a
    /// caller already on the main thread (or on a queue the main thread is
    /// waiting on).
    private func invokeOnMain(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

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
        pinnedSession?.invalidateAndCancel()
        pinnedSession = nil
        contentKeySession = nil
        contentKeyDelegate = nil
        // Fail (rather than silently drop) any content-key requests still
        // queued on a certificate download that hasn't resolved yet — a
        // request must never hang forever just because the handler was torn
        // down mid-flight. No-ops if the certificate already resolved
        // (loaded/failed) — see `resolveCertificateState(_:)`.
        resolveCertificateState(.disposed)
        zlog("DrmHandler: Disposed")
    }
}

// MARK: - URLSessionDelegate (certificate pinning)

@available(iOS 10.0, *)
extension DrmHandler: URLSessionDelegate {

    /// Called for every TLS server-trust challenge on the pinned URLSession.
    ///
    /// Logic:
    ///   1. Extract the host from the protection space.
    ///   2. Look up configured pins (exact + wildcard).
    ///   3. If no pins exist for this host → performDefaultHandling (no-op).
    ///   4. If pins exist → evaluate the trust object, then for each cert in the
    ///      chain compute hex(SHA-256(SPKI)) and compare against the pins.
    ///      Accept on first match; cancel otherwise.
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // No pins for this host → perform default TLS validation
        guard let hostPins = pins(for: host), !hostPins.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // We have pins; validate the server trust ourselves
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            zlog("DrmHandler: No server trust in challenge for '\(host)' — cancelling")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Evaluate the trust with the system's default policy
        var secResult = SecTrustResultType.invalid
        if #available(iOS 12.0, *) {
            var error: CFError?
            let evaluated = SecTrustEvaluateWithError(serverTrust, &error)
            if !evaluated {
                zlog("DrmHandler: Trust evaluation failed for '\(host)': \(String(describing: error))")
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        } else {
            // iOS < 12 fallback
            let status = SecTrustEvaluate(serverTrust, &secResult)
            guard status == errSecSuccess,
                  secResult == .unspecified || secResult == .proceed else {
                zlog("DrmHandler: Trust evaluation failed for '\(host)' result=\(secResult.rawValue)")
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }

        // Walk the certificate chain and look for a matching pin
        let certCount = SecTrustGetCertificateCount(serverTrust)
        for i in 0 ..< certCount {
            guard let cert = SecTrustGetCertificateAtIndex(serverTrust, i) else { continue }
            guard let certHex = spkiSha256Hex(for: cert) else {
                // Unsupported key type — log and skip (see SPKI note in file header)
                zlog("DrmHandler: Could not compute SPKI hash for cert at index \(i) for '\(host)'")
                continue
            }

            if hostPins.contains(certHex) {
                zlog("DrmHandler: Pin matched for '\(host)' at chain index \(i)")
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
                return
            }
        }

        // No pin matched — reject the connection
        zlog("DrmHandler: Certificate pin mismatch for '\(host)' — cancelling licence request")
        notifyDrmError("Certificate pin mismatch for '\(host)' — DRM licence request rejected")
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

// MARK: - Content Key Delegate

@available(iOS 10.0, *)
private class ContentKeyDelegate: NSObject, AVContentKeySessionDelegate {
    private let playerId: String
    private weak var drmHandler: DrmHandler?

    init(playerId: String, drmHandler: DrmHandler) {
        self.playerId = playerId
        self.drmHandler = drmHandler
    }

    func contentKeySession(
        _ session: AVContentKeySession,
        didProvide keyRequest: AVContentKeyRequest
    ) {
        zlog("ContentKeyDelegate: Content key requested")
        handleStreamingContentKeyRequest(keyRequest)
    }

    func contentKeySession(
        _ session: AVContentKeySession,
        didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest
    ) {
        zlog("ContentKeyDelegate: Renewing content key requested")
        handleStreamingContentKeyRequest(keyRequest)
    }

    func contentKeySession(
        _ session: AVContentKeySession,
        contentKeyRequest keyRequest: AVContentKeyRequest,
        didFailWithError err: Error
    ) {
        zlog("ContentKeyDelegate: Content key request failed: \(err.localizedDescription)")
        drmHandler?.notifyDrmError("Content key request failed: \(err.localizedDescription)")
    }

    private func handleStreamingContentKeyRequest(_ keyRequest: AVContentKeyRequest) {
        guard let contentIdentifier = keyRequest.identifier as? String else {
            drmHandler?.notifyDrmError("Invalid content identifier")
            keyRequest.processContentKeyResponseError(DrmError.invalidContentIdentifier)
            return
        }

        guard let drmHandler = drmHandler else {
            // Handler already deallocated (e.g. player disposed mid-request).
            keyRequest.processContentKeyResponseError(DrmError.disposed)
            return
        }

        // The FairPlay application certificate may still be downloading when
        // the first key request arrives — `configure()` returns before its
        // async `loadCertificate()` completes, so this delegate can no
        // longer assume the certificate is ready (see B-01 in the Phase 1
        // remediation plan). `certificate(completion:)` queues the request
        // transparently if needed and fails it only once the download has
        // genuinely failed (or the handler is disposed).
        drmHandler.certificate { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let certificateData):
                self.processStreamingContentKeyRequest(
                    keyRequest,
                    contentIdentifier: contentIdentifier,
                    certificateData: certificateData
                )
            case .failure(let error):
                self.drmHandler?.notifyDrmError(
                    "FairPlay certificate unavailable: \(error.localizedDescription)"
                )
                keyRequest.processContentKeyResponseError(error)
            }
        }
    }

    private func processStreamingContentKeyRequest(
        _ keyRequest: AVContentKeyRequest,
        contentIdentifier: String,
        certificateData: Data
    ) {
        zlog("ContentKeyDelegate: Processing key request for: \(contentIdentifier)")

        let contentIdentifierData = contentIdentifier.data(using: .utf8)!

        keyRequest.makeStreamingContentKeyRequestData(
            forApp: certificateData,
            contentIdentifier: contentIdentifierData,
            options: nil
        ) { [weak self] spcData, error in
            guard let self = self else { return }

            if let error = error {
                zlog("ContentKeyDelegate: SPC request error: \(error.localizedDescription)")
                self.drmHandler?.notifyDrmError("SPC request failed: \(error.localizedDescription)")
                keyRequest.processContentKeyResponseError(error)
                return
            }

            guard let spcData = spcData else {
                self.drmHandler?.notifyDrmError("No SPC data")
                keyRequest.processContentKeyResponseError(DrmError.noSpcData)
                return
            }

            zlog("ContentKeyDelegate: SPC data generated (\(spcData.count) bytes)")

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

                let keyResponse = AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckcData)
                keyRequest.processContentKeyResponse(keyResponse)

                zlog("ContentKeyDelegate: Content key processed successfully")
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
    case disposed
    case invalidCertificateUrl

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
        case .disposed:
            return "DRM handler was disposed before this request completed"
        case .invalidCertificateUrl:
            return "Invalid FairPlay certificate URL"
        }
    }
}
