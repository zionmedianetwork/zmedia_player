/// Certificate pinning for secure connections
///
/// Prevents man-in-the-middle attacks by validating server certificates
/// against known good certificates (pins).
///
/// LICENSE-ONLY (H-02): pinning currently applies only to the DRM license
/// server request — NOT to media segment/CDN traffic. Android attaches the
/// pinned `OkHttpClient` solely to the DRM license callback in
/// `DrmHandler.kt`; media itself is fetched through a plain
/// `DefaultHttpDataSource.Factory` with no pinning. iOS uses a bare
/// `AVURLAsset` with no resource-loader delegate, so no pinning is applied
/// to media/CDN traffic there either. Segment/CDN pinning is a known,
/// deliberately deferred follow-up and is out of scope for this phase — do
/// not rely on this config to protect anything other than license
/// requests.
///
/// Pin format: lowercase hex string of SHA-256 over the DER-encoded
/// SubjectPublicKeyInfo (SPKI) of a certificate in the server's TLS chain.
/// Each pin is exactly 64 lowercase hex characters.
///
/// Generate a pin with openssl:
/// ```sh
/// openssl s_client -connect host:443 </dev/null 2>/dev/null \
///   | openssl x509 -pubkey -noout \
///   | openssl pkey -pubin -outform der \
///   | openssl dgst -sha256 -hex \
///   | awk '{print $2}'
/// ```
library;

/// Configuration for certificate pinning.
///
/// Pass an instance of this class to [DrmConfig] via the
/// `certificatePinning` parameter.  The config is serialised with
/// [toMap] and carried to native code inside the DRM config map.
/// Real pin enforcement happens natively:
///   - Android: OkHttp [CertificatePinner] (hex → base64 conversion done in
///     DrmHandler.kt)
///   - iOS: URLSessionDelegate server-trust challenge in DrmHandler.swift
class CertificatePinningConfig {
  /// Map of domains to their certificate pins.
  ///
  /// Keys may be:
  ///   - exact hostname:    "drm.example.com"
  ///   - wildcard:         "*.example.com"  (matches one label only)
  ///
  /// Values are lists of lowercase 64-character hex strings, each being
  /// SHA-256(DER SubjectPublicKeyInfo) of a certificate in the server's chain.
  final Map<String, List<String>> pins;

  /// Whether to enforce pin expiration (reserved for future use).
  final bool enforceExpiration;

  /// Whether to allow backup pins (reserved for future use).
  final bool allowBackupPins;

  /// Minimum number of pins required per domain for [isValid] to pass.
  final int minimumPins;

  const CertificatePinningConfig({
    required this.pins,
    this.enforceExpiration = true,
    this.allowBackupPins = true,
    this.minimumPins = 2,
  });

  /// Creates an empty config (no pinning).
  factory CertificatePinningConfig.disabled() {
    return const CertificatePinningConfig(pins: {});
  }

  /// Creates config from a domain→pins map.
  factory CertificatePinningConfig.fromPins(
    Map<String, List<String>> pins, {
    bool enforceExpiration = true,
  }) {
    return CertificatePinningConfig(
      pins: pins,
      enforceExpiration: enforceExpiration,
    );
  }

  /// Validates the configuration.
  ///
  /// Returns true when:
  ///   - [pins] is empty (no pinning — always valid), OR
  ///   - every domain has at least [minimumPins] entries and each entry is a
  ///     64-character lowercase hex string.
  bool isValid() {
    if (pins.isEmpty) return true;

    for (final entry in pins.entries) {
      if (entry.value.length < minimumPins) {
        return false;
      }
      for (final pin in entry.value) {
        if (!_isValidSha256Hex(pin)) {
          return false;
        }
      }
    }

    return true;
  }

  /// Returns the configured pins for [domain], supporting exact and wildcard
  /// matches.  Returns null when no pins are configured for the domain.
  ///
  /// Wildcard semantics: "*.example.com" matches "cdn.example.com" but NOT
  /// "example.com" or "a.b.example.com".
  List<String>? getPinsForDomain(String domain) {
    // Exact match
    if (pins.containsKey(domain)) {
      return pins[domain];
    }

    // Wildcard match (*.example.com)
    final parts = domain.split('.');
    if (parts.length >= 2) {
      final wildcard = '*.${parts.sublist(1).join('.')}';
      if (pins.containsKey(wildcard)) {
        return pins[wildcard];
      }
    }

    return null;
  }

  /// Checks if a domain has pinning configured.
  bool hasPinsForDomain(String domain) {
    return getPinsForDomain(domain) != null;
  }

  /// Converts to a map suitable for passing through a Flutter platform channel.
  ///
  /// The "pins" value uses the raw [Map<String, List<String>>] type so that
  /// the Kotlin/Swift side can cast it directly.
  Map<String, dynamic> toMap() {
    return {
      'pins': pins,
      'enforceExpiration': enforceExpiration,
      'allowBackupPins': allowBackupPins,
      'minimumPins': minimumPins,
    };
  }

  /// Creates from a platform-channel map (e.g. received from native).
  factory CertificatePinningConfig.fromMap(Map<String, dynamic> map) {
    final rawPins = map['pins'] as Map<dynamic, dynamic>? ?? {};
    final pinsMap = rawPins.map(
      (key, value) => MapEntry(
        key.toString(),
        (value as List<dynamic>).map((e) => e.toString()).toList(),
      ),
    );

    return CertificatePinningConfig(
      pins: pinsMap,
      enforceExpiration: map['enforceExpiration'] as bool? ?? true,
      allowBackupPins: map['allowBackupPins'] as bool? ?? true,
      minimumPins: map['minimumPins'] as int? ?? 2,
    );
  }

  /// Returns true when [hash] is a 64-character lowercase hex string.
  bool _isValidSha256Hex(String hash) {
    final regex = RegExp(r'^[a-fA-F0-9]{64}$');
    return regex.hasMatch(hash);
  }

  @override
  String toString() {
    return 'CertificatePinningConfig(domains: ${pins.length}, '
        'enforceExpiration: $enforceExpiration)';
  }
}

// NOTE: CertificatePinningHelper has been intentionally removed.
//
// The previous implementation of CertificatePinningHelper contained methods
// (calculateFingerprint, validateCertificate, pinFromPem) that computed a
// naive hex encoding of raw certificate bytes — NOT SHA-256(SPKI DER).  This
// produced values that would never match real OkHttp / iOS URLSession pins and
// gave false confidence in security.
//
// Real pin enforcement now happens natively:
//   Android — DrmHandler.kt builds an OkHttpClient.CertificatePinner
//   iOS     — DrmHandler.swift implements URLSessionDelegate server-trust challenge
//
// To generate a correct pin use the openssl command shown at the top of this file.
